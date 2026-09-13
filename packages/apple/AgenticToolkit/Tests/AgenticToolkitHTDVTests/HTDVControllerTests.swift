import XCTest
@testable import AgenticToolkitHTDV

/// In-memory tree keyed by "/"-joined item ids. Thread-safe because the controller calls it off the main actor.
final class TreeDataSource: HTDVDataSource, @unchecked Sendable {
    private let lock = NSLock()
    private var root: HTDVLevel
    private var children: [String: HTDVChild]
    private var delays: [String: UInt64] = [:]
    private var failNext = false
    private var recordedCalls: [String] = []

    struct Failure: Error, LocalizedError {
        var errorDescription: String? { "boom" }
    }

    init(root: HTDVLevel, children: [String: HTDVChild]) {
        self.root = root
        self.children = children
    }

    var calls: [String] { lock.withLock { recordedCalls } }

    func setRoot(_ level: HTDVLevel) { lock.withLock { root = level } }
    func setChild(_ child: HTDVChild, at key: String) { lock.withLock { children[key] = child } }
    func delay(_ nanos: UInt64, at key: String) { lock.withLock { delays[key] = nanos } }
    func failNextRequest() { lock.withLock { failNext = true } }

    func rootLevel() async throws -> HTDVLevel {
        try await respond(key: "") { root }
    }

    func child(for path: [HTDVItem]) async throws -> HTDVChild {
        let key = path.map(\.id).joined(separator: "/")
        return try await respond(key: key) { children[key] ?? .empty }
    }

    private func respond<T>(key: String, _ value: () -> T) async throws -> T {
        let (shouldFail, delay, result): (Bool, UInt64, T) = lock.withLock {
            recordedCalls.append(key)
            let fail = failNext
            failNext = false
            return (fail, delays[key] ?? 0, value())
        }
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        if shouldFail { throw Failure() }
        return result
    }
}

@MainActor
final class HTDVControllerTests: XCTestCase {
    private func makeTree() -> TreeDataSource {
        let root = HTDVLevel(id: "root", title: "Root", items: [
            HTDVItem(id: "a", label: "A"),
            HTDVItem(id: "b", label: "B"),
            HTDVItem(id: "s", label: "Settings", leadsTo: .detail)
        ])
        let aLevel = HTDVLevel(id: "a-children", title: "A", items: [
            HTDVItem(id: "a1", label: "A1", leadsTo: .detail),
            HTDVItem(id: "a2", label: "A2")
        ])
        let bLevel = HTDVLevel(id: "b-children", title: "B", items: [HTDVItem(id: "b1", label: "B1", leadsTo: .detail)])
        let detail = HTDVDetail(id: "settings", title: "Settings") { PlatformViewController() }
        return TreeDataSource(root: root, children: [
            "a": .level(aLevel),
            "b": .level(bLevel),
            "s": .detail(detail),
            "a/a1": .detail(HTDVDetail(id: "a1", title: "A1") { PlatformViewController() }),
            "a/a2": .empty
        ])
    }

    func testLoadPopulatesRootLevel() async {
        let controller = HTDVController(dataSource: makeTree())
        await controller.load()
        XCTAssertEqual(controller.levels.map(\.id), ["root"])
        XCTAssertTrue(controller.selection.isEmpty)
        XCTAssertNil(controller.error)
        XCTAssertFalse(controller.isLoading)
    }

    func testSelectListItemAppendsLevel() async {
        let controller = HTDVController(dataSource: makeTree())
        await controller.load()
        await controller.select(itemID: "a", atLevel: 0)
        XCTAssertEqual(controller.levels.map(\.id), ["root", "a-children"])
        XCTAssertEqual(controller.selection, ["a"])
        XCTAssertNil(controller.detail)
        XCTAssertEqual(controller.selectedPath().map(\.id), ["a"])
    }

    func testSelectDetailItemSetsDetail() async {
        let controller = HTDVController(dataSource: makeTree())
        await controller.load()
        await controller.select(itemID: "s", atLevel: 0)
        XCTAssertEqual(controller.levels.count, 1)
        XCTAssertEqual(controller.detail?.id, "settings")
    }

    func testSelectingAtShallowerLevelTruncatesDeeperLevels() async {
        let controller = HTDVController(dataSource: makeTree())
        await controller.load()
        await controller.select(itemID: "a", atLevel: 0)
        await controller.select(itemID: "a1", atLevel: 1)
        XCTAssertEqual(controller.detail?.id, "a1")
        await controller.select(itemID: "b", atLevel: 0)
        XCTAssertEqual(controller.levels.map(\.id), ["root", "b-children"])
        XCTAssertEqual(controller.selection, ["b"])
        XCTAssertNil(controller.detail)
    }

