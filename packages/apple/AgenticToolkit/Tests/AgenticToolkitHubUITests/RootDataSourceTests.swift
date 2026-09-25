import AgenticToolkitHTDV
import AgenticToolkitHub
import XCTest
import AgenticToolkitHubService
@testable import AgenticToolkitHubUI

@MainActor
final class RootDataSourceTests: XCTestCase {
    private let acme = HubWorkspace(slug: "acme", name: "Acme Inc", type: .organization)
    private let ada = HubWorkspace(slug: "ada", name: "Ada", type: .individual)

    /// A stand-in feature module: root level lists two personas; selecting one yields a facet level.
    private final class FakeModule: HTDVDataSource, @unchecked Sendable {
        var receivedPaths: [[String]] = []
        func rootLevel() async throws -> HTDVLevel {
            HTDVLevel(id: "personas", title: "Personas", items: [
                HTDVItem(id: "p1", label: "Atlas"), HTDVItem(id: "p2", label: "Nova")
            ])
        }
        func child(for path: [HTDVItem]) async throws -> HTDVChild {
            receivedPaths.append(path.map(\.id))
            return .level(HTDVLevel(
                id: "facets:\(path.last?.id ?? "")",
                title: "Facets",
                items: [HTDVItem(id: "identity", label: "Identity", leadsTo: .detail)]
            ))
        }
    }

    private func makeRoot(
        workspace: HubWorkspace,
        registry: FeatureModuleRegistry = FeatureModuleRegistry()
    ) -> RootDataSource {
        RootDataSource(workspace: workspace, registry: registry)
    }

    func testRootLevelListsGroupsThenExtras() async throws {
        let level = try await makeRoot(workspace: acme).rootLevel()
        XCTAssertEqual(level.id, "root")
        XCTAssertEqual(level.title, "Acme Inc (acme)")
        XCTAssertEqual(level.items.map(\.id), [
            "group:personas", "group:products", "group:security",
            "feature:organizations", "feature:teams", "feature:registries", "feature:settings", "feature:messages"
        ])
        XCTAssertEqual(level.items[2].dividerAfter, true)     // divider between groups and extras
        XCTAssertEqual(level.items[3].dividerAfter, false)
        XCTAssertEqual(level.items.first?.leadsTo, .list)
        XCTAssertEqual(level.items.last?.leadsTo, .detail)
        XCTAssertEqual(level.items.first?.systemImage, "person.2")
    }

    func testIndividualWorkspaceHidesTeams() async throws {
        let level = try await makeRoot(workspace: ada).rootLevel()
        XCTAssertFalse(level.items.contains { $0.id == "feature:teams" })
    }

    func testGroupChildIsTheFeatureLevel() async throws {
        let root = makeRoot(workspace: acme)
        let rootLevel = try await root.rootLevel()
        let group = try XCTUnwrap(rootLevel.items.first { $0.id == "group:products" })
        guard case .level(let level) = try await root.child(for: [group]) else {
            return XCTFail("expected level")
        }
        XCTAssertEqual(level.id, "features:products")
        XCTAssertEqual(level.title, "Products")
        XCTAssertEqual(level.items.map(\.id), ["feature:ecosystems", "feature:billing", "feature:gamification"])
        XCTAssertEqual(level.items.map(\.label), ["Products", "Billing", "Gamification"])
    }

    func testUnregisteredListFeatureShowsTheUnavailableLevel() async throws {
        let root = makeRoot(workspace: acme)
        let group = HTDVItem(id: "group:personas", label: "Personas")
        let feature = HTDVItem(id: "feature:personas", label: "Personas")
        guard case .level(let level) = try await root.child(for: [group, feature]) else {
            return XCTFail("expected level")
        }
        XCTAssertEqual(level.id, "unavailable:personas")
        XCTAssertEqual(level.items, [])
        XCTAssertEqual(level.emptyMessage, "Not available in this version")
    }

