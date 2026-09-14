import Foundation
import AgenticToolkitHTDV

/// Product ▸ Buckets: bucket list → bucket level (Settings form, Tables list) → table form.
@MainActor
public final class BucketsTopic: EcosystemTopicProvider {
    public static let entry = EcosystemTopicEntry(
        id: "buckets", label: "Buckets", systemImage: "tablecells",
        description: "Storage buckets and the tables they contain."
    )
    public var entry: EcosystemTopicEntry { Self.entry }

    private let dataSource: any BucketsDataSource

    public init(dataSource: any BucketsDataSource) {
        self.dataSource = dataSource
    }

    /// Pure and stateless, so `nonisolated`: `createTableSpec`'s save action calls it from inside a
    /// `FormAction.perform` closure, which runs off the main actor (`FormSpec.swift`).
    public nonisolated static func tableName(from name: String) -> String {
        let lowered = name.lowercased()
        var out = ""
        var pendingUnderscore = false
        for scalar in lowered.unicodeScalars {
            let isAlnum = (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9")
            if isAlnum {
                if pendingUnderscore, !out.isEmpty { out.append("_") }
                pendingUnderscore = false
                out.unicodeScalars.append(scalar)
            } else {
                pendingUnderscore = true
            }
        }
        return out
    }

    /// A name can be non-empty and still derive an EMPTY SQL identifier (every character stripped, e.g.
    /// an all-non-ASCII name). Posting `sqlTableName: ""` then makes a second such table collide on `""`
    /// and report a duplicate-name error that names the wrong cause, so the derivation is guarded and
    /// this message names the real one.
    public nonisolated static let unusableTableNameMessage =
        "That name has no letters or digits that can be used in a SQL table name. "
        + "Use at least one a–z letter or 0–9 digit."

    public static func tableCount(_ count: Int) -> String { count == 1 ? "1 table" : "\(count) tables" }

    // MARK: Rail

    public func child(for ecosystem: Ecosystem, path: [HTDVItem], rail: any EcosystemRail) async throws -> HTDVChild {
        guard let bucketID = RailPath.id(at: 0, in: path) else {
            return .level(try await listLevel(for: ecosystem))
        }
        let bucket: Bucket
        do {
            bucket = try await dataSource.get(id: bucketID)
        } catch HubError.notFound {
            return .empty
        } catch {
            throw HubError.wrap(error)
        }
        guard let section = RailPath.id(at: 1, in: path) else {
            return .level(bucketLevel(for: bucket))
        }
        switch section {
        case "settings":
            return .detail(settingsDetail(for: bucket))
        case "tables":
            let tables = try await tables(of: bucket, in: ecosystem)
            guard let tableID = RailPath.id(at: 2, in: path) else {
                return .level(tablesLevel(for: bucket, in: ecosystem, tables: tables))
            }
            guard let table = tables.first(where: { $0.id == tableID }) else { return .empty }
            return .detail(tableDetail(for: table, in: bucket))
        default:
            return .empty
        }
    }

    // MARK: Levels

    private func listLevel(for ecosystem: Ecosystem) async throws -> HTDVLevel {
        let buckets: [Bucket]
        let tables: [BucketTable]
        do {
            buckets = try await dataSource.list(ecosystemID: ecosystem.id)
            tables = try await dataSource.tables(ecosystemID: ecosystem.id)
        } catch {
            throw HubError.wrap(error)
        }
        var counts: [String: Int] = [:]
        for table in tables { counts[table.bucketId, default: 0] += 1 }
        let items = buckets.map { bucket in
            HTDVItem(
                id: bucket.id, label: bucket.name, sublabel: Self.tableCount(counts[bucket.id] ?? 0),
                systemImage: "tablecells", leadsTo: .list
            )
        }
        let spec = createSpec(for: ecosystem)
        let action = HTDVCreateAction(title: "New bucket") { presenter in
            _ = await FormSheet.present(title: "New bucket", spec: spec, from: presenter)
        }
        return HTDVLevel(
            id: "buckets-list", title: "Buckets", items: items, emptyMessage: "No buckets yet.", createAction: action
        )
    }

    private func bucketLevel(for bucket: Bucket) -> HTDVLevel {
        HTDVLevel(id: "bucket:\(bucket.id)", title: bucket.name, items: [
            HTDVItem(
                id: "settings", label: "Settings", sublabel: "Name and description.",
                systemImage: "gearshape", leadsTo: .detail
            ),
            HTDVItem(
                id: "tables", label: "Tables", sublabel: "The tables this bucket contains.",
                systemImage: "tablecells", leadsTo: .list
            )
        ])
    }

    private func tables(of bucket: Bucket, in ecosystem: Ecosystem) async throws -> [BucketTable] {
        do {
            return try await dataSource.tables(ecosystemID: ecosystem.id).filter { $0.bucketId == bucket.id }
        } catch {
            throw HubError.wrap(error)
        }
    }

    private func tablesLevel(for bucket: Bucket, in ecosystem: Ecosystem, tables: [BucketTable]) -> HTDVLevel {
        let items = tables.map {
            HTDVItem(id: $0.id, label: $0.name, sublabel: $0.sqlTableName, systemImage: "tablecells", leadsTo: .detail)
        }
        let spec = createTableSpec(for: ecosystem, bucket: bucket)
        let action = HTDVCreateAction(title: "New table") { presenter in
            _ = await FormSheet.present(title: "New table", spec: spec, from: presenter)
        }
        return HTDVLevel(
            id: "bucket-tables:\(bucket.id)", title: "Tables", items: items,
            emptyMessage: "No tables yet.", createAction: action
        )
    }

    // MARK: Forms

    /// "New bucket" dialog: Name + Description; rejects a name already used in the ecosystem (case-insensitive).
    public func createSpec(for ecosystem: Ecosystem) -> FormSpec {
        let dataSource = self.dataSource
        let save = FormAction(id: "create", title: "Create") { values in
            let name = values["name"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let description = values["description"]?.stringValue ?? ""
            let existing: [Bucket]
            do {
                existing = try await dataSource.list(ecosystemID: ecosystem.id)
            } catch {
                throw HubError.wrap(error)
            }
            if existing.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                throw HubError.validation("A bucket named \"\(name)\" already exists.")
            }
            do {
                _ = try await dataSource.create(BucketCreate(
                    ecosystemId: ecosystem.id, name: name,
                    metadata: BucketMetadata(description: description.isEmpty ? nil : description)
                ))
            } catch HubError.conflict {
                throw HubError.validation("A bucket named \"\(name)\" already exists.")
            } catch {
                throw HubError.wrap(error)
            }
        }
        return FormSpec(sections: [
            FormSection(fields: [
                .text(FormTextField(key: "name", label: "Name", placeholder: "Profile Basics", isRequired: true)),
                .textArea(FormTextAreaField(
                    key: "description", label: "Description", placeholder: "What this bucket is for.",
                    isRequired: false, minLines: 2
                ))
            ])
        ], actions: FormActions(save: save))
    }

    private func settingsDetail(for bucket: Bucket) -> HTDVDetail {
        let dataSource = self.dataSource
        let save = FormAction(id: "save", title: "Save") { values in
            let name = values["name"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let description = values["description"]?.stringValue ?? ""
            do {
                _ = try await dataSource.update(id: bucket.id, BucketUpdate(
                    name: name, metadata: BucketMetadata(description: description.isEmpty ? nil : description)
                ))
            } catch HubError.conflict {
                throw HubError.validation("A bucket named \"\(name)\" already exists.")
            } catch {
                throw HubError.wrap(error)
            }
        }
        let delete: FormDeleteAction? = bucket.isBuiltIn ? nil : FormDeleteAction(
            title: "Delete bucket",
            confirmationText: "Delete bucket \"\(bucket.name)\"? Applications that granted it will lose those tables."
        ) {
            do { try await dataSource.delete(id: bucket.id) } catch { throw HubError.wrap(error) }
        }
        let spec = FormSpec(sections: [
            FormSection(fields: [
                .text(FormTextField(key: "name", label: "Name", placeholder: "Profile Basics", isRequired: true)),
                .textArea(FormTextAreaField(
                    key: "description", label: "Description", placeholder: "What this bucket is for.",
                    isRequired: false, minLines: 2
                ))
            ])
        ], actions: FormActions(save: save, delete: delete))
        return FormDetails.form(
            id: "bucket:\(bucket.id):settings", title: "Bucket", spec: spec,
            values: ["name": .string(bucket.name), "description": .string(bucket.description)]
        )
    }

    /// "New table" dialog: Name only; the SQL table name is derived with `tableName(from:)`.
    public func createTableSpec(for ecosystem: Ecosystem, bucket: Bucket) -> FormSpec {
        let dataSource = self.dataSource
        let save = FormAction(id: "create", title: "Create") { values in
            let name = values["name"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if name.isEmpty { throw HubError.validation("Every table needs a name.") }
            let sqlName = Self.tableName(from: name)
            if sqlName.isEmpty { throw HubError.validation(Self.unusableTableNameMessage) }
            let existing: [BucketTable]
            do {
                existing = try await dataSource.tables(ecosystemID: ecosystem.id).filter { $0.bucketId == bucket.id }
            } catch {
                throw HubError.wrap(error)
            }
            let isDuplicate = existing.contains {
                $0.name.caseInsensitiveCompare(name) == .orderedSame || $0.sqlTableName == sqlName
            }
            if isDuplicate {
                throw HubError.validation("Two tables share the name \"\(name)\". Names must be unique.")
            }
            do {
                _ = try await dataSource.createTable(BucketTableCreate(
                    ecosystemId: ecosystem.id, bucketId: bucket.id, sqlTableName: sqlName, name: name
                ))
            } catch HubError.conflict {
                throw HubError.validation("Two tables share the name \"\(name)\". Names must be unique.")
            } catch {
                throw HubError.wrap(error)
            }
        }
        return FormSpec(sections: [
            FormSection(fields: [
                .text(FormTextField(key: "name", label: "Name", placeholder: "contacts", isRequired: false))
            ])
        ], actions: FormActions(save: save))
    }

    private func tableDetail(for table: BucketTable, in bucket: Bucket) -> HTDVDetail {
        let dataSource = self.dataSource
        let save = FormAction(id: "save", title: "Save") { values in
            let name = values["name"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if name.isEmpty { throw HubError.validation("Every table needs a name.") }
            do {
                _ = try await dataSource.updateTable(id: table.id, BucketTableUpdate(name: name))
            } catch {
                throw HubError.wrap(error)
            }
        }
        let delete = FormDeleteAction(
            title: "Remove table",
            confirmationText: "Remove table \"\(table.name)\"? Data in it is not deleted until the bucket is."
        ) {
            do { try await dataSource.deleteTable(id: table.id) } catch { throw HubError.wrap(error) }
        }
        let spec = FormSpec(sections: [
            FormSection(fields: [
                .text(FormTextField(key: "name", label: "Name", placeholder: "contacts", isRequired: false)),
                .readOnly(FormReadOnlyField(key: "sqlTableName", label: "SQL table name", isMonospaced: true))
            ])
        ], actions: FormActions(save: save, delete: delete))
        return FormDetails.form(
            id: "bucket-table:\(table.id)", title: table.name, spec: spec,
            values: ["name": .string(table.name), "sqlTableName": .string(table.sqlTableName)]
        )
    }
}