    func testEmptyChildLeavesLevelsAndDetailUnchanged() async {
        let controller = HTDVController(dataSource: makeTree())
        await controller.load()
        await controller.select(itemID: "a", atLevel: 0)
        await controller.select(itemID: "a2", atLevel: 1)
        XCTAssertEqual(controller.levels.count, 2)
        XCTAssertEqual(controller.selection, ["a", "a2"])
        XCTAssertNil(controller.detail)
    }

    func testSelectUnknownItemIsIgnored() async {
        let tree = makeTree()
        let controller = HTDVController(dataSource: tree)
        await controller.load()
        await controller.select(itemID: "zzz", atLevel: 0)
        XCTAssertEqual(tree.calls, [""])
        XCTAssertTrue(controller.selection.isEmpty)
    }

    func testReloadKeepsSelectionWhenItemStillExists() async {
        let tree = makeTree()
        let controller = HTDVController(dataSource: tree)
        await controller.load()
        await controller.select(itemID: "a", atLevel: 0)
        tree.setRoot(HTDVLevel(id: "root", title: "Root", items: [
            HTDVItem(id: "a", label: "A renamed"),
            HTDVItem(id: "b", label: "B")
        ]))
        await controller.reload(level: 0)
        XCTAssertEqual(controller.levels[0].items.first?.label, "A renamed")
        XCTAssertEqual(controller.levels.map(\.id), ["root", "a-children"])
        XCTAssertEqual(controller.selection, ["a"])
    }

    func testReloadDropsSelectionWhenItemDisappeared() async {
        let tree = makeTree()
        let controller = HTDVController(dataSource: tree)
        await controller.load()
        await controller.select(itemID: "a", atLevel: 0)
        tree.setRoot(HTDVLevel(id: "root", title: "Root", items: [HTDVItem(id: "b", label: "B")]))
        await controller.reload(level: 0)
        XCTAssertEqual(controller.levels.map(\.id), ["root"])
        XCTAssertTrue(controller.selection.isEmpty)
        XCTAssertNil(controller.detail)
    }

    func testReloadOfNestedLevelUsesParentPath() async {
        let tree = makeTree()
        let controller = HTDVController(dataSource: tree)
        await controller.load()
        await controller.select(itemID: "a", atLevel: 0)
        tree.setChild(
            .level(HTDVLevel(id: "a-children", title: "A", items: [HTDVItem(id: "a9", label: "A9")])),
            at: "a"
        )
        await controller.reload(level: 1)
        XCTAssertEqual(tree.calls.last, "a")
        XCTAssertEqual(controller.levels[1].items.map(\.id), ["a9"])
    }

    func testErrorSurfacesAndRetryRecovers() async {
        let tree = makeTree()
        let controller = HTDVController(dataSource: tree)
        await controller.load()
        tree.failNextRequest()
        await controller.select(itemID: "a", atLevel: 0)
        XCTAssertEqual(controller.error, HTDVLoadError(levelIndex: 1, message: "boom"))
        XCTAssertEqual(controller.levels.count, 1)
        XCTAssertFalse(controller.isLoading)
        await controller.retry()
        XCTAssertNil(controller.error)
        XCTAssertEqual(controller.levels.map(\.id), ["root", "a-children"])
    }

    func testRootErrorRetryReloadsRoot() async {
        let tree = makeTree()
        tree.failNextRequest()
        let controller = HTDVController(dataSource: tree)
        await controller.load()
        XCTAssertEqual(controller.error?.levelIndex, 0)
        XCTAssertTrue(controller.levels.isEmpty)
        await controller.retry()
        XCTAssertEqual(controller.levels.map(\.id), ["root"])
    }

    func testStaleResultIsDropped() async throws {
        let tree = makeTree()
        tree.delay(200_000_000, at: "a")
        let controller = HTDVController(dataSource: tree)
        await controller.load()
        let slow = Task { await controller.select(itemID: "a", atLevel: 0) }
        try await Task.sleep(nanoseconds: 20_000_000)
        let fast = Task { await controller.select(itemID: "b", atLevel: 0) }
        await slow.value
        await fast.value
        XCTAssertEqual(controller.selection, ["b"])
        XCTAssertEqual(controller.levels.map(\.id), ["root", "b-children"])
        XCTAssertFalse(controller.isLoading)
    }

