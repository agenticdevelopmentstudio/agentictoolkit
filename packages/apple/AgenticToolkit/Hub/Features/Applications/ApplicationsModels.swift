import Foundation

public enum ConsumerKind: String, Codable, CaseIterable, Sendable {
    case staff, developer, customer

    /// The contract types `consumerKind` as a free `string` (`maxLength: 16`) with no enum, so an
    /// unrecognized value must not fail the whole `[Application]` decode and blank the rail. Narrow
    /// it to `.developer`, exactly as the web client does.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ConsumerKind(rawValue: raw) ?? .developer
    }

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

/// A per-table grant inside a `SchemaGrant`. `level` is a UI-only concept ("table" vs. the
/// not-yet-supported "row") and has no wire counterpart, so it is never sent.
///
/// Deliberately NOT `Codable`: this is a domain/UI type. The wire shape lives in the adapter
/// (`TableGrantWire`), so it is impossible to serialize this shape onto the API by accident.
public struct TableGrant: Hashable, Sendable {
    public var level: String
    public var permissions: String
    public init(level: String, permissions: String) { self.level = level; self.permissions = permissions }
}

/// One application-to-bucket grant. `tables` is keyed by the table's **id** (the wire's `tableId`),
/// never by its `sqlTableName`.
///
/// Deliberately NOT `Codable` — see `TableGrant`. The API speaks
/// `{schemaId, crud, tables: [{tableId, crud}]}`; the adapter converts.
public struct SchemaGrant: Hashable, Sendable {
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
