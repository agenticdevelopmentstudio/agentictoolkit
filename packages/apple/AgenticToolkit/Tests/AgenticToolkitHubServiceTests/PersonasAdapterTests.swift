import AgenticDeveloperHubClient
import AgenticToolkitHub
import Foundation
import HTTPTypes
import XCTest
@testable import AgenticToolkitHubService

@MainActor
final class PersonasAdapterTests: XCTestCase {
    private func makeAdapter() -> (PersonasAdapter, StubClientTransport) {
        let stub = StubClientTransport()
        let store = InMemorySessionStore(Session(credentials: Credentials(token: "jwt", kind: .jwt), refreshToken: "r"))
        let environment = HubEnvironment(
            sessionStore: store,
            transportSource: StaticTransportSource(.direct(transport: stub)),
            initialTransport: .direct(transport: stub)
        )
        let adapter = PersonasAdapter(
            environment: environment,
            workspace: HubWorkspace(slug: "acme", name: "Acme", type: .organization)
        )
        return (adapter, stub)
    }

    private static let personaJSON = #"""
    {"id":"persona.acme.ada","userId":"u1","ownerKind":"organization","ownerId":"o1","slug":"ada","name":"Ada",
     "description":null,"visibility":"private","model":null,"serviceId":null,"appId":null,
     "avatarAttachmentId":null,"modelPrompt":"You are Ada.","voice":null,"character":null,"examples":null,
     "createdAt":"2026-09-01T00:00:00.000Z","updatedAt":"2026-09-01T00:00:00.000Z"}
    """#

    func testListSendsWorkspaceQuery() async throws {
        let (adapter, stub) = makeAdapter()
        stub.on(.get, "/persona/personas", json: "[\(Self.personaJSON)]")
        let rows = try await adapter.list()
        XCTAssertEqual(rows.map(\.id), ["persona.acme.ada"])
        XCTAssertEqual(stub.lastRequest(.get, "/persona/personas")?.path, "/persona/personas?workspace=acme")
        XCTAssertEqual(stub.lastRequest(.get, "/persona/personas")?.headerFields[.authorization], "Bearer jwt")
    }

    func testGet() async throws {
        let (adapter, stub) = makeAdapter()
        stub.on(.get, "/persona/personas/persona.acme.ada", json: Self.personaJSON)
        let persona = try await adapter.get(id: "persona.acme.ada")
        XCTAssertEqual(persona.name, "Ada")
        XCTAssertEqual(
            stub.lastRequest(.get, "/persona/personas/persona.acme.ada")?.path,
            "/persona/personas/persona.acme.ada?workspace=acme"
        )
    }

    func testCreatePostsBody() async throws {
        let (adapter, stub) = makeAdapter()
        stub.on(.post, "/persona/personas", status: 201, json: Self.personaJSON)
        let body = PersonaBody(
            slug: "ada", name: "Ada", description: nil, modelPrompt: "You are Ada.", model: "", visibility: "private"
        )
        _ = try await adapter.create(body)
        let sent = stub.lastBody(.post, "/persona/personas")
        XCTAssertEqual(sent?["slug"] as? String, "ada")
        XCTAssertEqual(sent?["name"] as? String, "Ada")
        XCTAssertEqual(sent?["model"] as? String, "")
        XCTAssertEqual(sent?["visibility"] as? String, "private")
        XCTAssertNil(sent?["description"] ?? nil, "nil optionals are omitted, not sent as null")
        XCTAssertEqual(stub.lastRequest(.post, "/persona/personas")?.path, "/persona/personas?workspace=acme")
    }

    func testUpdatePuts() async throws {
        let (adapter, stub) = makeAdapter()
        stub.on(.put, "/persona/personas/persona.acme.ada", json: Self.personaJSON)
        var body = PersonaBody(slug: "ada", name: "Ada L", modelPrompt: "p", visibility: "hub")
        body.cannedChat = .object(["mode": .string("script")])
        _ = try await adapter.update(id: "persona.acme.ada", body)
        XCTAssertEqual(
            stub.lastRequest(.put, "/persona/personas/persona.acme.ada")?.path,
            "/persona/personas/persona.acme.ada?workspace=acme"
        )
        let sent = stub.lastBody(.put, "/persona/personas/persona.acme.ada")
        XCTAssertEqual(sent?["name"] as? String, "Ada L")
        XCTAssertEqual((sent?["cannedChat"] as? [String: Any])?["mode"] as? String, "script")
    }

    func testDelete() async throws {
        let (adapter, stub) = makeAdapter()
        stub.on(.delete, "/persona/personas/persona.acme.ada", status: 204, json: "")
        try await adapter.delete(id: "persona.acme.ada")
        XCTAssertEqual(
            stub.lastRequest(.delete, "/persona/personas/persona.acme.ada")?.path,
            "/persona/personas/persona.acme.ada?workspace=acme"
        )
    }

    func testListServices() async throws {
        let (adapter, stub) = makeAdapter()
        stub.on(.get, "/persona/services", json: #"""
        [{"id":"svc1","templateId":null,"providerKind":"openai","name":"OpenAI",
          "baseUrl":"https://api.openai.com","hasApiKey":true,
          "connectStatus":"connected","connectError":null,"lastConnectedAt":null,"documentationUrl":null,
          "statusUrl":null,
          "models":[{"id":"gpt-x","displayName":"GPT X","contextWindow":128000}],"modelsFetchedAt":null}]
        """#)
        let services = try await adapter.listServices()
        XCTAssertEqual(services.map(\.name), ["OpenAI"])
        XCTAssertEqual(services[0].models.map(\.id), ["gpt-x"])
        XCTAssertNil(stub.lastRequest(.get, "/persona/services")?.path?.split(separator: "?").dropFirst().first)
    }

    func testUnauthorizedMapsToHubError() async {
        let (adapter, stub) = makeAdapter()
        stub.on(.get, "/persona/personas", status: 401, json: "{}")
        stub.on(.post, "/auth/refresh", status: 503, json: "")
        do {
            _ = try await adapter.list()
            XCTFail("expected unauthorized error")
        } catch {
            XCTAssertEqual(error as? HubError, .unauthorized)
        }
        XCTAssertEqual(stub.lastRequest(.get, "/persona/personas")?.path, "/persona/personas?workspace=acme")
    }
}
