import Foundation
import GRDB
import AgenticToolkitSync

/// Stores a subset of a `GRDBSyncStore`'s resources in typed tables instead of
/// the generic `(id, sync_version, deleted_at, data)` mirror.
///
/// The generic mirror is the right default: it survives schema evolution
/// without a migration, because a new server field is just another JSON key.
/// It is the wrong shape when the local side has to index, join, or constrain
/// what it stores — a document store wants `WHERE is_deleted = 0 ORDER BY
/// updated_at` on real columns, and a category graph wants foreign keys.
///
/// A projection claims resources by name. Every mirror-touching site in
/// `GRDBSyncStore` asks the projection first and falls through to the JSON
/// mirror when the resource is not claimed, so a store can hold both kinds at
/// once and a store with no projection is bit-for-bit what it always was.
///
/// Every method is handed the connection to work on. The store never opens a
/// transaction on a projection's behalf, so a projection is always inside the
/// caller's — a pulled batch stays atomic.
public protocol SyncMirrorProjection: Sendable {

    /// The resource names this projection owns. Anything else falls through.
    var resources: Set<String> { get }

    /// Creates whatever tables and indexes the projection needs. Called from
    /// `prepare`, so it must be idempotent.
    func createTables(in conn: Database) throws

    func upsert(
        resource: String, id: String, syncVersion: Int,
        data: [String: JSONValue], in conn: Database) throws

    /// The `isFullRow`-aware overload of the requirement above. `isFullRow`
    /// tells the projection whether `data` is the server's whole current row
    /// (`true` — a pulled change from `apply`) or a deliberate partial patch
    /// (`false` — a local mutation staged through `stage(_:)`); a projection
    /// that force-binds a column regardless of whether `data` supplies it
    /// (e.g. a delete-state tombstone on a full-row pull) needs that signal
    /// to avoid doing the same thing to a partial patch, where it would
    /// silently overwrite a column the patch never meant to touch.
    ///
    /// This has a default implementation below that forwards to the
    /// original requirement above, ignoring `isFullRow` — so a projection
    /// written before this parameter existed (or one with no reason to care
    /// about the distinction) needs no changes at all to keep conforming.
    /// `GRDBSyncStore`'s two call sites always call this overload directly,
    /// naming which case they are; only a projection that wants to
    /// distinguish the two overrides it.
    func upsert(
        resource: String, id: String, syncVersion: Int,
        data: [String: JSONValue], isFullRow: Bool, in conn: Database) throws

    /// `syncVersion` is `nil` for a local delete, which has no server version
    /// yet; the projection should leave the stored version alone in that case.
    func markDeleted(resource: String, id: String, syncVersion: Int?, in conn: Database) throws

    /// Adopts the version the server assigned to a pushed row.
    func setSyncVersion(_ version: Int, resource: String, id: String, in conn: Database) throws

    /// The row's current version, or `nil` when the row is not stored yet.
    func syncVersion(resource: String, id: String, in conn: Database) throws -> Int?

    /// Empties the projection's storage for the given resources.
    func truncate(resources: [String], in conn: Database) throws

    /// Live rows as the generic mirror would have returned them — including
    /// an `"id"` key — so `liveRows`/`liveRow` have one return contract.
    func rows(resource: String, limit: Int, offset: Int, in conn: Database) throws -> [[String: JSONValue]]

    func row(resource: String, id: String, in conn: Database) throws -> [String: JSONValue]?
}

public extension SyncMirrorProjection {
    /// Default for the `isFullRow`-aware requirement: forward to the
    /// original `upsert(resource:id:syncVersion:data:in:)`, discarding
    /// `isFullRow`. This is what makes adding the new requirement
    /// source-compatible for every conformer written before it existed —
    /// dispatch through `any SyncMirrorProjection` still resolves to this
    /// default for a type that never overrides it (the same
    /// default-satisfies-a-requirement mechanism `Collection.count` uses:
    /// the default runs unless the conformer supplies its own
    /// implementation of this exact requirement, in which case dispatch
    /// picks that one instead, even through an existential).
    func upsert(
        resource: String, id: String, syncVersion: Int,
        data: [String: JSONValue], isFullRow: Bool, in conn: Database
    ) throws {
        try upsert(resource: resource, id: id, syncVersion: syncVersion, data: data, in: conn)
    }
}
