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
