import AgenticToolkitMacOS
import XCTest

final class AppUpdaterConfigurationTests: XCTestCase {
    private let good: [String: Any] = [
        "AgenticReleaseChannel": "release",
        "SUFeedURL": "https://agenticstenographer.app/appcast.xml",
        "SUPublicEDKey": "abc123="
    ]
    func testReleaseChannelWithFeedAndKeyIsEnabled() {
        XCTAssertEqual(AppUpdaterConfiguration(infoDictionary: good)?.feedURL.absoluteString,
                       "https://agenticstenographer.app/appcast.xml")
    }
    func testDevChannelIsDisabled() {
        var info = good; info["AgenticReleaseChannel"] = "dev"
        XCTAssertNil(AppUpdaterConfiguration(infoDictionary: info))
    }
    func testMissingChannelIsDisabled() {
        var info = good; info.removeValue(forKey: "AgenticReleaseChannel")
        XCTAssertNil(AppUpdaterConfiguration(infoDictionary: info))
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
