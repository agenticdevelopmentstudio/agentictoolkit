import Testing
import Foundation
import JavaScriptCore
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// A non-suspending `ExtensionMessagePresenting` double: it records every
/// request and answers immediately, keyed by `request.message` rather than by
/// call order, so a suite that fires several calls in the same script turn
/// gets each one's own prepared answer regardless of how `Task` happens to
/// schedule them. A message with no entry answers `nil` (dismissed) — the
/// same default a real presenter with no items gives.
@MainActor
private final class RecordingMessagePresenter: ExtensionMessagePresenting {
    private(set) var requests: [ExtensionMessageRequest] = []
    var responseForMessage: [String: Int?] = [:]

    func presentMessage(_ request: ExtensionMessageRequest) async -> Int? {
        requests.append(request)
        return responseForMessage[request.message] ?? nil
    }
}

/// An `ExtensionMessagePresenting` double whose `presentMessage` suspends
/// until the test releases it — for the two tests that need a presentation
/// genuinely in flight rather than merely called: disposal racing an
/// in-flight presentation, and two calls whose overlap must be real, not
/// just two calls issued back-to-back and settled one at a time before the
/// next begins.
///
/// `waitUntilEntered(_:)` blocks until `count` calls are simultaneously
/// parked awaiting `release`, the same "wait for the real thing, not a
/// delay" shape `SuspendingFileSystemService` uses in
/// `MainThreadWorkspaceTests`. `release(at:with:)` resumes the call that
/// entered at that 0-based position, in call order, so a test can release
/// two overlapping calls in either order and confirm neither answer crosses
/// over to the other call.
@MainActor
private final class SuspendingMessagePresenter: ExtensionMessagePresenting {
    private(set) var requests: [ExtensionMessageRequest] = []
    private var releaseContinuations: [CheckedContinuation<Int?, Never>] = []
    private var enteredWaiters: [(threshold: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func waitUntilEntered(_ count: Int) async {
        if releaseContinuations.count >= count { return }
        await withCheckedContinuation { continuation in
            enteredWaiters.append((count, continuation))
        }
    }

    /// Removes the entry once released, not just resumes it — otherwise
    /// `waitUntilEntered` would count an already-released call as still
    /// parked, a trap for a future suite that releases and then waits again.
    func release(at index: Int, with result: Int?) {
        let continuation = releaseContinuations.remove(at: index)
        continuation.resume(returning: result)
    }

    func presentMessage(_ request: ExtensionMessageRequest) async -> Int? {
        requests.append(request)
        return await withCheckedContinuation { continuation in
            releaseContinuations.append(continuation)
            let enteredCount = releaseContinuations.count
            let satisfied = enteredWaiters.filter { enteredCount >= $0.threshold }
            enteredWaiters.removeAll { enteredCount >= $0.threshold }
            for waiter in satisfied {
                waiter.continuation.resume()
            }
        }
    }
}

/// `vscode.window` (task 5.5a): `showInformationMessage`,
/// `showWarningMessage` and `showErrorMessage`, wired onto a real
/// `ExtensionHost` and a recording or suspending `ExtensionMessagePresenting`
/// double — never `NSAlertMessagePresenter`, which this bundle has no UI to
/// drive and no business exercising: the point of this suite is the argument
/// parsing, the promise settlement, and the disposal races, all of which sit
/// in `MainThreadWindow` itself, upstream of AppKit.
@MainActor
@Suite
struct MainThreadWindowTests {

    // MARK: - Fixtures

    private func makeTempDirectory() throws -> URL {
        try ExtensionFixtures.makeTemporaryDirectory("MainThreadWindowTests")
    }

    private func manifest(name: String, browser: String) throws -> ExtensionManifest {
        let json = """
        {
            "name": "\(name)",
            "publisher": "test",
            "version": "1.0.0",
            "engines": { "vscode": "^1.74.0" },
            "browser": "\(browser)"
        }
        """
        return try JSONDecoder().decode(ExtensionManifest.self, from: Data(json.utf8))
    }

    /// Writes `source` as the extension's `browser` entry point and returns a
    /// host over the result. `MainThreadWindow` needs no `workspaceRoots`, so
    /// unlike `MainThreadWorkspaceTests.makeHost` this one omits it entirely
    /// rather than threading through a parameter nothing here would ever
    /// pass.
    private func makeHost(
        name: String = "alpha",
        source: String,
        entryPath: String = "dist/web.js",
        in directory: URL,
        ledger: NotImplementedLedger = NotImplementedLedger()
    ) throws -> ExtensionHost {
        try ExtensionFixtures.write(source, to: entryPath, in: directory)
        let loaded = LoadedExtension(
            manifest: try manifest(name: name, browser: entryPath),
            directory: directory
        )
        return ExtensionHost(loadedExtension: loaded, notImplementedLedger: ledger)
    }

    /// Installs all three of `window`'s members onto `host`'s `vscode.window`
    /// namespace, exactly as a later `ExtensionsCoordinator` task will.
    private func install(_ window: MainThreadWindow, on host: ExtensionHost) throws {
        try host.defineVSCodeMember(
            namespacePath: "vscode.window", name: "showInformationMessage",
            implementation: window.showInformationMessage)
        try host.defineVSCodeMember(
            namespacePath: "vscode.window", name: "showWarningMessage",
            implementation: window.showWarningMessage)
        try host.defineVSCodeMember(
            namespacePath: "vscode.window", name: "showErrorMessage",
            implementation: window.showErrorMessage)
    }

    /// Polls `expression` until it evaluates to something other than
    /// `null`/`undefined`, or gives up after two seconds — the same helper
    /// `MainThreadWorkspaceTests` uses (400 × 5 ms; measured —
    /// `MainThreadCommandsTests`' own version loops 200 times, not 400, so it
    /// is not named here), for the same reason: a `.then()` reaction is a
    /// microtask, never invoked synchronously no matter how settled the
    /// promise already is by the time `evaluateScript` returns.
    private func waitForGlobal(_ context: JSContext, _ expression: String) async throws -> JSValue? {
        for _ in 0..<400 {
            if let value = context.evaluateScript(expression), !value.isNull, !value.isUndefined {
                return value
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        return nil
    }

    // MARK: - 1. No items resolves `undefined`, message and severity verbatim

    /// Kills a mutation that resolves with `null`, with the message string
    /// itself, or with any other stand-in for "nothing chosen" — an
    /// extension's `if (result === undefined)` would read any of those as a
    /// different answer. Also kills a mutation that drops or mangles the
    /// message text, or that mis-tags the severity `showInformationMessage`
    /// is supposed to carry.
    @Test
    func noItemsResolvesUndefinedAndThePresenterSeesTheMessageVerbatimWithInformationSeverity() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingMessagePresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.window.showInformationMessage('hello world').then(function (result) {
                    globalThis.__settled = { ok: true, isUndefined: result === undefined };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: directory
        )
        let window = MainThreadWindow(
            presenter: presenter, notImplementedLedger: host.notImplementedLedger, extensionIdentifier: host.identifier)
        defer { host.dispose(); window.dispose() }
        try install(window, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)
        #expect(settled.forProperty("isUndefined")?.toBool() == true)

        #expect(presenter.requests.count == 1)
        let request = try #require(presenter.requests.first)
        #expect(request.message == "hello world")
        #expect(request.severity == .information)
        #expect(request.itemTitles.isEmpty)
    }

    // MARK: - 2. showWarningMessage and showErrorMessage carry distinguishable severities

    /// Two calls, one per member, in one activation. Kills a mutation that
    /// swaps `.warning` and `.error` between the two members, or that gives
    /// either the same severity as `showInformationMessage`. Looks each
    /// request up **by message** rather than by `presenter.requests`'
    /// position — matching `RecordingMessagePresenter`'s own stated contract
    /// — rather than depending on the FIFO scheduling of the two
    /// `Task { @MainActor }`s these two calls create in one script turn,
    /// which is not a guarantee this test should rely on.
    @Test
    func showWarningMessageAndShowErrorMessageCarryDistinguishableSeverities() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingMessagePresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.window.showWarningMessage('warn-msg');
                vscode.window.showErrorMessage('err-msg').then(function () {
                    globalThis.__settled = true;
                });
            };
            """,
            in: directory
        )
        let window = MainThreadWindow(
            presenter: presenter, notImplementedLedger: host.notImplementedLedger, extensionIdentifier: host.identifier)
        defer { host.dispose(); window.dispose() }
        try install(window, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        _ = try #require(await waitForGlobal(context, "globalThis.__settled"))

        #expect(presenter.requests.count == 2)
        let warnRequest = try #require(presenter.requests.first { $0.message == "warn-msg" })
        #expect(warnRequest.severity == .warning)
        let errRequest = try #require(presenter.requests.first { $0.message == "err-msg" })
        #expect(errRequest.severity == .error)
    }

    // MARK: - 3. String items reach the presenter as titles in order; index 1 resolves the second item

    /// Kills a mutation that reverses, drops, or otherwise reorders
    /// `itemTitles` relative to the arguments the extension passed, and a
    /// mutation that resolves with the wrong item for a given chosen index
    /// (off-by-one in either direction would resolve `"Alpha"` or `"Gamma"`
    /// here instead of `"Beta"`).
    @Test
    func stringItemsReachThePresenterAsTitlesInOrderAndIndexOneResolvesTheSecondItem() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingMessagePresenter()
        presenter.responseForMessage["pick one"] = 1
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.window.showInformationMessage('pick one', 'Alpha', 'Beta', 'Gamma').then(function (result) {
                    globalThis.__settled = { ok: true, result: result };
                });
            };
            """,
            in: directory
        )
        let window = MainThreadWindow(
            presenter: presenter, notImplementedLedger: host.notImplementedLedger, extensionIdentifier: host.identifier)
        defer { host.dispose(); window.dispose() }
        try install(window, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))

        let request = try #require(presenter.requests.first)
        #expect(request.itemTitles == ["Alpha", "Beta", "Gamma"])
        #expect(settled.forProperty("result")?.toString() == "Beta")
    }

