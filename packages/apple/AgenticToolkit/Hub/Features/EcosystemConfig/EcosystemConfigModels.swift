import Foundation

// MARK: - User Auth

public enum SignupMode: String, Codable, CaseIterable, Hashable, Sendable {
    case open
    case inviteOnly = "invite_only"
    case closed

    public var title: String {
        switch self {
        case .open: return "Open"
        case .inviteOnly: return "Invite only"
        case .closed: return "Closed"
        }
    }

    public var help: String {
        switch self {
        case .open: return "Anyone with a supported provider can create an account."
        case .inviteOnly: return "Only people you've invited can create an account."
        case .closed: return "No new accounts can be created."
        }
    }
}

public struct AuthSettings: Codable, Hashable, Sendable {
    public var signupMode: SignupMode
    public var loginEnabled: Bool
    public var allowedProviders: [String]?
    public init(signupMode: SignupMode, loginEnabled: Bool, allowedProviders: [String]? = nil) {
        self.signupMode = signupMode; self.loginEnabled = loginEnabled; self.allowedProviders = allowedProviders
    }
}

public struct AuthSettingsUpdate: Codable, Hashable, Sendable {
    public var signupMode: SignupMode?
    public var loginEnabled: Bool?
    public init(signupMode: SignupMode? = nil, loginEnabled: Bool? = nil) {
        self.signupMode = signupMode; self.loginEnabled = loginEnabled
    }
}

// MARK: - Sign-in apps

public struct SigninApp: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var slug: String
    public var name: String
    public var allowedReturnOrigins: [String]
    public var defaultEcosystemId: String
    public var githubEnabled: Bool

    public init(id: String, slug: String, name: String, allowedReturnOrigins: [String] = [],
                defaultEcosystemId: String, githubEnabled: Bool = false) {
        self.id = id; self.slug = slug; self.name = name; self.allowedReturnOrigins = allowedReturnOrigins
        self.defaultEcosystemId = defaultEcosystemId; self.githubEnabled = githubEnabled
    }

    /// The part of the client id after the ecosystem prefix (`myeco.whatsnow` → `whatsnow`).
    public func leaf(in ecosystem: Ecosystem) -> String {
        let prefix = "\(ecosystem.slug)."
        return slug.hasPrefix(prefix) ? String(slug.dropFirst(prefix.count)) : slug
    }
}

public struct SigninAppCreate: Codable, Hashable, Sendable {
    public var slug: String
    public var name: String
    public var allowedReturnOrigins: [String]
    public var enableGithub: Bool
    public init(slug: String, name: String, allowedReturnOrigins: [String] = [], enableGithub: Bool = false) {
        self.slug = slug; self.name = name
        self.allowedReturnOrigins = allowedReturnOrigins; self.enableGithub = enableGithub
    }
}

public struct SigninAppUpdate: Codable, Hashable, Sendable {
    public var name: String?
    public var allowedReturnOrigins: [String]?
    public var githubEnabled: Bool?
    public init(name: String? = nil, allowedReturnOrigins: [String]? = nil, githubEnabled: Bool? = nil) {
        self.name = name; self.allowedReturnOrigins = allowedReturnOrigins; self.githubEnabled = githubEnabled
    }
}

// MARK: - Feature flags

