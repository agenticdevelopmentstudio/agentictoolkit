import Foundation

/// One ecosystem ("product") row as the hub API returns it.
public struct Ecosystem: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var slug: String
    public var name: String
    public var description: String?
    public var region: String?
    public var primaryDomain: String?
    public var createdAt: String?
    public var updatedAt: String?
    public var isDefault: Bool
    public var isInfrastructure: Bool?
    public var parentId: String?
    public var canManage: Bool?

    public init(
        id: String, slug: String, name: String, description: String?, region: String?, primaryDomain: String?,
        createdAt: String?, updatedAt: String?, isDefault: Bool = false, isInfrastructure: Bool?,
        parentId: String?, canManage: Bool?
    ) {
        self.id = id; self.slug = slug; self.name = name; self.description = description
        self.region = region; self.primaryDomain = primaryDomain
        self.createdAt = createdAt; self.updatedAt = updatedAt
        self.isDefault = isDefault; self.isInfrastructure = isInfrastructure
        self.parentId = parentId; self.canManage = canManage
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        slug = try container.decode(String.self, forKey: .slug)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        region = try container.decodeIfPresent(String.self, forKey: .region)
        primaryDomain = try container.decodeIfPresent(String.self, forKey: .primaryDomain)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        isInfrastructure = try container.decodeIfPresent(Bool.self, forKey: .isInfrastructure)
        parentId = try container.decodeIfPresent(String.self, forKey: .parentId)
        canManage = try container.decodeIfPresent(Bool.self, forKey: .canManage)
    }

    /// Everything up to and including the last dot of the identifier: `"org.acme."` for `"org.acme.shop"`.
    public var identifierPrefix: String {
        guard let dot = id.lastIndex(of: ".") else { return "" }
        return String(id[...dot])
    }

    /// The API omits `canManage` for the caller's own ecosystems; only an explicit `false` blocks the rail.
    public var isManageable: Bool { canManage ?? true }
}

public struct EcosystemCreate: Codable, Hashable, Sendable {
    public var id: String
    public var slug: String
    public var name: String
    public var description: String
    public var region: String
    public var primaryDomain: String

    public init(
        id: String, slug: String, name: String, description: String, region: String = "", primaryDomain: String = ""
    ) {
        self.id = id; self.slug = slug; self.name = name; self.description = description
        self.region = region; self.primaryDomain = primaryDomain
    }
}

public struct EcosystemUpdate: Codable, Hashable, Sendable {
    public var slug: String?
    public var name: String?
    public var description: String?
    public var region: String?
    public var primaryDomain: String?

    public init(
        slug: String? = nil, name: String? = nil, description: String? = nil,
        region: String? = nil, primaryDomain: String? = nil
    ) {
        self.slug = slug; self.name = name; self.description = description
        self.region = region; self.primaryDomain = primaryDomain
    }
}
