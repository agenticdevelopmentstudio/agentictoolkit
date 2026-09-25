import AgenticDeveloperHubClient
import XCTest
import AgenticToolkitHubService
@testable import AgenticToolkitHubUI

final class StatusStripStateTests: XCTestCase {
    func testDaemonModeIsHidden() {
        XCTAssertEqual(
            StatusStripState.resolve(transportKind: .daemon, servedFromCache: false, expectsDaemon: true),
            .hidden
        )
        XCTAssertNil(StatusStripState.hidden.message)
    }

    func testDirectOnMacShowsDaemonOffline() {
        let state = StatusStripState.resolve(transportKind: .direct, servedFromCache: false, expectsDaemon: true)
        XCTAssertEqual(state, .daemonOffline)
        XCTAssertEqual(state.message, "Daemon offline — direct mode")
    }

    func testDirectWithoutAnExpectedDaemonIsHidden() {
        XCTAssertEqual(
            StatusStripState.resolve(transportKind: .direct, servedFromCache: false, expectsDaemon: false),
            .hidden
        )
    }

    func testCachedResponsesWinOverDaemonState() {
        let state = StatusStripState.resolve(transportKind: .daemon, servedFromCache: true, expectsDaemon: true)
        XCTAssertEqual(state, .backendOffline)
        XCTAssertEqual(state.message, "Offline — showing cached data")
        XCTAssertEqual(
            StatusStripState.resolve(transportKind: .direct, servedFromCache: true, expectsDaemon: true),
            .backendOffline
        )
    }
}
