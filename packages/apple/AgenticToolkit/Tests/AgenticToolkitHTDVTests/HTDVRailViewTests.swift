#if canImport(AppKit)
import AppKit
import XCTest
@testable import AgenticToolkitHTDV

@MainActor
final class HTDVRailViewTests: XCTestCase {
    private func level() -> HTDVLevel {
        HTDVLevel(id: "root", title: "Root", items: [
            HTDVItem(id: "a", label: "Alpha", sublabel: "one"),
            HTDVItem(id: "b", label: "Beta", leadsTo: .detail, badge: .count(2))
        ], createAction: HTDVCreateAction(title: "New") { _ in })
    }

    func testApplyPopulatesRows() {
        let rail = HTDVRailView(levelIndex: 0)
        rail.frame = NSRect(x: 0, y: 0, width: 240, height: 400)
        rail.apply(level: level(), selectedID: "b")
        XCTAssertEqual(rail.rowCount, 2)
        XCTAssertEqual(rail.title, "Root")
        XCTAssertEqual(rail.tableView.selectedRow, 1)
        XCTAssertFalse(rail.createButton.isHidden)
    }

    func testCreateButtonHiddenWithoutAction() {
        let rail = HTDVRailView(levelIndex: 0)
        rail.apply(level: HTDVLevel(id: "x", title: "X", items: []), selectedID: nil)
        XCTAssertTrue(rail.createButton.isHidden)
        XCTAssertFalse(rail.emptyLabel.isHidden)
        XCTAssertEqual(rail.emptyLabel.stringValue, "Nothing here yet")
    }

    func testCellRendersContent() {
        let cell = HTDVRailCellView()
        cell.apply(HTDVCellContent(item: HTDVItem(id: "a", label: "Alpha", sublabel: "one", badge: .count(3))))
        XCTAssertEqual(cell.titleLabel.stringValue, "Alpha")
        XCTAssertEqual(cell.subtitleLabel.stringValue, "one")
        XCTAssertEqual(cell.badgeLabel.stringValue, "3")
        XCTAssertFalse(cell.chevron.isHidden)
    }

    func testErrorStateShowsRetry() {
        let rail = HTDVRailView(levelIndex: 1)
        var retried = false
        rail.showError("boom") { retried = true }
        XCTAssertFalse(rail.errorView.isHidden)
        XCTAssertEqual(rail.errorView.messageLabel.stringValue, "boom")
        rail.errorView.retryButton.performClick(nil)
        XCTAssertTrue(retried)
    }

    func testBreadcrumbBarBuildsButtons() {
        let bar = HTDVBreadcrumbBar()
        var picked: [Int] = []
        bar.onSelectCrumb = { picked.append($0) }
        bar.apply(titles: ["Root", "Personas", "Ada"])
        XCTAssertEqual(bar.buttons.map(\.title), ["Root", "Personas", "Ada"])
        bar.buttons[1].performClick(nil)
        XCTAssertEqual(picked, [1])
    }

    func testViewControllerRendersControllerLevels() async {
        let root = level()
        let source = TreeDataSource(root: root, children: [
            "a": .level(HTDVLevel(id: "a-kids", title: "Alpha", items: [HTDVItem(id: "a1", label: "A1")])),
            "b": .detail(HTDVDetail(id: "b", title: "Beta") { NSViewController() })
        ])
        let controller = HTDVController(dataSource: source)
        let viewController = HTDVViewController(controller: controller)
        viewController.view.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
        viewController.loadViewIfNeeded()
        await controller.load()
        XCTAssertEqual(viewController.railViews.count, 1)
        await controller.select(itemID: "a", atLevel: 0)
        XCTAssertEqual(viewController.railViews.count, 2)
        XCTAssertEqual(viewController.breadcrumbBar.buttons.map(\.title), ["Root", "Alpha"])
        await controller.select(itemID: "b", atLevel: 0)
        XCTAssertEqual(viewController.railViews.count, 1)
        XCTAssertNotNil(viewController.detailViewController)
        XCTAssertFalse(viewController.hasUnsavedChanges)
    }

    // MARK: Sabotage-resistant additions
    //
    // These pin behaviour that the brief's own tests above would still pass without, per the
    // plan's standing warning about self-satisfying tests.

