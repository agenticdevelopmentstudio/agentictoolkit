import Foundation
import AgenticToolkitHTDV

/// Product ▸ Applications: list → application level (Settings, Bucket permissions, Access tokens).
@MainActor
public final class ApplicationsTopic: EcosystemTopicProvider {
    public static let entry = EcosystemTopicEntry(
        id: "applications", label: "Applications", systemImage: "app.badge",
        description: "The applications registered to this product and what they may reach."
    )
    public nonisolated static let deletedSchemaLabel = "(deleted schema)"
    public nonisolated static let rowLevelMessage = "Per-row permissions are coming soon. Choose \"Table\"."
    public static let revealMessage = "Copy this token now — you won't be able to see it again."
    nonisolated static let noSchemasMessage = "No schemas defined yet. Create one in the Buckets section first."

    public var entry: EcosystemTopicEntry { Self.entry }
    public private(set) var revealedSecrets: [String: String] = [:]

    private let dataSource: any ApplicationsDataSource
    private let buckets: any BucketsDataSource

    public init(dataSource: any ApplicationsDataSource, buckets: any BucketsDataSource) {
        self.dataSource = dataSource
        self.buckets = buckets
    }

    // MARK: Rail

    public func child(for ecosystem: Ecosystem, path: [HTDVItem], rail: any EcosystemRail) async throws -> HTDVChild {
        guard let appID = RailPath.id(at: 0, in: path) else {
            return .level(try await listLevel(for: ecosystem))
        }
        let app: Application
        do {
            app = try await dataSource.get(id: appID)
        } catch HubError.notFound {
            return .empty
        } catch {
            throw HubError.wrap(error)
        }
        guard let section = RailPath.id(at: 1, in: path) else {
            return .level(applicationLevel(for: app))
        }
        switch section {
        case "settings":
            return .detail(settingsDetail(for: app))
        case "grants":
            return try await grantsChild(for: app, in: ecosystem, path: Array(path.dropFirst(2)))
        case "tokens":
            return try await tokensChild(for: app, path: Array(path.dropFirst(2)))
        default:
            return .empty
        }
    }

    // MARK: List + application level

    private func listLevel(for ecosystem: Ecosystem) async throws -> HTDVLevel {
        let apps: [Application]
        do {
            apps = try await dataSource.list(ecosystemID: ecosystem.id)
        } catch {
            throw HubError.wrap(error)
        }
        let items = apps.map {
            HTDVItem(
                id: $0.id, label: $0.displayName, sublabel: $0.id, systemImage: $0.consumerKind.systemImage,
                leadsTo: .list
            )
        }
        let spec = createSpec(for: ecosystem)
        let action = HTDVCreateAction(title: "New application") { presenter in
            _ = await FormSheet.present(title: "New application", spec: spec, from: presenter)
        }
        return HTDVLevel(
            id: "applications-list", title: "Applications", items: items,
            emptyMessage: "No applications yet.", createAction: action
        )
    }

    private func applicationLevel(for app: Application) -> HTDVLevel {
        HTDVLevel(id: "application:\(app.id)", title: app.displayName, items: [
            HTDVItem(
                id: "settings", label: "Settings", sublabel: "Name, identifier and consumer kind.",
                systemImage: "gearshape", leadsTo: .detail
            ),
            HTDVItem(
                id: "grants", label: "Bucket permissions",
                sublabel: "Which buckets and tables this application can reach.",
                systemImage: "tablecells.badge.ellipsis", leadsTo: .list
            ),
            HTDVItem(
                id: "tokens", label: "Access tokens", sublabel: "Credentials this application presents.",
                systemImage: "key", leadsTo: .list
            )
        ])
    }

    private static let kindOptions = ConsumerKind.allCases.map { FormSelectOption(value: $0.rawValue, title: $0.title) }

