import Testing
import Foundation
import JavaScriptCore
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// Holds the `JSValue` an extension handed to this suite's capture member.
///
/// A recorder rather than a `JSValue` returned straight out of the block:
/// `defineVSCodeMember` takes an implementation, not a result, so the value
/// has to be parked somewhere the test body can read it afterwards.
@MainActor
private final class ValueCapture {

    /// Every value the member was called with, in call order. A list rather
    /// than one slot so a fixture that calls the member twice is visible as
    /// two entries instead of silently overwriting the first.
    private(set) var values: [JSValue] = []

    /// What `ExtensionHost.defineVSCodeMember(namespacePath:name:implementation:)`
    /// installs.
    ///
    /// No formal parameters, read through `VSCodeAPI.currentArguments()`, for
    /// the reason `VSCodeAPI.member(_:of:whenTornDown:body:)` gives: the
    /// argument is read off the actual argument list rather than off however
    /// many parameters the block happened to declare.
    var implementation: Any {
        let block: @convention(block) () -> Void = { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let value = VSCodeAPI.currentArguments().first else { return }
                self.values.append(value)
            }
        }
        return block
    }
}

/// Where a `VSCodeAPI.settlement(of:in:)` started on its own `Task` puts its
/// answer.
///
/// `@MainActor`, which is also what makes it `Sendable` enough to be captured
/// by the `Task` below: a global-actor-isolated class is implicitly `Sendable`,
/// and `VSCodeAPI.Settlement` — which carries a `JSValue` — never leaves that
/// actor.
@MainActor
private final class SettlementRecorder {
    private(set) var settlement: VSCodeAPI.Settlement?

    func record(_ settlement: VSCodeAPI.Settlement) {
        self.settlement = settlement
    }
}

/// Carries the two non-`Sendable` JavaScriptCore values into that `Task`.
///
/// `@unchecked Sendable` on `VSCodeAPI.UncheckedSettlementBox`'s own terms:
/// `Task.init`'s `operation` closure is checked against `Sendable` and neither
/// `JSValue` nor `JSContext` is, but the closure is `@MainActor` and both
/// values were created on — and are only ever touched from — that same actor.
private struct SettlementInputBox: @unchecked Sendable {
    let value: JSValue
    let context: JSContext
}

/// Records every exception JavaScriptCore reports through a context's handler,
/// and forwards each one to the handler that was already installed.
///
/// This is the only observation of "did an exception escape into the host's
/// bookkeeping" available to this bundle. `ExtensionHost.pendingException` is
/// `private` — unreachable even under `@testable` — and every reader of it
/// clears it first, so there is nothing to read after the fact. What *writes*
/// it is reachable: `ExtensionHost.makeContext` installs a
/// `context.exceptionHandler` whose entire body is
/// `pendingException = describe(exception)`, so an exception that never
/// reaches the handler is an exception that never reaches `pendingException`.
/// Forwarding rather than swallowing keeps the host's own behaviour intact,
/// so a test that installs this observes the host rather than replacing it.
@MainActor
private final class ExceptionRecorder {

    /// One entry per exception reported, as the handler's own `JSValue`
    /// stringified.
    private(set) var messages: [String] = []

    static func install(on context: JSContext) -> ExceptionRecorder {
        let recorder = ExceptionRecorder()
        let previous = context.exceptionHandler
        context.exceptionHandler = { reportingContext, exception in
            MainActor.assumeIsolated {
                recorder.messages.append(exception?.toString() ?? "<no exception value>")
            }
            previous?(reportingContext, exception)
        }
        return recorder
    }
}

/// `VSCodeAPI.settlement(of:in:)` (task 5.5b-i): the primitive that waits for
/// an extension-supplied thenable and hands its fulfilled or rejected value
/// back to Swift, so `showQuickPick`'s `readonly T[] | Thenable<readonly T[]>`
/// first argument (`vscode.d.ts:11421`, `:11431`, `:11441`, `:11451`) can be
/// read at all. It ships before any `window` member uses it, so nothing here
/// goes through an adaptor.
///
/// **Every thenable under test is authored by the extension**, in its own
/// module scope, and reaches Swift through a test-only `vscode.window` member
/// installed with `ExtensionHost.defineVSCodeMember`. A `JSValue` minted in
/// Swift would be the wrong subject twice over: the primitive exists because
/// `then` can be a `Proxy` trap or a throwing accessor written by an
/// extension, and a Swift-built object is neither.
///
/// The one exception is the `.unavailable` test, which needs a context whose
/// trampoline cannot answer `thenOf` and therefore cannot have a working
/// `ExtensionHost` around it — a bare `JSContext`, as `VSCodeAPISubNamespaceTests`
/// uses throughout.
@MainActor
@Suite
struct VSCodeAPISettlementTests {