    /// `HTDVRailCellView.apply` defaults every field to values that already match what
    /// `testCellRendersContent` asserts (a fresh `NSImageView`'s `isHidden` is already `false`), so
    /// deleting `chevron.isHidden = !content.isDisclosing` would still leave that test green. This
    /// drives an item that leads to a detail pane (`isDisclosing == false`) so only a real
    /// assignment can hide the chevron.
    func testCellHidesChevronForNonDisclosingItem() {
        let cell = HTDVRailCellView()
        cell.apply(HTDVCellContent(item: HTDVItem(id: "b", label: "Beta", leadsTo: .detail)))
        XCTAssertTrue(cell.chevron.isHidden)
    }

    /// `HTDVRailView.apply` sets selection programmatically. Nothing in `testApplyPopulatesRows`
    /// would notice if the `isApplyingSelection` guard around `tableViewSelectionDidChange` were
    /// deleted, because that test never inspects `onSelect`. Without the guard, AppKit's
    /// synchronous selection-changed notification would re-enter `onSelect` for a selection the
    /// caller never asked for.
    func testApplyingSelectionDoesNotInvokeOnSelect() {
        let rail = HTDVRailView(levelIndex: 0)
        rail.frame = NSRect(x: 0, y: 0, width: 240, height: 400)
        var selected: [String] = []
        rail.onSelect = { selected.append($0) }
        rail.apply(level: level(), selectedID: "b")
        XCTAssertTrue(selected.isEmpty)
    }

    /// `testBreadcrumbBarBuildsButtons` only ever calls `apply(titles:)` once, so it would not
    /// notice if `buttons = []` were deleted: `bar.buttons` would just accumulate stale entries
    /// from a previous navigation alongside the new ones instead of replacing them.
    func testBreadcrumbBarReplacesButtonsOnReapply() {
        let bar = HTDVBreadcrumbBar()
        bar.apply(titles: ["Root", "Personas", "Ada"])
        bar.apply(titles: ["Root"])
        XCTAssertEqual(bar.buttons.map(\.title), ["Root"])
    }

    /// `testViewControllerRendersControllerLevels` only ever hosts a plain `NSViewController` as
    /// the detail, so `(detailViewController as? HTDVDetailHosting)` always fails to cast there —
    /// `hasUnsavedChanges` could be hardcoded to `false` and that test would still pass. This drives
    /// a detail pane that actually conforms to `HTDVDetailHosting` and checks both the forwarded
    /// property and that `confirmDiscard()` calls through to it.
    func testHasUnsavedChangesAndConfirmDiscardForwardToDetailHosting() async {
        let source = TreeDataSource(root: level(), children: [
            "b": .detail(HTDVDetail(id: "b", title: "Beta") { MockHostingViewController() })
        ])
        let controller = HTDVController(dataSource: source)
        let viewController = HTDVViewController(controller: controller)
        viewController.view.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
        viewController.loadViewIfNeeded()
        await controller.load()
        await controller.select(itemID: "b", atLevel: 0)
        guard let hosting = viewController.detailViewController as? MockHostingViewController else {
            return XCTFail("expected the mock hosting detail controller")
        }
        hosting.hasUnsavedChanges = true
        XCTAssertTrue(viewController.hasUnsavedChanges)
        hosting.confirmDiscardResult = false
        let discarded = await viewController.confirmDiscard()
        XCTAssertEqual(hosting.confirmDiscardCallCount, 1)
        XCTAssertFalse(discarded)
    }

    // MARK: Fix round 1 additions

    /// `showLoading()`/`showError(_:retry:)` never used to hide `scrollView`, so a reload of an
    /// already-populated rail left the stale rows visible behind the status overlay. Pins that
    /// both status methods hide the scroll view and `apply(level:selectedID:)` un-hides it again.
    func testStatusOverlaysHideStaleRowsBehindThem() {
        let rail = HTDVRailView(levelIndex: 0)
        rail.apply(level: level(), selectedID: nil)
        XCTAssertFalse(rail.scrollView.isHidden, "rows are visible once a level has loaded")

        rail.showLoading()
        XCTAssertTrue(rail.scrollView.isHidden, "stale rows must not show through the loading spinner")

        rail.apply(level: level(), selectedID: nil)
        XCTAssertFalse(rail.scrollView.isHidden)

        rail.showError("boom") { }
        XCTAssertTrue(rail.scrollView.isHidden, "stale rows must not show through the error message")

        rail.apply(level: level(), selectedID: nil)
        XCTAssertFalse(rail.scrollView.isHidden, "apply() must restore the rows once the overlay is gone")
    }