    /// "New application" dialog: Name, Id (leaf), Consumer kind.
    public func createSpec(for ecosystem: Ecosystem) -> FormSpec {
        let dataSource = self.dataSource
        let save = FormAction(id: "create", title: "Create") { values in
            let slug = (values["slug"]?.stringValue ?? "").lowercased()
            let input = ApplicationCreate(
                ecosystemId: ecosystem.id, slug: slug,
                displayName: values["displayName"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                consumerKind: ConsumerKind(rawValue: values["consumerKind"]?.stringValue ?? "") ?? .customer
            )
            do {
                _ = try await dataSource.create(input)
            } catch HubError.conflict {
                throw HubError.validation("An application with identifier \"\(slug)\" already exists.")
            } catch {
                throw HubError.wrap(error)
            }
        }
        return FormSpec(sections: [
            FormSection(fields: [
                .text(FormTextField(
                    key: "displayName", label: "Name", placeholder: "My Application", isRequired: true
                )),
                .text(FormTextField(
                    key: "slug", label: "Id", placeholder: "my-app", isRequired: true,
                    pattern: Slug.pattern, patternMessage: Slug.patternMessage
                )),
                .select(FormSelectField(
                    key: "consumerKind", label: "Consumer kind", options: Self.kindOptions, isRequired: true
                ))
            ])
        ], actions: FormActions(save: save))
    }

    private func settingsDetail(for app: Application) -> HTDVDetail {
        let dataSource = self.dataSource
        let save = FormAction(id: "save", title: "Save") { values in
            let slug = (values["slug"]?.stringValue ?? "").lowercased()
            let update = ApplicationUpdate(
                slug: slug,
                displayName: values["displayName"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                consumerKind: ConsumerKind(rawValue: values["consumerKind"]?.stringValue ?? "") ?? app.consumerKind
            )
            var targetID = app.id
            if slug != app.slug {
                let next = app.identifierPrefix + slug
                do {
                    try await dataSource.renameIdentifier(app.id, to: next)
                } catch HubError.conflict {
                    throw HubError.validation("The identifier \"\(next)\" is already in use.")
                } catch {
                    throw HubError.wrap(error)
                }
                // Re-home the schema grants under the new identifier, as the web does.
                do {
                    let grants = try await dataSource.schemaGrants(applicationID: app.id)
                    try await dataSource.setSchemaGrants(applicationID: app.id, [])
                    try await dataSource.setSchemaGrants(applicationID: next, grants)
                } catch {
                    throw HubError.wrap(error)
                }
                targetID = next
            }
            do {
                _ = try await dataSource.update(id: targetID, update)
            } catch {
                throw HubError.wrap(error)
            }
        }
        let delete = FormDeleteAction(
            title: "Delete application",
            confirmationText: "Delete application \"\(app.displayName)\"? This cannot be undone."
        ) {
            do {
                try await dataSource.setSchemaGrants(applicationID: app.id, [])
                try await dataSource.delete(id: app.id)
            } catch {
                throw HubError.wrap(error)
            }
        }
        let spec = FormSpec(sections: [
            FormSection(fields: [
                .text(FormTextField(
                    key: "displayName", label: "Name", placeholder: "My Application", isRequired: true
                )),
                .text(FormTextField(
                    key: "slug", label: "Id", placeholder: "my-app", isRequired: true,
                    pattern: Slug.pattern, patternMessage: Slug.patternMessage
                )),
                .readOnly(FormReadOnlyField(key: "identifier", label: "Identifier", isMonospaced: true)),
                .select(FormSelectField(
                    key: "consumerKind", label: "Consumer kind", options: Self.kindOptions, isRequired: true
                ))
            ])
        ], actions: FormActions(save: save, delete: delete))
        return FormDetails.form(id: "application:\(app.id):settings", title: "Application", spec: spec, values: [
            "displayName": .string(app.displayName), "slug": .string(app.slug),
            "identifier": .string(app.id), "consumerKind": .string(app.consumerKind.rawValue)
        ])
    }

    // MARK: Schema grants

    private struct GrantContext {
        var app: Application
        var grants: [SchemaGrant]
        var buckets: [Bucket]
        var tables: [BucketTable]
        func bucket(_ schemaID: String) -> Bucket? { buckets.first { $0.id == schemaID } }
        func label(_ schemaID: String) -> String { bucket(schemaID)?.name ?? ApplicationsTopic.deletedSchemaLabel }
        func tables(of schemaID: String) -> [BucketTable] { tables.filter { $0.bucketId == schemaID } }
    }

    private func grantContext(for app: Application, in ecosystem: Ecosystem) async throws -> GrantContext {
        do {
            return GrantContext(
                app: app,
                grants: try await dataSource.schemaGrants(applicationID: app.id),
                buckets: try await buckets.list(ecosystemID: ecosystem.id),
                tables: try await buckets.tables(ecosystemID: ecosystem.id)
            )
        } catch {
            throw HubError.wrap(error)
        }
    }

    private func grantsChild(
        for app: Application, in ecosystem: Ecosystem, path: [HTDVItem]
    ) async throws -> HTDVChild {
        let context = try await grantContext(for: app, in: ecosystem)
        guard let schemaID = RailPath.id(at: 0, in: path) else {
            return .level(grantsLevel(context, ecosystem: ecosystem))
        }
        guard let grant = context.grants.first(where: { $0.schemaId == schemaID }) else { return .empty }
        guard let leaf = RailPath.id(at: 1, in: path) else {
            return .level(grantLevel(context, grant: grant))
        }
        if leaf == "schema" {
            return .detail(schemaDetail(context, grant: grant))
        }
        guard let table = context.tables(of: schemaID).first(where: { $0.sqlTableName == leaf }) else { return .empty }
        return .detail(tableDetail(context, grant: grant, table: table))
    }

    private func grantsLevel(_ context: GrantContext, ecosystem: Ecosystem) -> HTDVLevel {
        let items = context.grants.map { grant in
            HTDVItem(
                id: grant.schemaId, label: context.label(grant.schemaId),
                sublabel: CrudPermissions(wire: grant.permissions).summary, systemImage: "tablecells", leadsTo: .list
            )
        }
        let granted = Set(context.grants.map(\.schemaId))
        let spec = addSchemaSpec(
            applicationID: context.app.id, ecosystem: ecosystem,
            ungranted: context.buckets.filter { !granted.contains($0.id) }
        )
        let action = HTDVCreateAction(title: "Add schema") { presenter in
            _ = await FormSheet.present(title: "Add schema", spec: spec, from: presenter)
        }
        return HTDVLevel(
            id: "application-grants:\(context.app.id)", title: "Bucket permissions", items: items,
            emptyMessage: "No schemas granted.", createAction: action
        )
    }

    /// "Add schema" dialog: pick an ungranted bucket; the new grant starts read-only.
    public func addSchemaSpec(applicationID: String, ecosystem: Ecosystem, ungranted: [Bucket]) -> FormSpec {
        let dataSource = self.dataSource
        let save = FormAction(id: "add", title: "Add") { values in
            if ungranted.isEmpty { throw HubError.validation(Self.noSchemasMessage) }
            let schemaID = values["schemaId"]?.stringValue ?? ""
            guard ungranted.contains(where: { $0.id == schemaID }) else {
                throw HubError.validation("Schema is required")
            }
            do {
                var grants = try await dataSource.schemaGrants(applicationID: applicationID)
                grants.removeAll { $0.schemaId == schemaID }
                grants.append(SchemaGrant(schemaId: schemaID, permissions: CrudPermissions.readOnly.wire, tables: [:]))
                try await dataSource.setSchemaGrants(applicationID: applicationID, grants)
            } catch {
                throw HubError.wrap(error)
            }
        }
        let options = ungranted.map { FormSelectOption(value: $0.id, title: $0.name) }
        return FormSpec(sections: [
            FormSection(fields: [
                .select(FormSelectField(key: "schemaId", label: "Schema", options: options, isRequired: false))
            ])
        ], actions: FormActions(save: save))
    }

    private func grantLevel(_ context: GrantContext, grant: SchemaGrant) -> HTDVLevel {
        var items = [
            HTDVItem(
                id: "schema", label: "Schema permissions", sublabel: CrudPermissions(wire: grant.permissions).summary,
                systemImage: "lock.shield", dividerAfter: true, leadsTo: .detail
            )
        ]
        for table in context.tables(of: grant.schemaId) {
            let summary = grant.tables[table.sqlTableName].map {
                CrudPermissions(wire: $0.permissions).summary
            } ?? "No access"
            items.append(HTDVItem(
                id: table.sqlTableName, label: table.name, sublabel: summary,
                systemImage: "tablecells", leadsTo: .detail
            ))
        }
        return HTDVLevel(
            id: "application-grant:\(context.app.id):\(grant.schemaId)", title: context.label(grant.schemaId),
            items: items, emptyMessage: "This schema has no tables."
        )
    }

    private static func permissionFields() -> [FormField] {
        [
            .toggle(FormToggleField(key: "create", label: "Create", help: nil)),
            .toggle(FormToggleField(key: "read", label: "Read", help: nil)),
            .toggle(FormToggleField(key: "update", label: "Update", help: nil)),
            .toggle(FormToggleField(key: "delete", label: "Delete", help: nil))
        ]
    }

    private nonisolated static func permissions(from values: [String: FormValue]) -> CrudPermissions {
        CrudPermissions(
            create: values["create"]?.boolValue ?? false, read: values["read"]?.boolValue ?? false,
            update: values["update"]?.boolValue ?? false, delete: values["delete"]?.boolValue ?? false
        )
    }

    private static func values(for permissions: CrudPermissions) -> [String: FormValue] {
        [
            "create": .bool(permissions.create), "read": .bool(permissions.read),
            "update": .bool(permissions.update), "delete": .bool(permissions.delete)
        ]
    }

    /// Replace one grant (or drop it when `replacement` is nil) and write the whole list back.
    private func rewriteGrant(applicationID: String, schemaID: String, replacement: SchemaGrant?) async throws {
        do {
            var grants = try await dataSource.schemaGrants(applicationID: applicationID)
            grants.removeAll { $0.schemaId == schemaID }
            if let replacement { grants.append(replacement) }
            try await dataSource.setSchemaGrants(applicationID: applicationID, grants)
        } catch {
            throw HubError.wrap(error)
        }
    }

    private func schemaDetail(_ context: GrantContext, grant: SchemaGrant) -> HTDVDetail {
        let appID = context.app.id
        let label = context.label(grant.schemaId)
        let save = FormAction(id: "save", title: "Save") { [self] values in
            var updated = grant
            updated.permissions = Self.permissions(from: values).wire
            try await rewriteGrant(applicationID: appID, schemaID: grant.schemaId, replacement: updated)
        }
        let delete = FormDeleteAction(
            title: "Remove grant",
            confirmationText: "Remove the \"\(label)\" grant? This application will lose access to its tables."
        ) { [self] in
            try await rewriteGrant(applicationID: appID, schemaID: grant.schemaId, replacement: nil)
        }
        let spec = FormSpec(sections: [
            FormSection(fields: [.readOnly(FormReadOnlyField(key: "schema", label: "Schema"))]),
            FormSection(title: "Permissions", fields: Self.permissionFields())
        ], actions: FormActions(save: save, delete: delete))
        var values = Self.values(for: CrudPermissions(wire: grant.permissions))
        values["schema"] = .string(
            context.bucket(grant.schemaId) == nil
                ? "\(label) — This schema no longer exists. Remove the grant, or recreate the bucket."
                : label
        )
        return FormDetails.form(
            id: "application-grant:\(appID):\(grant.schemaId):schema", title: "Schema permissions", spec: spec,
            values: values
        )
    }

    private func tableDetail(_ context: GrantContext, grant: SchemaGrant, table: BucketTable) -> HTDVDetail {
        let appID = context.app.id
        let ceiling = CrudPermissions(wire: grant.permissions)
        let save = FormAction(id: "save", title: "Save") { [self] values in
            if values["level"]?.stringValue == "row" { throw HubError.validation(Self.rowLevelMessage) }
            let permissions = Self.permissions(from: values)
            guard permissions.isWithin(ceiling) else {
                throw HubError.validation("\"\(table.name)\" can't exceed the schema's permissions.")
            }
            var updated = grant
            if permissions.isEmpty {
                updated.tables.removeValue(forKey: table.sqlTableName)
            } else {
                updated.tables[table.sqlTableName] = TableGrant(level: "table", permissions: permissions.wire)
            }
            try await rewriteGrant(applicationID: appID, schemaID: grant.schemaId, replacement: updated)
        }
        let spec = FormSpec(sections: [
            FormSection(fields: [
                .select(FormSelectField(key: "level", label: "Permission level", options: [
                    FormSelectOption(
                        value: "table", title: "Table — These permissions apply to every row in the table."
                    ),
                    FormSelectOption(value: "row", title: "Row — Per-row permissions (coming soon)")
                ], isRequired: true))
            ]),
            FormSection(title: "Permissions (ceiling: \(ceiling.summary))", fields: Self.permissionFields())
        ], actions: FormActions(save: save))
        let existing = grant.tables[table.sqlTableName]
        var values = Self.values(for: CrudPermissions(wire: existing?.permissions ?? ""))
        values["level"] = .string(existing?.level ?? "table")
        return FormDetails.form(
            id: "application-grant:\(appID):\(grant.schemaId):\(table.sqlTableName)", title: table.name, spec: spec,
            values: values
        )
    }

    // MARK: Access tokens

    private func tokensChild(for app: Application, path: [HTDVItem]) async throws -> HTDVChild {
        let tokens: [ApplicationToken]
        do {
            tokens = try await dataSource.tokens(applicationID: app.id)
        } catch {
            throw HubError.wrap(error)
        }
        guard let tokenID = RailPath.id(at: 0, in: path) else {
            let items = tokens.map {
                HTDVItem(
                    id: $0.id, label: $0.name, sublabel: "\($0.prefix)… · \(HubDates.display($0.createdAt))",
                    systemImage: "key", leadsTo: .detail
                )
            }
            let spec = createTokenSpec(applicationID: app.id)
            let action = HTDVCreateAction(title: "New token") { presenter in
                _ = await FormSheet.present(title: "New token", spec: spec, from: presenter)
            }
            return .level(HTDVLevel(
                id: "application-tokens:\(app.id)", title: "Access tokens", items: items,
                emptyMessage: "No tokens yet.", createAction: action
            ))
        }
        guard let token = tokens.first(where: { $0.id == tokenID }) else { return .empty }
        return .detail(tokenDetail(for: token, in: app))
    }

    /// "New token" dialog: one name field. The minted secret is kept in `revealedSecrets` and shown on the
    /// token's detail. `FormAction.perform` is a plain `@Sendable` closure — not `@MainActor` — so it cannot
    /// mutate the `@MainActor`-isolated `revealedSecrets` directly; the write is hoisted into `MainActor.run`.
    public func createTokenSpec(applicationID: String) -> FormSpec {
        let dataSource = self.dataSource
        let save = FormAction(id: "create", title: "Create") { [self] values in
            let name = values["name"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let created: ApplicationTokenCreated
            do {
                created = try await dataSource.createToken(applicationID: applicationID, name: name)
            } catch {
                throw HubError.wrap(error)
            }
            await MainActor.run { self.revealedSecrets[created.id] = created.token }
        }
        return FormSpec(sections: [
            FormSection(fields: [
                .text(FormTextField(key: "name", label: "Token name", placeholder: "CI deploy", isRequired: true))
            ])
        ], actions: FormActions(save: save))
    }

    private func tokenDetail(for token: ApplicationToken, in app: Application) -> HTDVDetail {
        let dataSource = self.dataSource
        var fields: [FormField] = [
            .readOnly(FormReadOnlyField(key: "name", label: "Name")),
            .readOnly(FormReadOnlyField(key: "prefix", label: "Prefix", isMonospaced: true)),
            .readOnly(FormReadOnlyField(key: "created", label: "Created"))
        ]
        var values: [String: FormValue] = [
            "name": .string(token.name), "prefix": .string("\(token.prefix)…"),
            "created": .string(HubDates.display(token.createdAt))
        ]
        if let secret = revealedSecrets[token.id] {
            fields.append(.readOnly(FormReadOnlyField(key: "token", label: "Token", isMonospaced: true)))
            fields.append(.readOnly(FormReadOnlyField(key: "notice", label: "Keep it safe")))
            values["token"] = .string(secret)
            values["notice"] = .string(Self.revealMessage)
        }
        let revoke = FormDeleteAction(
            title: "Revoke token",
            confirmationText: "Revoke token \"\(token.name)\"? Applications using it will lose access."
        ) { [self] in
            do {
                try await dataSource.revokeToken(applicationID: app.id, tokenID: token.id)
            } catch {
                throw HubError.wrap(error)
            }
            await MainActor.run { _ = self.revealedSecrets.removeValue(forKey: token.id) }
        }
        let spec = FormSpec(sections: [FormSection(fields: fields)], actions: FormActions(delete: revoke))
        return FormDetails.form(id: "application-token:\(token.id)", title: token.name, spec: spec, values: values)
    }
}