    /// The test-only member's name. On `vscode.window` because
    /// `defineVSCodeMember` refuses a namespace the shim does not know, and
    /// `window` is the namespace this primitive was built for.
    private static let captureMemberName = "__captureForTest"

    /// The global the trampoline caches under, spelled out because the last
    /// test has to pre-empt it. The same deliberate coupling
    /// `MainThreadCommandsTests.theEagerlyInstalledTrampolineIgnoresALatePreemptionAttempt`
    /// documents: the name is a documented part of the design, with its own
    /// doc comment on `VSCodeAPI.helperGlobalName`, so a test that must be
    /// updated when it changes is honest coupling.
    private static let trampolineGlobalName = "__vscodeAPITrampoline"

    // MARK: - Fixtures

    private func makeTempDirectory() throws -> URL {
        try ExtensionFixtures.makeTemporaryDirectory("VSCodeAPISettlementTests")
    }

    private func manifest(browser: String) throws -> ExtensionManifest {
        let json = """
        {
            "name": "settlement",
            "publisher": "test",
            "version": "1.0.0",
            "engines": { "vscode": "^1.74.0" },
            "browser": "\(browser)"
        }
        """
        return try JSONDecoder().decode(ExtensionManifest.self, from: Data(json.utf8))
    }

    private func makeHost(source: String, in directory: URL) throws -> ExtensionHost {
        let entryPath = "dist/web.js"
        try ExtensionFixtures.write(source, to: entryPath, in: directory)
        let loaded = LoadedExtension(
            manifest: try manifest(browser: entryPath),
            directory: directory
        )
        return ExtensionHost(loadedExtension: loaded)
    }

    /// An extension whose `activate` evaluates `expression` in its own module
    /// scope and hands the result to the capture member. `preamble` runs first,
    /// for the one fixture that needs to keep a settler reachable afterwards.
    private func source(handing expression: String, preamble: String = "") -> String {
        """
        var vscode = require('vscode');
        exports.activate = function () {
            \(preamble)
            vscode.window.\(Self.captureMemberName)(\(expression));
        };
        """
    }

    /// Activates a host over `source` with the capture member installed, and
    /// answers the host, its context, and the single value the extension
    /// handed over.
    ///
    /// The caller owns `host` and must `dispose()` it; returning it rather
    /// than tearing it down here is what keeps the context alive for the
    /// settlement that follows.
    private func capture(
        _ source: String,
        in directory: URL
    ) async throws -> (host: ExtensionHost, context: JSContext, value: JSValue) {
        let capture = ValueCapture()
        let host = try makeHost(source: source, in: directory)
        try host.defineVSCodeMember(
            namespacePath: "vscode.window",
            name: Self.captureMemberName,
            implementation: capture.implementation)
        try await host.activate()
        let context = try #require(host.javaScriptContext)
        #expect(capture.values.count == 1)
        let value = try #require(capture.values.first)
        return (host, context, value)
    }

    /// Starts `VSCodeAPI.settlement(of:in:)` on its own `Task` and answers the
    /// recorder its result will land in.
    ///
    /// A `Task` rather than a bare `await`, and only one test needs the
    /// difference: the deferred promise below has to be resolved from
    /// JavaScript *while* the primitive is suspended on it, which a test body
    /// already suspended inside `settlement(of:in:)` could never do.
    private func startSettlement(of value: JSValue, in context: JSContext) -> SettlementRecorder {
        let recorder = SettlementRecorder()
        let input = SettlementInputBox(value: value, context: context)
        Task { @MainActor in
            recorder.record(await VSCodeAPI.settlement(of: input.value, in: input.context))
        }
        return recorder
    }