    /// `render()` used to gate the loading spinner on `index >= controller.levels.count`, which
    /// made it unreachable for `reload(level:)` on an already-loaded level — the rail simply froze
    /// on stale rows for the whole in-flight reload. Delays the reload's fetch to observe the
    /// spinner while it is genuinely in flight.
    func testReloadOfAlreadyLoadedLevelShowsLoadingSpinner() async throws {
        let tree = TreeDataSource(root: level(), children: [:])
        let controller = HTDVController(dataSource: tree)
        let viewController = HTDVViewController(controller: controller)
        viewController.view.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
        viewController.loadViewIfNeeded()
        await controller.load()
        XCTAssertEqual(viewController.railViews.count, 1)
        let rail = viewController.railViews[0]
        XCTAssertTrue(rail.loadingView.isHidden)

        tree.delay(200_000_000, at: "")
        let reloadTask = Task { await controller.reload(level: 0) }
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertFalse(
            rail.loadingView.isHidden,
            "the spinner must be reachable while a reload of an already-loaded level is in flight"
        )
        await reloadTask.value
        XCTAssertTrue(rail.loadingView.isHidden)
    }

    /// `HTDVRailCellView.apply`'s badge switch is exhaustive and every branch resets both
    /// `badgeLabel` and `badgeDot` today, but no existing test ever calls `apply()` twice on the
    /// SAME instance with different badge kinds — the actual `NSTableView` reuse scenario this
    /// class of bug hides in. Applies a `.count` badge, then a `nil` badge, to the same cell.
    func testCellResetsBadgeAcrossReuseWithDifferentContent() {
        let cell = HTDVRailCellView()
        cell.apply(HTDVCellContent(item: HTDVItem(id: "a", label: "Alpha", badge: .count(3))))
        XCTAssertFalse(cell.badgeLabel.isHidden)
        XCTAssertEqual(cell.badgeLabel.stringValue, "3")

        cell.apply(HTDVCellContent(item: HTDVItem(id: "b", label: "Beta", badge: nil)))
        XCTAssertTrue(cell.badgeLabel.isHidden)
        XCTAssertEqual(cell.badgeLabel.stringValue, "", "a reused cell must not keep the previous badge's text")
        XCTAssertTrue(cell.badgeDot.isHidden)
    }

    /// `railSelected`/`crumbSelected` each spawned a `Task` awaiting `confirmDiscard()` with no
    /// re-entrancy guard, so a second selection issued while the first prompt was still awaiting
    /// the user put up a second prompt. Holds the first `confirmDiscard()` open with the same
    /// continuation-based pause/release handshake `FormStateTests.SaveRecorder.pauseInFlight()`
    /// uses, then issues a second selection while it is pending.
    func testSecondSelectionWhileConfirmDiscardIsPendingIsIgnored() async throws {
        let hosting = PausingHostingViewController()
        let source = TreeDataSource(root: level(), children: [
            "b": .detail(HTDVDetail(id: "b", title: "Beta") { hosting })
        ])
        let controller = HTDVController(dataSource: source)
        let viewController = HTDVViewController(controller: controller)
        viewController.view.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
        viewController.loadViewIfNeeded()
        await controller.load()
        await controller.select(itemID: "b", atLevel: 0)
        XCTAssertTrue(viewController.detailViewController === hosting)

        let rail = viewController.railViews[0]
        rail.onSelect("b")
        await hosting.waitUntilEntered()
        XCTAssertEqual(hosting.confirmDiscardCallCount, 1)

        rail.onSelect("b")
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(
            hosting.confirmDiscardCallCount, 1,
            "a second selection issued while the first discard prompt is pending must not open a second one"
        )

        hosting.release()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(hosting.confirmDiscardCallCount, 1, "still only the one confirmation, after it resolved")
    }

    // MARK: Fix round 2 additions

