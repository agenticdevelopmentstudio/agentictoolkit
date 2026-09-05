import Foundation
import GRDB
// `AgenticDeveloperToolkit` is re-exported from `MarkdownReExports.swift`, so
// every type it defines (`MarkdownDocument`, `MarkdownText`, `Frontmatter`,
// ...) is already in scope here without an explicit import.
import AgenticToolkitDatabase
import AgenticToolkitSync
import AgenticToolkitSyncGRDB

/// Which of adh's three marker tables a document is filed in.
///
/// The tables are structurally identical; the row's *existence* is the whole
/// classification, which is why `MarkdownDocument` carries no `kind`.
public enum MarkdownMarker: String, CaseIterable, Sendable {
    case note, doc, paper

    public var table: String {
        switch self {
        case .note: "notes"
        case .doc: "docs"
        case .paper: "papers"
        }
    }

    public var resource: String { "content.\(table)" }

    /// The flag adh's `POST /content/markdown` takes for this marker.
    /// `papers` has no create-time flag upstream; a paper is marked by a
    /// separate call, so it contributes nothing to a create payload.
    var createFlag: String? {
        switch self {
        case .note: "note"
        case .doc: "doc"
        case .paper: nil
        }
    }
}

public enum MarkdownStoreError: Error, Equatable {
    case notFound(String)
    case categoryCycle(parent: String, child: String)
    /// `JSONEncoder` only ever emits valid UTF-8, so this is unreachable in
    /// practice — it exists so the UTF-8 decode stays a failable initializer
    /// rather than an unsafe cast (SwiftLint's `optional_data_string_conversion`).
    case payloadEncodingFailed
    /// An `_markdown_outbox` row's `intent` column does not match any
    /// `MarkdownRemoteIntent` case. This store is the only writer of that
    /// column, so it means on-disk corruption, not a legitimate unknown
    /// intent — silently coercing it to `.update` would push adh a content
    /// write for what might have been a `delete`.
    case unknownRemoteIntent(String)
}

/// The nine mirrored tables, plus the local REST queue, over one GRDB database.
///
/// Synchronous throughout, because that is what its callers are: Whippet's
/// `Features.init()` builds it inline, and `NoteStorage` is a synchronous
/// four-method protocol. Every method opens its own transaction on a
/// `BoundedDatabase` pool, so "synchronous" means "returns when the write is
/// durable", not "on the main thread" — callers doing bulk work move it off
/// themselves.
public final class MarkdownStore: @unchecked Sendable {

    public let database: BoundedDatabase

    /// Exposed so a host can pull into it; documents are pull-only, taxonomy
    /// pushes through its outbox (Task 11).
    public let syncStore: GRDBSyncStore

    let customerID: String
    let ecosystemID: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// `~/.whippet/Markdown.db` — deliberately not `Whippet.db`. That file is
    /// driven by raw SQLite3 C API code and this store is GRDB; two stacks on
    /// one file means two connection pools disagreeing about WAL state.
    public static func defaultPath(inHome home: URL) -> String {
        home.appendingPathComponent(".whippet").appendingPathComponent("Markdown.db").path
    }

