import AgenticToolkitHub
import Foundation
import HTTPTypes

@MainActor
public final class BucketsAdapter: BucketsDataSource {
    /// Wire row for `/bucket/bucket-types`; carries the ecosystem so lists can be filtered here.
    private struct TableRow: Decodable {
        let id: String
        let bucketId: String
        let ecosystemId: String?
        let sqlTableName: String
        let name: String
        var table: BucketTable { BucketTable(id: id, bucketId: bucketId, sqlTableName: sqlTableName, name: name) }
    }

    private let api: HubAPI
    private let workspace: HubWorkspace

    public init(environment: HubEnvironment, workspace: HubWorkspace) {
        self.api = HubAPI(environment: environment)
        self.workspace = workspace
    }

    public func list(ecosystemID: String) async throws -> [Bucket] {
        try await api.get("/bucket/buckets", query: workspace.query, as: [Bucket].self)
            .filter { $0.ecosystemId == ecosystemID }
    }

    public func get(id: String) async throws -> Bucket {
        try await api.get("/bucket/buckets/\(id)", query: workspace.query, as: Bucket.self)
    }

    public func create(_ input: BucketCreate) async throws -> Bucket {
        try await api.send(.post, "/bucket/buckets", query: workspace.query, body: input, as: Bucket.self)
    }

    public func update(id: String, _ input: BucketUpdate) async throws -> Bucket {
        try await api.send(.put, "/bucket/buckets/\(id)", query: workspace.query, body: input, as: Bucket.self)
    }

    public func delete(id: String) async throws {
        try await api.send(.delete, "/bucket/buckets/\(id)", query: workspace.query)
    }

    public func tables(ecosystemID: String) async throws -> [BucketTable] {
        try await api.get("/bucket/bucket-types", query: workspace.query, as: [TableRow].self)
            .filter { $0.ecosystemId == ecosystemID }
            .map(\.table)
    }

    public func createTable(_ input: BucketTableCreate) async throws -> BucketTable {
        try await api.send(.post, "/bucket/bucket-types", query: workspace.query, body: input, as: TableRow.self).table
    }

    public func updateTable(id: String, _ input: BucketTableUpdate) async throws -> BucketTable {
        try await api.send(
            .put, "/bucket/bucket-types/\(id)", query: workspace.query, body: input, as: TableRow.self
        ).table
    }

    public func deleteTable(id: String) async throws {
        try await api.send(.delete, "/bucket/bucket-types/\(id)", query: workspace.query)
    }
}
