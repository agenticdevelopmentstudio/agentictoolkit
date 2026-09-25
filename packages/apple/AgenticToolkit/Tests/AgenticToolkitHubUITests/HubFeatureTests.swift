import AgenticToolkitHubService
import AgenticToolkitPermissions
import XCTest
@testable import AgenticToolkitHubUI

/// `HubFeature` is what a host assembles; these pin the parts a host relies
/// on before `launch()` — the process-wide handle the script commands read,
/// and a main script window that answers `nil` rather than crashing when
/// nothing has been built.
@MainActor
final class HubFeatureTests: XCTestCase {

    func testInitPublishesTheCurrentFeature() {
        let feature = HubFeature(permissions: HubPermissions.required)
        XCTAssertTrue(HubFeature.current === feature)
        XCTAssertEqual(feature.permissions.count, HubPermissions.required.count)
    }

    func testMainScriptWindowIsNamedMainAndEmptyBeforeLaunch() {
        let feature = HubFeature(permissions: HubPermissions.required)
        let entry = feature.mainScriptWindow
        XCTAssertEqual(entry.name, "main")
        XCTAssertNil(entry.window())
    }

    func testReloadBeforeLaunchIsANoOp() {
        let feature = HubFeature(permissions: HubPermissions.required)
        feature.reload()
        XCTAssertNil(feature.mainWindow)
    }
}
