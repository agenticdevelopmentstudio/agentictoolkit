import AgenticDeveloperHubClient
import AgenticToolkitHub
import Foundation
import HTTPTypes
import XCTest
@testable import AgenticToolkitHubService

@MainActor
final class ApplicationsAdapterTests: XCTestCase {
    private var stub: StubClientTransport!
    private var adapter: ApplicationsAdapter!

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
        adapter = ApplicationsAdapter(
            environment: environment,
            workspace: HubWorkspace(slug: "acme", name: "Acme", type: .organization)
        )
    }

    private let webJSON = #"""
    {"id":"app.acme.shop.web","ecosystemId":"org.acme.shop","slug":"web","displayName":"Web Storefront",
     "consumerKind":"customer",
     "createdAt":"2026-09-01T00:00:00.000Z","updatedAt":"2026-09-01T00:00:00.000Z"}
    """#
    private let otherJSON = #"""
    {"id":"app.acme.blog.cms","ecosystemId":"org.acme.blog","slug":"cms","displayName":"CMS","consumerKind":"staff",
     "createdAt":"2026-09-01T00:00:00.000Z","updatedAt":"2026-09-01T00:00:00.000Z"}
    """#
    /// The contract's shape: `crud`, not `permissions`, and `tables` an ARRAY of `{tableId, crud}`.
    /// The previous `{permissions, tables: {name: {...}}}` spelling decoded to nothing on the wire.
    private let grantsJSON = #"""
    {"grants":[{"schemaId":"b-profile","crud":"R,U","tables":[{"tableId":"t-contacts","crud":"R"}]}]}
    """#

    func testListFiltersByEcosystem() async throws {
        stub.on(.get, "/ecosystem/applications", json: "[\(webJSON),\(otherJSON)]")
        let rows = try await adapter.list(ecosystemID: "org.acme.shop")
        XCTAssertEqual(rows.map(\.id), ["app.acme.shop.web"])
        XCTAssertEqual(rows.first?.consumerKind, .customer)
        XCTAssertEqual(
            stub.lastRequest(.get, "/ecosystem/applications")?.path,
            "/ecosystem/applications?workspace=acme"
        )
    }

    func testGet() async throws {
        stub.on(.get, "/ecosystem/applications/app.acme.shop.web", json: webJSON)
        let app = try await adapter.get(id: "app.acme.shop.web")
        XCTAssertEqual(app.displayName, "Web Storefront")
        XCTAssertEqual(
            stub.lastRequest(.get, "/ecosystem/applications/app.acme.shop.web")?.path,
            "/ecosystem/applications/app.acme.shop.web?workspace=acme"
        )
    }

    func testCreatePostsBody() async throws {
        stub.on(.post, "/ecosystem/applications", status: 201, json: webJSON)
        _ = try await adapter.create(
            ApplicationCreate(
                ecosystemId: "org.acme.shop", slug: "web", displayName: "Web Storefront", consumerKind: .customer
            )
        )
        XCTAssertEqual(
            stub.lastRequest(.post, "/ecosystem/applications")?.path, "/ecosystem/applications?workspace=acme"
        )
        let sent = stub.lastBody(.post, "/ecosystem/applications")
        XCTAssertEqual(sent?["ecosystemId"] as? String, "org.acme.shop")
        XCTAssertEqual(sent?["slug"] as? String, "web")
        XCTAssertEqual(sent?["displayName"] as? String, "Web Storefront")
        XCTAssertEqual(sent?["consumerKind"] as? String, "customer")
    }

    func testUpdatePutsOnlyProvidedFields() async throws {
        stub.on(.put, "/ecosystem/applications/app.acme.shop.web", json: webJSON)
        _ = try await adapter.update(id: "app.acme.shop.web", ApplicationUpdate(displayName: "Storefront"))
        XCTAssertEqual(
            stub.lastRequest(.put, "/ecosystem/applications/app.acme.shop.web")?.path,
            "/ecosystem/applications/app.acme.shop.web?workspace=acme"
        )
        let sent = stub.lastBody(.put, "/ecosystem/applications/app.acme.shop.web")
        XCTAssertEqual(sent?["displayName"] as? String, "Storefront")
        XCTAssertNil(sent?["slug"] ?? nil)
        XCTAssertNil(sent?["consumerKind"] ?? nil)
    }

    func testDelete() async throws {
        stub.on(.delete, "/ecosystem/applications/app.acme.shop.web", status: 204, json: "")
        try await adapter.delete(id: "app.acme.shop.web")
        XCTAssertEqual(
            stub.lastRequest(.delete, "/ecosystem/applications/app.acme.shop.web")?.path,
            "/ecosystem/applications/app.acme.shop.web?workspace=acme"
        )
    }

    func testRenameIdentifierPatchesRegistry() async throws {
        stub.on(.patch, "/registry/identifiers/app.acme.shop.web", json: #"{"rdid":"app.acme.shop.store"}"#)
        try await adapter.renameIdentifier("app.acme.shop.web", to: "app.acme.shop.store")
        XCTAssertEqual(
            stub.lastBody(.patch, "/registry/identifiers/app.acme.shop.web")?["rdid"] as? String,
            "app.acme.shop.store"
        )
        XCTAssertEqual(
            stub.lastRequest(.patch, "/registry/identifiers/app.acme.shop.web")?.path,
            "/registry/identifiers/app.acme.shop.web"
        )
    }

    func testRenameConflictBecomesHubErrorConflict() async throws {
        stub.on(.patch, "/registry/identifiers/app.acme.shop.web", status: 409, json: #"{"error":"identifier taken"}"#)
        do {
            try await adapter.renameIdentifier("app.acme.shop.web", to: "app.acme.shop.store")
            XCTFail("expected throw")
        } catch let error as HubError {
            XCTAssertEqual(error, .conflict("identifier taken"))
        }
        // The registry is workspace-agnostic: the identifier is globally unique, so no query at all.
        XCTAssertEqual(
            stub.lastRequest(.patch, "/registry/identifiers/app.acme.shop.web")?.path,
            "/registry/identifiers/app.acme.shop.web"
        )
    }

    func testSchemaGrantsUnwrapsEnvelope() async throws {
        stub.on(.get, "/ecosystem/applications/app.acme.shop.web/schema-grants", json: grantsJSON)
        let grants = try await adapter.schemaGrants(applicationID: "app.acme.shop.web")
        XCTAssertEqual(grants.count, 1)
        XCTAssertEqual(grants.first?.schemaId, "b-profile")
        XCTAssertEqual(grants.first?.permissions, "R,U")
        // Keyed by the table's ID, which is what every lookup in `ApplicationsTopic` has.
        XCTAssertEqual(grants.first?.tables["t-contacts"]?.permissions, "R")
        XCTAssertEqual(grants.first?.tables["t-contacts"]?.level, "table")
        XCTAssertEqual(
            stub.lastRequest(.get, "/ecosystem/applications/app.acme.shop.web/schema-grants")?.path,
            "/ecosystem/applications/app.acme.shop.web/schema-grants?workspace=acme"
        )
    }

    func testSetSchemaGrantsPutsEnvelope() async throws {
        stub.on(.put, "/ecosystem/applications/app.acme.shop.web/schema-grants", json: grantsJSON)
        let grant = SchemaGrant(
            schemaId: "b-profile", permissions: "R",
            tables: [
                "t-contacts": TableGrant(level: "table", permissions: "R"),
                "t-empty": TableGrant(level: "table", permissions: "")
            ]
        )
        try await adapter.setSchemaGrants(applicationID: "app.acme.shop.web", [grant])
        XCTAssertEqual(
            stub.lastRequest(.put, "/ecosystem/applications/app.acme.shop.web/schema-grants")?.path,
            "/ecosystem/applications/app.acme.shop.web/schema-grants?workspace=acme"
        )
        let sent = stub.lastBody(.put, "/ecosystem/applications/app.acme.shop.web/schema-grants")
        let grants = sent?["grants"] as? [[String: Any]]
        XCTAssertEqual(grants?.count, 1)
        XCTAssertEqual(grants?.first?["schemaId"] as? String, "b-profile")
        XCTAssertEqual(grants?.first?["crud"] as? String, "R")
        XCTAssertNil(grants?.first?["permissions"] ?? nil)
        // An array of `{tableId, crud}`; `level` is UI-only, and a table with no permissions
        // carries no row at all — exactly what the web client sends.
        let tables = grants?.first?["tables"] as? [[String: Any]]
        XCTAssertEqual(tables?.count, 1)
        XCTAssertEqual(tables?.first?["tableId"] as? String, "t-contacts")
        XCTAssertEqual(tables?.first?["crud"] as? String, "R")
        XCTAssertNil(tables?.first?["level"] ?? nil)
    }

    func testTokensListAndCreateAndRevoke() async throws {
        stub.on(
            .get, "/ecosystem/applications/app.acme.shop.web/tokens",
            json: #"[{"id":"tok-1","name":"CI","prefix":"apk_ab12","createdAt":"2026-09-01T00:00:00.000Z"}]"#
        )
        stub.on(
            .post, "/ecosystem/applications/app.acme.shop.web/tokens", status: 201,
            json: #"""
            {"id":"tok-2","name":"Deploy","prefix":"apk_cd34","token":"apk_cd34ef56gh78",
             "createdAt":"2026-09-02T00:00:00.000Z"}
            """#
        )
        stub.on(.delete, "/ecosystem/applications/app.acme.shop.web/tokens/tok-1", status: 204, json: "")

        let tokens = try await adapter.tokens(applicationID: "app.acme.shop.web")
        XCTAssertEqual(tokens.map(\.name), ["CI"])
        XCTAssertEqual(
            stub.lastRequest(.get, "/ecosystem/applications/app.acme.shop.web/tokens")?.path,
            "/ecosystem/applications/app.acme.shop.web/tokens?workspace=acme"
        )

        let created = try await adapter.createToken(applicationID: "app.acme.shop.web", name: "Deploy")
        XCTAssertEqual(created.token, "apk_cd34ef56gh78")
        XCTAssertEqual(
            stub.lastBody(.post, "/ecosystem/applications/app.acme.shop.web/tokens")?["name"] as? String,
            "Deploy"
        )
        XCTAssertEqual(
            stub.lastRequest(.post, "/ecosystem/applications/app.acme.shop.web/tokens")?.path,
            "/ecosystem/applications/app.acme.shop.web/tokens?workspace=acme"
        )

        try await adapter.revokeToken(applicationID: "app.acme.shop.web", tokenID: "tok-1")
        XCTAssertEqual(stub.requestCount(.delete, "/ecosystem/applications/app.acme.shop.web/tokens/tok-1"), 1)
        XCTAssertEqual(
            stub.lastRequest(.delete, "/ecosystem/applications/app.acme.shop.web/tokens/tok-1")?.path,
            "/ecosystem/applications/app.acme.shop.web/tokens/tok-1?workspace=acme"
        )
    }
}
