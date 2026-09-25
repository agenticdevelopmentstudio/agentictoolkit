import AgenticToolkitCoreMacOS
import AgenticToolkitHTDV
import AgenticToolkitHub
import Foundation
import XCTest
import AgenticToolkitHubService
@testable import AgenticToolkitHubUI

/// The vocabulary a script types and the snapshot it reads back.
///
/// These are the parts of the scripting surface that hold no AppKit state, so
/// they can be exercised without a window: the parsers that turn a script's
/// word into an intent, the JSON shape `ui state` answers with, and the one
/// decision — quiet presentation — that changes what a screenshot means.
final class HubScriptingStateTests: XCTestCase {

    // MARK: Field

    func testFieldParsesEveryCaseAndFoldsCase() {
        XCTAssertEqual(HubScripting.Field.parse("email"), .email)
        XCTAssertEqual(HubScripting.Field.parse("Password"), .password)
        XCTAssertEqual(HubScripting.Field.parse("  CODE  "), .code)
        XCTAssertEqual(HubScripting.Field.allCases.count, 3)
        for field in HubScripting.Field.allCases {
            XCTAssertEqual(HubScripting.Field.parse(field.rawValue), field)
        }
    }

    func testFieldRejectsUnknownNames() {
        XCTAssertNil(HubScripting.Field.parse("username"))
        XCTAssertNil(HubScripting.Field.parse(""))
    }

    // MARK: Action

    func testActionParsesEverySpelling() {
        XCTAssertEqual(HubScripting.Action.parse("sign-in"), .signIn)
        XCTAssertEqual(HubScripting.Action.parse("signin"), .signIn)
        XCTAssertEqual(HubScripting.Action.parse("Passkey"), .passkey)
        XCTAssertEqual(HubScripting.Action.parse("send-code"), .sendCode)
        XCTAssertEqual(HubScripting.Action.parse("sendcode"), .sendCode)
        XCTAssertEqual(HubScripting.Action.parse("verify"), .verify)
        XCTAssertEqual(HubScripting.Action.parse(" BACK "), .back)
    }

    func testActionParsesSocialProviders() {
        XCTAssertEqual(HubScripting.Action.parse("social:google"), .social(.google))
        XCTAssertEqual(HubScripting.Action.parse("SOCIAL:GitHub"), .social(.github))
        XCTAssertNil(HubScripting.Action.parse("social:myspace"))
        XCTAssertNil(HubScripting.Action.parse("social:"))
        XCTAssertNil(HubScripting.Action.parse("social"))
    }

    func testActionRejectsUnknownWords() {
        XCTAssertNil(HubScripting.Action.parse("submit"))
        XCTAssertNil(HubScripting.Action.parse(""))
    }

    // MARK: Account menu

    func testAccountMenuItemParsesRawValuesAndTheHyphenatedSpelling() {
        for item in AccountMenuModel.Item.allCases {
            XCTAssertEqual(AccountMenuModel.Item.parse(item.rawValue), item)
        }
        XCTAssertEqual(AccountMenuModel.Item.parse("log-out"), .logOut)
        XCTAssertEqual(AccountMenuModel.Item.parse("logout"), .logOut)
        XCTAssertEqual(AccountMenuModel.Item.parse("  LOGOUT "), .logOut)
        XCTAssertEqual(AccountMenuModel.Item.parse("Home"), .home)
    }

    func testAccountMenuItemRejectsUnknownWords() {
        XCTAssertNil(AccountMenuModel.Item.parse("sign-out"))
        XCTAssertNil(AccountMenuModel.Item.parse(""))
    }

    // MARK: Workspace lookup

    private let workspaces = [
        HubWorkspace(slug: "ada", name: "Ada", type: .individual),
        HubWorkspace(slug: "acme", name: "Acme Inc", type: .organization)
    ]

    func testWorkspaceSlugMatchesSlugAndPopupLabel() {
        XCTAssertEqual(HubScripting.workspaceSlug(matching: "acme", in: workspaces), "acme")
        XCTAssertEqual(HubScripting.workspaceSlug(matching: "Acme Inc (acme)", in: workspaces), "acme")
        XCTAssertEqual(HubScripting.workspaceSlug(matching: "  ada  ", in: workspaces), "ada")
        XCTAssertEqual(HubScripting.workspaceSlug(matching: "ACME INC (ACME)", in: workspaces), "acme")
    }

    func testWorkspaceSlugRejectsUnknownNames() {
        XCTAssertNil(HubScripting.workspaceSlug(matching: "Acme", in: []))
        XCTAssertNil(HubScripting.workspaceSlug(matching: "widgets", in: workspaces))
    }

    // MARK: HubUIState JSON

    func testLaunchingSnapshotEncodesTheFieldsAScriptPollsFor() throws {
        let state = HubUIState(
            pid: 4242,
            bundlePath: "/Applications/Agentic Developer Hub.app",
            phase: "launching",
            window: HubUIState.WindowInfo(
                title: "Agentic Developer Hub",
                isVisible: true,
                isKey: false,
                frame: ["x": 0, "y": 0, "width": 960, "height": 640]
            )
        )
        let object = try Self.decode(state.jsonString())
        XCTAssertEqual(object["pid"] as? Int, 4242)
        XCTAssertEqual(object["phase"] as? String, "launching")
        XCTAssertEqual(object["permissionWalkthroughComplete"] as? Bool, false)
        XCTAssertEqual(object["quietPresentation"] as? Bool, false)
        XCTAssertEqual((object["workspaces"] as? [Any])?.count, 0)
        XCTAssertNil(object["signIn"])
        XCTAssertNil(object["htdv"])
        let window = try XCTUnwrap(object["window"] as? [String: Any])
        XCTAssertEqual(window["isVisible"] as? Bool, true)
        XCTAssertEqual((window["frame"] as? [String: Any])?["width"] as? Double, 960)
    }

