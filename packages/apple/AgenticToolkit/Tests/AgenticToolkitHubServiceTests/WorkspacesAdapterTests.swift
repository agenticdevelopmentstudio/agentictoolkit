import AgenticDeveloperHubClient
import AgenticToolkitHub
import Foundation
import XCTest
@testable import AgenticToolkitHubService

@MainActor
final class WorkspacesAdapterTests: XCTestCase {
    private static let workspacesJSON = #"""
    [{"slug":"ada","name":"Ada","type":"individual"},
     {"slug":"acme","name":"Acme Inc","type":"organization"},
     {"slug":"acme-core","name":"Core","type":"team"}]
    """#

    private func makeAdapter() -> (WorkspacesAdapter, StubClientTransport) {
        let stub = StubClientTransport()
        let store = InMemorySessionStore(Session(credentials: Credentials(token: "jwt", kind: .jwt), refreshToken: "r"))
        let environment = HubEnvironment(
            sessionStore: store,
            transportSource: StaticTransportSource(.direct(transport: stub)),
            initialTransport: .direct(transport: stub)
        )
        return (WorkspacesAdapter(environment: environment), stub)
    }

    func testListMapsTypes() async throws {
        let (adapter, stub) = makeAdapter()
        stub.on(.get, "/workspaces", json: Self.workspacesJSON)
        let list = try await adapter.listWorkspaces()
        XCTAssertEqual(list, [
            HubWorkspace(slug: "ada", name: "Ada", type: .individual),
            HubWorkspace(slug: "acme", name: "Acme Inc", type: .organization),
            HubWorkspace(slug: "acme-core", name: "Core", type: .team)
        ])
    }

    func testListUnauthorizedIsHubError() async {
        let (adapter, stub) = makeAdapter()
        stub.on(.get, "/workspaces", status: 401, json: #"{"error":{"message":"expired"}}"#)
        stub.on(.post, "/auth/refresh", status: 503, json: "")
        do {
            _ = try await adapter.listWorkspaces()
            XCTFail("expected unauthorized")
        } catch {
            XCTAssertEqual(error as? HubError, .unauthorized)
        }
    }

    func testPreferredSlugReadsPrefsEnvelope() async throws {
        let (adapter, stub) = makeAdapter()
        stub.on(.get, "/me/workspace-prefs", json: #"{"prefs":{"slug":"acme"}}"#)
        let slug = try await adapter.preferredSlug()
        XCTAssertEqual(slug, "acme")
        stub.on(.get, "/me/workspace-prefs", json: #"{"prefs":{}}"#)
        let none = try await adapter.preferredSlug()
        XCTAssertNil(none)
    }

    func testSetPreferredSlugPutsTheSlug() async throws {
        let (adapter, stub) = makeAdapter()
        stub.on(.put, "/me/workspace-prefs", json: #"{"prefs":{"slug":"acme"}}"#)
        try await adapter.setPreferredSlug("acme")
        XCTAssertEqual(stub.lastBody(.put, "/me/workspace-prefs")?["slug"] as? String, "acme")
        XCTAssertEqual(stub.lastRequest(.put, "/me/workspace-prefs")?.headerFields[.authorization], "Bearer jwt")
    }
}
