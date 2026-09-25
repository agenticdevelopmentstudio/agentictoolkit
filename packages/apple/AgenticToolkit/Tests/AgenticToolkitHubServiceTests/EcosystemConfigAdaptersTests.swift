import AgenticDeveloperHubClient
import AgenticToolkitHub
import Foundation
import HTTPTypes
import XCTest
@testable import AgenticToolkitHubService

@MainActor
final class EcosystemConfigAdaptersTests: XCTestCase {
    private var stub: StubClientTransport!
    private var environment: HubEnvironment!
    private let workspace = HubWorkspace(slug: "acme", name: "Acme", type: .organization)
    private let eco = "org.acme.shop"

    override func setUp() async throws {
        try await super.setUp()
        stub = StubClientTransport()
        let store = InMemorySessionStore(
            Session(credentials: Credentials(token: "jwt", kind: .jwt), refreshToken: "r")
        )
        environment = HubEnvironment(
            sessionStore: store,
            transportSource: StaticTransportSource(.direct(transport: stub)),
            initialTransport: .direct(transport: stub)
        )
    }

    // MARK: Auth settings

    func testAuthSettingsGet() async throws {
        stub.on(
            .get, "/ecosystem/auth-settings/\(eco)",
            json: #"{"signupMode":"open","loginEnabled":false,"allowedProviders":["github"]}"#
        )
        let settings = try await AuthSettingsAdapter(environment: environment, workspace: workspace)
            .get(ecosystemID: eco)
        XCTAssertEqual(settings, AuthSettings(signupMode: .open, loginEnabled: false, allowedProviders: ["github"]))
        XCTAssertEqual(
            stub.lastRequest(.get, "/ecosystem/auth-settings/\(eco)")?.path,
            "/ecosystem/auth-settings/\(eco)?workspace=acme"
        )
    }

