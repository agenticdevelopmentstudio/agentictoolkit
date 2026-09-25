import AgenticToolkitHub
import XCTest
@testable import AgenticToolkitHubService

final class WorkspaceResolverTests: XCTestCase {
    private let ada = HubWorkspace(slug: "ada", name: "Ada", type: .individual)
    private let acme = HubWorkspace(slug: "acme", name: "Acme Inc", type: .organization)
    private let core = HubWorkspace(slug: "acme-core", name: "Core", type: .team)
    private var all: [HubWorkspace] { [ada, acme, core] }

    func testExplicitSlugWins() {
        XCTAssertEqual(
            WorkspaceResolver.resolve(workspaces: all, requestedSlug: "acme", serverPrefSlug: "ada"),
            .workspace(acme)
        )
    }

    func testUnknownExplicitSlugIsNotFound() {
        XCTAssertEqual(
            WorkspaceResolver.resolve(workspaces: all, requestedSlug: "ghost", serverPrefSlug: "ada"),
            .notFound("ghost")
        )
    }

    func testServerPreferenceWhenKnown() {
        XCTAssertEqual(
            WorkspaceResolver.resolve(workspaces: all, requestedSlug: nil, serverPrefSlug: "acme-core"),
            .workspace(core)
        )
    }

    func testUnknownPreferenceFallsBackToFirst() {
        XCTAssertEqual(
            WorkspaceResolver.resolve(workspaces: all, requestedSlug: "", serverPrefSlug: "gone"),
            .workspace(ada)
        )
    }

    func testNoWorkspacesIsNone() {
        XCTAssertEqual(WorkspaceResolver.resolve(workspaces: [], requestedSlug: nil, serverPrefSlug: nil), .none)
    }

    func testOnlyNonTeamPicksPersist() {
        XCTAssertTrue(WorkspaceResolver.shouldPersist(ada))
        XCTAssertTrue(WorkspaceResolver.shouldPersist(acme))
        XCTAssertFalse(WorkspaceResolver.shouldPersist(core))
    }
}