    /// Round 1's guard held `isConfirmingDiscard` across the whole `railSelected` `Task` via `defer`, not
    /// just across the discard decision. With no unsaved changes `confirmDiscard()` resolves immediately, so
    /// the flag then stayed true for the entire in-flight `controller.select(...)` and silently dropped a
    /// second click issued during that load — worse than the double discard-prompt round 1 fixed, since
    /// AppKit had already moved the table's selection to the new row by then. The controller's generation
    /// counter already supersedes a stale in-flight select correctly; this pins that a second click during
    /// the first one's fetch actually reaches `controller.select` at all, and that the later selection wins.
    func testSecondSelectionWhileFirstSelectIsInFlightWins() async throws {
        let source = PausingChildDataSource(root: level(), children: [
            "a": .level(HTDVLevel(id: "a-children", title: "Alpha", items: [HTDVItem(id: "a1", label: "A1")])),
            "b": .level(HTDVLevel(id: "b-children", title: "Beta", items: [HTDVItem(id: "b1", label: "B1")]))
        ])
        source.pause(at: "a")
        let controller = HTDVController(dataSource: source)
        let viewController = HTDVViewController(controller: controller)
        viewController.view.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
        viewController.loadViewIfNeeded()
        await controller.load()

        let rail = viewController.railViews[0]
        rail.onSelect("a")
        await source.waitUntilEntered("a")
        // `selection` is updated synchronously before the fetch; the appended level is not, so that's
        // what distinguishes "still in flight" from "applied".
        XCTAssertEqual(controller.selection, ["a"])
        XCTAssertEqual(controller.levels.count, 1, "the first select's child level must not be applied yet")

        rail.onSelect("b")
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(
            controller.selection, ["b"],
            "a second selection issued while the first's fetch is in flight must not be dropped"
        )
        XCTAssertEqual(controller.levels.map(\.id), ["root", "b-children"])

        source.release("a")
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(
            controller.selection, ["b"],
            "the stale in-flight select must not override the later one once it finally resolves"
        )
        XCTAssertEqual(
            controller.levels.map(\.id), ["root", "b-children"],
            "the stale select's level must not replace the later one once it finally resolves"
        )
    }

    // MARK: Fix round 3 additions

    private func threeLevelSource() -> TreeDataSource {
        TreeDataSource(root: level(), children: [
            "a": .level(HTDVLevel(id: "a-children", title: "Alpha", items: [HTDVItem(id: "a1", label: "A1")])),
            "a/a1": .level(HTDVLevel(id: "a1-children", title: "A1", items: [HTDVItem(id: "x", label: "X")]))
        ])
    }

    private func hostedViewController(_ source: TreeDataSource) -> HTDVViewController {
        let viewController = HTDVViewController(controller: HTDVController(dataSource: source))
        viewController.view.frame = NSRect(x: 0, y: 0, width: 1200, height: 800)
        viewController.loadViewIfNeeded()
        return viewController
    }

    /// A breadcrumb POPS. `crumbSelected(i)` used to call `railSelected(level: i)`, which re-selected
    /// the item at level `i` and fetched its child — navigating one level DEEPER than the crumb the
    /// user clicked and GROWING the bar. The depth must shrink.
    func testBreadcrumbPopsToThatLevelInsteadOfNavigatingDeeper() async throws {
        let viewController = hostedViewController(threeLevelSource())
        let controller = viewController.controller
        await controller.load()
        await controller.select(itemID: "a", atLevel: 0)
        await controller.select(itemID: "a1", atLevel: 1)
        XCTAssertEqual(controller.levels.map(\.id), ["root", "a-children", "a1-children"])

        viewController.breadcrumbBar.buttons[0].performClick(nil)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(
            controller.levels.map(\.id), ["root"],
            "clicking crumb 0 must pop back to level 0, not push a fourth level"
        )
        XCTAssertTrue(controller.selection.isEmpty)
        XCTAssertEqual(viewController.breadcrumbBar.buttons.map(\.title), ["Root"])
    }

    /// Popping to an intermediate crumb keeps that level's own selection — the user asked to go back
    /// TO it, not to deselect within it.
    func testBreadcrumbPopToIntermediateLevelKeepsThatLevelSelected() async throws {
        let viewController = hostedViewController(threeLevelSource())
        let controller = viewController.controller
        await controller.load()
        await controller.select(itemID: "a", atLevel: 0)
        await controller.select(itemID: "a1", atLevel: 1)

        viewController.breadcrumbBar.buttons[1].performClick(nil)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(controller.levels.map(\.id), ["root", "a-children"])
        XCTAssertEqual(controller.selection, ["a"])
    }

