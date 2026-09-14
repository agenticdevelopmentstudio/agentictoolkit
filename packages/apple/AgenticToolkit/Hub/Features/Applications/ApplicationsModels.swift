import Foundation

public enum ConsumerKind: String, Codable, CaseIterable, Sendable {
    case staff, developer, customer

    public var title: String {
        switch self {
        case .staff: "Staff"
        case .developer: "Developer"
        case .customer: "Customer"
        }
    }

    public var systemImage: String {
        switch self {
        case .staff: "person.badge.key"
        case .developer: "chevron.left.forwardslash.chevron.right"
        case .customer: "person.2"
        }
    }
}

/// A registered application (`/ecosystem/applications` row). `id` is the reverse-domain identifier
/// (`app.<ecosystem>.<leaf>`); renaming the leaf through the registry changes it.
public struct Application: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var ecosystemId: String
    public var slug: String
    public var displayName: String
    public var consumerKind: ConsumerKind
    public var createdAt: String?
    public var updatedAt: String?

    public init(
        id: String, ecosystemId: String, slug: String, displayName: String, consumerKind: ConsumerKind,
        createdAt: String? = nil, updatedAt: String? = nil
    ) {
        self.id = id; self.ecosystemId = ecosystemId; self.slug = slug; self.displayName = displayName
        self.consumerKind = consumerKind; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    /// Everything up to and including the last dot: `"app.acme.shop."` for `"app.acme.shop.web"`.
    public var identifierPrefix: String {
        guard let dot = id.lastIndex(of: ".") else { return "" }
        return String(id[...dot])
    }
}

public struct ApplicationCreate: Codable, Hashable, Sendable {
    public var ecosystemId: String
    public var slug: String
    public var displayName: String
    public var consumerKind: ConsumerKind
    public init(ecosystemId: String, slug: String, displayName: String, consumerKind: ConsumerKind) {
        self.ecosystemId = ecosystemId; self.slug = slug; self.displayName = displayName
        self.consumerKind = consumerKind
    }
}

public struct ApplicationUpdate: Codable, Hashable, Sendable {
    public var slug: String?
    public var displayName: String?
    public var consumerKind: ConsumerKind?
    public init(slug: String? = nil, displayName: String? = nil, consumerKind: ConsumerKind? = nil) {
        self.slug = slug; self.displayName = displayName; self.consumerKind = consumerKind
    }
}

/// The C/R/U/D set the wire spells as a comma-separated string (`"C,R,U,D"`).
public struct CrudPermissions: Hashable, Sendable {
    public var create: Bool
    public var read: Bool
    public var update: Bool
    public var delete: Bool

    public init(create: Bool = false, read: Bool = false, update: Bool = false, delete: Bool = false) {
        self.create = create; self.read = read; self.update = update; self.delete = delete
    }

    public init(wire: String) {
        let letters = Set(wire.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() })
        self.init(
            create: letters.contains("C"), read: letters.contains("R"),
            update: letters.contains("U"), delete: letters.contains("D")
        )
    }

    public static let readOnly = CrudPermissions(read: true)

    private var flags: [(Bool, letter: String, word: String)] {
        [(create, "C", "Create"), (read, "R", "Read"), (update, "U", "Update"), (delete, "D", "Delete")]
    }

    public var wire: String { flags.filter { $0.0 }.map(\.letter).joined(separator: ",") }
    public var summary: String { isEmpty ? "No access" : flags.filter { $0.0 }.map(\.word).joined(separator: ", ") }
    public var isEmpty: Bool { !(create || read || update || delete) }

    /// True when every permission set here is also set in `ceiling`.
    public func isWithin(_ ceiling: CrudPermissions) -> Bool {
        (!create || ceiling.create) && (!read || ceiling.read)
            && (!update || ceiling.update) && (!delete || ceiling.delete)
    }
}

public struct TableGrant: Codable, Hashable, Sendable {
    public var level: String
    public var permissions: String
    public init(level: String, permissions: String) { self.level = level; self.permissions = permissions }
}

/// One entry of `PUT /ecosystem/applications/{id}/schema-grants`. `tables` is keyed by SQL table name.
public struct SchemaGrant: Codable, Hashable, Sendable {
    public var schemaId: String
    public var permissions: String
    public var tables: [String: TableGrant]
    public init(schemaId: String, permissions: String, tables: [String: TableGrant]) {
        self.schemaId = schemaId; self.permissions = permissions; self.tables = tables
    }
}

public struct ApplicationToken: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var prefix: String
    public var createdAt: String?
    public init(id: String, name: String, prefix: String, createdAt: String? = nil) {
        self.id = id; self.name = name; self.prefix = prefix; self.createdAt = createdAt
    }
}

/// The `POST …/tokens` response: the row plus the one-time secret.
public struct ApplicationTokenCreated: Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var prefix: String
    public var token: String
    public var createdAt: String?
    public init(id: String, name: String, prefix: String, token: String, createdAt: String? = nil) {
        self.id = id; self.name = name; self.prefix = prefix; self.token = token; self.createdAt = createdAt
    }
}
