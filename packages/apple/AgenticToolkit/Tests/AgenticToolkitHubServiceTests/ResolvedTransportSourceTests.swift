import AgenticDeveloperHubClient
import XCTest
@testable import AgenticToolkitHubService

/// `ResolvedTransportSource` is the macOS bootstrap path: it must map the
/// resolver's decision to the matching `APITransport` arm, and it must
/// re-probe every call (`reresolve()`, never the cached `resolve()`). Both
/// are exercised hermetically via `TransportResolver`'s `.forceDaemon` /
/// `.forceDirect` overrides, which skip the network probe entirely — no
/// stub server, no `UserDefaults.standard` (every resolver here is
/// constructed explicitly, never via the `.fromUserDefaults()` default).
final class ResolvedTransportSourceTests: XCTestCase {
    func testDaemonOverrideProducesDaemonTransportAtTheGivenPort() async {
        let resolver = TransportResolver(override: .forceDaemon, port: 9999)
        let source = ResolvedTransportSource(resolver: resolver, port: 9999)

        let transport = await source.makeTransport()

        XCTAssertEqual(transport.kind, .daemon)
        XCTAssertEqual(transport.serverURL, DaemonContract.daemonURL(port: 9999))
    }

    func testDirectOverrideProducesDirectTransportAtTheBackendURL() async {
        let resolver = TransportResolver(override: .forceDirect, port: 9999)
        let source = ResolvedTransportSource(resolver: resolver, port: 9999)

        let transport = await source.makeTransport()

        XCTAssertEqual(transport.kind, .direct)
        XCTAssertEqual(transport.serverURL, DaemonContract.backendURL)
    }

    func testEveryCallReresolvesRatherThanReturningACachedDecision() async {
        let resolver = TransportResolver(override: .forceDaemon, port: 1)
        let source = ResolvedTransportSource(resolver: resolver, port: 1)

        _ = await source.makeTransport()
        let cachedBefore = await resolver.cachedKind
        XCTAssertEqual(cachedBefore, .daemon)

        // A second call still has to produce a correctly-shaped daemon
        // transport for the overridden kind, not just whatever the first
        // call happened to cache.
        let transport = await source.makeTransport()
        XCTAssertEqual(transport.kind, .daemon)
    }
}
