import Foundation

public struct BucketMetadata: Codable, Hashable, Sendable {
    public var description: String?
    public init(description: String? = nil) { self.description = description }
}

/// A storage bucket (`/bucket/buckets` row). `kind` is `"custom"` for user-created buckets;
/// any other kind is built in and cannot be deleted.
public struct Bucket: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var ecosystemId: String
    public var name: String
    public var kind: String
    public var metadata: BucketMetadata?
    public var createdAt: String?
    public var updatedAt: String?

    public init(
        id: String, ecosystemId: String, name: String, kind: String = "custom", metadata: BucketMetadata? = nil,
        createdAt: String? = nil, updatedAt: String? = nil
    ) {
        self.id = id; self.ecosystemId = ecosystemId; self.name = name; self.kind = kind
        self.metadata = metadata; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey { case id, ecosystemId, name, kind, metadata, createdAt, updatedAt }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        ecosystemId = try container.decode(String.self, forKey: .ecosystemId)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "custom"
        metadata = try container.decodeIfPresent(BucketMetadata.self, forKey: .metadata)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    public var description: String { metadata?.description ?? "" }
    public var isBuiltIn: Bool { kind != "custom" }
}

public struct BucketCreate: Codable, Hashable, Sendable {
    public var ecosystemId: String
    public var name: String
    public var metadata: BucketMetadata
    public init(ecosystemId: String, name: String, metadata: BucketMetadata) {
        self.ecosystemId = ecosystemId; self.name = name; self.metadata = metadata
    }
}

public struct BucketUpdate: Codable, Hashable, Sendable {
    public var name: String?
    public var metadata: BucketMetadata?
    public init(name: String? = nil, metadata: BucketMetadata? = nil) { self.name = name; self.metadata = metadata }
}

/// A table inside a bucket (`/bucket/bucket-types` row).
public struct BucketTable: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var bucketId: String
    public var sqlTableName: String
    public var name: String
    public init(id: String, bucketId: String, sqlTableName: String, name: String) {
        self.id = id; self.bucketId = bucketId; self.sqlTableName = sqlTableName; self.name = name
    }
}

public struct BucketTableCreate: Codable, Hashable, Sendable {
    public var ecosystemId: String
    public var bucketId: String
    public var sqlTableName: String
    public var name: String
    public init(ecosystemId: String, bucketId: String, sqlTableName: String, name: String) {
        self.ecosystemId = ecosystemId; self.bucketId = bucketId; self.sqlTableName = sqlTableName; self.name = name
    }
}

public struct BucketTableUpdate: Codable, Hashable, Sendable {
    public var name: String?
    public init(name: String? = nil) { self.name = name }
}
