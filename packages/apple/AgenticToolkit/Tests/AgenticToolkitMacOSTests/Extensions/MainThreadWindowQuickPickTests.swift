import Testing
import Foundation
import JavaScriptCore
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// A non-suspending `ExtensionQuickPickPresenting` double: it records every
/// request, fires `onHighlight` for each index in `highlightIndices` before
/// answering, and answers `response`.
///
/// `response` defaults to `nil` — dismissed — which is the same default a
/// real picker the user closes without choosing gives, and is deliberately
/// **not** `[]`: `[]` is a real, different answer, and a double whose default
/// conflated the two would make the test that pins that distinction pass for
/// the wrong reason.
@MainActor
private final class RecordingQuickPickPresenter: ExtensionQuickPickPresenting {
    private(set) var requests: [ExtensionQuickPickRequest] = []
    var response: [Int]?
    var highlightIndices: [Int] = []

    func presentQuickPick(
        _ request: ExtensionQuickPickRequest,
        onHighlight: @escaping (Int) -> Void
    ) async -> [Int]? {
        requests.append(request)
        for index in highlightIndices {
            onHighlight(index)
        }
        return response
    }
}

/// An `ExtensionQuickPickPresenting` double whose `presentQuickPick` suspends
/// until the test releases it — the `SuspendingMessagePresenter` shape from
/// `MainThreadWindowTests`, for the same reason: a disposal race is only a
/// race if the presentation is genuinely in flight when `dispose()` runs, and
/// "issue the call, then dispose" does not establish that.
///
/// `waitUntilEntered(_:)` returns only once `count` calls are simultaneously
/// parked on a continuation.
@MainActor
private final class SuspendingQuickPickPresenter: ExtensionQuickPickPresenting {
    private(set) var requests: [ExtensionQuickPickRequest] = []
    private var releaseContinuations: [CheckedContinuation<[Int]?, Never>] = []
    private var enteredWaiters: [(threshold: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func waitUntilEntered(_ count: Int) async {
        if releaseContinuations.count >= count { return }
        await withCheckedContinuation { continuation in
            enteredWaiters.append((count, continuation))
        }
    }

    /// Removes the entry as well as resuming it, matching
    /// `SuspendingMessagePresenter.release(at:with:)`.
    func release(at index: Int, with result: [Int]?) {
        let continuation = releaseContinuations.remove(at: index)
        continuation.resume(returning: result)
    }

    func presentQuickPick(
        _ request: ExtensionQuickPickRequest,
        onHighlight: @escaping (Int) -> Void
    ) async -> [Int]? {
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

/// The message seam, for a suite that presents no message.
/// `MainThreadWindow.init` does not default `presenter:` either, so every
/// construction here has to name one, and one that records an `Issue` turns a
/// `showQuickPick` that somehow reached the message presenter into a failure
/// rather than a silent pass.
@MainActor
private final class UnusedMessagePresenter: ExtensionMessagePresenting {
    func presentMessage(_ request: ExtensionMessageRequest) async -> Int? {
        Issue.record("presentMessage was called by a suite that exercises no message.")
        return nil
    }
}

/// The input box seam, for a suite that presents no input box, on
/// `UnusedMessagePresenter`'s own reasoning: `MainThreadWindow.init` does not
/// default `inputBoxPresenter:` either.
@MainActor
private final class UnusedInputBoxPresenter: ExtensionInputBoxPresenting {
    func presentInputBox(
        _ request: ExtensionInputBoxRequest,
        validate: @escaping (String) async -> ExtensionInputValidation?
    ) async -> String? {
        Issue.record("presentInputBox was called by a suite that exercises no input box.")
        return nil
    }
}

/// `vscode.window.showQuickPick` (task 5.5b-ii), wired onto a real
/// `ExtensionHost` and an `ExtensionQuickPickPresenting` double.
///
/// A separate suite from `MainThreadWindowTests` rather than more cases in
/// it: the two exercise different members through different seams, and this
/// one's fixtures answer `[Int]?` where that one's answer `Int?`. The
/// fixtures below are deliberate near-copies of that file's — they are
/// `private` to its own suite type and cannot be shared without promoting
/// them into production or a shared test target, which is a larger move than
/// one duplicated `makeHost` justifies.
///
/// No conformer of `ExtensionQuickPickPresenting` ships in the module yet
/// (task 5.5b-iv builds the panel), so every presenter here is a double by
/// necessity rather than by the choice `MainThreadWindowTests` makes about
/// `NSAlertMessagePresenter`.
@MainActor
@Suite
struct MainThreadWindowQuickPickTests {

    // MARK: - Fixtures

    private func makeTempDirectory() throws -> URL {
        try ExtensionFixtures.makeTemporaryDirectory("MainThreadWindowQuickPickTests")
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

    /// Installs `showQuickPick` onto `vscode.window` and the
    /// `QuickPickItemKind` table onto **`vscode`** — the top-level namespace,
    /// not `vscode.window`, because that is where the declaration puts the
    /// enum and where `MainThreadWindow.quickPickItemKindMembers`' own doc
    /// says an installer must put it. Exactly what a later
    /// `ExtensionsCoordinator` task will do.
    private func install(_ window: MainThreadWindow, on host: ExtensionHost) throws {
        try host.defineVSCodeMember(
            namespacePath: "vscode.window", name: "showQuickPick",
            implementation: window.showQuickPick)
        try host.defineVSCodeMember(
            namespacePath: "vscode", name: "QuickPickItemKind",
            implementation: MainThreadWindow.quickPickItemKindMembers)
    }

    /// Polls `expression` until it is neither `null` nor `undefined`, or gives
    /// up after two seconds (400 × 5 ms) — `MainThreadWindowTests`' own
    /// helper, for its stated reason: a `.then()` reaction is a microtask and
    /// is never invoked synchronously, however settled the promise already is.
    private func waitForGlobal(_ context: JSContext, _ expression: String) async throws -> JSValue? {
        for _ in 0..<400 {
            if let value = context.evaluateScript(expression), !value.isNull, !value.isUndefined {
                return value
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        return nil
    }

    /// Builds a window over `presenter`, installs it on `host`, and activates.
    private func activate(
        _ host: ExtensionHost,
        presenter: ExtensionQuickPickPresenting
    ) async throws -> MainThreadWindow {
        let window = MainThreadWindow(
            presenter: UnusedMessagePresenter(), quickPickPresenter: presenter,
            inputBoxPresenter: UnusedInputBoxPresenter(),
            notImplementedLedger: host.notImplementedLedger, extensionIdentifier: host.identifier)
        try install(window, on: host)
        try await host.activate()
        return window
    }

    // MARK: - 1. Identity, not label, is what resolves

    /// Two items with the **same** label, with the presenter choosing the
    /// second. Kills a mutation that resolves by re-matching the chosen
    /// label against the items, or that rebuilds a fresh object from the
    /// parsed `ExtensionQuickPickItem`: either would hand back `items[0]`,
    /// and `result === items[1]` would be `false` while a label comparison
    /// still passed. Also kills a mutation that resolves the index itself.
    @Test
    func aChosenItemResolvesAsTheExtensionsOwnObjectEvenWhenTwoItemsShareALabel() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingQuickPickPresenter()
        presenter.response = [1]
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                var items = [{ label: 'dup' }, { label: 'dup' }];
                globalThis.__items = items;
                vscode.window.showQuickPick(items).then(function (result) {
                    globalThis.__settled = {
                        ok: true, first: result === items[0], second: result === items[1]
                    };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)
        #expect(settled.forProperty("first")?.toBool() == false)
        #expect(settled.forProperty("second")?.toBool() == true)
    }

    // MARK: - 2. A string element is its own label

    /// Kills a mutation that rejects a string element, or that reads its
    /// `label` property (a string has none) and produces an empty label. The
    /// order assertion additionally kills a mutation that reverses or sorts
    /// the items on the way to the presenter.
    ///
    /// The resolution is checked with `===` against the caller's own array
    /// element rather than against a literal, which is the identity rule
    /// applied to the string overload. It is a weaker instrument here than in
    /// the object case above — JavaScript compares two equal strings `===`
    /// whatever their provenance — so the same-label object test is what
    /// actually pins identity; this one pins that the *right* element comes
    /// back.
    @Test
    func stringElementsBecomeLabelOnlyItemsInTheOrderSupplied() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingQuickPickPresenter()
        presenter.response = [0]
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                var items = ['zulu', 'alpha', 'mike'];
                vscode.window.showQuickPick(items).then(function (result) {
                    globalThis.__settled = { ok: true, value: result, same: result === items[0] };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)
        #expect(settled.forProperty("value")?.toString() == "zulu")
        #expect(settled.forProperty("same")?.toBool() == true)

        let request = try #require(presenter.requests.first)
        #expect(request.items.map(\.label) == ["zulu", "alpha", "mike"])
        #expect(request.items.allSatisfy { $0.description == nil && $0.detail == nil })
        #expect(request.items.allSatisfy { !$0.isPicked && !$0.alwaysShow && !$0.isSeparator })
    }

    // MARK: - 3. Every `QuickPickItem` field carried

    /// Kills a mutation that drops `description`, `detail`, `picked` or
    /// `alwaysShow`, and one that swaps `description` with `detail` — the two
    /// carry distinct strings here precisely so a swap is visible. Also kills
    /// a mutation that coerces a non-string `description` (`7`) into `"7"`
    /// instead of omitting it: these are decoration, and a number is not a
    /// description.
    @Test
    func itemFieldsAreCarriedAndANonStringDescriptionIsOmittedRatherThanCoerced() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingQuickPickPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                var items = [
                    { label: 'one', description: 'desc-1', detail: 'det-1', picked: true, alwaysShow: true },
                    { label: 'two', description: 7 }
                ];
                vscode.window.showQuickPick(items).then(function () {
                    globalThis.__settled = { ok: true };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)

        let request = try #require(presenter.requests.first)
        #expect(request.items.count == 2)
        let first = try #require(request.items.first)
        #expect(first.description == "desc-1")
        #expect(first.detail == "det-1")
        #expect(first.isPicked)
        #expect(first.alwaysShow)
        let second = try #require(request.items.last)
        #expect(second.description == nil)
        #expect(!second.isPicked)
        #expect(!second.alwaysShow)
    }

    // MARK: - 4. A separator is marked, and carries only its label

    /// `kind: vscode.QuickPickItemKind.Separator` read through the installed
    /// table, so this test also proves the enum is reachable from extension
    /// code under the namespace `install(_:on:)` puts it in. Kills a mutation
    /// that ignores `kind` entirely (the row would arrive
    /// `isSeparator == false`), and one that sets the flag while still
    /// carrying the row's other fields: the separator object here deliberately
    /// supplies `description`, `detail`, `picked` and `alwaysShow`, and all
    /// four must be defaulted, because "The only property that applies is
    /// {@link QuickPickItem.label label}. All other properties on {@link
    /// QuickPickItem} will be ignored and have no effect."
    /// (`vscode.d.ts:1881-1884`) — an implementation that merely sets the
    /// flag passes a weaker test than this one.
    @Test
    func anItemWhoseKindIsSeparatorIsMarkedAsOneAndDropsItsOtherFields() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingQuickPickPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                var items = [
                    {
                        label: 'Group',
                        kind: vscode.QuickPickItemKind.Separator,
                        description: 'ignored',
                        detail: 'ignored too',
                        picked: true,
                        alwaysShow: true
                    },
                    { label: 'row', kind: vscode.QuickPickItemKind.Default, description: 'kept' }
                ];
                vscode.window.showQuickPick(items).then(function () {
                    globalThis.__settled = { ok: true };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)

        let request = try #require(presenter.requests.first)
        let separator = try #require(request.items.first)
        #expect(separator.isSeparator)
        #expect(separator.label == "Group")
        #expect(separator.description == nil)
        #expect(separator.detail == nil)
        #expect(!separator.isPicked)
        #expect(!separator.alwaysShow)
        let row = try #require(request.items.last)
        #expect(!row.isSeparator)
        #expect(row.description == "kept")
    }

    // MARK: - 5. `kind` is compared as a number, not coerced

    /// A `kind` of the **string** `'-1'`, and one of `true`. Kills a mutation
    /// that compares `kind` after a `toInt32()` coercion or by truthiness:
    /// either would mark one of these a separator, and neither is
    /// `QuickPickItemKind.Separator`, which is the number `-1`.
    @Test
    func aNonNumericKindIsNeverTreatedAsASeparator() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingQuickPickPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                var items = [{ label: 'a', kind: '-1' }, { label: 'b', kind: true }];
                vscode.window.showQuickPick(items).then(function () {
                    globalThis.__settled = { ok: true };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)

        let request = try #require(presenter.requests.first)
        #expect(request.items.map(\.label) == ["a", "b"])
        #expect(request.items.allSatisfy { !$0.isSeparator })
    }

    // MARK: - 6. A thenable items argument is awaited

    /// The items arrive as a `Promise` that resolves on a later microtask.
    /// Kills a mutation that drops `VSCodeAPI.settlement(of:in:)` and
    /// requires argument 0 to be an array synchronously — the call would
    /// reject "neither an array nor a promise of one" instead of presenting a
    /// two-row picker.
    @Test
    func aPromiseOfItemsIsAwaitedBeforeThePickerIsPresented() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingQuickPickPresenter()
        presenter.response = [1]
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                var later = Promise.resolve().then(function () { return ['p-one', 'p-two']; });
                vscode.window.showQuickPick(later).then(function (result) {
                    globalThis.__settled = { ok: true, value: result };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)
        #expect(settled.forProperty("value")?.toString() == "p-two")
        #expect(try #require(presenter.requests.first).items.map(\.label) == ["p-one", "p-two"])
    }

    // MARK: - 7. A rejected items promise passes the reason through

    /// Kills a mutation that rewrites the rejection into this member's own
    /// wording, or that swallows it and resolves `undefined`: the extension's
    /// `Error` carries a message only a pass-through preserves, and the
    /// picker must never have been presented.
    @Test
    func aRejectedItemsPromiseRejectsWithTheExtensionsOwnReasonAndPresentsNothing() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingQuickPickPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                var failing = Promise.reject(new Error('items blew up'));
                vscode.window.showQuickPick(failing).then(function () {
                    globalThis.__settled = { ok: true };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == false)
        #expect(settled.forProperty("message")?.toString() == "items blew up")
        // No positive assertion is available here: `requests` is the
        // recorder's only observable, and the items promise's rejection is
        // what settles the call — there is never an array to build a
        // request from.
        #expect(presenter.requests.isEmpty)
    }

    // MARK: - 8. A non-array items argument rejects

    /// Kills a mutation that treats a non-array argument 0 as an empty item
    /// list and presents an empty picker: an extension that passed a number
    /// by mistake would then see a dismissal rather than an error. Covers
    /// both the bare non-array value and a promise that fulfils with one,
    /// since `VSCodeAPI.settlement` answers a non-thenable with itself and a
    /// mutation could plausibly special-case only the synchronous form.
    @Test
    func aNonArrayItemsArgumentRejectsAndPresentsNothing() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingQuickPickPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                var calls = [
                    vscode.window.showQuickPick(42),
                    vscode.window.showQuickPick(Promise.resolve(42))
                ];
                Promise.all(calls).then(function () {
                    globalThis.__settled = { ok: true };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == false)
        let message = try #require(settled.forProperty("message")?.toString())
        #expect(message.contains("vscode.window.showQuickPick"))
        #expect(message.contains("neither an array nor a promise of one"))
        // No positive assertion is available here: `requests` is the
        // recorder's only observable, and both calls reject while parsing
        // argument 0 — before either would produce a request to record.
        #expect(presenter.requests.isEmpty)
    }

    // MARK: - 9. An unreadable element rejects, naming its index

    /// Two calls in one activation, at two different indices. The first has a
    /// bare **number** at `items[1]`; the second an object whose `label` is a
    /// number, at `items[0]`.
    ///
    /// Together they kill three mutations, and each is the one only this pair
    /// catches: dropping an unreadable row and presenting the survivors — a
    /// silently shortened picker is exactly what this rejection exists to
    /// prevent, and `presenter.requests` would not be empty; reporting a
    /// fixed or off-by-one index, which the two differing indices expose; and
    /// dropping the `labelValue.isString` check, which would coerce
    /// `{ label: 5 }` into the label `"5"` and let the second call through
    /// while the first still rejected.
    @Test
    func anUnreadableElementRejectsNamingItsOwnIndexAndALabelMustBeAString() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingQuickPickPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                var messages = {};
                function record(key) {
                    return function (error) {
                        messages[key] = error.message;
                        if (messages.number && messages.label) {
                            globalThis.__settled = { ok: false, number: messages.number, label: messages.label };
                        }
                    };
                }
                vscode.window.showQuickPick(['fine', 42, 'also fine']).then(function () {
                    globalThis.__settled = { ok: true, which: 'number' };
                }, record('number'));
                vscode.window.showQuickPick([{ label: 5 }]).then(function () {
                    globalThis.__settled = { ok: true, which: 'label' };
                }, record('label'));
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == false)
        let numberMessage = try #require(settled.forProperty("number")?.toString())
        #expect(numberMessage.contains("items[1]"))
        #expect(numberMessage.contains("neither a string nor an object with a string 'label'"))
        let labelMessage = try #require(settled.forProperty("label")?.toString())
        #expect(labelMessage.contains("items[0]"))
        #expect(labelMessage.contains("neither a string nor an object with a string 'label'"))
        // No positive assertion is available here: `requests` is the
        // recorder's only observable, and both calls reject while parsing an
        // element, before either finishes building a request.
        #expect(presenter.requests.isEmpty)
    }

    // MARK: - 10. A missing items argument rejects

    /// Kills a mutation that defaults a missing argument 0 to an empty array
    /// and presents an empty picker. `showQuickPick()` has no overload in the
    /// declaration, so there is nothing to show and nothing to guess.
    @Test
    func aMissingItemsArgumentRejectsRatherThanPresentingAnEmptyPicker() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingQuickPickPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.window.showQuickPick().then(function () {
                    globalThis.__settled = { ok: true };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == false)
        #expect(try #require(settled.forProperty("message")?.toString()).contains("requires an items argument"))
        // No positive assertion is available here: `requests` is the
        // recorder's only observable, and there is no argument 0 at all to
        // read, so nothing about a request is ever built.
        #expect(presenter.requests.isEmpty)
    }

    // MARK: - 11. A non-object argument 1 rejects

    /// Kills a mutation that ignores an unusable options argument, or that
    /// coerces a string into an options object with every field `undefined`:
    /// an extension that passed its cancellation token in slot 1 by mistake
    /// deserves an error rather than a picker with silently-lost options.
    @Test
    func aNonObjectOptionsArgumentRejectsAndPresentsNothing() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingQuickPickPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.window.showQuickPick(['a'], 'not-options').then(function () {
                    globalThis.__settled = { ok: true };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == false)
        let message = try #require(settled.forProperty("message")?.toString())
        #expect(message.contains("argument 1 is neither an options object nor undefined"))
        // No positive assertion is available here: `requests` is the
        // recorder's only observable, and argument 1 is rejected before
        // argument 0's items are ever turned into a request.
        #expect(presenter.requests.isEmpty)
    }

    // MARK: - 12. `undefined` and `null` in slot 1 are absence, not error

    /// Three calls: no argument 1, an explicit `undefined`, and an explicit
    /// `null`. Kills a mutation that tests only `arguments.count` (the
    /// explicit `undefined` would then take the object path and reject) and a
    /// mutation that drops `!arguments[1].isNull` from the guard at
    /// `MainThreadWindow.swift:1076`: with that check gone, `null` reaches
    /// `arguments[1].isObject` at `:1077`, which is `false` for `null` —
    /// `JSValueIsObject` does not follow `typeof null === 'object'` — so the
    /// third call would reject instead of building its request, and this
    /// test's `ok == true` assertion catches that. Every request arrives with
    /// the documented defaults.
    @Test
    func absentUndefinedAndNullOptionsAllMeanEveryDefault() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingQuickPickPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                var calls = [
                    vscode.window.showQuickPick(['a']),
                    vscode.window.showQuickPick(['b'], undefined),
                    vscode.window.showQuickPick(['c'], null)
                ];
                Promise.all(calls).then(function () {
                    globalThis.__settled = { ok: true };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)

        #expect(presenter.requests.count == 3)
        #expect(presenter.requests.allSatisfy { $0.title == nil && $0.placeHolder == nil && $0.prompt == nil })
        #expect(presenter.requests.allSatisfy { !$0.canPickMany && !$0.ignoreFocusOut })
        #expect(presenter.requests.allSatisfy { !$0.matchOnDescription && !$0.matchOnDetail })
    }

    // MARK: - 13. Every option field reaches the request

    /// `matchOnDescription` and `matchOnDetail` are given **different**
    /// values, and `canPickMany`/`ignoreFocusOut` likewise, so a mutation
    /// that swaps either pair, or that hard-codes one of the four, changes an
    /// assertion here. The three strings are distinct for the same reason.
    @Test
    func titlePlaceHolderPromptAndTheFourBooleansAllReachTheRequest() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingQuickPickPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.window.showQuickPick(['a'], {
                    title: 'the-title',
                    placeHolder: 'the-place',
                    prompt: 'the-prompt',
                    canPickMany: false,
                    matchOnDescription: true,
                    matchOnDetail: false,
                    ignoreFocusOut: true
                }).then(function () {
                    globalThis.__settled = { ok: true };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)

        let request = try #require(presenter.requests.first)
        #expect(request.title == "the-title")
        #expect(request.placeHolder == "the-place")
        #expect(request.prompt == "the-prompt")
        #expect(!request.canPickMany)
        #expect(request.matchOnDescription)
        #expect(!request.matchOnDetail)
        #expect(request.ignoreFocusOut)
    }

    // MARK: - 14. `canPickMany` resolves an array of the original values

    /// Kills a mutation that resolves the first pick alone when
    /// `canPickMany` is set — an extension doing `result.length` would get
    /// `undefined` — and one that resolves rebuilt objects rather than the
    /// extension's own, which the two identity assertions catch. The chosen
    /// indices are `[2, 0]`, out of ascending order, so a mutation that sorts
    /// the presenter's answer is visible too.
    @Test
    func canPickManyResolvesAnArrayOfTheOriginalValuesInThePresentersOrder() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingQuickPickPresenter()
        presenter.response = [2, 0]
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                var items = [{ label: 'a' }, { label: 'b' }, { label: 'c' }];
                vscode.window.showQuickPick(items, { canPickMany: true }).then(function (result) {
                    globalThis.__settled = {
                        ok: true,
                        isArray: Array.isArray(result),
                        length: result.length,
                        firstIsC: result[0] === items[2],
                        secondIsA: result[1] === items[0]
                    };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)
        #expect(settled.forProperty("isArray")?.toBool() == true)
        #expect(settled.forProperty("length")?.toInt32() == 2)
        #expect(settled.forProperty("firstIsC")?.toBool() == true)
        #expect(settled.forProperty("secondIsA")?.toBool() == true)
    }

    // MARK: - 15. An empty `canPickMany` selection is not a dismissal

    /// Kills a mutation that folds an empty `[]` from the presenter into the
    /// `nil` dismissal path: the extension would see `undefined` where the
    /// user genuinely accepted a selection of nothing, which
    /// `ExtensionQuickPickPresenting`'s own doc names as a different answer.
    @Test
    func anEmptySelectionWithCanPickManyResolvesAnEmptyArrayNotUndefined() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingQuickPickPresenter()
        presenter.response = []
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.window.showQuickPick(['a', 'b'], { canPickMany: true }).then(function (result) {
                    globalThis.__settled = {
                        ok: true,
                        isUndefined: result === undefined,
                        isArray: Array.isArray(result),
                        length: Array.isArray(result) ? result.length : -1
                    };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)
        #expect(settled.forProperty("isUndefined")?.toBool() == false)
        #expect(settled.forProperty("isArray")?.toBool() == true)
        #expect(settled.forProperty("length")?.toInt32() == 0)
    }

    // MARK: - 16. A dismissal resolves `undefined`

    /// The presenter answers `nil` for two calls, one in each `canPickMany`
    /// mode. Kills a mutation that resolves `null`, an empty array, or the
    /// first item as a stand-in for "nothing chosen" — an extension's
    /// `if (result === undefined)` reads each of those as a different answer
    /// — and, by covering the multi-select call too, a mutation that returns
    /// an empty array for a dismissal when `canPickMany` is set, which the
    /// single-select call alone would not reach.
    @Test
    func aDismissedPickerResolvesUndefinedInBothCanPickManyModes() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingQuickPickPresenter()
        presenter.response = nil
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                var answers = {};
                function record(key) {
                    return function (result) {
                        answers[key] = { isUndefined: result === undefined, isNull: result === null };
                        if (answers.single && answers.multi) {
                            globalThis.__settled = { ok: true, single: answers.single, multi: answers.multi };
                        }
                    };
                }
                function fail(error) {
                    globalThis.__settled = { ok: false, message: error.message };
                }
                vscode.window.showQuickPick(['a', 'b']).then(record('single'), fail);
                vscode.window.showQuickPick(['a', 'b'], { canPickMany: true }).then(record('multi'), fail);
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)
        let single = try #require(settled.forProperty("single"))
        #expect(single.forProperty("isUndefined")?.toBool() == true)
        #expect(single.forProperty("isNull")?.toBool() == false)
        let multi = try #require(settled.forProperty("multi"))
        #expect(multi.forProperty("isUndefined")?.toBool() == true)
        #expect(multi.forProperty("isNull")?.toBool() == false)
    }

    // MARK: - 17. An out-of-range index from the presenter is not trapped

    /// The presenter answers `[7]` for a two-item picker. Kills a mutation
    /// that replaces the bounds check with a direct subscript: the test
    /// process would trap on an index-out-of-range rather than resolving
    /// `undefined`. The presenter is a protocol anyone may conform to, so its
    /// answer is input, not a programmer error this adaptor may assert away.
    @Test
    func anOutOfRangeIndexFromThePresenterResolvesUndefinedRatherThanTrapping() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingQuickPickPresenter()
        presenter.response = [7]
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                vscode.window.showQuickPick(['a', 'b']).then(function (result) {
                    globalThis.__settled = { ok: true, isUndefined: result === undefined };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)
        #expect(settled.forProperty("isUndefined")?.toBool() == true)
    }

    // MARK: - 18. `onDidSelectItem` gets the original item, with `this` bound

    /// The presenter highlights rows 1 then 0. Kills a mutation that passes
    /// the index, the label, or a rebuilt object rather than the extension's
    /// own value (`seen[0] === items[1]` would fail); one that fires the
    /// callback with the wrong `this` (`thisWasOptions` would fail), which is
    /// what dropping the `thisArg` argument produces; and one that fires it
    /// once, or in the wrong order, since both calls are recorded in
    /// sequence.
    @Test
    func onDidSelectItemReceivesTheOriginalItemValueWithTheOptionsObjectAsThis() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingQuickPickPresenter()
        presenter.highlightIndices = [1, 0]
        presenter.response = [0]
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                var items = [{ label: 'a' }, { label: 'b' }];
                var seen = [];
                var thisWasOptions = [];
                var options = {
                    onDidSelectItem: function (item) {
                        seen.push(item);
                        thisWasOptions.push(this === options);
                    }
                };
                vscode.window.showQuickPick(items, options).then(function () {
                    globalThis.__settled = {
                        ok: true,
                        count: seen.length,
                        firstIsB: seen[0] === items[1],
                        secondIsA: seen[1] === items[0],
                        thisOk: thisWasOptions[0] === true && thisWasOptions[1] === true
                    };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)
        #expect(settled.forProperty("count")?.toInt32() == 2)
        #expect(settled.forProperty("firstIsB")?.toBool() == true)
        #expect(settled.forProperty("secondIsA")?.toBool() == true)
        #expect(settled.forProperty("thisOk")?.toBool() == true)
    }

    // MARK: - 19. A throwing `onDidSelectItem` does not derail the picker

    /// Kills a mutation that treats a `.threw` outcome from `onDidSelectItem`
    /// as grounds to reject the picker's promise, instead of swallowing it
    /// the way `VSCodeAPI.call`'s `.threw` case requires: the picker the user
    /// is still looking at would be torn down over the extension's own bug.
    /// The selection still resolves, and both highlights still happen. A
    /// mutation that calls the callback directly instead of through
    /// `VSCodeAPI.call(_:thisArg:arguments:)` is test 18's, above — its
    /// `thisOk` assertion already fails on that mutant, since a direct
    /// `JSValue.call(withArguments:)` binds `this` to `undefined`, not to
    /// `options`.
    @Test
    func aThrowingOnDidSelectItemIsIgnoredAndTheSelectionStillResolves() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingQuickPickPresenter()
        presenter.highlightIndices = [0, 1]
        presenter.response = [1]
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                var items = [{ label: 'a' }, { label: 'b' }];
                globalThis.__calls = 0;
                vscode.window.showQuickPick(items, {
                    onDidSelectItem: function () {
                        globalThis.__calls += 1;
                        throw new Error('callback exploded');
                    }
                }).then(function (result) {
                    globalThis.__settled = {
                        ok: true, isB: result === items[1], calls: globalThis.__calls
                    };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)
        #expect(settled.forProperty("isB")?.toBool() == true)
        #expect(settled.forProperty("calls")?.toInt32() == 2)
    }

    // MARK: - 20. An out-of-range highlight index invokes nothing

    /// The presenter highlights row 9 of a two-row picker. Kills a mutation
    /// that drops the bounds check in the highlight handler: the test process
    /// would trap on the subscript. The callback must not fire at all — a
    /// mutation that clamps to the last item instead would show one call.
    @Test
    func anOutOfRangeHighlightIndexInvokesTheCallbackNotAtAll() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingQuickPickPresenter()
        presenter.highlightIndices = [9]
        presenter.response = [0]
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                globalThis.__calls = 0;
                vscode.window.showQuickPick(['a', 'b'], {
                    onDidSelectItem: function () { globalThis.__calls += 1; }
                }).then(function () {
                    globalThis.__settled = { ok: true, calls: globalThis.__calls };
                }, function (error) {
                    globalThis.__settled = { ok: false, message: error.message };
                });
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == true)
        #expect(settled.forProperty("calls")?.toInt32() == 0)
    }

    // MARK: - 21. Disposal while the picker is genuinely on screen rejects

    /// `SuspendingQuickPickPresenter.presentQuickPick` is confirmed parked on
    /// its continuation before `dispose()` runs, and is released only
    /// afterwards. Kills a mutation that removes the post-`await`
    /// `!self.isDisposed` guard in `presentQuickPickPromise`: the presenter's
    /// answer would be delivered into a torn-down window as `ok: true`
    /// instead of a "torn down" rejection.
    @Test
    func disposeWhileThePickerIsGenuinelySuspendedRejectsRatherThanDeliveringAResult() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = SuspendingQuickPickPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                globalThis.run = function () {
                    vscode.window.showQuickPick(['a', 'b']).then(
                        function () { globalThis.__settled = { ok: true }; },
                        function (error) { globalThis.__settled = { ok: false, message: error.message }; }
                    );
                };
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose() }