    // MARK: - 4. A MessageItem object resolves with the same object — identity, not title

    /// Two items deliberately share a title (`"Retry"`). Kills a mutation
    /// that resolves by re-matching the chosen title against `itemTitles`
    /// instead of returning the original argument by index: a title-based
    /// match cannot distinguish these two objects and would either resolve
    /// the wrong one or resolve a value that fails both identity checks
    /// below.
    @Test
    func aMessageItemObjectResolvesWithTheSameObjectEvenWhenTitlesCollide() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingMessagePresenter()
        presenter.responseForMessage["conflict"] = 1
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                var itemA = { title: 'Retry' };
                var itemB = { title: 'Retry' };
                globalThis.__itemA = itemA;
                globalThis.__itemB = itemB;
                vscode.window.showWarningMessage('conflict', itemA, itemB).then(function (result) {
                    globalThis.__settled = {
                        isItemA: result === globalThis.__itemA,
                        isItemB: result === globalThis.__itemB
                    };
                });
            };
            """,
            in: directory
        )
        let window = MainThreadWindow(
            presenter: presenter, notImplementedLedger: host.notImplementedLedger, extensionIdentifier: host.identifier)
        defer { host.dispose(); window.dispose() }
        try install(window, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("isItemA")?.toBool() == false)
        #expect(settled.forProperty("isItemB")?.toBool() == true)
    }

    // MARK: - 5. `{ modal, detail }` is read as options, not as the first item

    /// Kills a mutation that treats a plain object argument as an item
    /// regardless of position (which would make `itemTitles` non-empty
    /// here, since `[object Object]` or a `title`-less object would either
    /// be rejected or wrongly accepted), and a mutation that drops `modal`
    /// or `detail` while still correctly recognising the argument as
    /// options.
    @Test
    func optionsArgumentIsReadAsOptionsNotAsAnItem() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingMessagePresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.window.showInformationMessage('with options', { modal: true, detail: 'd' }).then(function () {
                    globalThis.__settled = true;
                });
            };
            """,
            in: directory
        )
        let window = MainThreadWindow(
            presenter: presenter, notImplementedLedger: host.notImplementedLedger, extensionIdentifier: host.identifier)
        defer { host.dispose(); window.dispose() }
        try install(window, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        _ = try #require(await waitForGlobal(context, "globalThis.__settled"))

        let request = try #require(presenter.requests.first)
        #expect(request.itemTitles.isEmpty)
        #expect(request.isModal == true)
        #expect(request.detail == "d")
    }

    // MARK: - 6. An invalid item rejects, naming the argument index

    /// The invalid value (`99`) sits at argument index 2 — after the message
    /// (0) and an options object (1) — so this also kills a mutation that
    /// miscomputes where items start once an options argument has been
    /// consumed (which would name index 1, not 2, or accept `99` outright).
    @Test
    func anInvalidItemRejectsNamingTheArgumentIndex() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingMessagePresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.window.showErrorMessage('msg', { modal: true }, 99).then(
                    function () { globalThis.__settled = { ok: true }; },
                    function (error) { globalThis.__settled = { ok: false, message: error.message }; }
                );
            };
            """,
            in: directory
        )
        let window = MainThreadWindow(
            presenter: presenter, notImplementedLedger: host.notImplementedLedger, extensionIdentifier: host.identifier)
        defer { host.dispose(); window.dispose() }
        try install(window, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == false)
        let message = try #require(settled.forProperty("message")?.toString())
        #expect(message.contains("argument 2"))
        #expect(presenter.requests.isEmpty)
    }

    // MARK: - 7. dispose() while genuinely suspended rejects rather than delivering a result

    /// `SuspendingMessagePresenter.presentMessage` is actually parked on a
    /// continuation — confirmed by waiting for it to enter — before
    /// `dispose()` runs, and is released only afterward. Kills a mutation
    /// that removes or weakens the post-`await` `!self.isDisposed` guard in
    /// `presentMessagePromise`: without it, this test would observe
    /// `ok: true` with the presenter's answer delivered into a torn-down
    /// window instead of a "torn down" rejection.
    @Test
    func disposeWhileGenuinelySuspendedRejectsRatherThanDeliveringAResult() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = SuspendingMessagePresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                globalThis.run = function () {
                    vscode.window.showInformationMessage('suspend me').then(
                        function () { globalThis.__settled = { ok: true }; },
                        function (error) { globalThis.__settled = { ok: false, message: error.message }; }
                    );
                };
            };
            """,
            in: directory
        )
        let window = MainThreadWindow(
            presenter: presenter, notImplementedLedger: host.notImplementedLedger, extensionIdentifier: host.identifier)
        defer { host.dispose() }
        try install(window, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        context.evaluateScript("globalThis.run();")
        await presenter.waitUntilEntered(1)
        // `presentMessage` is now suspended, past the pre-flight guard and
        // before the post-await guard has run.
        window.dispose()
        presenter.release(at: 0, with: nil)

        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == false)
        #expect(settled.forProperty("message")?.toString()?.contains("torn down") == true)
    }

    // MARK: - 8. Two overlapping calls both settle, with the right result each

    /// Both calls are confirmed genuinely overlapping — `waitUntilEntered(2)`
    /// only returns once *both* are parked mid-`presentMessage` — and are
    /// then released **out of order** (the second call's continuation first),
    /// so a mutation that shares state between the two `SettlementBox`
    /// instances, or that resolves whichever promise happens to settle last
    /// with the wrong presenter answer, would cross the results: `__settledA`
    /// would come back `"B2"` or `__settledB` would come back `"A1"` instead
    /// of each answering its own call.
    @Test
    func twoOverlappingCallsBothSettleWithTheRightResultEach() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = SuspendingMessagePresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settledA = null;
                globalThis.__settledB = null;
                globalThis.run = function () {
                    vscode.window.showInformationMessage('call-a', 'A1', 'A2').then(function (r) {
                        globalThis.__settledA = r;
                    });
                    vscode.window.showWarningMessage('call-b', 'B1', 'B2').then(function (r) {
                        globalThis.__settledB = r;
                    });
                };
            };
            """,
            in: directory
        )
        let window = MainThreadWindow(
            presenter: presenter, notImplementedLedger: host.notImplementedLedger, extensionIdentifier: host.identifier)
        defer { host.dispose(); window.dispose() }
        try install(window, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        context.evaluateScript("globalThis.run();")
        await presenter.waitUntilEntered(2)
        // Both calls are now genuinely overlapping. Release the second call
        // first, deliberately out of arrival order.
        presenter.release(at: 1, with: 1)
        presenter.release(at: 0, with: 0)

        let settledA = try #require(await waitForGlobal(context, "globalThis.__settledA"))
        let settledB = try #require(await waitForGlobal(context, "globalThis.__settledB"))
        #expect(settledA.toString() == "A1")
        #expect(settledB.toString() == "B2")
        // By message, not position: `presenter.requests`' insertion order
        // depends on the same `Task { @MainActor }` FIFO scheduling
        // `RecordingMessagePresenter`'s doc comment says not to depend on.
        #expect(Set(presenter.requests.map(\.message)) == Set(["call-a", "call-b"]))
    }

    // MARK: - 9. An undefined `window` member still throws and is recorded

    /// Proves the three installs did not flatten the rest of `vscode.window`'s
    /// stubs: `showQuickPick` (task 5.5b's, not yet installed) still throws
    /// the shim's own `NotImplementedError` and is recorded in the ledger.
    /// Kills a mutation that installs the three members onto a fresh
    /// namespace object instead of the shim's existing `vscode.window` proxy,
    /// which would either make this call resolve as `undefined()` (a
    /// `TypeError`, not `NotImplementedError`) or silently drop the ledger
    /// recording.
    @Test
    func anUnimplementedWindowMemberRemainsAThrowingStub() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ledger = NotImplementedLedger()
        let presenter = RecordingMessagePresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__err = null;
                try {
                    vscode.window.showQuickPick(['a', 'b']);
                } catch (error) {
                    globalThis.__err = error.name;
                }
            };
            """,
            in: directory,
            ledger: ledger
        )
        let window = MainThreadWindow(
            presenter: presenter, notImplementedLedger: host.notImplementedLedger, extensionIdentifier: host.identifier)
        defer { host.dispose(); window.dispose() }
        try install(window, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__err")?.toString() == "NotImplementedError")
        #expect(ledger.accesses.map(\.memberPath) == ["vscode.window.showQuickPick"])
    }

    // MARK: - 10. `{ title: 'Reload' }` at argument 1 is an item, not options

    /// Kills a revert to the old `!isArray` classification rule: under that
    /// rule `{ title: 'Reload' }` is an object that is neither a string nor
    /// an array, so it would be swallowed as options and "Reload" would
    /// never reach the presenter as a button. VS Code's real rule
    /// (`isMessageItem`: truthy `title`) makes it the first item instead.
    /// Two items, in order, both reaching the presenter.
    @Test
    func aTitledObjectAtArgumentOneIsTheFirstItemWithTwoItems() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingMessagePresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.window.showInformationMessage(
                    'Reload?', { title: 'Reload' }, { title: 'Later' }
                ).then(function () {
                    globalThis.__settled = true;
                });
            };
            """,
            in: directory
        )
        let window = MainThreadWindow(
            presenter: presenter, notImplementedLedger: host.notImplementedLedger, extensionIdentifier: host.identifier)
        defer { host.dispose(); window.dispose() }
        try install(window, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        _ = try #require(await waitForGlobal(context, "globalThis.__settled"))

        let request = try #require(presenter.requests.first)
        #expect(request.itemTitles == ["Reload", "Later"])
        #expect(request.isModal == false)
    }

    /// The one-item form of the same fix: a lone `{ title: 'Reload' }` at
    /// argument 1 reaches the presenter as a single item, not as options with
    /// an empty item list.
    @Test
    func aTitledObjectAtArgumentOneIsTheFirstItemWithOneItem() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingMessagePresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.window.showInformationMessage('Reload?', { title: 'Reload' }).then(function () {
                    globalThis.__settled = true;
                });
            };
            """,
            in: directory
        )
        let window = MainThreadWindow(
            presenter: presenter, notImplementedLedger: host.notImplementedLedger, extensionIdentifier: host.identifier)
        defer { host.dispose(); window.dispose() }
        try install(window, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        _ = try #require(await waitForGlobal(context, "globalThis.__settled"))

        let request = try #require(presenter.requests.first)
        #expect(request.itemTitles == ["Reload"])
    }

    // MARK: - 12. An array at argument 1 is options, contributing no `modal`/`detail`

    /// Kills a re-added `isArrayArgument`-style carve-out: under that
    /// carve-out an array at argument 1 would be rejected as items are
    /// collected past it (arrays have no string `title`), or would otherwise
    /// change which arguments are items. VS Code's real rule needs no array
    /// special-case — an array's own `title` is `undefined`, so it already
    /// falls out as options, contributing no `modal` and no `detail`, and the
    /// items are exactly the arguments after it.
    @Test
    func anArrayAtArgumentOneIsOptionsContributingNoModalOrDetail() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingMessagePresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.window.showInformationMessage('with array', [1, 2, 3], 'Alpha', 'Beta').then(function () {
                    globalThis.__settled = true;
                });
            };
            """,
            in: directory
        )
        let window = MainThreadWindow(
            presenter: presenter, notImplementedLedger: host.notImplementedLedger, extensionIdentifier: host.identifier)
        defer { host.dispose(); window.dispose() }
        try install(window, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        _ = try #require(await waitForGlobal(context, "globalThis.__settled"))

        let request = try #require(presenter.requests.first)
        #expect(request.itemTitles == ["Alpha", "Beta"])
        #expect(request.isModal == false)
        #expect(request.detail == nil)
    }

    // MARK: - 13. A message whose `toString` throws rejects, and no request reaches the presenter

    /// The hostile object is built in JS inside the test script, exactly as
    /// the reviewer measured the underlying `JSValue.toString()` behaviour.
    /// Asserts both halves the defect touched: the call rejects (a mutation
    /// that reverts to unguarded `messageArgument.toString() ?? ""` would
    /// instead resolve with a blank message), *and* `presenter.requests` is
    /// empty (a mutation that only added the rejection but still presented
    /// something beforehand would still fail here).
    @Test
    func aMessageWhoseToStringThrowsRejectsAndPresentsNothing() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingMessagePresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                var hostile = { toString: function () { throw new Error('boom'); } };
                vscode.window.showInformationMessage(hostile).then(
                    function () { globalThis.__settled = { ok: true }; },
                    function (error) { globalThis.__settled = { ok: false, message: error.message }; }
                );
            };
            """,
            in: directory
        )
        let window = MainThreadWindow(
            presenter: presenter, notImplementedLedger: host.notImplementedLedger, extensionIdentifier: host.identifier)
        defer { host.dispose(); window.dispose() }
        try install(window, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == false)
        #expect(presenter.requests.isEmpty)
    }

    // MARK: - 14. A non-string message with a well-behaved `toString` is coerced and presented

    /// Guards against LB2's fix over-correcting into "reject everything
    /// non-string": a `toString` that returns normally is honoured, and the
    /// presenter still sees the call.
    @Test
    func aNonStringMessageWithAWellBehavedToStringIsCoercedAndPresented() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingMessagePresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                var polite = { toString: function () { return 'polite message'; } };
                vscode.window.showInformationMessage(polite).then(
                    function () { globalThis.__settled = { ok: true }; },
                    function (error) { globalThis.__settled = { ok: false, message: error.message }; }
                );
            };
            """,
            in: directory
        )
        let window = MainThreadWindow(
            presenter: presenter, notImplementedLedger: host.notImplementedLedger, extensionIdentifier: host.identifier)
        defer { host.dispose(); window.dispose() }
        try install(window, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)
        let request = try #require(presenter.requests.first)
        #expect(request.message == "polite message")
    }

    // MARK: - 15. A missing argument 0 rejects

    /// Specified in this task's original brief but never actually covered by
    /// a test until this round.
    @Test
    func aMissingMessageArgumentRejects() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingMessagePresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.window.showInformationMessage().then(
                    function () { globalThis.__settled = { ok: true }; },
                    function (error) { globalThis.__settled = { ok: false, message: error.message }; }
                );
            };
            """,
            in: directory
        )
        let window = MainThreadWindow(
            presenter: presenter, notImplementedLedger: host.notImplementedLedger, extensionIdentifier: host.identifier)
        defer { host.dispose(); window.dispose() }
        try install(window, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == false)
        let message = try #require(settled.forProperty("message")?.toString())
        #expect(message.contains("requires a message argument"))
        #expect(presenter.requests.isEmpty)
    }

    // MARK: - 16. `isCloseAffordance` parsing

    /// Asserts the indices positively in three directions: empty when no
    /// item carries `isCloseAffordance`, `[1]` when the second item does,
    /// and `[0, 2]` when two items do. An empty-array assertion on its own
    /// would pass just as well for a mutation that always answers empty, so
    /// this pairs it with both concrete cases in the same test, looked up by
    /// message rather than by position.
    ///
    /// The two-flagged case is what upstream keeps and this seam therefore
    /// has to: `extHostMessageService.ts` warns about the second one but
    /// still marks it, and `mainThreadMessageService.ts` keeps **both** out
    /// of the ordinary button list, letting the last fill the cancel slot.
    /// A model carrying only the first index cannot express that, and made
    /// the second render as an ordinary button.
    @Test
    func closeAffordanceIndicesReflectWhichItemsIfAnyAreMarkedCloseAffordance() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingMessagePresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.window.showWarningMessage('no affordance', { title: 'A' }, { title: 'B' });
                vscode.window.showWarningMessage(
                    'with affordance', { title: 'A' }, { title: 'B', isCloseAffordance: true }
                );
                vscode.window.showWarningMessage(
                    'two affordances',
                    { title: 'A', isCloseAffordance: true },
                    { title: 'B' },
                    { title: 'C', isCloseAffordance: true }
                ).then(function () {
                    globalThis.__settled = true;
                });
            };
            """,
            in: directory
        )
        let window = MainThreadWindow(
            presenter: presenter, notImplementedLedger: host.notImplementedLedger, extensionIdentifier: host.identifier)
        defer { host.dispose(); window.dispose() }
        try install(window, on: host)
        try await host.activate()

        let context = try #require(host.javaScriptContext)
        _ = try #require(await waitForGlobal(context, "globalThis.__settled"))

        let noAffordanceRequest = try #require(presenter.requests.first { $0.message == "no affordance" })
        #expect(noAffordanceRequest.closeAffordanceIndices.isEmpty)
        let withAffordanceRequest = try #require(presenter.requests.first { $0.message == "with affordance" })
        #expect(withAffordanceRequest.closeAffordanceIndices == [1])
        let twoAffordancesRequest = try #require(presenter.requests.first { $0.message == "two affordances" })
        #expect(twoAffordancesRequest.closeAffordanceIndices == [0, 2])
    }

    // MARK: - 17. `NSAlertMessagePresenter.buttonPlan(for:)` ordering

    /// Pins the position→item mapping the presenter renders, with requests
    /// built directly — no JS, no host, no presenter, no `NSAlert`. Every row
    /// is a concrete positive equality on the whole array, so a plan that is
    /// merely non-empty or merely the right length does not pass.
    ///
    /// Which mutation each row-group kills:
    ///
    /// - **No affordance (`[]` → `[0, 1, 2, nil]`, and the one-item
    ///   `[0, nil]`):** deleting the branch that appends the synthesized
    ///   `"Cancel"` slot — round 1's LB3 defect. Without it these answer
    ///   `[0, 1, 2]` and `[0]`.
    /// - **One affordance (`[0]` → `[1, 2, 0]`, `[1]` → `[0, 2, 1]`,
    ///   `[2]` → `[0, 1, 2]`):** dropping the skip, so the flagged item also
    ///   renders in its own position — that answers `[0, 1, 2, 0]` and
    ///   `[0, 1, 2, 1]`. The `[2]` row additionally pins that a flagged *last*
    ///   item still appears exactly once, in the slot: dropping the cancel
    ///   append answers `[0, 1]`.
    /// - **Two affordances (`[0, 2]` → `[1, 2]`) and all three
    ///   (`[0, 1, 2]` → `[2]`):** `request.closeAffordanceIndices.last` →
    ///   `.first`, which answers `[1, 0]` and `[0]`; and
    ///   `where !closeAffordanceIndices.contains(index)` →
    ///   `where index != request.closeAffordanceIndices.first` (round 1's
    ///   exact defect moved into the presenter), which answers `[1, 2, 2]`
    ///   for both. Neither mutation is visible with fewer than two flagged
    ///   items, which is why both rows are here.
    /// - **One item, flagged (`[0]` → `[0]`):** the flagged item is the whole
    ///   plan; a synthesized `"Cancel"` appended regardless —
    ///   `plan.append(nil)` in place of
    ///   `plan.append(request.closeAffordanceIndices.last)` — would answer
    ///   `[nil]`, since the loop has already skipped the flagged item and
    ///   nothing precedes the cancel slot.
    ///
    /// **The zero-items case is deliberately not a row here.**
    /// `presentMessage` short-circuits on `request.itemTitles.isEmpty` with a
    /// single "OK" before `buttonPlan(for:)` is ever called, so a row for it
    /// would pin a scenario that never occurs in production.
    @Test
    func buttonPlanOrdersButtonsAndFillsTheCancelSlotFromTheLastCloseAffordance() {
        func plan(items: [String], closeAffordanceIndices: [Int]) -> [Int?] {
            NSAlertMessagePresenter.buttonPlan(
                for: ExtensionMessageRequest(
                    severity: .warning,
                    message: "m",
                    detail: nil,
                    isModal: true,
                    itemTitles: items,
                    closeAffordanceIndices: closeAffordanceIndices
                )
            )
        }

        let abc = ["A", "B", "C"]
        #expect(plan(items: abc, closeAffordanceIndices: []) == [0, 1, 2, nil])
        #expect(plan(items: abc, closeAffordanceIndices: [0]) == [1, 2, 0])
        #expect(plan(items: abc, closeAffordanceIndices: [1]) == [0, 2, 1])
        #expect(plan(items: abc, closeAffordanceIndices: [2]) == [0, 1, 2])
        #expect(plan(items: abc, closeAffordanceIndices: [0, 2]) == [1, 2])
        #expect(plan(items: abc, closeAffordanceIndices: [0, 1, 2]) == [2])
        #expect(plan(items: ["A"], closeAffordanceIndices: []) == [0, nil])
        #expect(plan(items: ["A"], closeAffordanceIndices: [0]) == [0])
    }

    // MARK: - 18. `NSAlertMessagePresenter.escapeKeyEquivalentPosition(in:)`

    /// Pins which button, if any, gets Escape — over plans written inline as
    /// `[Int?]` literals, so no `NSAlert`, no presenter and no host are
    /// involved. Every row is a concrete positive equality: an answer, or
    /// `nil` asserted against the two plans that must have none.
    ///
    /// Which mutation each row-group kills:
    ///
    /// - **Multi-entry plans (`[0, 1, 2, nil]` → `3`, `[1, 2, 0]` → `2`,
    ///   `[1, 2]` → `1`, `[0, nil]` → `1`):** returning a fixed `0`, or `nil`
    ///   unconditionally — every row here expects a non-zero, non-`nil`
    ///   answer. Their expectations are three different numbers, each its own
    ///   plan's `count - 1`, so an off-by-one (`count`, or `count - 2`) fails
    ///   them too.
    /// - **One-entry plans (`[0]` → `nil`, `[2]` → `nil`):** returning
    ///   `plan.count - 1` unconditionally, the shape this function replaced,
    ///   which answers `0` for both; and loosening the guard to
    ///   `plan.count > 0`, which answers the same. These are the two
    ///   one-entry plans `buttonPlan(for:)` actually produces — one item that
    ///   is flagged, and three items with the last of three flagged — not
    ///   invented shapes.
    /// - **Last entry `nil` vs. an item index, on both sides of the guard**
    ///   (`[0, 1, 2, nil]` and `[0, nil]` against `[1, 2, 0]` and `[1, 2]`;
    ///   `[0]` and `[2]` among the one-entry rows): a mutation keying on what
    ///   fills the cancel slot rather than on how many entries the plan has.
    ///   The answer depends only on the count, and these rows say so.
    ///
    /// **The empty plan is deliberately not a row.** `buttonPlan(for:)`
    /// always appends a cancel slot, so it never returns an empty array, and
    /// `presentMessage` short-circuits on empty `itemTitles` before reaching
    /// it at all. Asserting on `[]` would pin a scenario that never occurs.
    /// The code still handles it — `plan.count > 1` is false for an empty
    /// plan — it is only the assertion that is withheld.
    @Test
    func escapeKeyEquivalentPositionIsTheCancelSlotOnlyWhenThePlanHasMoreThanOneButton() {
        func escapePosition(_ plan: [Int?]) -> Int? {
            NSAlertMessagePresenter.escapeKeyEquivalentPosition(in: plan)
        }

        #expect(escapePosition([0, 1, 2, nil]) == 3)
        #expect(escapePosition([1, 2, 0]) == 2)
        #expect(escapePosition([1, 2]) == 1)
        #expect(escapePosition([0, nil]) == 1)
        #expect(escapePosition([0]) == nil)
        #expect(escapePosition([2]) == nil)
    }
}