    func testAuthSettingsUpdateSendsCompactBody() async throws {
        stub.on(.put, "/ecosystem/auth-settings/\(eco)", json: #"{"signupMode":"closed","loginEnabled":true}"#)
        let settings = try await AuthSettingsAdapter(environment: environment, workspace: workspace)
            .update(ecosystemID: eco, AuthSettingsUpdate(signupMode: .closed, loginEnabled: nil))
        XCTAssertEqual(settings.signupMode, .closed)
        let body = stub.lastBody(.put, "/ecosystem/auth-settings/\(eco)")
        XCTAssertEqual(body?["signupMode"] as? String, "closed")
        XCTAssertNil(body?["loginEnabled"] ?? nil)
        XCTAssertEqual(
            stub.lastRequest(.put, "/ecosystem/auth-settings/\(eco)")?.path,
            "/ecosystem/auth-settings/\(eco)?workspace=acme"
        )
    }

    // MARK: Sign-in apps

    private let appJSON = #"""
    {"id":"app-1","slug":"shop.web","name":"Web","allowedReturnOrigins":["https://shop.acme.test"],
    "defaultEcosystemId":"org.acme.shop","githubEnabled":true}
    """#

    func testSigninAppsListCreateUpdateDelete() async throws {
        let adapter = SigninAppsAdapter(environment: environment, workspace: workspace)
        stub.on(.get, "/ecosystem/signin-apps/\(eco)", json: "[\(appJSON)]")
        stub.on(.post, "/ecosystem/signin-apps/\(eco)", status: 201, json: appJSON)
        stub.on(.patch, "/ecosystem/signin-apps/\(eco)/app-1", json: appJSON)
        stub.on(.delete, "/ecosystem/signin-apps/\(eco)/app-1", status: 204, json: "")

        let apps = try await adapter.list(ecosystemID: eco)
        XCTAssertEqual(apps.map(\.slug), ["shop.web"])
        XCTAssertEqual(
            stub.lastRequest(.get, "/ecosystem/signin-apps/\(eco)")?.path,
            "/ecosystem/signin-apps/\(eco)?workspace=acme"
        )

        _ = try await adapter.create(
            ecosystemID: eco,
            SigninAppCreate(slug: "web", name: "Web", allowedReturnOrigins: [], enableGithub: true)
        )
        let created = stub.lastBody(.post, "/ecosystem/signin-apps/\(eco)")
        XCTAssertEqual(created?["slug"] as? String, "web")
        XCTAssertEqual(created?["enableGithub"] as? Bool, true)
        XCTAssertEqual((created?["allowedReturnOrigins"] as? [String])?.count, 0)
        XCTAssertEqual(
            stub.lastRequest(.post, "/ecosystem/signin-apps/\(eco)")?.path,
            "/ecosystem/signin-apps/\(eco)?workspace=acme"
        )

        _ = try await adapter.update(
            ecosystemID: eco, id: "app-1",
            SigninAppUpdate(name: nil, allowedReturnOrigins: ["https://shop.acme.test"], githubEnabled: false)
        )
        let patched = stub.lastBody(.patch, "/ecosystem/signin-apps/\(eco)/app-1")
        XCTAssertNil(patched?["name"] ?? nil)
        XCTAssertEqual(patched?["githubEnabled"] as? Bool, false)
        XCTAssertEqual(patched?["allowedReturnOrigins"] as? [String], ["https://shop.acme.test"])
        XCTAssertEqual(
            stub.lastRequest(.patch, "/ecosystem/signin-apps/\(eco)/app-1")?.path,
            "/ecosystem/signin-apps/\(eco)/app-1?workspace=acme"
        )

        try await adapter.delete(ecosystemID: eco, id: "app-1")
        XCTAssertEqual(
            stub.lastRequest(.delete, "/ecosystem/signin-apps/\(eco)/app-1")?.path,
            "/ecosystem/signin-apps/\(eco)/app-1?workspace=acme"
        )
    }

    func testSigninAppConflictIsHubConflict() async throws {
        stub.on(.post, "/ecosystem/signin-apps/\(eco)", status: 409, json: #"{"detail":"duplicate"}"#)
        do {
            _ = try await SigninAppsAdapter(environment: environment, workspace: workspace)
                .create(ecosystemID: eco, SigninAppCreate(slug: "web", name: "Web"))
            XCTFail("expected conflict")
        } catch let error as HubError {
            guard case .conflict = error else { return XCTFail("expected .conflict, got \(error)") }
        }
        XCTAssertEqual(
            stub.lastRequest(.post, "/ecosystem/signin-apps/\(eco)")?.path,
            "/ecosystem/signin-apps/\(eco)?workspace=acme"
        )
    }

    // MARK: Feature flags

    private let flagJSON = #"""
    {"key":"dark_mode","enabled":true,"description":"Dark theme",
    "createdAt":"2026-09-01T00:00:00.000Z","updatedAt":"2026-09-01T00:00:00.000Z"}
    """#

    func testFeatureFlagsUnwrapAndRoundTrip() async throws {
        let adapter = FeatureFlagsAdapter(environment: environment, workspace: workspace)
        stub.on(.get, "/ecosystem/feature-flags/\(eco)", json: #"{"flags":[\#(flagJSON)]}"#)
        stub.on(.post, "/ecosystem/feature-flags/\(eco)", status: 201, json: flagJSON)
        stub.on(.put, "/ecosystem/feature-flags/\(eco)/dark_mode", json: flagJSON)
        stub.on(.delete, "/ecosystem/feature-flags/\(eco)/dark_mode", status: 204, json: "")

        let flags = try await adapter.list(ecosystemID: eco)
        XCTAssertEqual(flags, [
            FeatureFlag(
                key: "dark_mode", enabled: true, description: "Dark theme",
                createdAt: "2026-09-01T00:00:00.000Z", updatedAt: "2026-09-01T00:00:00.000Z"
            )
        ])
        XCTAssertEqual(
            stub.lastRequest(.get, "/ecosystem/feature-flags/\(eco)")?.path,
            "/ecosystem/feature-flags/\(eco)?workspace=acme"
        )

        _ = try await adapter.create(
            ecosystemID: eco, FeatureFlagCreate(key: "dark_mode", enabled: true, description: "Dark theme")
        )
        XCTAssertEqual(stub.lastBody(.post, "/ecosystem/feature-flags/\(eco)")?["key"] as? String, "dark_mode")
        XCTAssertEqual(
            stub.lastRequest(.post, "/ecosystem/feature-flags/\(eco)")?.path,
            "/ecosystem/feature-flags/\(eco)?workspace=acme"
        )

        _ = try await adapter.update(
            ecosystemID: eco, key: "dark_mode", FeatureFlagUpdate(enabled: false, description: nil)
        )
        let body = stub.lastBody(.put, "/ecosystem/feature-flags/\(eco)/dark_mode")
        XCTAssertEqual(body?["enabled"] as? Bool, false)
        XCTAssertNil(body?["description"] ?? nil)
        XCTAssertEqual(
            stub.lastRequest(.put, "/ecosystem/feature-flags/\(eco)/dark_mode")?.path,
            "/ecosystem/feature-flags/\(eco)/dark_mode?workspace=acme"
        )

        try await adapter.delete(ecosystemID: eco, key: "dark_mode")
        XCTAssertEqual(stub.requestCount(.delete, "/ecosystem/feature-flags/\(eco)/dark_mode"), 1)
        XCTAssertEqual(
            stub.lastRequest(.delete, "/ecosystem/feature-flags/\(eco)/dark_mode")?.path,
            "/ecosystem/feature-flags/\(eco)/dark_mode?workspace=acme"
        )
    }

    // MARK: Server bags

    private let bagJSON = #"""
    {"key":"limits","value":{"maxItems":20},"description":"Limits",
    "createdAt":"2026-09-01T00:00:00.000Z","updatedAt":"2026-09-01T00:00:00.000Z"}
    """#

    func testServerBagsUnwrapAndRoundTrip() async throws {
        let adapter = ServerBagsAdapter(environment: environment, workspace: workspace)
        stub.on(.get, "/ecosystem/server-bag/\(eco)", json: #"{"bags":[\#(bagJSON)]}"#)
        stub.on(.post, "/ecosystem/server-bag/\(eco)", status: 201, json: bagJSON)
        stub.on(.put, "/ecosystem/server-bag/\(eco)/limits", json: bagJSON)
        stub.on(.delete, "/ecosystem/server-bag/\(eco)/limits", status: 204, json: "")

        let bags = try await adapter.list(ecosystemID: eco)
        XCTAssertEqual(bags.map(\.key), ["limits"])
        XCTAssertEqual(bags.first?.value, .object(["maxItems": .int(20)]))
        XCTAssertEqual(
            stub.lastRequest(.get, "/ecosystem/server-bag/\(eco)")?.path,
            "/ecosystem/server-bag/\(eco)?workspace=acme"
        )

        _ = try await adapter.create(
            ecosystemID: eco,
            ServerBagCreate(key: "limits", value: .object(["maxItems": .number(20)]), description: "Limits")
        )
        let created = stub.lastBody(.post, "/ecosystem/server-bag/\(eco)")
        XCTAssertEqual((created?["value"] as? [String: Any])?["maxItems"] as? Double, 20)
        XCTAssertEqual(
            stub.lastRequest(.post, "/ecosystem/server-bag/\(eco)")?.path,
            "/ecosystem/server-bag/\(eco)?workspace=acme"
        )

        _ = try await adapter.update(
            ecosystemID: eco, key: "limits", ServerBagUpdate(value: .bool(true), description: nil)
        )
        let updated = stub.lastBody(.put, "/ecosystem/server-bag/\(eco)/limits")
        XCTAssertEqual(updated?["value"] as? Bool, true)
        XCTAssertNil(updated?["description"] ?? nil)
        XCTAssertEqual(
            stub.lastRequest(.put, "/ecosystem/server-bag/\(eco)/limits")?.path,
            "/ecosystem/server-bag/\(eco)/limits?workspace=acme"
        )

        try await adapter.delete(ecosystemID: eco, key: "limits")
        XCTAssertEqual(stub.requestCount(.delete, "/ecosystem/server-bag/\(eco)/limits"), 1)
        XCTAssertEqual(
            stub.lastRequest(.delete, "/ecosystem/server-bag/\(eco)/limits")?.path,
            "/ecosystem/server-bag/\(eco)/limits?workspace=acme"
        )
    }

    // MARK: Storage tokens

    private let tokenJSON = #"""
    {"id":"tok-1","slug":"ci-sync","description":"Sync","prefix":"adh_ab12","rdid":"token.acme.ci-sync",
    "bucketRdid":"storage.acme.ci-sync","expiresAt":null,"lastUsedAt":null,
    "createdAt":"2026-09-01T00:00:00.000Z"}
    """#

    func testStorageTokensListWithAndWithoutEcosystem() async throws {
        let adapter = StorageTokensAdapter(environment: environment, workspace: workspace)
        stub.on(.get, "/tokens", json: "[\(tokenJSON)]")
        let scoped = try await adapter.list(ecosystemID: eco)
        XCTAssertEqual(scoped.map(\.id), ["tok-1"])
        XCTAssertEqual(stub.lastRequest(.get, "/tokens")?.path, "/tokens?ecosystemId=\(eco)&workspace=acme")
        _ = try await adapter.list(ecosystemID: nil)
        XCTAssertEqual(stub.lastRequest(.get, "/tokens")?.path, "/tokens?workspace=acme")
    }

    func testStorageTokenCreateAndRevoke() async throws {
        let adapter = StorageTokensAdapter(environment: environment, workspace: workspace)
        stub.on(
            .post, "/tokens", status: 201,
            json: #"""
            {"id":"tok-2","rdid":"token.acme.nightly","slug":"nightly","description":"",
            "prefix":"adh_cd34","bucketRdid":"storage.acme.nightly","token":"adh_cd34ef56"}
            """#
        )
        stub.on(.delete, "/tokens/tok-2", status: 204, json: "")

        let created = try await adapter.create(
            ecosystemID: eco, StorageTokenCreate(name: "nightly", description: nil, expiresAt: nil, ecosystemId: nil)
        )
        XCTAssertEqual(created.token, "adh_cd34ef56")
        XCTAssertEqual(stub.lastRequest(.post, "/tokens")?.path, "/tokens?ecosystemId=\(eco)&workspace=acme")
        let body = stub.lastBody(.post, "/tokens")
        XCTAssertEqual(body?["name"] as? String, "nightly")
        XCTAssertEqual(body?["ecosystemId"] as? String, eco)
        XCTAssertNil(body?["description"] ?? nil)

        // The token id in the path identifies the row; `ecosystemId` is a list filter and has no
        // business on a DELETE — even when the caller is scoped to an ecosystem.
        try await adapter.revoke(ecosystemID: eco, id: "tok-2")
        XCTAssertEqual(stub.lastRequest(.delete, "/tokens/tok-2")?.path, "/tokens/tok-2?workspace=acme")
    }

    func testStorageTokenConflictIsHubConflict() async throws {
        stub.on(.post, "/tokens", status: 409, json: #"{"detail":"NAME_TAKEN"}"#)
        do {
            _ = try await StorageTokensAdapter(environment: environment, workspace: workspace)
                .create(
                    ecosystemID: nil,
                    StorageTokenCreate(name: "ci-sync", description: nil, expiresAt: nil, ecosystemId: nil)
                )
            XCTFail("expected conflict")
        } catch let error as HubError {
            guard case .conflict = error else { return XCTFail("expected .conflict, got \(error)") }
        }
        XCTAssertEqual(stub.lastRequest(.post, "/tokens")?.path, "/tokens?workspace=acme")
    }
}
