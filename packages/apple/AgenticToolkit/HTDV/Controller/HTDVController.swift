import Foundation

/// A failed level load. `levelIndex` is the index of the level that failed to load (0 = root).
public struct HTDVLoadError: Sendable, Equatable {
    public let levelIndex: Int
    public let message: String

    public init(levelIndex: Int, message: String) {
        self.levelIndex = levelIndex
        self.message = message
    }
}

/// Owns the selected path through an `HTDVDataSource` tree and the levels/detail loaded for it.
/// Views observe it through `onChange`, which fires after every state transition.
@MainActor
public final class HTDVController {
    public private(set) var levels: [HTDVLevel] = []
    /// Selected item id per level; `selection.count <= levels.count`.
    public private(set) var selection: [String] = []
    public private(set) var detail: HTDVDetail?
    /// Index of the level currently being fetched, or nil when idle.
    public private(set) var loadingLevelIndex: Int?
    public private(set) var error: HTDVLoadError?
    public var isLoading: Bool { loadingLevelIndex != nil }
    public var onChange: (HTDVController) -> Void = { _ in }

    private let dataSource: any HTDVDataSource
    /// Incremented on every request; a response whose generation no longer matches is dropped.
    private var generation = 0

    /// The operation whose failure produced the current `error`, so `retry()` can re-issue exactly it.
    private enum FailedRequest {
        case load
        case select(itemID: String, level: Int)
        case reload(level: Int)
    }
    private var failedRequest: FailedRequest?

    public init(dataSource: any HTDVDataSource) {
        self.dataSource = dataSource
    }

    // MARK: Queries

    public func selectedPath() -> [HTDVItem] {
        selection.enumerated().compactMap { index, id in selectedItem(atLevel: index, id: id) }
    }

    public func selectedItem(atLevel levelIndex: Int) -> HTDVItem? {
        guard levelIndex < selection.count else { return nil }
        return selectedItem(atLevel: levelIndex, id: selection[levelIndex])
    }

    private func selectedItem(atLevel levelIndex: Int, id: String) -> HTDVItem? {
        guard levelIndex < levels.count else { return nil }
        return levels[levelIndex].items.first { $0.id == id }
    }

    // MARK: Commands

    public func load() async {
        levels = []
        selection = []
        detail = nil
        error = nil
        failedRequest = nil
        let gen = beginRequest(levelIndex: 0)
        do {
            let root = try await dataSource.rootLevel()
            guard gen == generation else { return }
            levels = [root]
            finishRequest()
        } catch {
            fail(gen: gen, levelIndex: 0, error, request: .load)
        }
    }

    public func select(itemID: String, atLevel levelIndex: Int) async {
        guard levelIndex < levels.count, levels[levelIndex].items.contains(where: { $0.id == itemID }) else { return }
        levels = Array(levels.prefix(levelIndex + 1))
        selection = Array(selection.prefix(levelIndex)) + [itemID]
        detail = nil
        error = nil
        failedRequest = nil
        let childIndex = levelIndex + 1
        let gen = beginRequest(levelIndex: childIndex)
        let path = selectedPath()
        do {
            let child = try await dataSource.child(for: path)
            guard gen == generation else { return }
            apply(child)
            finishRequest()
        } catch {
            let request = FailedRequest.select(itemID: itemID, level: levelIndex)
            fail(gen: gen, levelIndex: childIndex, error, request: request)
        }
    }