        let context = try #require(host.javaScriptContext)
        context.evaluateScript("globalThis.run();")
        await presenter.waitUntilEntered(1)
        // Past the two pre-flight guards, before the post-await one.
        window.dispose()
        presenter.release(at: 0, with: [0])

        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == false)
        #expect(try #require(settled.forProperty("message")?.toString()).contains("torn down"))
    }

    // MARK: - 22. A call on an already-disposed window rejects

    /// `dispose()` before the script runs, so the **pre-await** guard in
    /// `presentQuickPickPromise` answers — not `VSCodeAPI.member`'s own
    /// torn-down path, which fires only once the adaptor is *deallocated*
    /// (see `VSCodeAPI.member`'s doc: `owner` is captured weakly) and the
    /// window is still alive here. Kills a mutation that removes that first
    /// `!self.isDisposed` guard, which test 21's post-await guard does not
    /// cover: without it a disposed window would still present a picker, so
    /// `presenter.requests` would not be empty. The `threw: false` assertion
    /// additionally kills a mutation that raises instead of rejecting — this
    /// member answers a `Thenable`, and an extension that wrote `.then`
    /// around it would never reach its rejection handler.
    @Test
    func aCallOnAnAlreadyDisposedWindowRejectsRatherThanRaising() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingQuickPickPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__settled = null;
                globalThis.run = function () {
                    try {
                        vscode.window.showQuickPick(['a']).then(
                            function () { globalThis.__settled = { ok: true }; },
                            function (error) {
                                globalThis.__settled = { ok: false, threw: false, message: error.message };
                            }
                        );
                    } catch (error) {
                        globalThis.__settled = { ok: false, threw: true, message: error.message };
                    }
                };
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose() }

        let context = try #require(host.javaScriptContext)
        window.dispose()
        context.evaluateScript("globalThis.run();")

        let settled = try #require(await waitForGlobal(context, "globalThis.__settled"))
        #expect(settled.forProperty("ok")?.toBool() == false)
        #expect(settled.forProperty("threw")?.toBool() == false)
        #expect(try #require(settled.forProperty("message")?.toString()).contains("torn down"))
        // No positive assertion is available here: `requests` is the
        // recorder's only observable, and this window was already disposed
        // before the call was even made, so no presenter is ever reached.
        #expect(presenter.requests.isEmpty)
    }

    // MARK: - 23. The `QuickPickItemKind` table

    /// The two values the declaration gives: `Separator = -1`
    /// (`vscode.d.ts:1886`) and `Default = 0` (`vscode.d.ts:1890`). Test 4,
    /// above, already reads `Separator` through this table and kills a
    /// mutation to its number or its name. `isSeparatorItem` spells its own
    /// `-1` rather than depending on the table (see that function's own
    /// doc), so no item here ever parses as a separator through `Default`'s
    /// value — this test alone kills a mutation to `Default`'s number (to
    /// anything but `-1`) or to `Default`'s member name.
    @Test
    func quickPickItemKindMembersCarriesSeparatorMinusOneAndDefaultZero() {
        #expect(MainThreadWindow.quickPickItemKindMembers == ["Separator": -1, "Default": 0])
    }
}
