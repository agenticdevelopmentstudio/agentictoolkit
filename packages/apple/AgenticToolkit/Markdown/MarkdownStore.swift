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
    /// A local edit moved a client-authored field that `PUT /content/markdown/:id`
    /// has no key for. `visibility`, `stage` and `public_route` change only
    /// through the route named in `method`, so writing the row here would
    /// leave a local state adh is never told about — silently, and forever,
    /// because the next pull would overwrite it with the server's.
    case useDedicatedIntent(field: String, method: String)
    /// A `publish` was asked for with an empty route, or a caller tried to
    /// move `visibility` and `public_route` apart. adh states the invariant as
    /// "public_route non-null IFF visibility='public'" and offers no way to
    /// set one without the other, so a document in that shape is
    /// unrepresentable on the wire.
    case inconsistentPublicationState(id: String)
    /// An `_markdown_outbox` row's `created_at` does not parse. Like
    /// `unknownRemoteIntent` this store is the column's only writer, so it
    /// means corruption; defaulting to `Date()` would silently reorder a
    /// queue whose whole point is that a `create` precedes its `update`.
    case unreadableOutboxTimestamp(opID: String)
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

    /// `customerID` and `ecosystemID` are the tenancy every mirrored row is
    /// stamped with, and they have no defaults on purpose. They were `""`
    /// before, which is a *value*, not an absence: every row written under it
    /// claims to belong to the empty tenant, and a later pull carrying the
    /// real ids cannot reconcile them because there is nothing in the row
    /// saying the ids were never supplied. Making both required means each
    /// call site has to answer the question out loud — including the ones
    /// whose answer really is `""` (a single-user local install, a test),
    /// which now say so at the call site where the reader can see it.
    public init(path: String, customerID: String, ecosystemID: String) throws {
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
            ).flatMap(Self.document(from:))
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
            ).compactMap(Self.document(from:))
        }
    }

    /// Writes the document's content and queues a `PUT /content/markdown/:id`.
    ///
    /// The wire payload is `content` and nothing else, which is narrower than
    /// it used to be and narrower than adh's `updateSchema`
    /// (`{ content?, category?, tags?, author? }`). Each omission has its own
    /// reason:
    ///
    /// - `visibility`, `stage` and `public_route` are not keys on that schema
    ///   at all. They were being sent, and adh's zod parse strips unknown
    ///   keys, so the writes were silently discarded. They move only through
    ///   `publishDocument`/`unpublishDocument`/`finalizeDocument`/
    ///   `definalizeDocument` and their four routes.
    /// - `category` and `tags` are real keys, but the state they carry already
    ///   pushes itself: `content.category_items` and `content.keyword_items`
    ///   are not pull-only, so `MarkdownTaxonomy` stages a `LocalMutation` for
    ///   every assignment and the generic sync outbox sends the link rows.
    ///   Sending them here as well would be a second writer for one piece of
    ///   state, with no ordering between the two.
    /// - `title` is derived by adh from the content and is on neither schema.
    ///
    /// A `document` whose authored state differs from the stored row therefore
    /// describes an edit this method cannot put on the wire, and it throws
    /// `useDedicatedIntent` naming the field rather than writing a local row
    /// that adh will never agree with (and that the next pull would silently
    /// revert).
    public func updateDocument(_ document: MarkdownDocument, now: Date = Date()) throws {
        let now = Self.normalizedTimestamp(now)
        try database.write { conn in
            guard let stored = try Row.fetchOne(
                conn, sql: "SELECT * FROM markdown WHERE id = ? AND is_deleted = 0",
                arguments: [document.id]) else {
                throw MarkdownStoreError.notFound(document.id)
            }
            try Self.refuseAuthoredFieldDrift(from: stored, to: document)

            var updated = document
            updated.updatedAt = now
            try write(updated, in: conn)
            try enqueue(.update, for: document.id, payload: [
                "content": .string(document.content)
            ], at: now, in: conn)
        }
    }

    /// Throws when `document` carries a different `visibility`, `stage` or
    /// `public_route` than the row on disk. Reading the stored row rather than
    /// comparing against a caller-supplied "original" is deliberate: the drift
    /// that matters is between what this write would store and what adh has
    /// been told, and the stored row is the only local record of the latter.
    private static func refuseAuthoredFieldDrift(
        from stored: Row, to document: MarkdownDocument
    ) throws {
        let publication = "publishDocument(id:route:) / unpublishDocument(id:)"
        let storedVisibility: String? = stored["visibility"]
        let storedStage: String? = stored["stage"]
        let storedRoute: String? = stored["public_route"]

        if storedVisibility != document.visibility.rawValue {
            throw MarkdownStoreError.useDedicatedIntent(field: "visibility", method: publication)
        }
        if storedRoute != document.publicRoute {
            throw MarkdownStoreError.useDedicatedIntent(field: "public_route", method: publication)
        }
        if storedStage != document.stage.rawValue {
            throw MarkdownStoreError.useDedicatedIntent(
                field: "stage", method: "finalizeDocument(id:) / definalizeDocument(id:)")
        }
    }

    // MARK: - The four lifecycle routes

    /// `POST /content/markdown/:id/publish` with `{ route }`.
    ///
    /// `visibility` and `public_route` move together because upstream they are
    /// one operation — adh's route file states the invariant as "public_route
    /// non-null IFF visibility='public'" and offers no endpoint that sets
    /// either alone. An empty route is refused here rather than sent, because
    /// it would store a row satisfying neither half of that invariant.
    public func publishDocument(id: String, route: String, now: Date = Date()) throws {
        guard !route.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MarkdownStoreError.inconsistentPublicationState(id: id)
        }
        try setAuthoredState(
            id: id, assignments: "visibility = 'public', public_route = ?", values: [route],
            intent: .publish, payload: ["route": .string(route)], now: now)
    }

    /// `POST /content/markdown/:id/unpublish` — the other half of the same
    /// invariant: clearing the route and going private is one move.
    public func unpublishDocument(id: String, now: Date = Date()) throws {
        try setAuthoredState(
            id: id, assignments: "visibility = 'private', public_route = NULL", values: [],
            intent: .unpublish, payload: [:], now: now)
    }

    /// `POST /content/markdown/:id/finalize`. adh's `assertMutable` refuses a
    /// *content* change on a final document with 409 afterwards;
    /// classification edits and publish/unpublish still work.
    public func finalizeDocument(id: String, now: Date = Date()) throws {
        try setAuthoredState(
            id: id, assignments: "stage = 'final'", values: [],
            intent: .finalize, payload: [:], now: now)
    }

    /// `POST /content/markdown/:id/definalize`.
    public func definalizeDocument(id: String, now: Date = Date()) throws {
        try setAuthoredState(
            id: id, assignments: "stage = 'draft'", values: [],
            intent: .definalize, payload: [:], now: now)
    }

    /// The shape all four lifecycle methods share, and deliberately the same
    /// shape as `updateDocument`: normalize `now`, refuse a document that is
    /// not there, then write the row and enqueue its op inside one
    /// `database.write` so the local state and the queued call can never
    /// disagree about whether the change happened.
    private func setAuthoredState(
        id: String, assignments: String, values: [(any DatabaseValueConvertible)?],
        intent: MarkdownRemoteIntent, payload: [String: JSONValue], now: Date
    ) throws {
        let now = Self.normalizedTimestamp(now)
        try database.write { conn in
            let exists = try Bool.fetchOne(
                conn, sql: "SELECT EXISTS(SELECT 1 FROM markdown WHERE id = ? AND is_deleted = 0)",
                arguments: [id]) ?? false
            guard exists else { throw MarkdownStoreError.notFound(id) }

            var arguments = StatementArguments(values)
            arguments += [MarkdownTimestamp.string(now), id]
            try conn.execute(
                sql: "UPDATE markdown SET \(assignments), updated_at = ? WHERE id = ?",
                arguments: arguments)
            try enqueue(intent, for: id, payload: payload, at: now, in: conn)
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
            // Every op still queued for this document is now moot, and one of
            // them is actively harmful: a pending `create` would make adh
            // create the document seconds before the `delete` removed it
            // again, and a pending `publish` would make a public route for a
            // document about to vanish. So the queue is cleared first.
            //
            // Whether a `delete` then replaces them turns on one question:
            // does adh know this document exists? It does not if its `create`
            // was still queued — nothing was ever sent — and `DELETE /:id`
            // for an id the server never minted is a 404, so the whole
            // create/delete pair simply drops. Otherwise the delete is real
            // and is queued.
            let hasPendingCreate = try Bool.fetchOne(
                conn,
                sql: "SELECT EXISTS(SELECT 1 FROM _markdown_outbox WHERE document_id = ? AND intent = 'create')",
                arguments: [id]) ?? false
            try conn.execute(
                sql: "DELETE FROM _markdown_outbox WHERE document_id = ?", arguments: [id])
            if !hasPendingCreate {
                try enqueue(.delete, for: id, payload: [:], at: now, in: conn)
            }
        }
    }

    // MARK: - The REST queue

    /// Ordered by `seq`, the monotonic counter `enqueue` stamps — not by
    /// `created_at`, which is truncated to milliseconds and so ties for any
    /// two ops enqueued in the same millisecond, and not by `op_id`, whose
    /// UUIDv7 tie-break is random. Under the old ordering an `update` could
    /// come back ahead of the `create` it depends on.
    public func pendingRemoteOps(limit: Int = 100) throws -> [MarkdownRemoteOp] {
        try database.read { conn in
            try Row.fetchAll(
                conn,
                sql: """
                    SELECT o.*, r.remote_id AS remote_id
                    FROM _markdown_outbox o
                    LEFT JOIN _markdown_remote_id r ON r.local_id = o.document_id
                    ORDER BY o.seq LIMIT ?
                    """,
                arguments: [limit]
            ).map { row in
                // An unreadable `intent`, `payload` or `created_at` is on-disk
                // corruption, not a legitimate default — `?? .update` / `?? [:]`
                // / `?? Date()` would silently turn it into a content push, drop
                // already-queued fields, or invent a send time, so all three
                // throw instead of guessing.
                let opID: String = row["op_id"]
                let rawIntent: String = row["intent"]
                guard let intent = MarkdownRemoteIntent(rawValue: rawIntent) else {
                    throw MarkdownStoreError.unknownRemoteIntent(rawIntent)
                }
                guard let createdAt = MarkdownTimestamp.date(row["created_at"]) else {
                    throw MarkdownStoreError.unreadableOutboxTimestamp(opID: opID)
                }
                return MarkdownRemoteOp(
                    opID: opID,
                    documentID: row["document_id"],
                    remoteID: row["remote_id"],
                    intent: intent,
                    payload: try self.decodePayload(row["payload"]),
                    createdAt: createdAt)
            }
        }
    }

    /// The id adh knows a locally-created document by, once its `create` has
    /// drained and the writer reported one.
    public func remoteID(forDocument documentID: String) throws -> String? {
        try database.read { conn in
            try String.fetchOne(
                conn, sql: "SELECT remote_id FROM _markdown_remote_id WHERE local_id = ?",
                arguments: [documentID])
        }
    }

    public func completeRemoteOp(opID: String) throws {
        try complete(opID: opID, recording: nil, for: nil)
    }

    /// Clears a drained op and, for a `create` the writer answered with an id,
    /// records the local↔remote pairing — in one transaction, because the two
    /// facts must land together. Clear first and crash and the pairing is lost
    /// with no queued op left to re-derive it from; record first and crash and
    /// the create re-sends, making a second document upstream.
    private func complete(opID: String, recording remoteID: String?, for documentID: String?) throws {
        try database.write { conn in
            if let remoteID, let documentID {
                try conn.execute(
                    sql: """
                        INSERT INTO _markdown_remote_id (local_id, remote_id, created_at)
                        VALUES (?, ?, ?)
                        ON CONFLICT(local_id) DO UPDATE SET remote_id = excluded.remote_id
                        """,
                    arguments: [documentID, remoteID, MarkdownTimestamp.string(Date())])
            }
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
        for queued in try pendingRemoteOps(limit: limit) {
            // The remote id is re-read immediately before each send rather
            // than trusted from the batch snapshot: an `update` queued behind
            // its own document's `create` had no remote id when the batch was
            // read, and acquires one from the `create` that drains a few
            // iterations earlier in this very loop.
            let remoteOp = MarkdownRemoteOp(
                opID: queued.opID,
                documentID: queued.documentID,
                remoteID: try remoteID(forDocument: queued.documentID),
                intent: queued.intent,
                payload: queued.payload,
                createdAt: queued.createdAt)
            let assigned = try await writer.send(remoteOp)
            // adh mints the id — `POST /content/markdown` takes none — so a
            // create's response is the only place the document's upstream
            // identity ever appears. Recording it here, before any later op
            // for the same document is sent, is what lets `update`/`delete`/
            // the four lifecycle calls address `/:id` at all.
            try complete(
                opID: remoteOp.opID,
                recording: remoteOp.intent == .create ? assigned : nil,
                for: remoteOp.documentID)
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

    /// `nil` for a row whose `created_at`/`updated_at` will not parse.
    ///
    /// Failable rather than substituting `Date()`, which is what it used to
    /// do: a fabricated "now" reads as a real timestamp everywhere downstream
    /// — it sorts to the top of a notes list, it is what `updateDocument`
    /// would then write back over the unreadable value, and nothing
    /// distinguishes it from a document genuinely touched this second. A row
    /// that cannot say when it was written is better left out of the answer
    /// than described wrongly, so both callers `compactMap` it away.
    private static func document(from row: Row) -> MarkdownDocument? {
        guard let createdAt = MarkdownTimestamp.date(row["created_at"]),
              let updatedAt = MarkdownTimestamp.date(row["updated_at"]) else { return nil }
        return MarkdownDocument(
            id: row["id"],
            content: row["content"],
            visibility: MarkdownVisibility(rawValue: row["visibility"]) ?? .private,
            stage: MarkdownStage(rawValue: row["stage"]) ?? .draft,
            publicRoute: row["public_route"],
            ownerKind: MarkdownOwnerKind(rawValue: row["owner_kind"]) ?? .customer,
            ownerID: row["owner_id"],
            createdAt: createdAt,
            updatedAt: updatedAt,
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
            // `MAX(seq) + 1` rather than `AUTOINCREMENT`, which SQLite allows
            // only on an `INTEGER PRIMARY KEY` — a column this table cannot
            // grow by `ALTER TABLE`. Values are reused once the queue drains,
            // which is harmless: every row that could have held the reused
            // value is gone, so the order among the rows that remain is still
            // the order they were enqueued in. Merging into an `existing` row
            // above deliberately leaves its `seq` alone — an `update` folded
            // into a pending `create` must keep the create's position.
            let nextSeq = try Int.fetchOne(
                conn, sql: "SELECT COALESCE(MAX(seq), 0) + 1 FROM _markdown_outbox") ?? 1
            try conn.execute(
                sql: """
                    INSERT INTO _markdown_outbox (op_id, document_id, intent, payload, created_at, seq)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [SyncID.uuidV7(), documentID, target.rawValue,
                            try encodePayload(payload), MarkdownTimestamp.string(now), nextSeq])
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
