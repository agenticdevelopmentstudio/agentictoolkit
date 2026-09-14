import Foundation

/// An ecosystem end user (`/customer/customers` row). Every descriptive field is nullable on the wire.
public struct Customer: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var ecosystemId: String
    public var email: String?
    public var displayName: String?
    public var externalId: String?
    public var slug: String?
    public var avatarUrl: String?
    public var createdAt: String?
    public var updatedAt: String?

    public init(
        id: String, ecosystemId: String, email: String? = nil, displayName: String? = nil, externalId: String? = nil,
        slug: String? = nil, avatarUrl: String? = nil, createdAt: String? = nil, updatedAt: String? = nil
    ) {
        self.id = id; self.ecosystemId = ecosystemId; self.email = email; self.displayName = displayName
        self.externalId = externalId; self.slug = slug; self.avatarUrl = avatarUrl
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    /// `displayName || email || "—"`, treating blank strings as missing.
    public var label: String { HubText.nonBlank(displayName) ?? HubText.nonBlank(email) ?? "—" }
    /// `email || externalId || "—"`.
    public var sublabel: String { HubText.nonBlank(email) ?? HubText.nonBlank(externalId) ?? "—" }
}

/// Body for `POST /customer/customers` and `PUT /customer/customers/{id}`. Optional fields encode as absent,
/// never `null`.
public struct CustomerInput: Codable, Hashable, Sendable {
    public var ecosystemId: String
    public var email: String
    public var displayName: String?
    public var externalId: String?
    public var slug: String?
    public var avatarUrl: String?

    public init(
        ecosystemId: String, email: String, displayName: String? = nil, externalId: String? = nil,
        slug: String? = nil, avatarUrl: String? = nil
    ) {
        self.ecosystemId = ecosystemId; self.email = email; self.displayName = displayName
        self.externalId = externalId; self.slug = slug; self.avatarUrl = avatarUrl
    }
}
