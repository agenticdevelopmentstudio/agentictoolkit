import AgenticToolkitHTDV
import AgenticToolkitHub
import XCTest
import AgenticToolkitHubService
@testable import AgenticToolkitHubUI

final class FeatureCatalogTests: XCTestCase {
    func testIdsAreUniqueAndInRailOrder() {
        let ids = FeatureCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(ids, [
            "personas", "ecosystems", "billing", "gamification", "authentication", "integrations",
            "organizations", "teams", "registries", "settings", "messages"
        ])
    }

    func testGroupsFollowWorkspaceType() {
        XCTAssertEqual(FeatureCatalog.groups(for: .individual), [.personas, .products, .security])
        XCTAssertEqual(FeatureCatalog.groups(for: .team), [.personas, .products, .security])
        XCTAssertEqual(FeatureCatalog.features(in: .products, for: .team).map(\.id), ["ecosystems"])
        XCTAssertEqual(
            FeatureCatalog.features(in: .products, for: .organization).map(\.id),
            ["ecosystems", "billing", "gamification"]
        )
        XCTAssertEqual(FeatureCatalog.features(in: .security, for: .team).map(\.id), ["authentication"])
    }

    func testGroupsExcludeTeamOnlyGatedGroups() {
        // Pins the rows whose gating differs from `everyone`: billing, gamification, integrations
        // are unavailable to `.team`, so `.products`/`.security` still resolve (personas/ecosystems/
        // authentication remain), but none of the team-gated members leak through.
        XCTAssertFalse(FeatureCatalog.features(in: .products, for: .team).map(\.id).contains("billing"))
        XCTAssertFalse(FeatureCatalog.features(in: .products, for: .team).map(\.id).contains("gamification"))
        XCTAssertFalse(FeatureCatalog.features(in: .security, for: .team).map(\.id).contains("integrations"))
    }

    func testRootExtrasAreGatedByWorkspaceType() {
        XCTAssertEqual(
            FeatureCatalog.rootExtras(for: .individual).map(\.id),
            ["organizations", "registries", "settings", "messages"]
        )
        XCTAssertEqual(
            FeatureCatalog.rootExtras(for: .organization).map(\.id),
            ["organizations", "teams", "registries", "settings", "messages"]
        )
        XCTAssertEqual(FeatureCatalog.rootExtras(for: .team).map(\.id), ["settings", "messages"])
    }

    func testLookupAndLinkOut() throws {
        let messages = try XCTUnwrap(FeatureCatalog.feature(id: "messages"))
        XCTAssertEqual(messages.leadsTo, .detail)
        XCTAssertEqual(messages.linkPath, "/messages")
        XCTAssertNil(FeatureCatalog.feature(id: "notebook"))
        XCTAssertTrue(try XCTUnwrap(FeatureCatalog.feature(id: "teams")).isAvailable(in: .organization))
        XCTAssertFalse(try XCTUnwrap(FeatureCatalog.feature(id: "teams")).isAvailable(in: .individual))
    }

    func testEveryNonTeamsRowIsUnavailableToTeamWorkspaces() throws {
        // Every row gated `notTeams` in the table must independently report false for `.team`,
        // not just be absent from a filtered list — this would catch a wrong `workspaceTypes`
        // set on any one of these rows even if the others happened to be correct.
        for id in ["billing", "gamification", "integrations", "organizations", "registries"] {
            let feature = try XCTUnwrap(FeatureCatalog.feature(id: id))
            XCTAssertFalse(feature.isAvailable(in: .team), "\(id) should not be available to .team")
            XCTAssertTrue(feature.isAvailable(in: .individual), "\(id) should be available to .individual")
            XCTAssertTrue(feature.isAvailable(in: .organization), "\(id) should be available to .organization")
        }
    }

    func testTeamsIsOrganizationOnly() throws {
        let teams = try XCTUnwrap(FeatureCatalog.feature(id: "teams"))
        XCTAssertFalse(teams.isAvailable(in: .individual))
        XCTAssertTrue(teams.isAvailable(in: .organization))
        XCTAssertFalse(teams.isAvailable(in: .team))
    }

    func testHubLinks() {
        let acme = HubWorkspace(slug: "acme", name: "Acme", type: .organization)
        XCTAssertEqual(HubLinks.url(path: "/messages").absoluteString, "https://agenticdeveloperhub.com/messages")
        XCTAssertEqual(
            HubLinks.workspaceURL(acme, path: "/messages").absoluteString,
            "https://agenticdeveloperhub.com/acme/messages"
        )
        XCTAssertEqual(
            HubLinks.workspaceURL(acme, path: "settings").absoluteString,
            "https://agenticdeveloperhub.com/acme/settings"
        )
    }
}
