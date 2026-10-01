@testable import AgenticToolkitMacOS
import Sparkle
import XCTest

final class AppUpdaterConfigurationTests: XCTestCase {
    private let good: [String: Any] = [
        "AgenticReleaseChannel": "release",
        "SUFeedURL": "https://agenticstenographer.app/appcast.xml",
        "SUPublicEDKey": "abc123="
    ]
    func testReleaseChannelWithFeedAndKeyChecksInBackground() {
        let config = AppUpdaterConfiguration(infoDictionary: good)
        XCTAssertEqual(config?.feedURL.absoluteString, "https://agenticstenographer.app/appcast.xml")
        XCTAssertEqual(config?.channel, .release)
        XCTAssertEqual(config?.checksInBackground, true)
    }
    /// A dev build still gets an updater — its user can ask for a check — but
    /// never checks on its own.
    func testDevChannelChecksOnlyWhenAsked() {
        var info = good; info["AgenticReleaseChannel"] = "dev"
        let config = AppUpdaterConfiguration(infoDictionary: info)
        XCTAssertEqual(config?.channel, .dev)
        XCTAssertEqual(config?.checksInBackground, false)
    }
    func testMissingChannelIsDev() {
        var info = good; info.removeValue(forKey: "AgenticReleaseChannel")
        XCTAssertEqual(AppUpdaterConfiguration(infoDictionary: info)?.channel, .dev)
    }
    func testMissingOrEmptyKeyIsDisabled() {
        var info = good; info["SUPublicEDKey"] = ""
        XCTAssertNil(AppUpdaterConfiguration(infoDictionary: info))
        info.removeValue(forKey: "SUPublicEDKey")
        XCTAssertNil(AppUpdaterConfiguration(infoDictionary: info))
    }
    func testNonHTTPSFeedIsDisabled() {
        var info = good; info["SUFeedURL"] = "http://agenticstenographer.app/appcast.xml"
        XCTAssertNil(AppUpdaterConfiguration(infoDictionary: info))
    }
}

/// What Sparkle is allowed to do on its own, per channel.
@MainActor
final class AppUpdaterPolicyTests: XCTestCase {
    private let updater = SPUUpdater(
        hostBundle: .main, applicationBundle: .main,
        userDriver: SPUStandardUserDriver(hostBundle: .main, delegate: nil), delegate: nil)

    func testDevRefusesBackgroundChecksButAllowsAskedForOnes() {
        let policy = AppUpdaterPolicy(checksInBackground: false)
        XCTAssertThrowsError(try policy.updater(updater, mayPerform: .updatesInBackground))
        XCTAssertNoThrow(try policy.updater(updater, mayPerform: .updates))
        XCTAssertNoThrow(try policy.updater(updater, mayPerform: .updateInformation))
        XCTAssertFalse(policy.updaterShouldPromptForPermissionToCheck(forUpdates: updater))
    }

    func testReleaseAllowsEverything() {
        let policy = AppUpdaterPolicy(checksInBackground: true)
        XCTAssertNoThrow(try policy.updater(updater, mayPerform: .updatesInBackground))
        XCTAssertNoThrow(try policy.updater(updater, mayPerform: .updates))
        XCTAssertTrue(policy.updaterShouldPromptForPermissionToCheck(forUpdates: updater))
    }
}
