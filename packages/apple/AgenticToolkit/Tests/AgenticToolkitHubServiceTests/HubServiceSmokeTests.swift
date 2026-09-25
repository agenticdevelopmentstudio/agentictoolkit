import AgenticDeveloperHubClient
import AgenticToolkitHub
import XCTest
@testable import AgenticToolkitHubService

/// Proves the test bundle links every tier HubService depends on. Each assertion
/// touches one framework; a link failure shows up as a compile error here
/// before any real test exists.
final class HubServiceSmokeTests: XCTestCase {
    func testStaticTransportSourceReturnsItsTransport() async {
        let source = StaticTransportSource(.direct())
        let transport = await source.makeTransport()
        XCTAssertEqual(transport.kind, .direct)
        XCTAssertEqual(transport.serverURL, DaemonContract.backendURL)
    }

    func testLowerTiersLink() {
        XCTAssertEqual(HubWorkspaceType.allCases.count, 3)
        XCTAssertEqual(DaemonContract.port, 22850)
    }
}
