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
}
