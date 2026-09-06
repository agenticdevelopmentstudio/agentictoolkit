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

    func testOnChangeFiresForLoadingAndLoaded() async {
        let controller = HTDVController(dataSource: makeTree())
        var snapshots: [(loading: Int?, count: Int)] = []
        controller.onChange = { snapshots.append(($0.loadingLevelIndex, $0.levels.count)) }
        await controller.load()
        XCTAssertEqual(snapshots.map(\.loading), [0, nil])
        XCTAssertEqual(snapshots.map(\.count), [0, 1])
    }
}
