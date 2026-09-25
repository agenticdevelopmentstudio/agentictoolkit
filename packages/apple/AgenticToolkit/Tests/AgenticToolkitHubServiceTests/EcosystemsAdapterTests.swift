import AgenticDeveloperHubClient
import AgenticToolkitHub
import Foundation
import HTTPTypes
import XCTest
@testable import AgenticToolkitHubService

@MainActor
final class EcosystemsAdapterTests: XCTestCase {
    private func makeAdapter() -> (EcosystemsAdapter, StubClientTransport) {
        let stub = StubClientTransport()
        let store = InMemorySessionStore(Session(credentials: Credentials(token: "jwt", kind: .jwt), refreshToken: "r"))
        let environment = HubEnvironment(
            sessionStore: store,
            transportSource: StaticTransportSource(.direct(transport: stub)),
            initialTransport: .direct(transport: stub)
        )
        let adapter = EcosystemsAdapter(
            environment: environment,
            workspace: HubWorkspace(slug: "acme", name: "Acme", type: .organization)
        )
        return (adapter, stub)
    }

    private let shopJSON = #"""
    {"id":"org.acme.shop","slug":"shop","name":"Shop","description":"Storefront","region":null,"primaryDomain":null,
     "createdAt":"2026-09-01T00:00:00.000Z","updatedAt":"2026-09-01T00:00:00.000Z","isDefault":false,"parentId":null}
    """#
    private let infraJSON = #"""
    {"id":"org.acme","slug":"acme","name":"Acme","createdAt":"2026-09-01T00:00:00.000Z",
     "updatedAt":"2026-09-01T00:00:00.000Z","isDefault":true,"isInfrastructure":true}
    """#

    func testListSendsWorkspaceQuery() async throws {
        let (adapter, stub) = makeAdapter()
        stub.on(.get, "/ecosystem/ecosystems", json: "[\(shopJSON)]")
        let rows = try await adapter.list()
        XCTAssertEqual(rows.map(\.id), ["org.acme.shop"])
        XCTAssertEqual(stub.lastRequest(.get, "/ecosystem/ecosystems")?.path, "/ecosystem/ecosystems?workspace=acme")
        XCTAssertEqual(stub.lastRequest(.get, "/ecosystem/ecosystems")?.headerFields[.authorization], "Bearer jwt")
    }

    /// `parent=` alone, as the web sends it. Adding `workspace=` AND'd the two scopes and the child
    /// list read empty for a product that has children.
    func testChildrenSendsParentAloneWithoutWorkspace() async throws {
        let (adapter, stub) = makeAdapter()
        stub.on(.get, "/ecosystem/ecosystems", json: "[]")
        let rows = try await adapter.children(of: "org.acme.shop")
        XCTAssertTrue(rows.isEmpty)
        XCTAssertEqual(
            stub.lastRequest(.get, "/ecosystem/ecosystems")?.path,
            "/ecosystem/ecosystems?parent=org.acme.shop"
        )
    }

    func testGet() async throws {
        let (adapter, stub) = makeAdapter()
        stub.on(.get, "/ecosystem/ecosystems/org.acme.shop", json: shopJSON)
        let ecosystem = try await adapter.get(id: "org.acme.shop")
        XCTAssertEqual(ecosystem.name, "Shop")
        XCTAssertFalse(ecosystem.isDefault)
        XCTAssertEqual(
            stub.lastRequest(.get, "/ecosystem/ecosystems/org.acme.shop")?.path,
            "/ecosystem/ecosystems/org.acme.shop?workspace=acme"
        )
    }

    func testInfrastructureIDIsFirstRow() async throws {
        let (adapter, stub) = makeAdapter()
        stub.on(.get, "/ecosystem/ecosystems", json: "[\(infraJSON)]")
        let id = try await adapter.infrastructureID()
        XCTAssertEqual(id, "org.acme")
        XCTAssertEqual(
            stub.lastRequest(.get, "/ecosystem/ecosystems")?.path,
            "/ecosystem/ecosystems?infrastructure=true&workspace=acme"
        )
    }

    func testInfrastructureIDThrowsWhenMissing() async throws {
        let (adapter, stub) = makeAdapter()
        stub.on(.get, "/ecosystem/ecosystems", json: "[]")
        do {
            _ = try await adapter.infrastructureID()
            XCTFail("expected throw")
        } catch let error as HubError {
            XCTAssertEqual(error, .unexpected("No infrastructure ecosystem for workspace acme"))
        }
        XCTAssertEqual(
            stub.lastRequest(.get, "/ecosystem/ecosystems")?.path,
            "/ecosystem/ecosystems?infrastructure=true&workspace=acme"
        )
    }

    func testIdentifierExists() async throws {
        let (adapter, stub) = makeAdapter()
        stub.on(.get, "/registry/identifiers/org.acme.shop/exists", json: #"{"exists":true}"#)
        let exists = try await adapter.identifierExists("org.acme.shop")
        XCTAssertTrue(exists)
        XCTAssertEqual(
            stub.lastRequest(.get, "/registry/identifiers/org.acme.shop/exists")?.path,
            "/registry/identifiers/org.acme.shop/exists"
        )
    }

    func testCreatePostsBodyWithParent() async throws {
        let (adapter, stub) = makeAdapter()
        stub.on(.post, "/ecosystem/ecosystems", status: 201, json: shopJSON)
        let input = EcosystemCreate(id: "org.acme.shop", slug: "shop", name: "Shop", description: "Storefront")
        _ = try await adapter.create(input, parentID: "org.acme")
        let sent = stub.lastBody(.post, "/ecosystem/ecosystems")
        XCTAssertEqual(sent?["id"] as? String, "org.acme.shop")
        XCTAssertEqual(sent?["slug"] as? String, "shop")
        XCTAssertEqual(sent?["name"] as? String, "Shop")
        XCTAssertEqual(sent?["description"] as? String, "Storefront")
        XCTAssertEqual(sent?["region"] as? String, "")
        XCTAssertEqual(sent?["primaryDomain"] as? String, "")
        XCTAssertEqual(
            stub.lastRequest(.post, "/ecosystem/ecosystems")?.path,
            "/ecosystem/ecosystems?parent=org.acme&workspace=acme"
        )
    }

    func testCreateWithoutParentOmitsParentQuery() async throws {
        let (adapter, stub) = makeAdapter()
        stub.on(.post, "/ecosystem/ecosystems", status: 201, json: shopJSON)
        let input = EcosystemCreate(id: "org.acme.shop", slug: "shop", name: "Shop", description: "")
        _ = try await adapter.create(input, parentID: nil)
        XCTAssertEqual(stub.lastRequest(.post, "/ecosystem/ecosystems")?.path, "/ecosystem/ecosystems?workspace=acme")
    }

    func testUpdatePutsOnlyProvidedFields() async throws {
        let (adapter, stub) = makeAdapter()
        stub.on(.put, "/ecosystem/ecosystems/org.acme.shop", json: shopJSON)
        _ = try await adapter.update(id: "org.acme.shop", EcosystemUpdate(slug: "shop", name: "Web Shop"))
        let sent = stub.lastBody(.put, "/ecosystem/ecosystems/org.acme.shop")
        XCTAssertEqual(sent?["slug"] as? String, "shop")
        XCTAssertEqual(sent?["name"] as? String, "Web Shop")
        XCTAssertNil(sent?["description"] ?? nil)
        XCTAssertNil(sent?["region"] ?? nil)
        XCTAssertEqual(
            stub.lastRequest(.put, "/ecosystem/ecosystems/org.acme.shop")?.path,
            "/ecosystem/ecosystems/org.acme.shop?workspace=acme"
        )
    }

    func testDelete() async throws {
        let (adapter, stub) = makeAdapter()
        stub.on(.delete, "/ecosystem/ecosystems/org.acme.shop", status: 204, json: "")
        try await adapter.delete(id: "org.acme.shop")
        XCTAssertEqual(stub.requestCount(.delete, "/ecosystem/ecosystems/org.acme.shop"), 1)
        XCTAssertEqual(
            stub.lastRequest(.delete, "/ecosystem/ecosystems/org.acme.shop")?.path,
            "/ecosystem/ecosystems/org.acme.shop?workspace=acme"
        )
    }

    func testConflictBecomesHubErrorConflict() async throws {
        let (adapter, stub) = makeAdapter()
        stub.on(.post, "/ecosystem/ecosystems", status: 409, json: #"{"error":"duplicate identifier"}"#)
        let input = EcosystemCreate(id: "org.acme.shop", slug: "shop", name: "Shop", description: "")
        do {
            _ = try await adapter.create(input, parentID: nil)
            XCTFail("expected throw")
        } catch let error as HubError {
            XCTAssertEqual(error, .conflict("duplicate identifier"))
        }
        XCTAssertEqual(stub.lastRequest(.post, "/ecosystem/ecosystems")?.path, "/ecosystem/ecosystems?workspace=acme")
    }
}