    public func reload(level levelIndex: Int) async {
        guard levelIndex < levels.count else { return }
        error = nil
        failedRequest = nil
        let gen = beginRequest(levelIndex: levelIndex)
        do {
            let fresh: HTDVLevel
            if levelIndex == 0 {
                fresh = try await dataSource.rootLevel()
            } else {
                let parentPath = Array(selectedPath().prefix(levelIndex))
                let child = try await dataSource.child(for: parentPath)
                guard gen == generation else { return }
                guard case .level(let level) = child else {
                    // The source no longer has a level at this path. Drop everything from here down,
                    // then apply whatever it returned instead: a `.detail` is real content the caller
                    // handed us, and throwing it away would show the user nothing at all.
                    levels = Array(levels.prefix(levelIndex))
                    selection = Array(selection.prefix(levelIndex))
                    detail = nil
                    apply(child)
                    finishRequest()
                    return
                }
                fresh = level
            }
            guard gen == generation else { return }
            levels[levelIndex] = fresh
            if levelIndex < selection.count, !fresh.items.contains(where: { $0.id == selection[levelIndex] }) {
                truncate(toLevel: levelIndex)
            }
            finishRequest()
        } catch {
            fail(gen: gen, levelIndex: levelIndex, error, request: .reload(level: levelIndex))
        }
    }

    public func retry() async {
        guard error != nil, let failed = failedRequest else { return }
        switch failed {
        case .load:
            await load()
        case .select(let itemID, let level):
            await select(itemID: itemID, atLevel: level)
        case .reload(let level):
            await reload(level: level)
        }
    }

    /// Reconciles the model with a user-driven pop (e.g. Back or an edge swipe) that already
    /// landed on `levelIndex` in the UI. `levelIndex == -1` means no level survives (all rails
    /// were popped off screen) and clears `levels`, `selection` and `detail` entirely. No-ops
    /// when `levelIndex` is at or beyond the current depth, or below `-1`, since there is
    /// nothing to truncate. Bumps `generation` first so any load already in flight for a level
    /// deeper than `levelIndex` is discarded by the existing `guard gen == generation` checks
    /// and cannot resurrect the popped state.
    @MainActor
    public func popToLevel(_ levelIndex: Int) {
        guard levelIndex >= -1, levelIndex < levels.count - 1 else { return }
        generation += 1
        truncate(toLevel: levelIndex)
        error = nil
        failedRequest = nil
        loadingLevelIndex = nil
        onChange(self)
    }

    /// Reconciles the model with a user-driven dismissal of the detail screen alone (the level it
    /// belongs to is unchanged — only the detail itself is gone). No-ops when there is no `detail`
    /// to clear, since there is nothing to reconcile. Bumps `generation` first so a detail load
    /// already in flight is discarded by the existing `guard gen == generation` checks and cannot
    /// resurrect the dismissed detail. Leaves `levels` and `selection` untouched: the user backed
    /// out of the detail, not the level that owns it, so the rail selection must stay highlighted.
    @MainActor
    public func clearDetail() {
        guard detail != nil else { return }
        generation += 1
        detail = nil
        error = nil
        failedRequest = nil
        loadingLevelIndex = nil
        onChange(self)
    }

    // MARK: Private

    /// Drops everything below `levelIndex`: keeps `levels[0...levelIndex]`, clears the selection at
    /// and below it, and clears the detail.
    private func truncate(toLevel levelIndex: Int) {
        levels = Array(levels.prefix(levelIndex + 1))
        selection = Array(selection.prefix(max(0, levelIndex)))
        detail = nil
    }

    private func apply(_ child: HTDVChild) {
        switch child {
        case .level(let level): levels.append(level)
        case .detail(let detail): self.detail = detail
        case .empty: break
        }
    }

    private func beginRequest(levelIndex: Int) -> Int {
        generation += 1
        loadingLevelIndex = levelIndex
        onChange(self)
        return generation
    }

    private func finishRequest() {
        loadingLevelIndex = nil
        failedRequest = nil
        onChange(self)
    }

    private func fail(gen: Int, levelIndex: Int, _ error: any Error, request: FailedRequest) {
        guard gen == generation else { return }
        let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        self.error = HTDVLoadError(levelIndex: levelIndex, message: message)
        failedRequest = request
        loadingLevelIndex = nil
        onChange(self)
    }
}