    func testRetryAfterFailedReloadPreservesDeeperLevels() async {
        let tree = makeTree()
        let controller = HTDVController(dataSource: tree)
        await controller.load()
        await controller.select(itemID: "a", atLevel: 0)
        tree.setChild(
            .level(HTDVLevel(id: "a2-children", title: "A2", items: [HTDVItem(id: "a2x", label: "A2X")])),
            at: "a/a2"
        )
        await controller.select(itemID: "a2", atLevel: 1)
        XCTAssertEqual(controller.levels.map(\.id), ["root", "a-children", "a2-children"])

        tree.failNextRequest()
        await controller.reload(level: 1)
        XCTAssertEqual(controller.error?.levelIndex, 1)
        XCTAssertEqual(controller.levels.map(\.id), ["root", "a-children", "a2-children"])

        await controller.retry()
        XCTAssertNil(controller.error)
        XCTAssertEqual(controller.levels.map(\.id), ["root", "a-children", "a2-children"])
        XCTAssertEqual(controller.levels[2].items.map(\.id), ["a2x"])
    }

    /// `reload(level:)` used to throw away the `HTDVChild` it was handed whenever it was not a
    /// `.level` — so a level whose only child had been deleted, leaving the source returning a
    /// `.detail` for that path, truncated and showed nothing instead of the detail it was given.
    /// The payload is part of the public data-source contract every later feature inherits.
    func testReloadAppliesDetailReturnedWhereLevelWasExpected() async {
        let tree = makeTree()
        let controller = HTDVController(dataSource: tree)
        await controller.load()
        await controller.select(itemID: "a", atLevel: 0)
        XCTAssertEqual(controller.levels.count, 2)

        tree.setChild(.detail(HTDVDetail(id: "a-detail", title: "A") { PlatformViewController() }), at: "a")
        await controller.reload(level: 1)

        XCTAssertEqual(controller.levels.map(\.id), ["root"])
        XCTAssertEqual(controller.selection, ["a"])
        XCTAssertEqual(controller.detail?.id, "a-detail")
        XCTAssertNil(controller.error)
        XCTAssertFalse(controller.isLoading)
    }

    func testReloadWhereChildStopsBeingLevelKeepsParentSelection() async {
        let tree = makeTree()
        let controller = HTDVController(dataSource: tree)
        await controller.load()
        await controller.select(itemID: "a", atLevel: 0)
        XCTAssertEqual(controller.selection, ["a"])
        XCTAssertEqual(controller.levels.count, 2)

        tree.setChild(.empty, at: "a")
        await controller.reload(level: 1)

        XCTAssertEqual(controller.levels.count, 1)
        XCTAssertEqual(controller.selection, ["a"])
        XCTAssertNil(controller.detail)
    }

    func testOnChangeFiresForLoadingAndLoaded() async {
        let controller = HTDVController(dataSource: makeTree())
        var snapshots: [(loading: Int?, count: Int)] = []
        controller.onChange = { snapshots.append(($0.loadingLevelIndex, $0.levels.count)) }
        await controller.load()
        XCTAssertEqual(snapshots.map(\.loading), [0, nil])
        XCTAssertEqual(snapshots.map(\.count), [0, 1])
    }

    // MARK: popToLevel

    /// A tree three levels deep, distinct from `makeTree()`'s two-level shape, so truncation tests
    /// can drop a real intermediate level rather than only ever dropping to root.
    private func makeDeepTree() -> TreeDataSource {
        let root = HTDVLevel(id: "root", title: "Root", items: [HTDVItem(id: "a", label: "A")])
        let aLevel = HTDVLevel(id: "a-children", title: "A", items: [HTDVItem(id: "a1", label: "A1")])
        let a1Level = HTDVLevel(id: "a1-children", title: "A1", items: [HTDVItem(id: "a1x", label: "A1X")])
        return TreeDataSource(root: root, children: ["a": .level(aLevel), "a/a1": .level(a1Level)])
    }

    func testPopToLevelTruncatesLevelsAndSelection() async {
        let controller = HTDVController(dataSource: makeDeepTree())
        await controller.load()
        await controller.select(itemID: "a", atLevel: 0)
        await controller.select(itemID: "a1", atLevel: 1)
        XCTAssertEqual(controller.levels.map(\.id), ["root", "a-children", "a1-children"])
        XCTAssertEqual(controller.selection, ["a", "a1"])

        controller.popToLevel(1)

        XCTAssertEqual(controller.levels.map(\.id), ["root", "a-children"])
        XCTAssertEqual(controller.selection, ["a"])
    }

