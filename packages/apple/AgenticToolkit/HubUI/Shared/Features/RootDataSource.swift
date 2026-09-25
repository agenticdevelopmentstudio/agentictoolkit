import AgenticToolkitHubService
import AgenticToolkitHTDV
import AgenticToolkitHub

/// The root rail (spec §5.4): groups → features → whatever the feature's
/// module appends. Item ids are namespaced (`group:`/`feature:`) so the
/// module's own ids can never collide with the shell's.
@MainActor
public final class RootDataSource: HTDVDataSource {
    public static let groupPrefix = "group:"
    public static let featurePrefix = "feature:"
    public static let unavailableMessage = "Not available in this version"

    private let workspace: HubWorkspace
    private let registry: FeatureModuleRegistry
    private let catalog: [FeatureMeta]

    public init(
        workspace: HubWorkspace,
        registry: FeatureModuleRegistry,
        catalog: [FeatureMeta] = FeatureCatalog.all
    ) {
        self.workspace = workspace
        self.registry = registry
        self.catalog = catalog
    }

    public func rootLevel() async throws -> HTDVLevel {
        let type = workspace.type
        let groups = FeatureGroup.allCases.filter { !features(in: $0, for: type).isEmpty }
        let extras = catalog.filter { $0.group == nil && $0.isAvailable(in: type) }
        var items: [HTDVItem] = groups.enumerated().map { index, group in
            HTDVItem(
                id: Self.groupPrefix + group.rawValue,
                label: group.label,
                systemImage: group.systemImage,
                dividerAfter: index == groups.count - 1 && !extras.isEmpty,
                leadsTo: .list
            )
        }
        items += extras.map(item(for:))
        return HTDVLevel(id: "root", title: workspace.listLabel, items: items)
    }

    public func child(for path: [HTDVItem]) async throws -> HTDVChild {
        guard let first = path.first else { return .empty }
        if first.id.hasPrefix(Self.groupPrefix) {
            let rawGroup = String(first.id.dropFirst(Self.groupPrefix.count))
            guard let group = FeatureGroup(rawValue: rawGroup) else { return .empty }
            if path.count == 1 {
                return .level(HTDVLevel(
                    id: "features:\(group.rawValue)",
                    title: group.label,
                    items: features(in: group, for: workspace.type).map(item(for:))
                ))
            }
            return try await featureChild(featureItem: path[1], modulePath: Array(path.dropFirst(2)))
        }
        if first.id.hasPrefix(Self.featurePrefix) {
            return try await featureChild(featureItem: first, modulePath: Array(path.dropFirst(1)))
        }
        return .empty
    }

    // MARK: Private

    private func features(in group: FeatureGroup, for type: HubWorkspaceType) -> [FeatureMeta] {
        catalog.filter { $0.group == group && $0.isAvailable(in: type) }
    }

    private func item(for feature: FeatureMeta) -> HTDVItem {
        HTDVItem(
            id: Self.featurePrefix + feature.id,
            label: feature.label,
            systemImage: feature.systemImage,
            leadsTo: feature.leadsTo
        )
    }

    private func featureChild(featureItem: HTDVItem, modulePath: [HTDVItem]) async throws -> HTDVChild {
        let featureID = String(featureItem.id.dropFirst(Self.featurePrefix.count))
        guard
            featureItem.id.hasPrefix(Self.featurePrefix),
            let feature = catalog.first(where: { $0.id == featureID })
        else {
            return .empty
        }
        if let linkPath = feature.linkPath {
            let url = HubLinks.workspaceURL(workspace, path: linkPath)
            let title = feature.label
            return .detail(HTDVDetail(id: featureItem.id, title: title) {
                LinkOutViewController(title: title, url: url)
            })
        }
        if let module = registry.dataSource(for: feature.id, workspace: workspace) {
            if modulePath.isEmpty {
                return .level(try await module.rootLevel())
            }
            return try await module.child(for: modulePath)
        }
        if feature.leadsTo == .detail {
            let title = feature.label
            return .detail(HTDVDetail(id: featureItem.id, title: title) {
                UnavailableViewController(title: title)
            })
        }
        return .level(HTDVLevel(
            id: "unavailable:\(feature.id)",
            title: feature.label,
            items: [],
            emptyMessage: Self.unavailableMessage
        ))
    }
}
