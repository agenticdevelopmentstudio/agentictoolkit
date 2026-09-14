import Testing
import Foundation
import JavaScriptCore
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// A non-suspending `ExtensionStatusBarPresenting` double: it records every
/// `putOrUpdateStatusBarItem` request and every `removeStatusBarItem` id, in
/// call order, so a test can assert both *how many* times the presenter was
/// reached and *what* it was handed each time — task 5.5c's Ruling 7 ("one
/// presenter call per committed change") is only pinned by a test that can
/// count calls, not merely inspect a final state.
@MainActor
private final class RecordingStatusBarPresenter: ExtensionStatusBarPresenting {
    private(set) var putOrUpdateCalls: [ExtensionStatusBarItemRequest] = []
    private(set) var removeCalls: [String] = []

    func putOrUpdateStatusBarItem(_ request: ExtensionStatusBarItemRequest) {
        putOrUpdateCalls.append(request)
    }

    func removeStatusBarItem(internalID: String) {
        removeCalls.append(internalID)
    }
}

/// The message seam, for a suite that presents no message.
/// `MainThreadWindow.init` does not default `presenter:` either, so every
/// construction in this file has to name one, and naming one that traps
/// says these tests exercise no message.
@MainActor
private final class UnusedMessagePresenter: ExtensionMessagePresenting {
    func presentMessage(_ request: ExtensionMessageRequest) async -> Int? {
        Issue.record("presentMessage was called by a suite that exercises no message.")
        return nil
    }
}

/// The quick pick seam, for a suite that presents no quick pick, on
/// `UnusedMessagePresenter`'s own reasoning: `MainThreadWindow.init` does not
/// default `quickPickPresenter:` either.
@MainActor
private final class UnusedQuickPickPresenter: ExtensionQuickPickPresenting {
    func presentQuickPick(
        _ request: ExtensionQuickPickRequest,
        onHighlight: @escaping (Int) -> Void
    ) async -> [Int]? {
        Issue.record("presentQuickPick was called by a suite that exercises no quick pick.")
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

/// `vscode.window.createStatusBarItem` (task 5.5c), wired onto a real
/// `ExtensionHost` and a `RecordingStatusBarPresenter` double.
///
/// A separate suite from `MainThreadWindowTests`, `MainThreadWindowQuickPickTests`
/// and `MainThreadWindowInputBoxTests` rather than more cases in any of
/// them: this one exercises a fourth seam through a fourth member, with its
/// own request shape and its own long-lived mutable object — the returned
/// `StatusBarItem`, which none of those three ever returns anything
/// resembling.
///
/// This task builds no `ExtensionStatusBarPresenting` conformer that ships
/// (the eventual AppKit home is `WindowFooterBar.trailingAccessories`, a
/// later task), so every presenter here is a double by necessity, on
/// `MainThreadWindowQuickPickTests`'s own reasoning for the same situation.
@MainActor
@Suite
struct MainThreadWindowStatusBarTests {

    // MARK: - Fixtures

    private func makeTempDirectory() throws -> URL {
        try ExtensionFixtures.makeTemporaryDirectory("MainThreadWindowStatusBarTests")
    }

    /// Installs `createStatusBarItem` onto `vscode.window` and the
    /// `StatusBarAlignment` table onto **`vscode`** — the top-level
    /// namespace, not `vscode.window`, on `MainThreadWindow
    /// .statusBarAlignmentMembers`'s own doc, which gives the measured
    /// citation for why that resolves.
    private func install(_ window: MainThreadWindow, on host: ExtensionHost) throws {
        try host.defineVSCodeMember(
            namespacePath: "vscode.window", name: "createStatusBarItem",
            implementation: window.createStatusBarItem)
        try host.defineVSCodeMember(
            namespacePath: "vscode", name: "StatusBarAlignment",
            implementation: MainThreadWindow.statusBarAlignmentMembers)
    }

    /// Builds a window over `presenter`, installs it on `host`, and
    /// activates. `createStatusBarItem` never returns a `Thenable` (it is
    /// synchronous), so unlike the quick pick and input box suites, no test
    /// below needs `waitForGlobal`'s polling — a value written during
    /// `exports.activate` is already settled by the time `host.activate()`
    /// returns.
    private func activate(
        _ host: ExtensionHost,
        presenter: ExtensionStatusBarPresenting
    ) async throws -> MainThreadWindow {
        let window = MainThreadWindow(
            presenter: UnusedMessagePresenter(), quickPickPresenter: UnusedQuickPickPresenter(),
            inputBoxPresenter: UnusedInputBoxPresenter(),
            statusBarPresenter: presenter,
            notImplementedLedger: host.notImplementedLedger, extensionIdentifier: host.identifier)
        try install(window, on: host)
        try await host.activate()
        return window
    }

    // MARK: - 1-2. Defaults with no arguments at all

    /// No-args `createStatusBarItem()` defaults `alignment` to `Left` (`1`).
    /// Kills a mutation that defaults to `Right`, or to some other numeric
    /// value that happens to satisfy no other test.
    @Test
    func noArgumentsDefaultsAlignmentToLeft() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingStatusBarPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var item = vscode.window.createStatusBarItem();
                globalThis.__alignment = item.alignment;
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__alignment")?.toInt32() == 1)
    }

    /// No-args `createStatusBarItem()` leaves `priority` genuinely
    /// `undefined` — checked with `typeof`, not falsiness, so a mutation
    /// that answers `0` (a falsy but *defined* number) does not slip past
    /// an assertion that merely checked `!item.priority`.
    @Test
    func noArgumentsLeavesPriorityGenuinelyUndefined() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingStatusBarPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var item = vscode.window.createStatusBarItem();
                globalThis.__priorityType = typeof item.priority;
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__priorityType")?.toString() == "undefined")
    }