    public init(path: String, customerID: String = "", ecosystemID: String = "") throws {
        if path != ":memory:" {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: path).deletingLastPathComponent(),
                withIntermediateDirectories: true)
        }
        self.database = try BoundedDatabase(path: path)
        self.customerID = customerID
        self.ecosystemID = ecosystemID

        let projection = MarkdownProjection()
        self.syncStore = GRDBSyncStore(
            database: database,
            pullOnlyResources: Set(MarkdownProjection.pullOnlyResources),
            projection: projection)

        // Two separate transactions, not one — `MarkdownSchema.migrate` runs its
        // own `writeWithoutTransaction` PRAGMA call and `DatabaseMigrator`
        // transaction internally, and cannot join the `write { }` below even if
        // this init tried. That is safe rather than a hazard: both steps are
        // `IF NOT EXISTS`-shaped — the DDL (`CREATE TABLE IF NOT EXISTS`) and
        // `prepare(resources:in:)`'s own idempotent bookkeeping inserts — so a
        // crash between them just leaves work for the next `MarkdownStore.init`
        // to redo; a re-run self-heals rather than leaving a half-built
        // database that the store won't write to. `prepare(resources:in:)` is
        // the connection-taking overload from Task 8 — the async one would hop
        // queues and deadlock the pool's writer from inside this `write`.
        try MarkdownSchema.migrate(database)
        try database.write { conn in
            try syncStore.prepare(resources: MarkdownProjection.syncResources, in: conn)
        }
    }

    // MARK: - Documents

    public func createDocument(
        content: String,
        markers: [MarkdownMarker],
        id: String = UUID().uuidString.lowercased(),
        now: Date = Date()
    ) throws -> MarkdownDocument {
        // `now` is normalized to string-round-trip precision *before* it goes
        // into `MarkdownDocument.new` — `MarkdownTimestamp.string` truncates to
        // milliseconds, so an unnormalized `Date()` (sub-millisecond precision)
        // compared later against a value that came back through the database
        // can appear to sort *before* an earlier write that landed in the same
        // millisecond. Normalizing here means the value this method returns is
        // bit-for-bit what a caller gets back from `document(id:)` afterward.
        let now = Self.normalizedTimestamp(now)
        let document = MarkdownDocument.new(
            id: id,
            content: content,
            ownerKind: .customer,
            ownerID: customerID,
            now: now)
        try database.write { conn in
            try insert(document, in: conn)
            for marker in markers {
                try addMarker(marker, to: document.id, at: now, in: conn)
            }
            var payload: [String: JSONValue] = ["content": .string(content)]
            for flag in markers.compactMap(\.createFlag) {
                payload[flag] = .bool(true)
            }
            try enqueue(.create, for: document.id, payload: payload, at: now, in: conn)
        }
        return document
    }

    public func document(id: String) throws -> MarkdownDocument? {
        try database.read { conn in
            try Row.fetchOne(
                conn,
                sql: "SELECT * FROM markdown WHERE id = ? AND is_deleted = 0",
                arguments: [id]
            ).map(Self.document(from:))
        }
    }

    public func documents(marker: MarkdownMarker) throws -> [MarkdownDocument] {
        try database.read { conn in
            try Row.fetchAll(
                conn,
                sql: """
                    SELECT m.* FROM markdown m
                    JOIN \(marker.table) k ON k.markdown_id = m.id AND k.deleted_at IS NULL
                    WHERE m.is_deleted = 0
                    ORDER BY m.updated_at DESC
                    """
            ).map(Self.document(from:))
        }
    }

    public func updateDocument(_ document: MarkdownDocument, now: Date = Date()) throws {
        let now = Self.normalizedTimestamp(now)
        try database.write { conn in
            let exists = try Bool.fetchOne(
                conn, sql: "SELECT EXISTS(SELECT 1 FROM markdown WHERE id = ? AND is_deleted = 0)",
                arguments: [document.id]) ?? false
            guard exists else { throw MarkdownStoreError.notFound(document.id) }

            var updated = document
            updated.updatedAt = now
            try write(updated, in: conn)
            // All four keys, every time — not just `content`. `visibility`, `stage`
            // and `public_route` are client-authored (unlike `title`/hash/size/
            // version, which adh derives), so a caller that only touched one of
            // them still needs it on the wire. `public_route` is sent as JSON
            // `null` rather than omitted when there is none: omitting the key
            // means "unchanged" to adh, which would make clearing a route
            // impossible. Sending the document's full authored state on every
            // update (rather than a diff) is also what keeps `enqueue`'s
            // field-wise merge safe — a later update can never carry a smaller,
            // stale-looking payload that erases a field an earlier queued op set.
            try enqueue(.update, for: document.id, payload: [
                "content": .string(document.content),
                "visibility": .string(document.visibility.rawValue),
                "stage": .string(document.stage.rawValue),
                "public_route": document.publicRoute.map(JSONValue.string) ?? .null
            ], at: now, in: conn)
        }
    }

    public func deleteDocument(id: String, now: Date = Date()) throws {
        let now = Self.normalizedTimestamp(now)
        try database.write { conn in
            let stamp = MarkdownTimestamp.string(now)
            // Both flags, because adh carries both: its indexes filter on
            // `is_deleted` and the markers filter on `deleted_at`. Inventing one
            // local flag would break a synced row's fidelity.
            try conn.execute(
                sql: "UPDATE markdown SET is_deleted = 1, deleted_at = ?, updated_at = ? WHERE id = ?",
                arguments: [stamp, stamp, id])
            for marker in MarkdownMarker.allCases {
                try conn.execute(
                    sql: """
                        UPDATE \(marker.table) SET deleted_at = ?, updated_at = ?
                        WHERE markdown_id = ? AND deleted_at IS NULL
                        """,
                    arguments: [stamp, stamp, id])
            }
            try enqueue(.delete, for: id, payload: [:], at: now, in: conn)
        }
    }

    // MARK: - The REST queue

    public func pendingRemoteOps(limit: Int = 100) throws -> [MarkdownRemoteOp] {
        try database.read { conn in
            try Row.fetchAll(
                conn,
                sql: "SELECT * FROM _markdown_outbox ORDER BY created_at, op_id LIMIT ?",
                arguments: [limit]
            ).map { row in
                // An unreadable `intent` or `payload` is on-disk corruption, not a
                // legitimate default — `?? .update` / `?? [:]` would silently turn
                // it into a content push (or drop already-queued fields), so both
                // throw instead of guessing.
                let rawIntent: String = row["intent"]
                guard let intent = MarkdownRemoteIntent(rawValue: rawIntent) else {
                    throw MarkdownStoreError.unknownRemoteIntent(rawIntent)
                }
                return MarkdownRemoteOp(
                    opID: row["op_id"],
                    documentID: row["document_id"],
                    intent: intent,
                    payload: try self.decodePayload(row["payload"]),
                    createdAt: MarkdownTimestamp.date(row["created_at"]) ?? Date())
            }
        }
    }

    public func completeRemoteOp(opID: String) throws {
        try database.write { conn in
            try conn.execute(sql: "DELETE FROM _markdown_outbox WHERE op_id = ?", arguments: [opID])
        }
    }

    /// Sends queued ops oldest-first, clearing each as the writer accepts it.
    /// A throw stops the drain with the failing op still queued — order matters
    /// (a `create` before its `update`), so skipping past a failure would push
    /// an update for a document adh has never seen.
    ///
    /// Never call this from inside a `database.write { }` block. It `await`s
    /// the network writer between reading and clearing each op, and that
    /// `await` may resume on a different thread than the one that entered the
    /// surrounding `write` — `BoundedDatabase`'s reentrancy tracks the writer
    /// via a thread-local (`currentDB`), so resuming elsewhere finds no
    /// in-progress write and the next nested `database.write`/`.read` call
    /// blocks forever waiting on a writer this thread already (invisibly)
    /// holds.
    public func drainRemoteQueue(into writer: any MarkdownRemoteWriter, limit: Int = 100) async throws {
        for remoteOp in try pendingRemoteOps(limit: limit) {
            try await writer.send(remoteOp)
            try completeRemoteOp(opID: remoteOp.opID)
        }
    }

    // MARK: - Timestamp normalization

    /// Round-trips a `Date` through `MarkdownTimestamp.string`/`.date` before
    /// it is used anywhere. `.string` always emits fractional (millisecond)
    /// form; `.date` accepts both fractional and non-fractional. Left
    /// unnormalized, a raw `Date()` (sub-millisecond precision) can compare as
    /// earlier than a value that already went through the database — which
    /// truncates to milliseconds — if both land in the same millisecond. This
    /// makes every timestamp this store hands back match what a fresh read
    /// would produce.
    private static func normalizedTimestamp(_ date: Date) -> Date {
        MarkdownTimestamp.date(MarkdownTimestamp.string(date)) ?? date
    }

    // MARK: - Row mapping

    private static func document(from row: Row) -> MarkdownDocument {
        MarkdownDocument(
            id: row["id"],
            content: row["content"],
            visibility: MarkdownVisibility(rawValue: row["visibility"]) ?? .private,
            stage: MarkdownStage(rawValue: row["stage"]) ?? .draft,
            publicRoute: row["public_route"],
            ownerKind: MarkdownOwnerKind(rawValue: row["owner_kind"]) ?? .customer,
            ownerID: row["owner_id"],
            createdAt: MarkdownTimestamp.date(row["created_at"]) ?? Date(),
            updatedAt: MarkdownTimestamp.date(row["updated_at"]) ?? Date(),
            deletedAt: (row["deleted_at"] as String?).flatMap(MarkdownTimestamp.date),
            isDeleted: (row["is_deleted"] as Int) != 0,
            currentVersion: row["current_version"],
            latestVersionID: row["latest_version_id"])
    }

    private func insert(_ document: MarkdownDocument, in conn: Database) throws {
        try conn.execute(
            sql: """
                INSERT INTO markdown
                    (id, customer_id, ecosystem_id, title, content, frontmatter,
                     content_hash, size_bytes, current_version, latest_version_id,
                     is_deleted, public_route, visibility, stage, owner_kind, owner_id,
                     created_at, updated_at, deleted_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: arguments(for: document))
    }

    private func write(_ document: MarkdownDocument, in conn: Database) throws {
        try conn.execute(
            sql: """
                UPDATE markdown SET
                    title = ?, content = ?, frontmatter = ?, content_hash = ?, size_bytes = ?,
                    public_route = ?, visibility = ?, stage = ?, owner_kind = ?, owner_id = ?,
                    updated_at = ?
                WHERE id = ?
                """,
            arguments: [
                document.title, document.content, document.frontmatterJSON,
                document.contentHash, document.sizeBytes,
                document.publicRoute, document.visibility.rawValue, document.stage.rawValue,
                document.ownerKind.rawValue, document.ownerID,
                MarkdownTimestamp.string(document.updatedAt),
                document.id
            ])
    }

    /// `title`, `content_hash` and `size_bytes` are written even though they
    /// are computed on the value: adh's columns exist and a synced row carries
    /// them, so the local row must too. They are a cache of `content`, never an
    /// authority — every write recomputes them.
    private func arguments(for document: MarkdownDocument) -> StatementArguments {
        [
            document.id, customerID, ecosystemID,
            document.title, document.content, document.frontmatterJSON,
            document.contentHash, document.sizeBytes,
            document.currentVersion, document.latestVersionID,
            document.isDeleted ? 1 : 0, document.publicRoute,
            document.visibility.rawValue, document.stage.rawValue,
            document.ownerKind.rawValue, document.ownerID,
            MarkdownTimestamp.string(document.createdAt),
            MarkdownTimestamp.string(document.updatedAt),
            document.deletedAt.map(MarkdownTimestamp.string)
        ]
    }

    private func addMarker(
        _ marker: MarkdownMarker, to documentID: String, at now: Date, in conn: Database
    ) throws {
        let stamp = MarkdownTimestamp.string(now)
        try conn.execute(
            sql: """
                INSERT INTO \(marker.table)
                    (id, customer_id, ecosystem_id, markdown_id, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
            arguments: [UUID().uuidString.lowercased(), customerID, ecosystemID,
                        documentID, stamp, stamp])
    }

    // MARK: - Outbox coalescing

    /// Coalesces on `(document_id, intent)`, with one exception that matters:
    /// an `update` for a document whose `create` has not drained yet merges
    /// into the `create`. Queueing both would send adh an update for a row it
    /// has never seen.
    private func enqueue(
        _ intent: MarkdownRemoteIntent, for documentID: String,
        payload: [String: JSONValue], at now: Date, in conn: Database
    ) throws {
        var target = intent
        if intent == .update {
            let hasPendingCreate = try Bool.fetchOne(
                conn,
                sql: "SELECT EXISTS(SELECT 1 FROM _markdown_outbox WHERE document_id = ? AND intent = 'create')",
                arguments: [documentID]) ?? false
            if hasPendingCreate { target = .create }
        }

        let existing = try Row.fetchOne(
            conn,
            sql: "SELECT op_id, payload FROM _markdown_outbox WHERE document_id = ? AND intent = ?",
            arguments: [documentID, target.rawValue])

        if let existing {
            // Not `(try? ...) ?? [:]` — a corrupt existing payload here is worse
            // than in `pendingRemoteOps`: falling back to `[:]` would silently
            // discard every field the earlier, already-queued op set, rather than
            // merely misreporting one row's intent.
            var merged = try decodePayload(existing["payload"])
            for (key, value) in payload { merged[key] = value }
            try conn.execute(
                sql: "UPDATE _markdown_outbox SET payload = ? WHERE op_id = ?",
                arguments: [try encodePayload(merged), existing["op_id"] as String])
        } else {
            try conn.execute(
                sql: """
                    INSERT INTO _markdown_outbox (op_id, document_id, intent, payload, created_at)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [SyncID.uuidV7(), documentID, target.rawValue,
                            try encodePayload(payload), MarkdownTimestamp.string(now)])
        }
    }

    private func encodePayload(_ payload: [String: JSONValue]) throws -> String {
        guard let text = String(bytes: try encoder.encode(payload), encoding: .utf8) else {
            throw MarkdownStoreError.payloadEncodingFailed
        }
        return text
    }

    private func decodePayload(_ text: String) throws -> [String: JSONValue] {
        try decoder.decode([String: JSONValue].self, from: Data(text.utf8))
    }
}