    /// Polls `recorder` until the settlement lands, re-entering JavaScriptCore
    /// on every turn.
    ///
    /// That re-entry is the reason this is not a bare `await`. A `then`
    /// reaction on a native promise is a microtask, and
    /// `MainThreadWindowTests.waitForGlobal`'s own doc records the consequence
    /// measured in this bundle: it is never invoked synchronously no matter
    /// how settled the promise already is by the time `evaluateScript`
    /// returns. That helper polls by re-evaluating the expression it is
    /// waiting on; this one has nothing to read back — the answer arrives in
    /// Swift — so it evaluates a literal purely to give JavaScriptCore a
    /// boundary. 400 × 5 ms, the same budget.
    private func waitForSettlement(
        _ recorder: SettlementRecorder,
        in context: JSContext
    ) async throws -> VSCodeAPI.Settlement {
        for _ in 0..<400 {
            if let settlement = recorder.settlement { return settlement }
            context.evaluateScript("undefined")
            try await Task.sleep(for: .milliseconds(5))
        }
        return try #require(recorder.settlement, "The settlement never landed.")
    }

    /// `startSettlement` and `waitForSettlement` in one call, for every test
    /// that does not have to interleave JavaScript with the wait.
    private func settlement(of value: JSValue, in context: JSContext) async throws -> VSCodeAPI.Settlement {
        try await waitForSettlement(startSettlement(of: value, in: context), in: context)
    }

    /// The fulfilled value, with the failure recorded and `nil` answered
    /// otherwise, so a test reads as one `#require` rather than a `guard case`
    /// block.
    private func fulfilledValue(_ settlement: VSCodeAPI.Settlement) -> JSValue? {
        guard case .fulfilled(let value) = settlement else {
            Issue.record("Expected .fulfilled, got \(settlement)")
            return nil
        }
        return value
    }

    private func rejectionReason(_ settlement: VSCodeAPI.Settlement) -> JSValue? {
        guard case .rejected(let reason) = settlement else {
            Issue.record("Expected .rejected, got \(settlement)")
            return nil
        }
        return reason
    }

    // MARK: - 1. A plain array is fulfilled with itself

    /// The `showQuickPick(['a', 'b'])` half of the one-code-path claim.
    ///
    /// Asserts the array's *contents*, not merely that `.fulfilled` came back:
    /// a mutation that answers `.fulfilled` with a fresh empty array, with
    /// `undefined`, or with the trampoline's own record would satisfy the case
    /// check and fail here. Two elements, and the second one checked, so a
    /// mutation that fulfils with some other array the fixture also created
    /// cannot pass on length alone.
    @Test
    func aPlainArrayIsFulfilledWithThatSameArray() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let captured = try await capture(source(handing: "['alpha', 'beta']"), in: directory)
        defer { captured.host.dispose() }

