import Foundation

// MARK: API tokens (`/auth/tokens`)

/// A personal API token (`tmp_…`). `scope` nil/empty means the legacy curated-only token.
public struct ApiToken: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var prefix: String
    public var createdAt: String
    public var expiresAt: String?
    public var lastUsedAt: String?
    public var scope: [String]?

    public init(
        id: String, name: String, prefix: String, createdAt: String,
        expiresAt: String? = nil, lastUsedAt: String? = nil, scope: [String]? = nil
    ) {
        self.id = id; self.name = name; self.prefix = prefix; self.createdAt = createdAt
        self.expiresAt = expiresAt; self.lastUsedAt = lastUsedAt; self.scope = scope
    }

    /// `"a, b"` for a scoped token, `"legacy"` for the curated-only kind.
    public var scopeLine: String {
        let scopes = scope ?? []
        return scopes.isEmpty ? "legacy" : scopes.joined(separator: ", ")
    }
}

public struct ApiTokenCreated: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var prefix: String
    public var createdAt: String
    public var expiresAt: String?
    public var scope: [String]?
    public var token: String

    public init(
        id: String, name: String, prefix: String, createdAt: String,
        expiresAt: String? = nil, scope: [String]? = nil, token: String
    ) {
        self.id = id; self.name = name; self.prefix = prefix; self.createdAt = createdAt
        self.expiresAt = expiresAt; self.scope = scope; self.token = token
    }
}

public struct ApiTokenCreate: Codable, Hashable, Sendable {
    public var name: String
    public var expiresAt: String?
    public var scope: [String]?
    public init(name: String, expiresAt: String? = nil, scope: [String]? = nil) {
        self.name = name; self.expiresAt = expiresAt; self.scope = scope
    }
}

public protocol ApiTokensDataSource: AnyObject, Sendable {
    func list() async throws -> [ApiToken]
    /// The scope catalogue (`GET /auth/tokens/scopes` → `prefixes`).
    func scopes() async throws -> [String]
    func create(_ body: ApiTokenCreate) async throws -> ApiTokenCreated
    func revoke(id: String) async throws
}

// MARK: Bucket access lists (`/bucket/access-groups`)

public enum AccessMemberType: String, CaseIterable, Codable, Sendable {
    case user, organization, persona
    /// The contract's enum is `["user","organization","persona","app","token"]`. Sending "application"
    /// 400s every time, so the raw value is "app"; the case keeps its readable name. Declared here, not
    /// appended, so `allCases` — and therefore the picker — keeps its order.
    case application = "app"
    case token

    public var title: String {
        switch self {
        case .user: "User"
        case .organization: "Organization"
        case .persona: "Persona"
        case .application: "Application"
        case .token: "Token"
        }
    }

    public var systemImage: String {
        switch self {
        case .user: "person"
        case .organization: "building.2"
        case .persona: "person.crop.circle"
        case .application: "app"
        case .token: "key"
        }
    }
}

public enum AccessTargetType: String, CaseIterable, Codable, Sendable {
    case bucket
    case bucketType = "bucket_type"
    case row

    public var title: String {
        switch self {
        case .bucket: "Whole bucket"
        case .bucketType: "Bucket type"
        case .row: "Single row"
        }
    }
}

/// The C/R/U/D flags of a grant, serialised as a comma-separated subset of `C,R,U,D` (`""` when none).
public struct AccessCRUD: Hashable, Sendable {
    public var create: Bool
    public var read: Bool
    public var update: Bool
    public var delete: Bool

    public init(create: Bool = false, read: Bool = false, update: Bool = false, delete: Bool = false) {
        self.create = create; self.read = read; self.update = update; self.delete = delete
    }

    public init(crud: String) {
        let flags = Set(crud.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() })
        self.init(
            create: flags.contains("C"), read: flags.contains("R"),
            update: flags.contains("U"), delete: flags.contains("D")
        )
    }

    public var crud: String {
        var parts: [String] = []
        if create { parts.append("C") }
        if read { parts.append("R") }
        if update { parts.append("U") }
        if delete { parts.append("D") }
        return parts.joined(separator: ",")
    }

    public var isEmpty: Bool { !(create || read || update || delete) }

    public var summary: String {
        var parts: [String] = []
        if create { parts.append("Create") }
        if read { parts.append("Read") }
        if update { parts.append("Update") }
        if delete { parts.append("Delete") }
        return parts.isEmpty ? "No access" : parts.joined(separator: " · ")
    }
}

