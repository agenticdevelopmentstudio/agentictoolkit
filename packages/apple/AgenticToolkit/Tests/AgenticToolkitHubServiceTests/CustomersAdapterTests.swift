import AgenticDeveloperHubClient
import AgenticToolkitHub
import Foundation
import HTTPTypes
import XCTest
@testable import AgenticToolkitHubService

@MainActor
final class CustomersAdapterTests: XCTestCase {
    private var stub: StubClientTransport!
    private var adapter: CustomersAdapter!

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
        adapter = CustomersAdapter(
            environment: environment,
            workspace: HubWorkspace(slug: "acme", name: "Acme", type: .organization)
        )
    }

    private let janeJSON = #"""
    {"id":"c-jane","ecosystemId":"org.acme.shop","email":"jane@example.com","displayName":"Jane Doe",
     "externalId":null,"slug":"jane","avatarUrl":null,
     "createdAt":"2026-09-01T00:00:00.000Z","updatedAt":"2026-09-01T00:00:00.000Z"}
    """#
    private let otherJSON = #"""
    {"id":"c-bob","ecosystemId":"org.acme.blog","email":"bob@example.com",
     "createdAt":"2026-09-01T00:00:00.000Z","updatedAt":"2026-09-01T00:00:00.000Z"}
    """#

    func testListFiltersByEcosystem() async throws {
        stub.on(.get, "/customer/customers", json: "[\(janeJSON),\(otherJSON)]")
        let rows = try await adapter.list(ecosystemID: "org.acme.shop")
        XCTAssertEqual(rows.map(\.id), ["c-jane"])
        XCTAssertEqual(rows.first?.label, "Jane Doe")
        XCTAssertEqual(stub.lastRequest(.get, "/customer/customers")?.path, "/customer/customers?workspace=acme")
    }

    func testGet() async throws {
        stub.on(.get, "/customer/customers/c-jane", json: janeJSON)
        let customer = try await adapter.get(id: "c-jane")
        XCTAssertEqual(customer.email, "jane@example.com")
        XCTAssertEqual(
            stub.lastRequest(.get, "/customer/customers/c-jane")?.path,
            "/customer/customers/c-jane?workspace=acme"
        )
    }

    func testCreatePostsBodyWithoutNilFields() async throws {
        stub.on(.post, "/customer/customers", status: 201, json: janeJSON)
        _ = try await adapter.create(
            CustomerInput(ecosystemId: "org.acme.shop", email: "jane@example.com", displayName: "Jane Doe")
        )
        XCTAssertEqual(stub.lastRequest(.post, "/customer/customers")?.path, "/customer/customers?workspace=acme")
        let sent = stub.lastBody(.post, "/customer/customers")
        XCTAssertEqual(sent?["ecosystemId"] as? String, "org.acme.shop")
        XCTAssertEqual(sent?["email"] as? String, "jane@example.com")
        XCTAssertEqual(sent?["displayName"] as? String, "Jane Doe")
        XCTAssertNil(sent?["externalId"] ?? nil)
        XCTAssertNil(sent?["slug"] ?? nil)
    }

    func testUpdatePutsFullInput() async throws {
        stub.on(.put, "/customer/customers/c-jane", json: janeJSON)
        _ = try await adapter.update(
            id: "c-jane",
            CustomerInput(ecosystemId: "org.acme.shop", email: "jane@example.com", displayName: "Jane", slug: "jane")
        )
        let sent = stub.lastBody(.put, "/customer/customers/c-jane")
        XCTAssertEqual(sent?["displayName"] as? String, "Jane")
        XCTAssertEqual(sent?["slug"] as? String, "jane")
        XCTAssertEqual(
            stub.lastRequest(.put, "/customer/customers/c-jane")?.path,
            "/customer/customers/c-jane?workspace=acme"
        )
    }

    func testDelete() async throws {
        stub.on(.delete, "/customer/customers/c-jane", status: 204, json: "")
        try await adapter.delete(id: "c-jane")
        XCTAssertEqual(
            stub.lastRequest(.delete, "/customer/customers/c-jane")?.path,
            "/customer/customers/c-jane?workspace=acme"
        )
    }

    func testConflictBecomesHubErrorConflict() async throws {
        stub.on(.post, "/customer/customers", status: 409, json: #"{"error":"email in use"}"#)
        do {
            _ = try await adapter.create(CustomerInput(ecosystemId: "org.acme.shop", email: "jane@example.com"))
            XCTFail("expected throw")
        } catch let error as HubError {
            XCTAssertEqual(error, .conflict("email in use"))
        }
        XCTAssertEqual(stub.lastRequest(.post, "/customer/customers")?.path, "/customer/customers?workspace=acme")
    }
}