        let settled = try await settlement(of: captured.value, in: captured.context)
        let items = try #require(fulfilledValue(settled))
        #expect(items.isArray)
        #expect(items.toArray()?.count == 2)
        #expect(items.atIndex(0)?.toString() == "alpha")
        #expect(items.atIndex(1)?.toString() == "beta")
    }

    // MARK: - 2. An already-resolved promise is fulfilled with what it resolved to

    /// The other half: the same call site, given a promise instead. Kills a
    /// mutation that fulfils with the *promise* rather than with the array it
    /// resolved to — which `.fulfilled` alone cannot tell apart, and which is
    /// exactly what `settledPromise(for:in:)`'s pass-through does.
    @Test
    func anAlreadyResolvedPromiseIsFulfilledWithTheResolvedArray() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let captured = try await capture(
            source(handing: "Promise.resolve(['gamma', 'delta'])"), in: directory)
        defer { captured.host.dispose() }

        let settled = try await settlement(of: captured.value, in: captured.context)
        let items = try #require(fulfilledValue(settled))
        #expect(items.isArray)
        #expect(items.toArray()?.count == 2)
        #expect(items.atIndex(0)?.toString() == "gamma")
        #expect(items.atIndex(1)?.toString() == "delta")
    }

    // MARK: - 3. A promise that resolves later is waited for

    /// The test that proves the wait is real rather than a synchronous read
    /// that happens to work on an already-settled promise. At the moment
    /// `settlement(of:in:)` is entered, the promise has no value at all: the
    /// only thing that can produce one is `globalThis.__resolveLater`, and
    /// this test does not call it until the primitive has demonstrably
    /// attached.
    ///
    /// "Demonstrably" is the fixture's job and is why it wraps `then`. A
    /// native promise gives no way to observe that a reaction was registered,
    /// so resolving after an arbitrary delay would prove only that the delay
    /// was long enough — and a test that resolved *before* the attachment
    /// would be test 2 again under a different name, passing for the wrong
    /// reason. The wrapper counts attachments and delegates to the promise's
    /// own `then`, so the settlement semantics under test stay
    /// `Promise.prototype.then`'s.
    ///
    /// No `setTimeout`: the wait here is for a step this test itself takes,
    /// not for time to pass.
    @Test
    func aPromiseThatResolvesLaterIsFulfilledWithWhatItLaterResolvedTo() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let preamble = """
        globalThis.__resolveLater = null;
                var pending = new Promise(function (resolve) { globalThis.__resolveLater = resolve; });
                globalThis.__attachCount = 0;
                var nativeThen = pending.then;
                pending.then = function () {
                    globalThis.__attachCount = globalThis.__attachCount + 1;
                    return nativeThen.apply(this, arguments);
                };
        """
        let captured = try await capture(
            source(handing: "pending", preamble: preamble), in: directory)
        defer { captured.host.dispose() }

        // Nothing has resolved it, and nothing else can: `__resolveLater` is
        // the only reference to the resolver.
        #expect(captured.context.evaluateScript("globalThis.__attachCount")?.toInt32() == 0)

        let recorder = startSettlement(of: captured.value, in: captured.context)
        var attached = false
        for _ in 0..<400 {
            if (captured.context.evaluateScript("globalThis.__attachCount")?.toInt32() ?? 0) > 0 {
                attached = true
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(attached, "The primitive never attached to the pending promise.")
        // Still nothing recorded: the primitive is suspended, not finished.
        #expect(recorder.settlement == nil)

        captured.context.evaluateScript("globalThis.__resolveLater(['late-one', 'late-two']);")

        let settled = try await waitForSettlement(recorder, in: captured.context)
        let items = try #require(fulfilledValue(settled))
        #expect(items.toArray()?.count == 2)
        #expect(items.atIndex(0)?.toString() == "late-one")
        #expect(items.atIndex(1)?.toString() == "late-two")
    }

    // MARK: - 4. A rejected promise answers `.rejected` with its reason

    /// The reason is carried back unchanged rather than paraphrased, which is
    /// what `message` being exactly `'nope'` pins — a mutation that rebuilds
    /// the error from the app's own wording, or that hands back the promise,
    /// fails here rather than at the case check.
    @Test
    func aRejectedPromiseAnswersRejectedWithItsOwnReason() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let captured = try await capture(
            source(handing: "Promise.reject(new Error('nope'))"), in: directory)
        defer { captured.host.dispose() }

        let settled = try await settlement(of: captured.value, in: captured.context)
        let reason = try #require(rejectionReason(settled))
        #expect(reason.forProperty("message")?.toString() == "nope")
    }

    // MARK: - 5. A `then` getter that throws rejects, and never reaches the host

    /// The test requirement 2 of this primitive's brief exists for, in two
    /// parts, because the second assertion is the whole point and an absent
    /// exception proves nothing unless the observation is known to be live.
    ///
    /// Part one is a control: an exception raised by ordinary extension code
    /// in this context genuinely does reach the context's `exceptionHandler`,
    /// which is `ExtensionHost.makeContext`'s handler, whose body is
    /// `pendingException = describe(exception)`. Part two then reads `.then`
    /// off a `Proxy`-shaped accessor that throws, and requires that the
    /// primitive answered `.rejected` with the getter's own error *and* that
    /// nothing arrived at the handler in between.
    ///
    /// Both assertions in part two are live against the mutant requirement 2
    /// exists to kill — an implementation that reads `.then` with
    /// `forProperty`. That read is `-[JSValue valueForProperty:]`, which on a
    /// throwing getter hands the exception to
    /// `-[JSContext valueFromNotifyException:]` and answers a `JSValue`
    /// holding **`undefined`**, not `nil` (`JSValue.mm:419-426`,
    /// `JSContext.mm:370-374`; `VSCodeAPI.CallOutcome.returned`'s own doc
    /// records the `undefined`-rather-than-`nil` answer for the missing-key
    /// case). Reading `undefined`, that implementation concludes "not a
    /// thenable" and answers `.fulfilled(value)` — so it fails the `#require`
    /// below. It also pushed the getter's error into the context's
    /// `exceptionHandler` on the way, which is what the message-count
    /// assertion catches, and that is the defect `thenFunction(of:in:)` exists
    /// to prevent: the exception gets attributed to whatever the host was
    /// doing at the time.
    @Test
    func aThrowingThenGetterRejectsWithoutReachingTheHostsExceptionHandler() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let captured = try await capture(
            source(handing: "{ get then() { throw new Error('getter-boom'); } }"), in: directory)
        defer { captured.host.dispose() }

        let recorder = ExceptionRecorder.install(on: captured.context)

        // Part one — the control. The seam really is live in this context.
        captured.context.evaluateScript("(function () { throw new Error('control-boom'); }());")
        #expect(recorder.messages.contains { $0.contains("control-boom") })

        // Part two — the claim.
        let baseline = recorder.messages.count
        let settled = try await settlement(of: captured.value, in: captured.context)
        let reason = try #require(rejectionReason(settled))
        #expect(reason.forProperty("message")?.toString() == "getter-boom")
        #expect(recorder.messages.count == baseline, "escaped: \(recorder.messages.dropFirst(baseline))")
    }

    // MARK: - 6. A `then` that throws when called rejects with the thrown value

    /// The other half of "extension code can throw from either step". The
    /// value is the extension's own `Error`, not a stand-in, which
    /// `message == 'call-boom'` pins.
    @Test
    func aThenThatThrowsWhenCalledRejectsWithTheThrownValue() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let captured = try await capture(
            source(handing: "{ then: function () { throw new Error('call-boom'); } }"),
            in: directory)
        defer { captured.host.dispose() }

        let settled = try await settlement(of: captured.value, in: captured.context)
        let reason = try #require(rejectionReason(settled))
        #expect(reason.forProperty("message")?.toString() == "call-boom")
    }

    // MARK: - 7. `resolve` then `reject`: the first settlement wins

    /// A hand-rolled `then` that calls both handlers. The answer must be the
    /// fulfilment — and the fulfilled *value*, so a mutation that lets the
    /// later rejection through, or that fulfils with the wrong argument,
    /// fails. Reaching the assertions at all is the other half of the test:
    /// a second `resume` on the same continuation is a `fatalError`, so an
    /// implementation without the box crashes the suite here rather than
    /// failing an expectation.
    @Test
    func resolveFollowedByRejectAnswersTheFulfilmentAndDoesNotTrap() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let thenable = """
        {
                    then: function (onFulfilled, onRejected) {
                        onFulfilled(['first-win']);
                        onRejected(new Error('too-late'));
                    }
                }
        """
        let captured = try await capture(source(handing: thenable), in: directory)
        defer { captured.host.dispose() }

        let settled = try await settlement(of: captured.value, in: captured.context)
        let items = try #require(fulfilledValue(settled))
        #expect(items.toArray()?.count == 1)
        #expect(items.atIndex(0)?.toString() == "first-win")
    }

    // MARK: - 8. `resolve` twice: the first value wins

    /// The same guard from the other direction, and it is not the test above
    /// in different clothing: that one pins which *handler* wins, this one
    /// pins which *call* does. Checking the element rather than the case is
    /// what makes it bite — a mutation that let the second `resolve` through
    /// would answer `.fulfilled` either way, and only the value tells them
    /// apart.
    @Test
    func resolveCalledTwiceAnswersTheFirstValueAndDoesNotTrap() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let thenable = """
        {
                    then: function (onFulfilled) {
                        onFulfilled(['once']);
                        onFulfilled(['twice']);
                    }
                }
        """
        let captured = try await capture(source(handing: thenable), in: directory)
        defer { captured.host.dispose() }

        let settled = try await settlement(of: captured.value, in: captured.context)
        let items = try #require(fulfilledValue(settled))
        #expect(items.toArray()?.count == 1)
        #expect(items.atIndex(0)?.toString() == "once")
    }

    // MARK: - 9. `resolve()` with no argument fulfils with `undefined`

    /// `isUndefined` specifically. "Not `nil`" would be satisfied by any
    /// value at all, including the `null` that a Swift `nil` bridged back
    /// through JavaScriptCore would become — and an extension's
    /// `if (result === undefined)` reads those two as different answers.
    @Test
    func resolveWithNoArgumentFulfilsWithUndefined() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let captured = try await capture(
            source(handing: "{ then: function (onFulfilled) { onFulfilled(); } }"),
            in: directory)
        defer { captured.host.dispose() }

        let settled = try await settlement(of: captured.value, in: captured.context)
        let value = try #require(fulfilledValue(settled))
        #expect(value.isUndefined)
    }

    // MARK: - 10. A context whose trampoline cannot answer `thenOf` is `.unavailable`

    /// `.unavailable` is reachable in this bundle, but not the way its doc
    /// phrase "no trampoline" suggests, and the difference is worth stating
    /// because it is what this fixture is built around. A bare `JSContext`
    /// does not lack a trampoline: `VSCodeAPI.sharedHelper(in:)` evaluates one
    /// into any context lazily, and `helperSource` is pure JavaScript that
    /// succeeds there. The reachable shape is a context whose trampoline
    /// *global is already taken* by an object that cannot answer the lookup —
    /// `sharedHelper(in:)` adopts whatever object it finds under that name,
    /// and `helperFunction("thenOf", in:)` then answers `nil`.
    ///
    /// Both halves are asserted, because the `.unavailable` half alone would
    /// pass against an implementation that answered `.unavailable` for every
    /// plain array. The control is the identical array in an untouched bare
    /// context: it is `.fulfilled`, so the pre-emption is what made the
    /// difference.
    @Test
    func aContextWhoseTrampolineCannotAnswerThenOfIsUnavailable() async throws {
        let preempted = try #require(JSContext())
        preempted.evaluateScript("""
        Object.defineProperty(globalThis, '\(Self.trampolineGlobalName)', {
            value: { call: function () { return { ok: true, value: undefined }; } },
            writable: false,
            enumerable: false,
            configurable: false
        });
        """)
        let preemptedItems = try #require(preempted.evaluateScript("['alpha', 'beta']"))
        let refused = await VSCodeAPI.settlement(of: preemptedItems, in: preempted)
        guard case .unavailable = refused else {
            Issue.record("Expected .unavailable, got \(refused)")
            return
        }

        // The control: the same value, in a context nothing pre-empted.
        let healthy = try #require(JSContext())
        let healthyItems = try #require(healthy.evaluateScript("['alpha', 'beta']"))
        let settled = await VSCodeAPI.settlement(of: healthyItems, in: healthy)
        let items = try #require(fulfilledValue(settled))
        #expect(items.atIndex(0)?.toString() == "alpha")
    }

    // MARK: - 11. `resolve` then a throw: the fulfilment wins over the throw

    /// The arm of the once-only guard tests 7 and 8 leave unpinned. Test 7
    /// pins which *handler* wins and test 8 which *call* to the same handler
    /// does; this is the only case where the competing settlement does not
    /// come from a handler at all — it comes from `settlement(of:in:)`'s own
    /// `.threw` arm, which runs after the fulfilment handler has already
    /// fired on the same stack frame and must not overwrite it.
    ///
    /// Three mutations, one assertion each. An implementation whose `.threw`
    /// arm overwrote the settlement answers `.rejected`, so `fulfilledValue`
    /// records an Issue. One that swallowed the throw but fulfilled with the
    /// wrong argument still answers `.fulfilled`, so only `'settled-first'`
    /// separates it. And one without the box at all resumes twice, which is a
    /// `fatalError` rather than a failed expectation — reaching the
    /// assertions is itself part of the test.
    @Test
    func resolveFollowedByAThrowAnswersTheFulfilmentAndNotTheThrownReason() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let thenable = """
        {
                    then: function (onFulfilled) {
                        onFulfilled(['settled-first']);
                        throw new Error('thrown-after');
                    }
                }
        """
        let captured = try await capture(source(handing: thenable), in: directory)
        defer { captured.host.dispose() }

        let settled = try await settlement(of: captured.value, in: captured.context)
        let items = try #require(fulfilledValue(settled))
        #expect(items.toArray()?.count == 1)
        #expect(items.atIndex(0)?.toString() == "settled-first")
    }
}