public struct FeatureFlag: Codable, Hashable, Sendable, Identifiable {
    public var key: String
    public var enabled: Bool
    public var description: String
    public var createdAt: String?
    public var updatedAt: String?
    public var id: String { key }
    public init(key: String, enabled: Bool, description: String = "",
                createdAt: String? = nil, updatedAt: String? = nil) {
        self.key = key; self.enabled = enabled; self.description = description
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct FeatureFlagCreate: Codable, Hashable, Sendable {
    public var key: String
    public var enabled: Bool
    public var description: String
    public init(key: String, enabled: Bool, description: String) {
        self.key = key; self.enabled = enabled; self.description = description
    }
}

public struct FeatureFlagUpdate: Codable, Hashable, Sendable {
    public var enabled: Bool?
    public var description: String?
    public init(enabled: Bool? = nil, description: String? = nil) {
        self.enabled = enabled; self.description = description
    }
}

// MARK: - Server bags

public struct ServerBag: Codable, Hashable, Sendable, Identifiable {
    public var key: String
    public var value: JSONValue
    public var description: String
    public var createdAt: String?
    public var updatedAt: String?
    public var id: String { key }
    public init(key: String, value: JSONValue, description: String = "",
                createdAt: String? = nil, updatedAt: String? = nil) {
        self.key = key; self.value = value; self.description = description
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    /// The value on one line, for list rows: `{"maxItems": 20}`.
    public var preview: String {
        value.prettyText.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
    }
}

public struct ServerBagCreate: Codable, Hashable, Sendable {
    public var key: String
    public var value: JSONValue
    public var description: String
    public init(key: String, value: JSONValue, description: String) {
        self.key = key; self.value = value; self.description = description
    }
}

public struct ServerBagUpdate: Codable, Hashable, Sendable {
    public var value: JSONValue?
    public var description: String?
    public init(value: JSONValue? = nil, description: String? = nil) {
        self.value = value; self.description = description
    }
}

// MARK: - Storage tokens (token principals)

public struct StorageToken: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var slug: String
    public var description: String
    public var prefix: String
    public var rdid: String?
    public var bucketRdid: String?
    public var expiresAt: String?
    public var lastUsedAt: String?
    public var createdAt: String

    public init(id: String, slug: String, description: String = "", prefix: String,
                rdid: String? = nil, bucketRdid: String? = nil,
                expiresAt: String? = nil, lastUsedAt: String? = nil, createdAt: String) {
        self.id = id; self.slug = slug; self.description = description; self.prefix = prefix
        self.rdid = rdid; self.bucketRdid = bucketRdid
        self.expiresAt = expiresAt; self.lastUsedAt = lastUsedAt; self.createdAt = createdAt
    }
}

public struct StorageTokenCreated: Codable, Hashable, Sendable {
    public var id: String
    public var rdid: String
    public var slug: String
    public var description: String
    public var prefix: String
    public var bucketRdid: String
    public var token: String
    public init(id: String, rdid: String, slug: String, description: String = "",
                prefix: String, bucketRdid: String, token: String) {
        self.id = id; self.rdid = rdid; self.slug = slug; self.description = description
        self.prefix = prefix; self.bucketRdid = bucketRdid; self.token = token
    }
}

public struct StorageTokenCreate: Codable, Hashable, Sendable {
    public var name: String
    public var description: String?
    public var expiresAt: String?
    public var ecosystemId: String?
    public init(name: String, description: String? = nil, expiresAt: String? = nil, ecosystemId: String? = nil) {
        self.name = name; self.description = description; self.expiresAt = expiresAt; self.ecosystemId = ecosystemId
    }
}

// MARK: - Data sources

public protocol AuthSettingsDataSource: AnyObject, Sendable {
    func get(ecosystemID: String) async throws -> AuthSettings
    func update(ecosystemID: String, _ patch: AuthSettingsUpdate) async throws -> AuthSettings
}

public protocol SigninAppsDataSource: AnyObject, Sendable {
    func list(ecosystemID: String) async throws -> [SigninApp]
    func create(ecosystemID: String, _ body: SigninAppCreate) async throws -> SigninApp
    func update(ecosystemID: String, id: String, _ body: SigninAppUpdate) async throws -> SigninApp
    func delete(ecosystemID: String, id: String) async throws
}

public protocol FeatureFlagsDataSource: AnyObject, Sendable {
    func list(ecosystemID: String) async throws -> [FeatureFlag]
    func create(ecosystemID: String, _ body: FeatureFlagCreate) async throws -> FeatureFlag
    func update(ecosystemID: String, key: String, _ body: FeatureFlagUpdate) async throws -> FeatureFlag
    func delete(ecosystemID: String, key: String) async throws
}

public protocol ServerBagsDataSource: AnyObject, Sendable {
    func list(ecosystemID: String) async throws -> [ServerBag]
    func create(ecosystemID: String, _ body: ServerBagCreate) async throws -> ServerBag
    func update(ecosystemID: String, key: String, _ body: ServerBagUpdate) async throws -> ServerBag
    func delete(ecosystemID: String, key: String) async throws
}

/// `ecosystemID == nil` means "the caller's own (workspace) tokens" — used by the Authentication module (Task 16).
public protocol StorageTokensDataSource: AnyObject, Sendable {
    func list(ecosystemID: String?) async throws -> [StorageToken]
    func create(ecosystemID: String?, _ body: StorageTokenCreate) async throws -> StorageTokenCreated
    func revoke(ecosystemID: String?, id: String) async throws
}
