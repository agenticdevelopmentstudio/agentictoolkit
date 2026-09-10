import AgenticToolkitCore
import Foundation
import LanguageServerProtocol
import Testing
@testable import AgenticToolkitLanguage

/// Drives `LanguageServerSession` against `/bin/sh` scripted children rather
/// than a real language server, the way `SubprocessChannelTests` does: nothing
/// here needs `sourcekit-lsp` to be installed, and every test bounds its wait
/// so a regression that hangs the session fails the test instead of hanging
/// the suite.
///
/// `.serialized` for the same reason that suite is: these tests spawn real
/// children and several assert on wall-clock behaviour (an initialize budget
/// lapsing, a bounded stderr drain). Run in parallel they would compete for
/// exactly the resources they are measuring.
@Suite("LanguageServerSession", .serialized)
struct LanguageServerSessionTests {

    /// Every budget here is deliberately short. The production defaults (30 s
    /// initialize, 2 s shutdown) are sized for a cold `sourcekit-lsp` indexing
    /// a large package; a scripted child either answers at once or never.
    private static let initializeBudget: TimeInterval = 2
    private static let shutdownBudget: TimeInterval = 0.5

    /// The ceiling on any poll in this suite. Generous next to the budgets
    /// above, so a loaded machine does not turn a pass into a flake, and still
    /// short enough that a genuine hang fails instead of wedging the suite.
    private static let pollSeconds: TimeInterval = 10

    // MARK: - Scripted servers