    /// The deepest crumb names the level already on screen, so it is a no-op — and explicitly not a
    /// discard prompt for a navigation that cannot happen.
    func testDeepestBreadcrumbIsANoOp() async throws {
        let hosting = PausingHostingViewController()
        let source = TreeDataSource(root: level(), children: [
            "b": .detail(HTDVDetail(id: "b", title: "Beta") { hosting })
        ])
        let viewController = hostedViewController(source)
        let controller = viewController.controller
        await controller.load()
        await controller.select(itemID: "b", atLevel: 0)

        viewController.breadcrumbBar.buttons[0].performClick(nil)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(controller.levels.map(\.id), ["root"])
        XCTAssertNotNil(viewController.detailViewController, "a no-op crumb must not tear down the detail")
        XCTAssertEqual(
            hosting.confirmDiscardCallCount, 0,
            "the deepest crumb must not put up a discard prompt for a navigation that cannot happen"
        )
    }

    /// `popToLevel(-1)` empties the model deliberately. The host then rendered one blank placeholder
    /// rail — no rows, no spinner, no error, no retry — and the user was stuck. It re-issues the root
    /// load instead, so content comes back.
    func testEmptiedModelRecoversInsteadOfRenderingADeadRail() async throws {
        let source = threeLevelSource()
        let viewController = hostedViewController(source)
        let controller = viewController.controller
        await controller.load()
        XCTAssertEqual(source.calls.filter { $0 == "" }.count, 1)

        controller.popToLevel(-1)
        XCTAssertTrue(controller.levels.isEmpty, "popToLevel(-1) still empties the model; that is its contract")
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(controller.levels.map(\.id), ["root"], "the host must re-issue the root load")
        XCTAssertEqual(viewController.railViews.count, 1)
        XCTAssertEqual(viewController.railViews[0].rowCount, 2)
        XCTAssertTrue(viewController.railViews[0].emptyLabel.isHidden)
    }

    /// The recovery re-enters `render()` through `load()`'s own `onChange`, so it has to fire exactly
    /// once. An unguarded version spins forever, re-fetching the root on every render.
    func testEmptyModelRecoveryFiresExactlyOnce() async throws {
        let source = threeLevelSource()
        let viewController = hostedViewController(source)
        let controller = viewController.controller
        await controller.load()
        controller.popToLevel(-1)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(
            source.calls.filter { $0 == "" }.count, 2,
            "one app-driven load plus exactly one recovery load"
        )
    }

    /// An empty model that is empty BECAUSE the root load failed already shows an error and a retry
    /// button, so the recovery must stay out of the way rather than re-fetching behind the error.
    func testFailedRootLoadIsNotTreatedAsAnEmptyDeadEnd() async throws {
        let source = threeLevelSource()
        source.failNextRequest()
        let viewController = hostedViewController(source)
        let controller = viewController.controller
        await controller.load()
        XCTAssertNotNil(controller.error)
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(source.calls.filter { $0 == "" }.count, 1, "the error state must not be re-fetched over")
        XCTAssertFalse(viewController.railViews[0].errorView.isHidden)
    }

    // MARK: Fix round 4 additions

    /// Constructing the view must not imply a fetch. `render()` runs from `loadView()` against a
    /// pristine controller — no levels, no error, nothing loading — which is by value identical to the
    /// emptied-by-pop state the recovery net was written for, so the net fired and issued a root load
    /// the app never asked for. A host that installs the view before it loads (`contentViewController`
    /// in `applicationDidFinishLaunching`, then `load()` from `viewDidAppear`) got that fetch plus a
    /// second one of its own; a host that deliberately defers until the user picks a workspace got a
    /// fetch it had decided not to make yet. The net now requires the model to have HELD content once.
    func testBuildingTheViewDoesNotIssueAFetch() async throws {
        let source = threeLevelSource()
        let viewController = hostedViewController(source)
        // A full hop, so a recovery `Task` enqueued during `loadView()` would have run by now.
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(source.calls, [], "merely building the host's view must not fetch anything")
        XCTAssertTrue(viewController.controller.levels.isEmpty)
    }
}

/// A detail pane that reports unsaved changes, used to prove `HTDVViewController` genuinely
/// forwards `hasUnsavedChanges`/`confirmDiscard()` to whatever is currently hosted, rather than
/// hardcoding an answer that happens to match a plain `NSViewController` detail.
private final class MockHostingViewController: NSViewController, HTDVDetailHosting {
    var hasUnsavedChanges = false
    var confirmDiscardResult = true
    private(set) var confirmDiscardCallCount = 0

    func confirmDiscard() async -> Bool {
        confirmDiscardCallCount += 1
        return confirmDiscardResult
    }
}