    func testPopToLevelDiscardsInFlightDeeperLoad() async throws {
        let tree = makeDeepTree()
        tree.delay(200_000_000, at: "a/a1")
        let controller = HTDVController(dataSource: tree)
        await controller.load()
        await controller.select(itemID: "a", atLevel: 0)
        let slow = Task { await controller.select(itemID: "a1", atLevel: 1) }
        try await Task.sleep(nanoseconds: 20_000_000)
        // The user backed out to level 0 while the deeper load for level 2 is still in flight.
        controller.popToLevel(0)
        await slow.value

        XCTAssertEqual(controller.levels.map(\.id), ["root"])
        XCTAssertEqual(controller.selection, [])
        XCTAssertFalse(controller.isLoading)
    }

    func testPopToLevelClearsDetailAndError() async {
        let tree = makeTree()
        let controller = HTDVController(dataSource: tree)
        await controller.load()
        await controller.select(itemID: "a", atLevel: 0)
        await controller.select(itemID: "a1", atLevel: 1)
        XCTAssertEqual(controller.detail?.id, "a1")
        tree.failNextRequest()
        await controller.reload(level: 1)
        XCTAssertNotNil(controller.error)

        controller.popToLevel(0)

        XCTAssertNil(controller.detail)
        XCTAssertNil(controller.error)
        XCTAssertEqual(controller.levels.map(\.id), ["root"])
    }

    func testPopToLevelFiresOnChangeOnceWithUpdatedState() async {
        let controller = HTDVController(dataSource: makeTree())
        await controller.load()
        await controller.select(itemID: "a", atLevel: 0)
        var callCount = 0
        var snapshotLevels: [String] = []
        var snapshotSelection: [String] = []
        controller.onChange = { changed in
            callCount += 1
            snapshotLevels = changed.levels.map(\.id)
            snapshotSelection = changed.selection
        }

        controller.popToLevel(0)

        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(snapshotLevels, ["root"])
        XCTAssertEqual(snapshotSelection, [])
    }

    func testPopToLevelNoOpsWhenAtOrBeyondCurrentDepth() async {
        let controller = HTDVController(dataSource: makeTree())
        await controller.load()
        await controller.select(itemID: "a", atLevel: 0)
        XCTAssertEqual(controller.levels.map(\.id), ["root", "a-children"])
        var callCount = 0
        controller.onChange = { _ in callCount += 1 }

        controller.popToLevel(1)
        controller.popToLevel(5)

        XCTAssertEqual(callCount, 0)
        XCTAssertEqual(controller.levels.map(\.id), ["root", "a-children"])
        XCTAssertEqual(controller.selection, ["a"])
    }

    func testPopToLevelNegativeOneClearsEverything() async {
        let controller = HTDVController(dataSource: makeDeepTree())
        await controller.load()
        await controller.select(itemID: "a", atLevel: 0)
        await controller.select(itemID: "a1", atLevel: 1)
        XCTAssertEqual(controller.levels.map(\.id), ["root", "a-children", "a1-children"])
        var callCount = 0
        controller.onChange = { _ in callCount += 1 }

        controller.popToLevel(-1)

        XCTAssertEqual(callCount, 1)
        XCTAssertTrue(controller.levels.isEmpty)
        XCTAssertTrue(controller.selection.isEmpty)
        XCTAssertNil(controller.detail)
    }

    func testPopToLevelNegativeOneDiscardsInFlightDeeperLoad() async throws {
        let tree = makeDeepTree()
        tree.delay(200_000_000, at: "a/a1")
        let controller = HTDVController(dataSource: tree)
        await controller.load()
        await controller.select(itemID: "a", atLevel: 0)
        let slow = Task { await controller.select(itemID: "a1", atLevel: 1) }
        try await Task.sleep(nanoseconds: 20_000_000)
        // All rails were popped off screen while the deeper load for level 2 is still in flight.
        controller.popToLevel(-1)
        await slow.value

        XCTAssertTrue(controller.levels.isEmpty)
        XCTAssertTrue(controller.selection.isEmpty)
        XCTAssertFalse(controller.isLoading)
    }

    func testPopToLevelNegativeOneOnEmptyLevelsIsNoOp() {
        let controller = HTDVController(dataSource: makeDeepTree())
        var callCount = 0
        controller.onChange = { _ in callCount += 1 }

        controller.popToLevel(-1)

        XCTAssertEqual(callCount, 0)
        XCTAssertTrue(controller.levels.isEmpty)
    }

