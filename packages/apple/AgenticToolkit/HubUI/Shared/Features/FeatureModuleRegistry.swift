import AgenticToolkitHubService
import AgenticToolkitHTDV
import AgenticToolkitHub

public typealias FeatureModuleFactory = @MainActor (HubWorkspace) -> any HTDVDataSource

/// Where Plans 4–5 plug their feature modules in. A module is an
/// `HTDVDataSource` scoped to one workspace; the registry caches one
/// instance per (feature, workspace) so re-entering a feature keeps its state.
@MainActor
public final class FeatureModuleRegistry {
    private struct CacheKey: Hashable {
        let featureID: String
        let slug: String
    }

    private var factories: [String: FeatureModuleFactory] = [:]
    private var cache: [CacheKey: any HTDVDataSource] = [:]

    public init() {}

    public func register(id: String, make: @escaping FeatureModuleFactory) {
        factories[id] = make
        cache = cache.filter { $0.key.featureID != id }
    }

    public func isRegistered(_ id: String) -> Bool {
        factories[id] != nil
    }

    public func dataSource(for id: String, workspace: HubWorkspace) -> (any HTDVDataSource)? {
        guard let make = factories[id] else { return nil }
        let key = CacheKey(featureID: id, slug: workspace.slug)
        if let cached = cache[key] { return cached }
        let created = make(workspace)
        cache[key] = created
        return created
    }

    public func reset() {
        cache.removeAll()
    }
}
