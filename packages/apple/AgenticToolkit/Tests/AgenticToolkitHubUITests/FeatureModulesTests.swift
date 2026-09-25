import AgenticDeveloperHubClient
import AgenticToolkitHub
import Foundation
import XCTest
import AgenticToolkitHubService
@testable import AgenticToolkitHubUI

@MainActor
final class FeatureModulesTests: XCTestCase {
    func testRegisterAllRegistersEveryDeclaredModule() {
        let stub = StubClientTransport()
        let store = InMemorySessionStore(Session(credentials: Credentials(token: "jwt", kind: .jwt), refreshToken: "r"))
        let environment = HubEnvironment(
            sessionStore: store,
            transportSource: StaticTransportSource(.direct(transport: stub)),
            initialTransport: .direct(transport: stub)
        )
        let registry = FeatureModuleRegistry()
        FeatureModules.registerAll(in: registry, environment: environment)
        for id in FeatureModules.registeredIDs {
            XCTAssertTrue(registry.isRegistered(id), "\(id) should be registered")
            let workspace = HubWorkspace(slug: "acme", name: "Acme", type: .organization)
            XCTAssertNotNil(registry.dataSource(for: id, workspace: workspace))
        }
    }

    private func makeEnvironment() -> HubEnvironment {
        let stub = StubClientTransport()
        let store = InMemorySessionStore(Session(credentials: Credentials(token: "jwt", kind: .jwt), refreshToken: "r"))
        return HubEnvironment(
            sessionStore: store,
            transportSource: StaticTransportSource(.direct(transport: stub)),
            initialTransport: .direct(transport: stub)
        )
    }

    func testRegisteredIDsCoverPlanFourFeatures() {
        XCTAssertEqual(FeatureModules.registeredIDs, ["personas", "ecosystems", "authentication"])
        let registry = FeatureModuleRegistry()
        FeatureModules.registerAll(in: registry, environment: makeEnvironment())
        XCTAssertTrue(registry.isRegistered("ecosystems"))
        XCTAssertTrue(registry.isRegistered("authentication"))
        XCTAssertFalse(registry.isRegistered("teams"), "Plan 5 features are not wired by this plan")
    }

    func testProductTopicsFollowSpecOrder() {
        let workspace = HubWorkspace(slug: "acme", name: "Acme", type: .organization)
        let topics = FeatureModules.productTopics(environment: makeEnvironment(), workspace: workspace)
        XCTAssertEqual(topics.map(\.entry.id),
                       ["settings", "child-ecosystems", "storage", "invitations", "authentication",
                        "applications", "messaging", "config"])

        func children(_ id: String) -> [String] {
            (topics.first { $0.entry.id == id } as? EcosystemTopicGroup)?.children.map(\.entry.id) ?? []
        }
        XCTAssertEqual(children("storage"), ["buckets", "access", "all-data"])
        XCTAssertEqual(children("invitations"), ["users", "requests", "pending-users", "invites"])
        XCTAssertEqual(children("authentication"), ["auth", "signin-apps", "email-signup"])
        XCTAssertEqual(children("config"), ["feature-flags", "server-bags", "tokens", "billing"])
        XCTAssertEqual(topics.first { $0.entry.id == "invitations" }?.entry.label, "Users")
        XCTAssertEqual(topics.first { $0.entry.id == "config" }?.entry.label, "Configuration")
    }
}
