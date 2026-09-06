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
        let gen = beginRequest(levelIndex: 0)
        do {
            let root = try await dataSource.rootLevel()
            guard gen == generation else { return }
            levels = [root]
            finishRequest()
        } catch {
            fail(gen: gen, levelIndex: 0, error)
        }
    }

    public func select(itemID: String, atLevel levelIndex: Int) async {
        guard levelIndex < levels.count, levels[levelIndex].items.contains(where: { $0.id == itemID }) else { return }
        levels = Array(levels.prefix(levelIndex + 1))
        selection = Array(selection.prefix(levelIndex)) + [itemID]
        detail = nil
        error = nil
        let childIndex = levelIndex + 1
        let gen = beginRequest(levelIndex: childIndex)
        let path = selectedPath()
        do {
            let child = try await dataSource.child(for: path)
            guard gen == generation else { return }
            apply(child)
            finishRequest()
        } catch {
            fail(gen: gen, levelIndex: childIndex, error)
        }
    }

    public func reload(level levelIndex: Int) async {
        guard levelIndex < levels.count else { return }
        error = nil
        let gen = beginRequest(levelIndex: levelIndex)
        do {
            let fresh: HTDVLevel
            if levelIndex == 0 {
                fresh = try await dataSource.rootLevel()
            } else {
                let parentPath = Array(selectedPath().prefix(levelIndex))
                guard case .level(let level) = try await dataSource.child(for: parentPath) else {
                    guard gen == generation else { return }
                    truncate(toLevel: levelIndex - 1)
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
            fail(gen: gen, levelIndex: levelIndex, error)
        }
    }

    public func retry() async {
        guard let error else { return }
        if error.levelIndex == 0 {
            await load()
        } else {
            let parentIndex = error.levelIndex - 1
            guard parentIndex < selection.count else { return }
            await select(itemID: selection[parentIndex], atLevel: parentIndex)
        }
    }

    // MARK: Private

    /// Drops everything below `levelIndex`: keeps `levels[0...levelIndex]`, clears the selection at
    /// and below it, and clears the detail.
    private func truncate(toLevel levelIndex: Int) {
        levels = Array(levels.prefix(levelIndex + 1))
        selection = Array(selection.prefix(levelIndex))
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
        onChange(self)
    }

    private func fail(gen: Int, levelIndex: Int, _ error: any Error) {
        guard gen == generation else { return }
        let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        self.error = HTDVLoadError(levelIndex: levelIndex, message: message)
        loadingLevelIndex = nil
        onChange(self)
    }
}