    func testReadySnapshotCarriesWorkspacesAccountMenuAndStatusStrip() throws {
        let state = HubUIState(
            pid: 1,
            bundlePath: "/tmp/Hub.app",
            phase: "ready",
            workspaces: [HubUIState.WorkspaceItem(slug: "acme", label: "Acme Inc (acme)")],
            selectedWorkspaceSlug: "acme",
            accountMenu: AccountMenuModel.Item.allCases.map(\.label),
            statusStrip: "Connected to the local daemon.",
            permissionWalkthroughComplete: true,
            quietPresentation: true
        )
        let object = try Self.decode(state.jsonString())
        XCTAssertEqual(object["selectedWorkspaceSlug"] as? String, "acme")
        XCTAssertEqual(object["accountMenu"] as? [String], ["Home", "Profile", "Settings", "Log out"])
        XCTAssertEqual(object["statusStrip"] as? String, "Connected to the local daemon.")
        XCTAssertEqual(object["permissionWalkthroughComplete"] as? Bool, true)
        XCTAssertEqual(object["quietPresentation"] as? Bool, true)
        let workspace = try XCTUnwrap((object["workspaces"] as? [[String: Any]])?.first)
        XCTAssertEqual(workspace["label"] as? String, "Acme Inc (acme)")
    }

    func testErrorAndNotMemberPhasesReportSeparateFields() throws {
        let failed = HubUIState(pid: 1, bundlePath: "/tmp", phase: "error", errorMessage: "Network is down.")
        let refused = HubUIState(pid: 1, bundlePath: "/tmp", phase: "notMember", notMemberMessage: "acme")

        let failedObject = try Self.decode(failed.jsonString())
        XCTAssertEqual(failedObject["errorMessage"] as? String, "Network is down.")
        XCTAssertNil(failedObject["notMemberMessage"])

        let refusedObject = try Self.decode(refused.jsonString())
        XCTAssertEqual(refusedObject["notMemberMessage"] as? String, "acme")
        XCTAssertNil(refusedObject["errorMessage"])
    }

    func testJSONKeysAreSortedSoTwoSnapshotsDiffTextually() {
        let state = HubUIState(pid: 1, bundlePath: "/tmp", phase: "ready")
        let json = state.jsonString()
        let keys = json
            .split(separator: "\n")
            .compactMap { line -> String? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("\"") else { return nil }
                return trimmed.split(separator: "\"").first.map(String.init)
            }
        XCTAssertEqual(keys, keys.sorted())
        XCTAssertTrue(keys.contains("phase"))
    }

    // MARK: HTDV rows

    func testItemFlattensBothBadgeKindsDistinguishably() {
        let dotted = HubUIState.Item(
            HTDVItem(id: "a", label: "Alpha", badge: .dot(.red))
        )
        XCTAssertEqual(dotted.id, "a")
        XCTAssertEqual(dotted.label, "Alpha")
        XCTAssertEqual(dotted.badge, "dot:red")
        XCTAssertEqual(dotted.leadsTo, "list")

        let counted = HubUIState.Item(
            HTDVItem(id: "b", label: "Beta", leadsTo: .detail, badge: .count(3))
        )
        XCTAssertEqual(counted.badge, "count:3")
        XCTAssertEqual(counted.leadsTo, "detail")

        let plain = HubUIState.Item(HTDVItem(id: "c", label: "Gamma"))
        XCTAssertNil(plain.badge)
    }

    // MARK: Quiet presentation

    @MainActor
    func testQuietPresentationIsOnForATestHostWhateverTheDefaultsSay() throws {
        let defaults = try Self.scratchDefaults()
        defaults.removeObject(forKey: QuietWindowPresentation.defaultsKey)
        XCTAssertTrue(QuietWindowPresentation.resolve(isTestHost: true, defaults: defaults))
    }

    @MainActor
    func testQuietPresentationIsOffForANormalLaunchWithNoSwitch() throws {
        let defaults = try Self.scratchDefaults()
        defaults.removeObject(forKey: QuietWindowPresentation.defaultsKey)
        XCTAssertFalse(QuietWindowPresentation.resolve(isTestHost: false, defaults: defaults))
    }

    @MainActor
    func testQuietPresentationFollowsTheDebugSwitchForANormalLaunch() throws {
        let defaults = try Self.scratchDefaults()
        defaults.set(true, forKey: QuietWindowPresentation.defaultsKey)
        XCTAssertTrue(QuietWindowPresentation.resolve(isTestHost: false, defaults: defaults))
        defaults.set(false, forKey: QuietWindowPresentation.defaultsKey)
        XCTAssertFalse(QuietWindowPresentation.resolve(isTestHost: false, defaults: defaults))
    }

    // MARK: Helpers

    /// A throwaway defaults domain. Never `.standard`: this process is the test
    /// runner, and a flag written there would outlive the test and change how
    /// the next run of the app under this user presents its windows.
    private static func scratchDefaults() throws -> UserDefaults {
        let suite = "HubScriptingStateTests.\(UUID().uuidString)"
        return try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    private static func decode(_ json: String) throws -> [String: Any] {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
