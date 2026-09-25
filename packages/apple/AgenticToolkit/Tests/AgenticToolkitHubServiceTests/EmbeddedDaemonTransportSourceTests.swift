import AgenticDeveloperHubClient
import Foundation
import OpenAPIURLSession
import XCTest
@testable import AgenticToolkitHubService

/// Review focus 5: the service sees the embedded daemon only as a protocol,
/// and the transport source must hand out exactly the daemon's transport.
final class EmbeddedDaemonTransportSourceTests: XCTestCase {

    private actor FakeDaemon: EmbeddedDaemon {
        func start() async {}
        func stop() async {}
        func kickSync() async {}
        func shutdown() async {}
        nonisolated func transport() -> APITransport {
            APITransport(kind: .daemon, serverURL: DaemonContract.daemonURL(), transport: URLSessionTransport())
        }
    }

    func testMakesTheDaemonsTransport() async {
        let source = EmbeddedDaemonTransportSource(daemon: FakeDaemon())
        let transport = await source.makeTransport()
        XCTAssertEqual(transport.kind, .daemon)
        XCTAssertEqual(transport.serverURL, DaemonContract.daemonURL())
    }
}
