import AgenticDeveloperHubClient
import Foundation

/// Where the app's `APITransport` comes from. macOS resolves against a
/// running daemon (`ResolvedTransportSource`, Task 3); iOS hands out the
/// in-process daemon's transport (`LocalDaemonTransportSource`, Task 4).
/// `HubEnvironment` calls `makeTransport()` at bootstrap and again whenever
/// the app is foregrounded, rebuilding its client if the kind changed.
public protocol HubTransportSource: Sendable {
    func makeTransport() async -> APITransport
}

/// A source that always returns the same transport. Used by tests and by
/// any caller that already holds a transport.
public struct StaticTransportSource: HubTransportSource {
    public let transport: APITransport

    public init(_ transport: APITransport) {
        self.transport = transport
    }

    public func makeTransport() async -> APITransport {
        transport
    }
}

/// macOS: asks the ADT `TransportResolver` whether a daemon is listening and
/// returns the matching transport. Every call re-probes (`reresolve()`), so
/// calling `HubEnvironment.refreshTransport()` on app activation picks up a
/// daemon that started or stopped while the app was in the background.
public final class ResolvedTransportSource: HubTransportSource {
    private let resolver: TransportResolver
    private let port: Int

    public init(resolver: TransportResolver = .fromUserDefaults(), port: Int = DaemonContract.port) {
        self.resolver = resolver
        self.port = port
    }

    public func makeTransport() async -> APITransport {
        switch await resolver.reresolve() {
        case .daemon:
            return .daemon(port: port)
        case .direct:
            return .direct()
        }
    }
}