    func testRegisteredFeatureDelegatesWithTheModuleRelativePath() async throws {
        let registry = FeatureModuleRegistry()
        let module = FakeModule()
        registry.register(id: "personas") { _ in module }
        let root = makeRoot(workspace: acme, registry: registry)
        let group = HTDVItem(id: "group:personas", label: "Personas")
        let feature = HTDVItem(id: "feature:personas", label: "Personas")

        guard case .level(let personas) = try await root.child(for: [group, feature]) else {
            return XCTFail("expected level")
        }
        XCTAssertEqual(personas.items.map(\.id), ["p1", "p2"])

        guard case .level(let facets) = try await root.child(for: [group, feature, personas.items[1]]) else {
            return XCTFail("expected level")
        }
        XCTAssertEqual(facets.id, "facets:p2")
        XCTAssertEqual(module.receivedPaths, [["p2"]])
    }

    func testRootExtraFeatureDelegatesWithoutAGroup() async throws {
        let registry = FeatureModuleRegistry()
        let module = FakeModule()
        registry.register(id: "organizations") { _ in module }
        let root = makeRoot(workspace: acme, registry: registry)
        let feature = HTDVItem(id: "feature:organizations", label: "Organizations")
        guard case .level(let level) = try await root.child(for: [feature]) else {
            return XCTFail("expected level")
        }
        XCTAssertEqual(level.items.count, 2)
        _ = try await root.child(for: [feature, level.items[0]])
        XCTAssertEqual(module.receivedPaths, [["p1"]])
    }

    func testLinkOutAndPlaceholderDetails() async throws {
        let root = makeRoot(workspace: acme)
        let messagesItem = HTDVItem(id: "feature:messages", label: "Messages", leadsTo: .detail)
        guard case .detail(let messages) = try await root.child(for: [messagesItem]) else {
            return XCTFail("expected detail")
        }
        XCTAssertEqual(messages.id, "feature:messages")
        XCTAssertEqual(messages.title, "Messages")
        XCTAssertTrue(messages.make() is LinkOutViewController)

        let settingsItem = HTDVItem(id: "feature:settings", label: "Settings", leadsTo: .detail)
        guard case .detail(let settings) = try await root.child(for: [settingsItem]) else {
            return XCTFail("expected detail")
        }
        XCTAssertEqual(settings.id, "feature:settings")
        XCTAssertFalse(settings.make() is LinkOutViewController)
    }

    func testUnknownPathsAreEmpty() async throws {
        let root = makeRoot(workspace: acme)
        guard case .empty = try await root.child(for: []) else { return XCTFail("expected empty") }
        guard case .empty = try await root.child(for: [HTDVItem(id: "feature:nope", label: "?")]) else {
            return XCTFail("expected empty")
        }
        guard case .empty = try await root.child(for: [HTDVItem(id: "group:nope", label: "?")]) else {
            return XCTFail("expected empty")
        }
    }

    func testRegistryCachesPerWorkspaceAndResets() {
        let registry = FeatureModuleRegistry()
        var made = 0
        registry.register(id: "personas") { _ in made += 1; return FakeModule() }
        XCTAssertTrue(registry.isRegistered("personas"))
        XCTAssertFalse(registry.isRegistered("teams"))
        let first = registry.dataSource(for: "personas", workspace: acme)
        let again = registry.dataSource(for: "personas", workspace: acme)
        XCTAssertTrue(first === again)
        _ = registry.dataSource(for: "personas", workspace: ada)
        XCTAssertEqual(made, 2)
        registry.reset()
        _ = registry.dataSource(for: "personas", workspace: acme)
        XCTAssertEqual(made, 3)
        XCTAssertNil(registry.dataSource(for: "teams", workspace: acme))
    }

    func testRegistryReturnsDistinctInstancesForDifferentWorkspaces() {
        // Pins the "different instance for a different slug" half of the cache contract
        // (identity, not equality — HTDVDataSource is not Equatable).
        let registry = FeatureModuleRegistry()
        registry.register(id: "personas") { _ in FakeModule() }
        let acmeInstance = registry.dataSource(for: "personas", workspace: acme)
        let adaInstance = registry.dataSource(for: "personas", workspace: ada)
        XCTAssertNotNil(acmeInstance)
        XCTAssertNotNil(adaInstance)
        XCTAssertFalse((acmeInstance as AnyObject) === (adaInstance as AnyObject))
    }
}