    func testPopToLevelBelowNegativeOneIsNoOp() async {
        let controller = HTDVController(dataSource: makeDeepTree())
        await controller.load()
        await controller.select(itemID: "a", atLevel: 0)
        await controller.select(itemID: "a1", atLevel: 1)
        var callCount = 0
        controller.onChange = { _ in callCount += 1 }

        controller.popToLevel(-2)

        XCTAssertEqual(callCount, 0)
        XCTAssertEqual(controller.levels.map(\.id), ["root", "a-children", "a1-children"])
        XCTAssertEqual(controller.selection, ["a", "a1"])
    }

    /// Before the fix, `truncate(toLevel:)` called `selection.prefix(levelIndex)` directly, which
    /// traps at runtime for a negative count. This proves `popToLevel(-1)` clears a non-empty
    /// `selection` without crashing.
    func testPopToLevelNegativeOneClearsSelectionWithoutTrapping() async {
        let controller = HTDVController(dataSource: makeDeepTree())
        await controller.load()
        await controller.select(itemID: "a", atLevel: 0)
        XCTAssertEqual(controller.selection, ["a"])

        controller.popToLevel(-1)

        XCTAssertTrue(controller.selection.isEmpty)
    }

    // MARK: clearDetail

    func testClearDetailClearsDetailAndFiresOnChangeOnce() async {
        let controller = HTDVController(dataSource: makeTree())
        await controller.load()
        await controller.select(itemID: "a", atLevel: 0)
        await controller.select(itemID: "a1", atLevel: 1)
        XCTAssertEqual(controller.detail?.id, "a1")
        var callCount = 0
        var snapshotDetailID: String?
        controller.onChange = { changed in
            callCount += 1
            snapshotDetailID = changed.detail?.id
        }

        controller.clearDetail()

        XCTAssertEqual(callCount, 1)
        XCTAssertNil(snapshotDetailID)
        XCTAssertNil(controller.detail)
    }

    func testClearDetailLeavesLevelsAndSelectionUntouched() async {
        let controller = HTDVController(dataSource: makeTree())
        await controller.load()
        await controller.select(itemID: "a", atLevel: 0)
        await controller.select(itemID: "a1", atLevel: 1)
        XCTAssertEqual(controller.levels.map(\.id), ["root", "a-children"])
        XCTAssertEqual(controller.selection, ["a", "a1"])

        controller.clearDetail()

        XCTAssertEqual(controller.levels.map(\.id), ["root", "a-children"])
        XCTAssertEqual(controller.selection, ["a", "a1"])
        XCTAssertNil(controller.detail)
    }

    func testClearDetailNoOpsWhenNoDetail() async {
        let controller = HTDVController(dataSource: makeTree())
        await controller.load()
        await controller.select(itemID: "a", atLevel: 0)
        XCTAssertNil(controller.detail)
        var callCount = 0
        controller.onChange = { _ in callCount += 1 }

        controller.clearDetail()

        XCTAssertEqual(callCount, 0)
    }

    /// `select`/`load` both clear `detail` synchronously as the first thing they do when starting a
    /// new fetch, so neither can ever leave `detail` populated while its own fetch is in flight —
    /// there is no window in which `clearDetail()` would find something to clear from a select/load
    /// race. `reload` is the only controller operation that doesn't touch `detail` up front, making
    /// it the only way to construct a race where `detail` is still populated when `clearDetail()`
    /// runs concurrently with an in-flight load. This proves `clearDetail()`'s generation bump
    /// discards that load's landing (the refreshed level it would have applied never lands), the same
    /// mechanism `popToLevel` relies on.
    func testClearDetailDiscardsInFlightLoad() async throws {
        let tree = makeTree()
        let controller = HTDVController(dataSource: tree)
        await controller.load()
        await controller.select(itemID: "a", atLevel: 0)
        await controller.select(itemID: "a1", atLevel: 1)
        XCTAssertEqual(controller.detail?.id, "a1")

        let replacementLevel = HTDVLevel(
            id: "a-children-refreshed", title: "A", items: [HTDVItem(id: "a1", label: "A1", leadsTo: .detail)]
        )
        tree.setChild(.level(replacementLevel), at: "a")
        tree.delay(200_000_000, at: "a")
        let slow = Task { await controller.reload(level: 1) }
        try await Task.sleep(nanoseconds: 20_000_000)
        controller.clearDetail()
        await slow.value

        XCTAssertNil(controller.detail)
        XCTAssertFalse(controller.isLoading)
        XCTAssertEqual(controller.levels.map(\.id), ["root", "a-children"])
    }
}