    // MARK: - 3-5. Identity: `id`, and distinctness of id-less items

    /// `createStatusBarItem('my.id')` — the id-form overload — carries the
    /// given id through to `item.id` verbatim.
    @Test
    func idFormOverloadCarriesTheGivenIDVerbatim() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingStatusBarPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var item = vscode.window.createStatusBarItem('my.id');
                globalThis.__id = item.id;
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__id")?.toString() == "my.id")
    }

    /// No id given — `vscode.d.ts:7566-7568`'s own words: "the identifier
    /// will match the ... extension identifier." Kills a mutation that
    /// leaves `id` empty, or that answers some internal counter-derived
    /// string instead.
    @Test
    func noIDGivenAnswersTheExtensionIdentifier() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingStatusBarPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var item = vscode.window.createStatusBarItem();
                globalThis.__id = item.id;
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__id")?.toString() == host.identifier)
    }

    /// Two separate no-id `createStatusBarItem()` calls are distinct
    /// objects with independent state — writing one's `text` must not leak
    /// onto the other. Kills a mutation that caches or reuses a single
    /// `ExtensionStatusBarItem` (or a single JS object) across calls.
    @Test
    func twoNoIDItemsAreDistinctObjectsWithIndependentState() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingStatusBarPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var first = vscode.window.createStatusBarItem();
                var second = vscode.window.createStatusBarItem();
                first.text = 'first-text';
                globalThis.__sameObject = first === second;
                globalThis.__secondText = second.text;
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__sameObject")?.toBool() == false)
        #expect(context.evaluateScript("globalThis.__secondText")?.toString() == "")
    }

    // MARK: - 6-7. Overload discrimination

    /// `createStatusBarItem(2)` — a number as argument 0 — takes the
    /// alignment-form overload, not the id-form: `alignment` becomes `2`
    /// (`Right`) and `id` still answers the extension identifier, never the
    /// string `'2'`. Kills a mutation that coerces a non-string argument 0
    /// to a string and treats it as an id.
    @Test
    func numberAsFirstArgumentTakesTheAlignmentFormOverload() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingStatusBarPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var item = vscode.window.createStatusBarItem(2);
                globalThis.__alignment = item.alignment;
                globalThis.__id = item.id;
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__alignment")?.toInt32() == 2)
        #expect(context.evaluateScript("globalThis.__id")?.toString() == host.identifier)
    }

    /// `createStatusBarItem('x', 2, 7)` — the full id-form overload — routes
    /// all three arguments to their matching properties: `id`, `alignment`
    /// shifted to argument 1, `priority` shifted to argument 2.
    @Test
    func idFormOverloadRoutesAllThreeArgumentsToTheirProperties() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingStatusBarPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var item = vscode.window.createStatusBarItem('x', 2, 7);
                globalThis.__id = item.id;
                globalThis.__alignment = item.alignment;
                globalThis.__priority = item.priority;
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__id")?.toString() == "x")
        #expect(context.evaluateScript("globalThis.__alignment")?.toInt32() == 2)
        #expect(context.evaluateScript("globalThis.__priority")?.toDouble() == 7)
    }

    // MARK: - 8. `alignment`/`priority` are readonly

    /// Assigning to `alignment` or `priority` from JavaScript is a silent
    /// no-op — neither has a setter in the `defineProperty` descriptor this
    /// host installs, matching `vscode.d.ts`'s own `readonly` on both.
    /// Kills a mutation that installs an accessor pair (rather than a
    /// getter-only descriptor) for either property.
    @Test
    func alignmentAndPriorityAreReadonly() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingStatusBarPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var item = vscode.window.createStatusBarItem('x', 2, 7);
                item.alignment = 1;
                item.priority = 99;
                globalThis.__alignment = item.alignment;
                globalThis.__priority = item.priority;
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__alignment")?.toInt32() == 2)
        #expect(context.evaluateScript("globalThis.__priority")?.toDouble() == 7)
    }

    // MARK: - 9-16. show / hide / dispose lifecycle

    /// An item that is never `show()`n reaches the presenter zero times,
    /// even after property writes — `commitStatusBarUpdate`'s own
    /// `item.isVisible` guard, which every mutating setter now goes through
    /// (task 5.5c's Ruling 7), must hold even though the mutation itself
    /// always succeeds.
    @Test
    func neverShownItemReachesThePresenterZeroTimesEvenAfterWrites() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingStatusBarPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var item = vscode.window.createStatusBarItem();
                item.text = 'hello';
                item.name = 'greeting';
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        #expect(presenter.putOrUpdateCalls.isEmpty)
    }

    /// `show()` reaches the presenter exactly once, carrying the item's
    /// current `text`.
    @Test
    func showReachesThePresenterOnceWithCurrentText() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingStatusBarPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var item = vscode.window.createStatusBarItem();
                item.text = 'hello';
                item.show();
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        #expect(presenter.putOrUpdateCalls.count == 1)
        #expect(presenter.putOrUpdateCalls.first?.text == "hello")
    }

    /// A property write issued after `show()` reaches the presenter again —
    /// one call per write, with no coalescing (Divergence #1, task 5.5c's
    /// Ruling 7): `show()` itself commits once, then two further `text`
    /// writes each commit once more, for three calls total.
    @Test
    func aWriteAfterShowReachesThePresenterAgainWithNoCoalescing() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingStatusBarPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var item = vscode.window.createStatusBarItem();
                item.show();
                item.text = 'a';
                item.text = 'b';
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        #expect(presenter.putOrUpdateCalls.count == 3)
        #expect(presenter.putOrUpdateCalls.last?.text == "b")
    }

    /// `hide()` removes the item by its internal id, not its public `id`.
    @Test
    func hideRemovesByInternalID() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingStatusBarPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var item = vscode.window.createStatusBarItem('my.id');
                item.show();
                item.hide();
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        #expect(presenter.removeCalls.count == 1)
        #expect(presenter.removeCalls.first != "my.id")
        let putRequest = try #require(presenter.putOrUpdateCalls.first)
        #expect(presenter.removeCalls.first == putRequest.internalID)
    }

    /// `show()` called again after `hide()` puts the item back up.
    @Test
    func showAfterHidePutsTheItemBackUp() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingStatusBarPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var item = vscode.window.createStatusBarItem();
                item.show();
                item.hide();
                item.show();
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        #expect(presenter.putOrUpdateCalls.count == 2)
        #expect(presenter.removeCalls.count == 1)
    }

    /// `dispose()` removes the item, and a property write issued afterward
    /// reaches the presenter zero further times.
    @Test
    func disposeRemovesTheItemAndFurtherWritesReachThePresenterZeroTimes() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingStatusBarPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var item = vscode.window.createStatusBarItem();
                item.show();
                item.dispose();
                item.text = 'after-dispose';
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        #expect(presenter.putOrUpdateCalls.count == 1)
        #expect(presenter.removeCalls.count == 1)
    }

    /// `show()` called after `dispose()` reaches the presenter zero times —
    /// `showStatusBarItem`'s own `!item.isDisposed` guard.
    @Test
    func showAfterDisposeReachesThePresenterZeroTimes() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingStatusBarPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var item = vscode.window.createStatusBarItem();
                item.dispose();
                item.show();
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        #expect(presenter.putOrUpdateCalls.isEmpty)
    }

    /// `dispose()` called twice is not an error and removes the item only
    /// once — the `!item.isDisposed` guard makes the second call a no-op
    /// before it touches the presenter or the registry again.
    @Test
    func disposeTwiceIsNotAnErrorAndRemovesOnce() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingStatusBarPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var item = vscode.window.createStatusBarItem();
                item.show();
                item.dispose();
                item.dispose();
                globalThis.__ok = true;
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__ok")?.toBool() == true)
        #expect(presenter.removeCalls.count == 1)
    }

    // MARK: - 17-21. Property round trips

    /// `text` round-trips through the getter unchanged.
    @Test
    func textRoundTrips() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingStatusBarPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var item = vscode.window.createStatusBarItem();
                item.text = '$(sync) working';
                globalThis.__text = item.text;
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__text")?.toString() == "$(sync) working")
    }

    /// `color = 'red'` (a plain string) round-trips as the string `'red'`,
    /// and reaches the presenter's request carrying that same string.
    @Test
    func colorAsAPlainStringRoundTrips() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingStatusBarPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var item = vscode.window.createStatusBarItem();
                item.color = 'red';
                item.show();
                globalThis.__color = item.color;
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__color")?.toString() == "red")
        #expect(presenter.putOrUpdateCalls.last?.color == "red")
    }

    /// `color = {id: 'myTheme.color'}` (a `ThemeColor`-shaped object)
    /// reaches the presenter's request as that flat id string, and the
    /// getter answers a **different** object than the one that was set —
    /// this host mints no `ThemeColor` prototype, so the round-tripped
    /// value cannot be `===` the original, but must carry a matching `id`.
    @Test
    func colorAsAThemeColorShapedObjectRoundTripsAsAFreshObjectWithMatchingID() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingStatusBarPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var item = vscode.window.createStatusBarItem();
                var original = { id: 'myTheme.color' };
                item.color = original;
                item.show();
                var readBack = item.color;
                globalThis.__sameObject = readBack === original;
                globalThis.__id = readBack.id;
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__sameObject")?.toBool() == false)
        #expect(context.evaluateScript("globalThis.__id")?.toString() == "myTheme.color")
        #expect(presenter.putOrUpdateCalls.last?.color == "myTheme.color")
    }

    /// `backgroundColor` round-trips the same way `color` does — same
    /// `{id}`-object handling, its own accessor pair.
    @Test
    func backgroundColorAsAThemeColorShapedObjectRoundTripsAsAFreshObjectWithMatchingID() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingStatusBarPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var item = vscode.window.createStatusBarItem();
                var original = { id: 'myTheme.background' };
                item.backgroundColor = original;
                item.show();
                var readBack = item.backgroundColor;
                globalThis.__sameObject = readBack === original;
                globalThis.__id = readBack.id;
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__sameObject")?.toBool() == false)
        #expect(context.evaluateScript("globalThis.__id")?.toString() == "myTheme.background")
        #expect(presenter.putOrUpdateCalls.last?.backgroundColor == "myTheme.background")
    }

    /// `accessibilityInformation = {label, role}` reaches the presenter as
    /// two separate strings, and round-trips through the getter as an
    /// object carrying both.
    @Test
    func accessibilityInformationReachesThePresenterAsTwoStringsAndRoundTrips() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingStatusBarPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var item = vscode.window.createStatusBarItem();
                item.accessibilityInformation = { label: 'Sync status', role: 'button' };
                item.show();
                var readBack = item.accessibilityInformation;
                globalThis.__label = readBack.label;
                globalThis.__role = readBack.role;
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__label")?.toString() == "Sync status")
        #expect(context.evaluateScript("globalThis.__role")?.toString() == "button")
        let request = try #require(presenter.putOrUpdateCalls.last)
        #expect(request.accessibilityLabel == "Sync status")
        #expect(request.accessibilityRole == "button")
    }

    // MARK: - 22-25. Unsupported shapes go through the ledger, not an exception

    /// A `MarkdownString`-shaped tooltip (an object, not a string) records
    /// exactly one ledger entry at `vscode.StatusBarItem.tooltip`, throws
    /// nothing, and — because a real tooltip was set first — leaves that
    /// *previous* value in place rather than clearing it: the assertion is
    /// not vacuous, since a mutation that simply never wrote `tooltip` at
    /// all would otherwise also show `tooltip` unchanged.
    @Test
    func markdownStringShapedTooltipRecordsALedgerEntryAndLeavesThePreviousValue() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingStatusBarPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var item = vscode.window.createStatusBarItem();
                item.tooltip = 'a real tooltip';
                var threw = false;
                try {
                    item.tooltip = { value: '**bold**' };
                } catch (error) {
                    threw = true;
                }
                globalThis.__threw = threw;
                globalThis.__tooltip = item.tooltip;
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__threw")?.toBool() == false)
        #expect(context.evaluateScript("globalThis.__tooltip")?.toString() == "a real tooltip")
        let accesses = host.notImplementedLedger.accesses
        #expect(accesses.count == 1)
        let access = try #require(accesses.first)
        #expect(access.memberPath == "vscode.StatusBarItem.tooltip")
        #expect(access.count == 1)
    }

    /// A `Command`-object command does the same at
    /// `vscode.StatusBarItem.command`.
    @Test
    func commandObjectShapedCommandRecordsALedgerEntryAndLeavesThePreviousValue() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingStatusBarPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var item = vscode.window.createStatusBarItem();
                item.command = 'extension.doThing';
                var threw = false;
                try {
                    item.command = { title: 'Do Thing', command: 'extension.doThing' };
                } catch (error) {
                    threw = true;
                }
                globalThis.__threw = threw;
                globalThis.__command = item.command;
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__threw")?.toBool() == false)
        #expect(context.evaluateScript("globalThis.__command")?.toString() == "extension.doThing")
        let accesses = host.notImplementedLedger.accesses
        #expect(accesses.count == 1)
        let access = try #require(accesses.first)
        #expect(access.memberPath == "vscode.StatusBarItem.command")
        #expect(access.count == 1)
    }

    /// A plain string `command` is carried, not recorded — the negative
    /// case pinning that the ledger path is reached only by the
    /// non-string shape, never by every `command` write.
    @Test
    func plainStringCommandIsCarriedAndRecordsNothing() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingStatusBarPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var item = vscode.window.createStatusBarItem();
                item.command = 'extension.doThing';
                globalThis.__command = item.command;
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__command")?.toString() == "extension.doThing")
        #expect(host.notImplementedLedger.accesses.isEmpty)
    }

    /// Two identical unsupported writes record **one** ledger row, with
    /// `count == 2` — `NotImplementedLedger`'s own dedup-by-(extension,
    /// member path) behaviour, not two separate rows.
    @Test
    func twoIdenticalUnsupportedWritesRecordOneLedgerRowWithCountTwo() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingStatusBarPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                var item = vscode.window.createStatusBarItem();
                item.tooltip = { value: '**bold**' };
                item.tooltip = { value: '**bold**' };
                globalThis.__ok = true;
            };
            """,
            in: directory
        )
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose(); window.dispose() }

        let context = try #require(host.javaScriptContext)
        #expect(context.evaluateScript("globalThis.__ok")?.toBool() == true)
        let accesses = host.notImplementedLedger.accesses
        #expect(accesses.count == 1)
        #expect(accesses.first?.count == 2)
    }

    // MARK: - 26. Teardown: torn down but still alive

    /// `createStatusBarItem` has no `await` to re-check `isDisposed` after
    /// (unlike every other member in this file), so a call on a
    /// disposed-but-still-alive `MainThreadWindow` must be caught by its own
    /// pre-await `isDisposed` guard at the top of
    /// `handleCreateStatusBarItem` — **not** by `VSCodeAPI.member`'s
    /// weak-owner path, which only fires once `window` has actually
    /// deallocated, never merely because `isDisposed` was set while the
    /// instance referenced by the running `Task` in this test is still
    /// alive (it is kept alive by this test's own local `window` variable,
    /// held past the call).
    @Test
    func callOnADisposedButStillAliveWindowRaisesViaTheIsDisposedGuard() async throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let presenter = RecordingStatusBarPresenter()
        let host = try makeHost(
            source: """
            var vscode = require('vscode');
            exports.activate = function () {
                globalThis.__createStatusBarItem = vscode.window.createStatusBarItem;
            };
            """,
            in: directory
        )
        // `window` is a local `let`, held for the rest of this test — the
        // instance `handleCreateStatusBarItem` runs against is genuinely
        // still alive when the call below runs, so `VSCodeAPI.member`'s own
        // weak-owner check (which only fires once `self` has actually
        // deallocated) cannot be what raises here; only this member's own
        // `!isDisposed` guard can, matching `MainThreadCommandsTests`' own
        // "torn down" test's use of a plain JS `try`/`catch` around a
        // synchronous member that raises rather than rejects.
        let window = try await activate(host, presenter: presenter)
        defer { host.dispose() }
        window.dispose()

        let context = try #require(host.javaScriptContext)
        context.evaluateScript("""
            globalThis.__message = null;
            try {
                globalThis.__createStatusBarItem();
            } catch (error) {
                globalThis.__message = error.message;
            }
            """)
        let message = context.evaluateScript("globalThis.__message")?.toString()
        #expect(message
            == "vscode.window.createStatusBarItem is unavailable: this extension's host has been torn down.")
        #expect(presenter.putOrUpdateCalls.isEmpty)
    }
}