/// A detail pane whose `confirmDiscard()` can be held open until the test releases it, used to
/// prove `HTDVViewController` cannot open a second discard prompt while the first is still
/// awaiting the user. Mirrors the continuation-based pause/release handshake
/// `FormStateTests.SaveRecorder` uses for `pauseInFlight()`/`waitUntilEntered()`/`release()`; no
/// lock is needed here because `confirmDiscard()` is `@MainActor`, same as the test itself.
@MainActor
private final class PausingHostingViewController: NSViewController, HTDVDetailHosting {
    let hasUnsavedChanges = true
    private(set) var confirmDiscardCallCount = 0
    private var hasEntered = false
    private var enteredWaiter: CheckedContinuation<Void, Never>?
    private var canRelease = false
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func confirmDiscard() async -> Bool {
        confirmDiscardCallCount += 1
        hasEntered = true
        if let waiter = enteredWaiter {
            enteredWaiter = nil
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            if canRelease {
                canRelease = false
                continuation.resume()
            } else {
                releaseWaiter = continuation
            }
        }
        return true
    }

    /// Called from the test: suspends until a paused `confirmDiscard()` has recorded its entry.
    func waitUntilEntered() async {
        await withCheckedContinuation { continuation in
            if hasEntered {
                hasEntered = false
                continuation.resume()
            } else {
                enteredWaiter = continuation
            }
        }
    }

    /// Called from the test: lets a paused `confirmDiscard()` continue.
    func release() {
        if let waiter = releaseWaiter {
            releaseWaiter = nil
            waiter.resume()
        } else {
            canRelease = true
        }
    }
}

/// A data source whose `child(for:)` can be held open for one key until the test releases it, used to prove
/// a second `railSelected` issued while an earlier one's fetch is still in flight is no longer dropped.
/// Mirrors the continuation-based pause/release handshake `PausingHostingViewController` uses above, but
/// guarded with an `NSLock` instead of `@MainActor` confinement: `HTDVDataSource` conformers are `Sendable`
/// and, like `TreeDataSource` elsewhere in this target, `child(for:)` can resume execution off the main actor.
private final class PausingChildDataSource: HTDVDataSource, @unchecked Sendable {
    private let lock = NSLock()
    private let root: HTDVLevel
    private let children: [String: HTDVChild]
    private var pausedKeys: Set<String> = []
    private var entered: Set<String> = []
    private var enteredWaiters: [String: CheckedContinuation<Void, Never>] = [:]
    private var released: Set<String> = []
    private var releaseWaiters: [String: CheckedContinuation<Void, Never>] = [:]

    init(root: HTDVLevel, children: [String: HTDVChild]) {
        self.root = root
        self.children = children
    }

    func pause(at key: String) { lock.withLock { _ = pausedKeys.insert(key) } }

    func rootLevel() async throws -> HTDVLevel { root }

    func child(for path: [HTDVItem]) async throws -> HTDVChild {
        let key = path.map(\.id).joined(separator: "/")
        await waitIfPaused(key)
        return children[key] ?? .empty
    }

    private func waitIfPaused(_ key: String) async {
        let shouldWait = lock.withLock { pausedKeys.contains(key) }
        guard shouldWait else { return }
        let enterWaiter: CheckedContinuation<Void, Never>? = lock.withLock {
            entered.insert(key)
            defer { enteredWaiters[key] = nil }
            return enteredWaiters[key]
        }
        enterWaiter?.resume()
        await withCheckedContinuation { continuation in
            let alreadyReleased: Bool = lock.withLock {
                if released.contains(key) {
                    released.remove(key)
                    return true
                }
                releaseWaiters[key] = continuation
                return false
            }
            if alreadyReleased { continuation.resume() }
        }
    }

    /// Called from the test: suspends until `child(for:)` has entered its pause for `key`.
    func waitUntilEntered(_ key: String) async {
        await withCheckedContinuation { continuation in
            let alreadyEntered: Bool = lock.withLock {
                if entered.contains(key) {
                    entered.remove(key)
                    return true
                }
                enteredWaiters[key] = continuation
                return false
            }
            if alreadyEntered { continuation.resume() }
        }
    }

    /// Called from the test: lets a paused `child(for:)` continue for `key`.
    func release(_ key: String) {
        let waiter: CheckedContinuation<Void, Never>? = lock.withLock {
            if let waiter = releaseWaiters[key] {
                releaseWaiters[key] = nil
                return waiter
            }
            released.insert(key)
            return nil
        }
        waiter?.resume()
    }
}
#endif
