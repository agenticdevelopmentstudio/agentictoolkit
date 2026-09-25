import AgenticToolkitHubService
import AgenticToolkitHTDV
import AgenticToolkitHub

/// Spec §5.4: the web's rail groups.
public enum FeatureGroup: String, CaseIterable, Sendable {
    case personas, products, security

    public var label: String {
        switch self {
        case .personas: "Personas"
        case .products: "Products"
        case .security: "Security"
        }
    }

    public var systemImage: String {
        switch self {
        case .personas: "person.2"
        case .products: "shippingbox"
        case .security: "lock.shield"
        }
    }
}

public struct FeatureMeta: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let group: FeatureGroup?
    public let leadsTo: HTDVLeadsTo
    public let workspaceTypes: Set<HubWorkspaceType>
    public let systemImage: String
    /// Non-nil: the row opens `HubLinks.workspaceURL(_:path:)` in the browser.
    public let linkPath: String?

    public init(
        id: String,
        label: String,
        group: FeatureGroup?,
        leadsTo: HTDVLeadsTo,
        workspaceTypes: Set<HubWorkspaceType>,
        systemImage: String,
        linkPath: String? = nil
    ) {
        self.id = id
        self.label = label
        self.group = group
        self.leadsTo = leadsTo
        self.workspaceTypes = workspaceTypes
        self.systemImage = systemImage
        self.linkPath = linkPath
    }

    public func isAvailable(in type: HubWorkspaceType) -> Bool {
        workspaceTypes.contains(type)
    }
}

/// The static v1 feature table (spec §2.1, §5.4). Order here is rail order.
public enum FeatureCatalog {
    private static let everyone: Set<HubWorkspaceType> = [.individual, .organization, .team]
    private static let notTeams: Set<HubWorkspaceType> = [.individual, .organization]

    public static let all: [FeatureMeta] = [
        FeatureMeta(
            id: "personas", label: "Personas", group: .personas, leadsTo: .list,
            workspaceTypes: everyone, systemImage: "person.crop.circle"
        ),
        FeatureMeta(
            id: "ecosystems", label: "Products", group: .products, leadsTo: .list,
            workspaceTypes: everyone, systemImage: "shippingbox"
        ),
        FeatureMeta(
            id: "billing", label: "Billing", group: .products, leadsTo: .list,
            workspaceTypes: notTeams, systemImage: "creditcard"
        ),
        FeatureMeta(
            id: "gamification", label: "Gamification", group: .products, leadsTo: .list,
            workspaceTypes: notTeams, systemImage: "gamecontroller"
        ),
        FeatureMeta(
            id: "authentication", label: "Authentication", group: .security, leadsTo: .list,
            workspaceTypes: everyone, systemImage: "key"
        ),
        FeatureMeta(
            id: "integrations", label: "Integrations", group: .security, leadsTo: .list,
            workspaceTypes: notTeams, systemImage: "link"
        ),
        FeatureMeta(
            id: "organizations", label: "Organizations", group: nil, leadsTo: .list,
            workspaceTypes: notTeams, systemImage: "building.2"
        ),
        FeatureMeta(
            id: "teams", label: "Teams", group: nil, leadsTo: .list,
            workspaceTypes: [.organization], systemImage: "person.3"
        ),
        FeatureMeta(
            id: "registries", label: "Registries", group: nil, leadsTo: .list,
            workspaceTypes: notTeams, systemImage: "books.vertical"
        ),
        FeatureMeta(
            id: "settings", label: "Settings", group: nil, leadsTo: .detail,
            workspaceTypes: everyone, systemImage: "gearshape"
        ),
        FeatureMeta(
            id: "messages", label: "Messages", group: nil, leadsTo: .detail,
            workspaceTypes: everyone, systemImage: "envelope", linkPath: "/messages"
        )
    ]

    public static func feature(id: String) -> FeatureMeta? {
        all.first { $0.id == id }
    }

    public static func groups(for type: HubWorkspaceType) -> [FeatureGroup] {
        FeatureGroup.allCases.filter { !features(in: $0, for: type).isEmpty }
    }

    public static func features(in group: FeatureGroup, for type: HubWorkspaceType) -> [FeatureMeta] {
        all.filter { $0.group == group && $0.isAvailable(in: type) }
    }

    public static func rootExtras(for type: HubWorkspaceType) -> [FeatureMeta] {
        all.filter { $0.group == nil && $0.isAvailable(in: type) }
    }
}
