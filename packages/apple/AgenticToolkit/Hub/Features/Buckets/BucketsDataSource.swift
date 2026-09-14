import Foundation

/// Everything the Buckets topic needs from the server. Lists are ecosystem-scoped.
public protocol BucketsDataSource: AnyObject, Sendable {
    func list(ecosystemID: String) async throws -> [Bucket]
    func get(id: String) async throws -> Bucket
    func create(_ input: BucketCreate) async throws -> Bucket
    func update(id: String, _ input: BucketUpdate) async throws -> Bucket
    func delete(id: String) async throws
    /// Every table of every bucket in the ecosystem (the topic groups them by `bucketId`).
    func tables(ecosystemID: String) async throws -> [BucketTable]
    func createTable(_ input: BucketTableCreate) async throws -> BucketTable
    func updateTable(id: String, _ input: BucketTableUpdate) async throws -> BucketTable
    func deleteTable(id: String) async throws
}
