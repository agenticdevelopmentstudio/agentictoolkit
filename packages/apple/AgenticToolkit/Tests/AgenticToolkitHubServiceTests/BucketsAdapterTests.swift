import AgenticDeveloperHubClient
import AgenticToolkitHub
import Foundation
import HTTPTypes
import XCTest
@testable import AgenticToolkitHubService

@MainActor
final class BucketsAdapterTests: XCTestCase {
    private var stub: StubClientTransport!
    private var adapter: BucketsAdapter!

    override func setUp() async throws {
        try await super.setUp()
        stub = StubClientTransport()
        let store = InMemorySessionStore(
            Session(credentials: Credentials(token: "jwt", kind: .jwt), refreshToken: "r")
        )
        let environment = HubEnvironment(
            sessionStore: store,
            transportSource: StaticTransportSource(.direct(transport: stub)),
            initialTransport: .direct(transport: stub)
        )
        adapter = BucketsAdapter(
            environment: environment,
            workspace: HubWorkspace(slug: "acme", name: "Acme", type: .organization)
        )
    }

    private let profileJSON = #"""
    {"id":"b-profile","ecosystemId":"org.acme.shop","name":"Profile Basics","kind":"custom",
     "metadata":{"description":"Names and avatars"},
     "createdAt":"2026-09-01T00:00:00.000Z","updatedAt":"2026-09-01T00:00:00.000Z"}
    """#
    private let otherJSON = #"""
    {"id":"b-other","ecosystemId":"org.acme.blog","name":"Posts",
     "createdAt":"2026-09-01T00:00:00.000Z","updatedAt":"2026-09-01T00:00:00.000Z"}
    """#
    private let contactsJSON = #"""
    {"id":"t-contacts","bucketId":"b-profile","ecosystemId":"org.acme.shop","sqlTableName":"contacts","name":"Contacts"}
    """#
    private let postsTableJSON = #"""
    {"id":"t-posts","bucketId":"b-other","ecosystemId":"org.acme.blog","sqlTableName":"posts","name":"Posts"}
    """#

    func testListFiltersByEcosystemAndSendsWorkspace() async throws {
        stub.on(.get, "/bucket/buckets", json: "[\(profileJSON),\(otherJSON)]")
        let rows = try await adapter.list(ecosystemID: "org.acme.shop")
        XCTAssertEqual(rows.map(\.id), ["b-profile"])
        XCTAssertEqual(rows.first?.description, "Names and avatars")
        XCTAssertEqual(
            stub.lastRequest(.get, "/bucket/buckets")?.path,
            "/bucket/buckets?workspace=acme"
        )
    }

    func testMissingKindDecodesAsCustom() async throws {
        stub.on(.get, "/bucket/buckets", json: "[\(otherJSON)]")
        let rows = try await adapter.list(ecosystemID: "org.acme.blog")
        XCTAssertEqual(rows.first?.kind, "custom")
        XCTAssertFalse(rows.first?.isBuiltIn ?? true)
        XCTAssertEqual(stub.lastRequest(.get, "/bucket/buckets")?.path, "/bucket/buckets?workspace=acme")
    }

    func testGet() async throws {
        stub.on(.get, "/bucket/buckets/b-profile", json: profileJSON)
        let bucket = try await adapter.get(id: "b-profile")
        XCTAssertEqual(bucket.name, "Profile Basics")
        XCTAssertEqual(
            stub.lastRequest(.get, "/bucket/buckets/b-profile")?.path,
            "/bucket/buckets/b-profile?workspace=acme"
        )
    }

    func testCreatePostsBody() async throws {
        stub.on(.post, "/bucket/buckets", status: 201, json: profileJSON)
        _ = try await adapter.create(
            BucketCreate(
                ecosystemId: "org.acme.shop", name: "Profile Basics",
                metadata: BucketMetadata(description: "Names and avatars")
            )
        )
        let sent = stub.lastBody(.post, "/bucket/buckets")
        XCTAssertEqual(sent?["ecosystemId"] as? String, "org.acme.shop")
        XCTAssertEqual(sent?["name"] as? String, "Profile Basics")
        XCTAssertEqual((sent?["metadata"] as? [String: Any])?["description"] as? String, "Names and avatars")
        XCTAssertEqual(stub.lastRequest(.post, "/bucket/buckets")?.path, "/bucket/buckets?workspace=acme")
    }

    func testUpdatePutsOnlyProvidedFields() async throws {
        stub.on(.put, "/bucket/buckets/b-profile", json: profileJSON)
        _ = try await adapter.update(id: "b-profile", BucketUpdate(name: "Profiles"))
        XCTAssertEqual(
            stub.lastRequest(.put, "/bucket/buckets/b-profile")?.path, "/bucket/buckets/b-profile?workspace=acme"
        )
        let sent = stub.lastBody(.put, "/bucket/buckets/b-profile")
        XCTAssertEqual(sent?["name"] as? String, "Profiles")
        XCTAssertNil(sent?["metadata"] ?? nil)
    }

    func testDelete() async throws {
        stub.on(.delete, "/bucket/buckets/b-profile", status: 204, json: "")
        try await adapter.delete(id: "b-profile")
        XCTAssertEqual(
            stub.lastRequest(.delete, "/bucket/buckets/b-profile")?.path,
            "/bucket/buckets/b-profile?workspace=acme"
        )
    }

    func testTablesFiltersByEcosystem() async throws {
        stub.on(.get, "/bucket/bucket-types", json: "[\(contactsJSON),\(postsTableJSON)]")
        let rows = try await adapter.tables(ecosystemID: "org.acme.shop")
        XCTAssertEqual(rows.map(\.id), ["t-contacts"])
        XCTAssertEqual(rows.first?.bucketId, "b-profile")
        XCTAssertEqual(rows.first?.sqlTableName, "contacts")
        XCTAssertEqual(
            stub.lastRequest(.get, "/bucket/bucket-types")?.path,
            "/bucket/bucket-types?workspace=acme"
        )
    }

    func testCreateTablePostsBody() async throws {
        stub.on(.post, "/bucket/bucket-types", status: 201, json: contactsJSON)
        let row = try await adapter.createTable(
            BucketTableCreate(
                ecosystemId: "org.acme.shop", bucketId: "b-profile", sqlTableName: "contacts", name: "Contacts"
            )
        )
        XCTAssertEqual(row.id, "t-contacts")
        XCTAssertEqual(
            stub.lastRequest(.post, "/bucket/bucket-types")?.path, "/bucket/bucket-types?workspace=acme"
        )
        let sent = stub.lastBody(.post, "/bucket/bucket-types")
        XCTAssertEqual(sent?["bucketId"] as? String, "b-profile")
        XCTAssertEqual(sent?["sqlTableName"] as? String, "contacts")
        XCTAssertEqual(sent?["name"] as? String, "Contacts")
    }

    func testUpdateAndDeleteTable() async throws {
        stub.on(.put, "/bucket/bucket-types/t-contacts", json: contactsJSON)
        stub.on(.delete, "/bucket/bucket-types/t-contacts", status: 204, json: "")
        _ = try await adapter.updateTable(id: "t-contacts", BucketTableUpdate(name: "People"))
        XCTAssertEqual(stub.lastBody(.put, "/bucket/bucket-types/t-contacts")?["name"] as? String, "People")
        XCTAssertEqual(
            stub.lastRequest(.put, "/bucket/bucket-types/t-contacts")?.path,
            "/bucket/bucket-types/t-contacts?workspace=acme"
        )
        try await adapter.deleteTable(id: "t-contacts")
        XCTAssertEqual(
            stub.lastRequest(.delete, "/bucket/bucket-types/t-contacts")?.path,
            "/bucket/bucket-types/t-contacts?workspace=acme"
        )
    }

    func testConflictBecomesHubErrorConflict() async throws {
        stub.on(.post, "/bucket/buckets", status: 409, json: #"{"error":"duplicate name"}"#)
        do {
            _ = try await adapter.create(
                BucketCreate(ecosystemId: "org.acme.shop", name: "Profile Basics", metadata: BucketMetadata())
            )
            XCTFail("expected throw")
        } catch let error as HubError {
            XCTAssertEqual(error, .conflict("duplicate name"))
        }
        XCTAssertEqual(stub.lastRequest(.post, "/bucket/buckets")?.path, "/bucket/buckets?workspace=acme")
    }
}