public struct AccessGroup: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var ecosystemId: String
    public var bucketId: String
    public var name: String
    public var description: String
    public var kind: String
    public var createdAt: String?
    public var updatedAt: String?

    public init(
        id: String, ecosystemId: String, bucketId: String, name: String, description: String = "",
        kind: String = "custom", createdAt: String? = nil, updatedAt: String? = nil
    ) {
        self.id = id; self.ecosystemId = ecosystemId; self.bucketId = bucketId
        self.name = name; self.description = description
        self.kind = kind; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    public var isEveryone: Bool { kind == "everyone" }
    public var displayName: String { isEveryone ? "Everyone" : name }
}

public struct AccessGroupMember: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var ecosystemId: String
    public var accessGroupId: String
    public var memberType: String
    public var memberId: String
    public var createdAt: String?

    public init(
        id: String, ecosystemId: String, accessGroupId: String, memberType: String,
        memberId: String, createdAt: String? = nil
    ) {
        self.id = id; self.ecosystemId = ecosystemId; self.accessGroupId = accessGroupId
        self.memberType = memberType; self.memberId = memberId; self.createdAt = createdAt
    }

    public var type: AccessMemberType? { AccessMemberType(rawValue: memberType) }
    public var typeTitle: String { type?.title ?? memberType }
}

public struct AccessGrant: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var ecosystemId: String
    public var accessGroupId: String
    public var targetType: String
    public var targetId: String
    public var crud: String
    public var grantedBy: String?
    public var createdAt: String?

    public init(
        id: String, ecosystemId: String, accessGroupId: String, targetType: String, targetId: String,
        crud: String, grantedBy: String? = nil, createdAt: String? = nil
    ) {
        self.id = id; self.ecosystemId = ecosystemId; self.accessGroupId = accessGroupId
        self.targetType = targetType; self.targetId = targetId
        self.crud = crud; self.grantedBy = grantedBy; self.createdAt = createdAt
    }

    public var target: AccessTargetType? { AccessTargetType(rawValue: targetType) }
    public var permissions: AccessCRUD { AccessCRUD(crud: crud) }
}

/// `GET /bucket/access-groups/{id}`: the group's own fields plus its members and grants.
public struct AccessGroupDetail: Codable, Hashable, Sendable {
    public var id: String
    public var ecosystemId: String
    public var bucketId: String
    public var name: String
    public var description: String
    public var kind: String
    public var createdAt: String?
    public var updatedAt: String?
    public var members: [AccessGroupMember]
    public var grants: [AccessGrant]

    public init(group: AccessGroup, members: [AccessGroupMember] = [], grants: [AccessGrant] = []) {
        id = group.id; ecosystemId = group.ecosystemId; bucketId = group.bucketId
        name = group.name; description = group.description
        kind = group.kind; createdAt = group.createdAt; updatedAt = group.updatedAt
        self.members = members; self.grants = grants
    }

    public var group: AccessGroup {
        AccessGroup(
            id: id, ecosystemId: ecosystemId, bucketId: bucketId, name: name, description: description,
            kind: kind, createdAt: createdAt, updatedAt: updatedAt
        )
    }
}

public struct AccessGroupCreate: Codable, Hashable, Sendable {
    public var name: String
    public var description: String?
    public init(name: String, description: String? = nil) { self.name = name; self.description = description }
}

public struct AccessGroupUpdate: Codable, Hashable, Sendable {
    public var name: String?
    public var description: String?
    public init(name: String? = nil, description: String? = nil) { self.name = name; self.description = description }
}

public struct AccessMemberAdd: Codable, Hashable, Sendable {
    public var memberType: AccessMemberType
    public var memberId: String
    public init(memberType: AccessMemberType, memberId: String) {
        self.memberType = memberType; self.memberId = memberId
    }
}

public struct AccessGrantUpsert: Codable, Hashable, Sendable {
    public var targetType: AccessTargetType
    public var targetId: String
    public var crud: String
    public init(targetType: AccessTargetType, targetId: String, crud: String) {
        self.targetType = targetType; self.targetId = targetId; self.crud = crud
    }
}

public protocol BucketAccessDataSource: AnyObject, Sendable {
    func groups() async throws -> [AccessGroup]
    func detail(id: String) async throws -> AccessGroupDetail
    func create(bucketID: String, _ body: AccessGroupCreate) async throws -> AccessGroup
    func update(id: String, _ body: AccessGroupUpdate) async throws -> AccessGroup
    func delete(id: String) async throws
    func addMember(groupID: String, _ body: AccessMemberAdd) async throws -> AccessGroupMember
    func removeMember(groupID: String, memberRowID: String) async throws
    func upsertGrant(groupID: String, _ body: AccessGrantUpsert) async throws -> AccessGrant
    func removeGrant(groupID: String, grantID: String) async throws
}