    /// Answers exactly one `initialize` request, then stays alive swallowing
    /// everything else the client sends.
    ///
    /// It reads only the first header line before replying, which is enough to
    /// know the request has arrived — and therefore that `JSONRPCSession` has
    /// already registered the responder for id 1; a reply that beat the
    /// request would be dispatched as a response to an unknown id. The body
    /// and the trailing `initialized` notification are eaten by the `cat`,
    /// which is also what keeps the child alive: a server that exits at a
    /// frame boundary is an *unasked* death and the session is right to say so.
    private static let respondingServerScript = #"""
    CAPS='{"hoverProvider":true,"completionProvider":{"triggerCharacters":["."]}}'
    BODY='{"jsonrpc":"2.0","id":1,"result":{"capabilities":'"$CAPS"'}}'
    IFS= read -r HEADER_LINE
    printf 'Content-Length: %s\r\n\r\n%s' "${#BODY}" "$BODY"
    cat >/dev/null
    """#

    /// Answers the handshake and then exits on its own, cleanly, at a frame
    /// boundary — a server that crashes after `initialize`.
    private static let exitingServerScript = #"""
    CAPS='{"hoverProvider":true}'
    BODY='{"jsonrpc":"2.0","id":1,"result":{"capabilities":'"$CAPS"'}}'
    IFS= read -r HEADER_LINE
    printf 'Content-Length: %s\r\n\r\n%s' "${#BODY}" "$BODY"
    sleep 1
    """#

    /// Promises 100 body bytes, writes 16, and exits — a server that crashes
    /// mid-message.
    private static let truncatingServerScript = #"""
    printf 'Content-Length: 100\r\n\r\n{"jsonrpc":"2.0"'
    """#

    /// Explains itself on stderr and dies, the way a language server with a
    /// broken toolchain does.
    private static let failingServerScript = #"""
    echo 'boom: no toolchain here' >&2
    exit 3
    """#

    /// Copies everything the client writes to **stderr** and never answers.
    /// stderr is captured raw, byte for byte, with no framing applied by
    /// anything in this process — which makes it the one place the bytes
    /// actually put on the wire can be counted.
    private static let echoToStandardErrorScript = #"""
    cat >&2
    """#

    // MARK: - Helpers

    private func makeSession(script: String) -> LanguageServerSession {
        LanguageServerSession(configuration: .init(
            name: "Scripted",
            languageIds: ["swift"],
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            rootURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            initializeBudgetSeconds: Self.initializeBudget,
            shutdownBudgetSeconds: Self.shutdownBudget
        ))
    }

    /// Polls `condition` until it holds or the ceiling lapses, and reports
    /// whether it held — so a caller `#expect`s on a Bool and gets a failure
    /// rather than a hang.
    private func poll(
        seconds: TimeInterval = LanguageServerSessionTests.pollSeconds,
        until condition: () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return await condition()
    }

    private func countOccurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    // MARK: - 1. Round trip

    /// The whole stack, end to end: `SubprocessChannel` frames the request,
    /// the child reads a `Content-Length` header, answers with a framed
    /// response, and the decoded body reaches `InitializingServer`.
    ///
    /// What it catches: framing applied twice on the write side (the child's
    /// first header line then describes a body that is itself a header, its
    /// reply never matches, and the initialize budget lapses); framing applied
    /// twice on the read side (`addMessageFraming: true` re-frames an
    /// already-decoded body, so the response never parses); a bridge that
    /// drops frames; a handshake that never publishes `.running`; and
    /// capabilities accepted but not surfaced.
    @Test("a scripted server's framed initialize response reaches the session decoded")
    func framedInitializeResponseRoundTrips() async throws {
        let session = makeSession(script: Self.respondingServerScript)

        try await session.start()

        let state = await session.state
        guard case .running = state else {
            Issue.record("expected .running, got \(state)")
            await session.stop()
            return
        }

        let capabilities = await session.capabilities()
        // Values only the child could have supplied, so they prove the body
        // was decoded rather than defaulted.
        guard case .optionA(let hoverProvider) = capabilities?.hoverProvider else {
            Issue.record("expected a Bool hoverProvider, got \(String(describing: capabilities?.hoverProvider))")
            await session.stop()
            return
        }
        #expect(hoverProvider)
        #expect(capabilities?.completionProvider?.triggerCharacters == ["."])

        await session.stop()
    }

    // MARK: - 2. Framing is applied exactly once

    /// The permanent half of the double-framing control. The negative control
    /// the brief requires is a *mutation* — flip `addMessageFraming` to `true`
    /// and watch the round trip above fail — and a mutation cannot be
    /// committed. This can: it counts the `Content-Length` headers that
    /// actually reach the child.
    ///
    /// What it catches: any second framing on the write path, wherever it is
    /// added — `addMessageFraming: true` on `JSONRPCServerConnection`, a write
    /// handler that prepends a header of its own, or a switch to
    /// `SubprocessChannel.sendRaw` with hand-rolled framing. All three put two
    /// headers on the wire for one message, and all three are otherwise silent.
    @Test("the initialize request reaches the server framed exactly once")
    func initializeRequestIsFramedExactlyOnce() async throws {
        let session = makeSession(script: Self.echoToStandardErrorScript)

        // The child never answers, so the handshake lapses its budget. That is
        // the expected outcome; the assertions are about the bytes it saw.
        await #expect(throws: (any Error).self) { try await session.start() }

        // The child is still alive holding stderr open, so the capture comes
        // back with `SubprocessChannel`'s "drain did not finish" marker in
        // front of it. That marker is why these assertions look at what
        // follows the header rather than at the start of the string.
        let wire = await session.standardErrorText()
        #expect(countOccurrences(of: "Content-Length:", in: wire) == 1)
        #expect(wire.contains(#""method":"initialize""#))
        // The blank line ends the header and the body starts immediately.
        // Under double framing what follows it is a second header.
        #expect(wire.contains("\r\n\r\n{"))
        #expect(!wire.contains("\r\n\r\nContent-Length:"))

        await session.stop()
    }

    /// The semantic-token capabilities, asserted where they matter: in the
    /// bytes the server actually reads.
    ///
    /// Each of these three is a promise about what we will render correctly,
    /// and each fails *silently* if it is wrong — no error, no log, just the
    /// wrong characters coloured or a token stream we throw half of away:
    ///
    /// - `multilineTokenSupport: false` — `TokenRepresentation`'s decoder ends
    ///   every token on the line it began on, so a multiline token would be
    ///   painted as a same-line range of the wrong length.
    /// - `overlappingTokenSupport: false` — `SemanticTokenHighlightProvider`
    ///   drops a token that starts before the previous one ended, because the
    ///   package's own `applyHighlightResult` skips it anyway.
    /// - `augmentsSyntaxTokens: true` — the library's default, and correct for
    ///   us: tree-sitter is underneath, so a server that takes the hint sends
    ///   fewer tokens and we lose nothing. Asserted so that "still the default"
    ///   stays a decision rather than an accident.
    ///
    /// On the wire rather than by reading `LanguageServerSession`'s own static:
    /// reading the static proves a Swift constant has a value, which is not the
    /// question. The question is whether it is encoded and sent, and only the
    /// child's copy of the bytes answers that.
    @Test("the initialize request declares the semantic token capabilities we can actually honour")
    func initializeRequestDeclaresSemanticTokenCapabilities() async throws {
        let session = makeSession(script: Self.echoToStandardErrorScript)

        // As above: the child never answers, so the handshake lapses. The
        // assertions are about the bytes it saw on the way in.
        await #expect(throws: (any Error).self) { try await session.start() }

        let wire = await session.standardErrorText()
        #expect(wire.contains(#""multilineTokenSupport":false"#))
        #expect(wire.contains(#""overlappingTokenSupport":false"#))
        #expect(wire.contains(#""augmentsSyntaxTokens":true"#))

        await session.stop()
    }

    // MARK: - 3. Transport error is observable

    /// A child that truncates mid-body must land the session in `.failed`
    /// carrying the framing error — not in `.stopped`, and not in a `.failed`
    /// whose error is the `dataStreamClosed` the truncation went on to cause.
    ///
    /// What it catches: a bridge that swallows the stream's error and reports
    /// a clean end (the session would then say `serverExited`, or nothing);
    /// a session that treats any stream end as a normal shutdown; and the
    /// first-cause-wins ordering — without the synchronous stream-end box,
    /// `initializeIfNeeded`'s `dataStreamClosed` races the real explanation
    /// and sometimes wins.
    @Test("a server that truncates mid-body fails the session with the framing error")
    func truncatedFrameFailsTheSessionWithTheTransportError() async throws {
        let session = makeSession(script: Self.truncatingServerScript)

        await #expect(throws: (any Error).self) { try await session.start() }

        let failure = await session.state.failure
        #expect(failure != nil)
        let framingError = failure?.error as? AgenticToolkitCore.MessageFramingError
        #expect(framingError == .truncatedMessage(expected: 100, received: 16))

        // Stopping a failed session must not overwrite how it died.
        await session.stop()
        #expect(await session.state.failure?.error is AgenticToolkitCore.MessageFramingError)
    }

    // MARK: - 4. Stderr is captured on a failed start

    /// What it catches: a failure state that carries only the error. A
    /// language server that will not start almost always says why on stderr,
    /// and dropping that text is what turns "sourcekit-lsp cannot find its
    /// toolchain" into "the editor has no completions and nobody knows why".
    @Test("a server that dies noisily carries its stderr into the failure state")
    func standardErrorIsCapturedOnAFailedStart() async throws {
        let session = makeSession(script: Self.failingServerScript)

        await #expect(throws: (any Error).self) { try await session.start() }

        let failure = await session.state.failure
        #expect(failure != nil)
        #expect(failure?.standardErrorText.contains("boom: no toolchain here") == true)
        // Also readable directly, for a caller that wants it while running.
        #expect(await session.standardErrorText().contains("boom: no toolchain here"))
    }

    // MARK: - Lifecycle invariants

    /// A server that exits on its own, at a frame boundary, having said
    /// nothing on stderr, is still a death — and one the session has to notice
    /// promptly rather than by timing out on the next request.
    ///
    /// What it catches: a stream-end handler that only reports errors. A clean
    /// end would then be indistinguishable from a shutdown we asked for, and a
    /// crashed server would sit in `.running` forever.
    @Test("a clean, unasked exit is reported as a failure rather than a shutdown")
    func unaskedCleanExitFailsTheSession() async throws {
        let session = makeSession(script: Self.exitingServerScript)
        try await session.start()

        let failed = await poll { await session.state.failure != nil }
        #expect(failed)
        let error = await session.state.failure?.error as? LanguageServerSessionError
        #expect(error == .serverExited(status: 0))

        await session.stop()
    }

    /// `capabilities()` must go back to `nil` once a running server has died
    /// on its own, not just once it has been `stop()`ped.
    ///
    /// What it catches: the fall-through Task 3.7's brief traced wrong.
    /// `teardown()` is the only place that nils `server`, and the spontaneous-
    /// exit path (`publishStreamEnd` → `fail(with:)`) never calls it — so
    /// `guard let server else { return nil }` alone leaves `capabilities()`
    /// handing back the pre-crash `ServerCapabilities` forever after a crash.
    /// `LSPCompletionDelegate`'s cache-hit guard was fixed to stop returning a
    /// *cached* answer from a dead session, but the delegate then re-asks
    /// `capabilities()` itself and would go on re-caching this stale answer
    /// with a fresh stamp if this method did not also refuse it. This is a
    /// real subprocess, not `FakeEditorLanguageServerSession` — the fake
    /// already gated on `.running`, which is exactly why the delegate's tests
    /// passed against a defect that was still live in production.
    @Test("capabilities answers nil once a running server has died on its own")
    func capabilitiesGoesNilAfterARunningServerDiesOnItsOwn() async throws {
        let session = makeSession(script: Self.exitingServerScript)
        try await session.start()

        // Confirms the pre-crash capabilities really were on offer, so the
        // assertion below is about them going away rather than never having
        // existed.
        let beforeCrash = await session.capabilities()
        #expect(beforeCrash?.hoverProvider != nil)

        let failed = await poll { await session.state.failure != nil }
        #expect(failed)

        let afterCrash = await session.capabilities()
        #expect(afterCrash == nil)

        await session.stop()
    }

    /// `stop()` is terminal: `SubprocessChannel` is single-launch, so a
    /// restarted session would be a session with no child.
    ///
    /// What it catches: a `start()` that guards only on `state`. A `stop()`
    /// that completes before a queued `start()` enters the actor leaves
    /// nothing in `state` to refuse on, and the second `start()` would spawn a
    /// child nobody holds a reference to.
    @Test("start after stop is refused rather than silently spawning an orphan")
    func startAfterStopIsRefused() async throws {
        let session = makeSession(script: Self.respondingServerScript)
        try await session.start()
        await session.stop()

        await #expect(throws: LanguageServerSessionError.sessionHasBeenStopped) {
            try await session.start()
        }
    }

    /// More than one component starts a session on purpose:
    /// `LanguageServerRegistry.reconcile` starts every session it creates, and
    /// `LanguageServerDocumentSync` starts every session it sees, because
    /// `start()` returning is the only "the handshake is done" signal a session
    /// has. So the *second* caller's answer has to be as good as the first's.
    ///
    /// What it catches: the guard this method used to open with — `guard case
    /// .idle = state else { return }` — which returned success to the loser of
    /// that race having awaited nothing. Its caller then asked `capabilities()`
    /// of a session with no `InitializingServer` yet, got `nil`, and could only
    /// read that as "this server published no capabilities". Document
    /// synchronisation went silent for the life of the session, and nothing
    /// logged a thing.
    @Test("a concurrent second start joins the first and sees the handshake it waited for")
    func concurrentStartJoinsTheFirstRatherThanReturningEarly() async throws {
        let session = makeSession(script: Self.respondingServerScript)

        // Both calls are issued before either can finish, so exactly one takes
        // the `.idle` path and the other meets `.starting`. Which one wins does
        // not matter — that is the point.
        async let first: Void = session.start()
        async let second: Void = session.start()
        _ = try await (first, second)

        let state = await session.state
        guard case .running = state else {
            Issue.record("expected .running, got \(state)")
            await session.stop()
            return
        }

        // Values only the child could have supplied. Under the old guard this
        // was `nil` whenever the joiner asked first.
        let capabilities = await session.capabilities()
        #expect(capabilities?.completionProvider?.triggerCharacters == ["."])

        await session.stop()
        // Stopping is still terminal for every caller, joined or not.
        await #expect(throws: LanguageServerSessionError.sessionHasBeenStopped) {
            try await session.start()
        }
    }

    /// The other half: a joiner must not be told a start succeeded when it
    /// failed, and a later caller must not be told a failed session is fine.
    ///
    /// What it catches: propagating the outcome to the winner only. A pipeline
    /// built on the loser's silent success would queue notifications for a
    /// server that does not exist.
    @Test("a concurrent second start throws the first's failure, and so does a later one")
    func concurrentStartPropagatesTheFailureToEveryCaller() async throws {
        let session = makeSession(script: Self.failingServerScript)

        // Unstructured rather than `async let`, because each outcome has to be
        // asserted separately and an `async let` cannot be captured by the
        // `#expect(throws:)` closure. Whether the second call joins the first or
        // arrives after it has already landed in `.failed`, both must throw.
        let first = Task { try await session.start() }
        let second = Task { try await session.start() }
        let firstResult = await first.result
        let secondResult = await second.result
        #expect(throws: (any Error).self) { try firstResult.get() }
        #expect(throws: (any Error).self) { try secondResult.get() }

        // Failed, and torn down carrying the child's explanation — unchanged
        // behaviour, asserted here because the new non-`.idle` paths run beside
        // it.
        let failure = await session.state.failure
        #expect(failure != nil)
        #expect(failure?.standardErrorText.contains("boom: no toolchain here") == true)

        // A start on an already-`.failed` session reports that failure rather
        // than returning success, and does not spawn a second child or
        // overwrite how the first died.
        await #expect(throws: (any Error).self) { try await session.start() }
        #expect(await session.state.failure?.standardErrorText.contains("boom: no toolchain here") == true)
    }

    // MARK: - 6. The state stream

    /// Consumes `stateChanges` from the moment it is built.
    ///
    /// A recorder rather than a `for await` in the test body, for two reasons.
    /// The stream carries a single-iterator contract, so exactly one consumer
    /// may exist; and an inline loop would *block* on a stream that never
    /// finishes — which is precisely the regression test 5 looks for. Every
    /// assertion below therefore goes through the suite's bounded `poll`, so a
    /// stream that misbehaves fails the test instead of wedging the suite.
    private actor StateRecorder {

        /// The transcript, as `caseName`s.
        private(set) var states: [String] = []

        /// Every `.failed` payload the *stream* delivered, so a test can assert
        /// the reason travelled with the transition rather than re-reading it
        /// off the session afterwards.
        private(set) var failures: [LanguageServerFailure] = []

        private(set) var didFinish = false

        /// The reader is started and let go rather than held: it ends when the
        /// stream does, `[weak self]` keeps it from owning the recorder, and
        /// every test here stops its session, so there is nothing to cancel.
        init(_ stream: AsyncStream<LanguageServerSessionState>) {
            Task { [weak self] in
                for await state in stream {
                    await self?.append(state)
                }
                await self?.markFinished()
            }
        }

        private func append(_ state: LanguageServerSessionState) {
            states.append(state.caseName)
            if let failure = state.failure { failures.append(failure) }
        }

        private func markFinished() { didFinish = true }
    }

    /// What it catches: a `state` assignment that bypasses the one publisher,
    /// and a stream that reports only terminal states. `.starting` is the
    /// transition a status panel needs in order to draw a handshake in
    /// progress, and it is written on the path easiest to forget.
    @Test("a successful start publishes .starting then .running")
    func stateChangesEmitsStartingThenRunningForASuccessfulStart() async throws {
        let session = makeSession(script: Self.respondingServerScript)
        let recorder = StateRecorder(session.stateChanges)

        try await session.start()

        let arrived = await poll { await recorder.states.count >= 2 }
        #expect(arrived)
        #expect(Array(await recorder.states.prefix(2)) == ["starting", "running"])

        await session.stop()
    }

    /// What it catches: a failure recorded in `state` but never published, and
    /// a publication that drops the payload. The panel's whole reason for
    /// existing is the second line of a failed row, and it can only come from
    /// here.
    @Test("a start that throws publishes .failed carrying the child's explanation")
    func stateChangesEmitsFailedWhenStartThrows() async {
        let session = makeSession(script: Self.failingServerScript)
        let recorder = StateRecorder(session.stateChanges)

        await #expect(throws: (any Error).self) { try await session.start() }

        let failed = await poll { await recorder.states.last == "failed" }
        #expect(failed)
        #expect(await recorder.states == ["starting", "failed"])
        #expect(await recorder.failures.last?.standardErrorText.contains("boom: no toolchain here") == true)

        await session.stop()
    }

    /// ★ The `teardown()` trap, stated as a test.
    ///
    /// `stop()` writes `.stopped` *after* `teardown()` returns, so finishing
    /// this stream where `publishedDiagnostics` finishes its own — inside
    /// `teardown()` — yields the terminal state into a finished continuation,
    /// where it is dropped without a trace. Nothing else notices: `state` is
    /// still correct, the child is still reaped, every other test in this file
    /// still passes. Only a consumer of the stream sees it, and what it sees is
    /// a server that says "running" forever.
    @Test("stop() delivers .stopped before the stream ends")
    func stateChangesDeliversStoppedBeforeTheStreamEnds() async throws {
        let session = makeSession(script: Self.respondingServerScript)
        let recorder = StateRecorder(session.stateChanges)

        try await session.start()
        await session.stop()

        let ended = await poll { await recorder.didFinish }
        #expect(ended)
        #expect(await recorder.states == ["starting", "running", "stopped"])
    }

    /// The other half of the contract: the stream *does* end, so a consumer's
    /// `for await` returns rather than parking forever on a session that no
    /// longer exists. An observation task that never returns is how a closed
    /// project keeps its registry — and its subprocesses — alive.
    @Test("the consumer's loop terminates once the session has stopped")
    func stateChangesFinishesAfterStop() async throws {
        let session = makeSession(script: Self.respondingServerScript)
        let recorder = StateRecorder(session.stateChanges)

        try await session.start()
        await session.stop()
        #expect(await poll { await recorder.didFinish })

        // And on the path with no child at all. A session retired before its
        // start ever landed must still release its observer, or a registry that
        // reconciles twice in quick succession leaks one parked task per pass.
        let neverStarted = makeSession(script: Self.respondingServerScript)
        let idleRecorder = StateRecorder(neverStarted.stateChanges)

        await neverStarted.stop()

        #expect(await poll { await idleRecorder.didFinish })
        #expect(await idleRecorder.states == ["stopped"])
    }

    /// An *unasked* death is news about a session that is still standing, not
    /// the end of the session — the same contract `publishedDiagnostics`
    /// carries. Finishing here would make `.failed` the last thing a panel
    /// could ever hear, and would retire the observation before `stop()` has
    /// been called.
    @Test("a running server that dies on its own publishes .failed and leaves the stream open")
    func stateChangesStaysOpenWhenARunningServerDiesOnItsOwn() async throws {
        let session = makeSession(script: Self.exitingServerScript)
        let recorder = StateRecorder(session.stateChanges)

        try await session.start()

        let failed = await poll { await recorder.states.last == "failed" }
        #expect(failed)
        #expect(await recorder.didFinish == false)

        await session.stop()
        let ended = await poll { await recorder.didFinish }
        #expect(ended)
        // `.failed` survives the stop, so the transcript never says "stopped".
        #expect(await recorder.states == ["starting", "running", "failed"])
    }

    /// What it catches: `stop()`'s failure branch written as an early `return`.
    /// The state is right either way — that is the point — but the stream is
    /// never finished, and every consumer of a server that failed to start is
    /// parked on it for the lifetime of the process.
    @Test("stopping a failed session keeps the failure and still ends the stream")
    func stoppingAFailedSessionKeepsTheFailureAndStillEndsTheStream() async {
        let session = makeSession(script: Self.failingServerScript)
        let recorder = StateRecorder(session.stateChanges)

        await #expect(throws: (any Error).self) { try await session.start() }
        await session.stop()

        let ended = await poll { await recorder.didFinish }
        #expect(ended)
        #expect(await recorder.states == ["starting", "failed"])
        #expect(await session.state.failure != nil)
    }

    // MARK: - The outstanding-request barrier

    /// `teardown()` must not close the transport under a request that is still
    /// on the wire.
    ///
    /// The hazard is `JSONRPCSession`'s: a request write that fails *after*
    /// `readSequenceFinished()` has already drained its responder resumes one
    /// `CheckedContinuation` twice, which is `SWIFT TASK CONTINUATION MISUSE`
    /// — a `fatalError` that kills the app, not a recoverable error. Until
    /// this branch nothing in production issued a request, so the missing
    /// barrier was latent; `LSPHoverController`, `LSPCompletionDelegate` and
    /// `LSPJumpToDefinitionDelegate` now all do, which makes "the user hovers
    /// as the server is retired" a shipping crash.
    ///
    /// This measures the barrier rather than the crash, because the crash is
    /// a microsecond-wide race that no test can schedule reliably: the
    /// scripted server answers `initialize` and then swallows everything, so
    /// the hover below stays outstanding for as long as the session lets it,
    /// and `stop()` returning early is exactly the defect. Wall-clock, not
    /// instrumentation, because the counter is teardown's private business.
    @Test("teardown waits for a request that is still on the wire")
    func teardownWaitsForOutstandingRequests() async throws {
        let session = makeSession(script: Self.respondingServerScript)
        try await session.start()

        // Never answered: the child's `cat >/dev/null` eats it.
        let hover = Task { try? await session.hover(TextDocumentPositionParams(
            uri: "file:///tmp/outstanding.swift",
            position: Position(line: 0, character: 0)
        )) }
        // Long enough for the request to be counted and written, short next to
        // the barrier budget it is about to be measured against.
        try await Task.sleep(for: .milliseconds(300))

        let started = Date()
        await session.stop()
        let elapsed = Date().timeIntervalSince(started)

        // The default barrier is 2s; the other budgets this session uses are
        // 0.5s shutdown and 1s abandoned-start, and the scripted child dies on
        // SIGTERM at once. A teardown with no barrier lands well under 1.5s.
        #expect(elapsed >= 1.5, "stop() returned in \(elapsed)s; it did not wait for the request")
        #expect(elapsed < 12, "stop() took \(elapsed)s; the barrier is not bounded")

        _ = await hover.value
    }

    /// The barrier must be a wait *for* something, not a fixed cost on every
    /// teardown. With nothing outstanding it has to fall straight through, or
    /// `LanguageServerRegistry.stopAll` pays the full budget per session at
    /// app quit.
    @Test("teardown does not wait when no request is outstanding")
    func teardownDoesNotWaitWithNothingOutstanding() async throws {
        let session = makeSession(script: Self.respondingServerScript)
        try await session.start()

        let started = Date()
        await session.stop()
        let elapsed = Date().timeIntervalSince(started)

        #expect(elapsed < 1.5, "stop() took \(elapsed)s with nothing outstanding")
    }
}
