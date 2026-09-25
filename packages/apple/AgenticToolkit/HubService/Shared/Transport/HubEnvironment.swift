import AgenticDeveloperHubClient
import Foundation
import HTTPTypes
import os

/// Owns the app's `ADHClient` and the facts the shell shows about it: which
/// transport kind is in use and whether the last successful response came
/// from the daemon's mirror. The client is a value; when the transport kind
/// changes (`refreshTransport()`), a new client is built and `onChange` fires
/// so controllers that cached `client` re-read it.
///
/// Callbacks from the transport (responses, session expiry) arrive off the
/// main actor; `EnvironmentRelay` hops them onto it so `HubEnvironment` never
/// has to capture itself before initialization completes.
@MainActor
public final class HubEnvironment {
    public let sessionStore: any SessionStore
    public private(set) var client: ADHClient
    public private(set) var transportKind: TransportKind
    public private(set) var servedFromCache = false

    /// Called on the main actor after the session store has been cleared by
    /// the refresh middleware (refresh token rejected). `SessionController`
    /// moves to `.signedOut`.
    public var onSessionExpired: @MainActor () -> Void = {}

    /// Called whenever `client`, `transportKind` or `servedFromCache` changes.
    public var onChange: @MainActor (HubEnvironment) -> Void = { _ in }

    /// How long `bootstrap` and `refreshTransport()` wait for the transport
    /// source before giving up and using direct HTTPS.
    ///
    /// Resolving the transport is the first `await` on the launch path, and on
    /// macOS it probes for a daemon that may not be there. Nothing downstream
    /// can recover from that await never returning — the shell would sit on its
    /// spinner forever with no error to show — so it is bounded here and falls
    /// back to the transport that always works.
    public static let transportDeadline: Duration = .seconds(3)

    private nonisolated static let log = Logger(
        subsystem: "com.agentic-cookbook.agenticdeveloperhub",
        category: "transport"
    )

    private let transportSource: any HubTransportSource
    private let deadline: Duration
    private let relay = EnvironmentRelay()
    private var refreshInFlight: Task<Bool, Never>?

    public static func bootstrap(
        sessionStore: any SessionStore,
        transportSource: any HubTransportSource,
        deadline: Duration = transportDeadline
    ) async -> HubEnvironment {
        let transport = await resolveTransport(from: transportSource, deadline: deadline)
        return HubEnvironment(
            sessionStore: sessionStore,
            transportSource: transportSource,
            initialTransport: transport,
            deadline: deadline
        )
    }

    public init(
        sessionStore: any SessionStore,
        transportSource: any HubTransportSource,
        initialTransport: APITransport,
        deadline: Duration = transportDeadline
    ) {
        self.sessionStore = sessionStore
        self.transportSource = transportSource
        self.deadline = deadline
        self.transportKind = initialTransport.kind
        self.client = Self.makeClient(transport: initialTransport, sessionStore: sessionStore, relay: relay)
        relay.environment = self
    }

    /// Re-asks the transport source. Returns `true` when the kind changed and
    /// the client was rebuilt. Overlapping calls (e.g. two app-activation
    /// notifications in quick succession) share one in-flight probe instead
    /// of each running its own daemon health check, client rebuild, and
    /// `onChange` notification.
    @discardableResult
    public func refreshTransport() async -> Bool {
        if let refreshInFlight {
            return await refreshInFlight.value
        }
        let task = Task { @MainActor () -> Bool in
            let transport = await Self.resolveTransport(from: self.transportSource, deadline: self.deadline)
            guard transport.kind != self.transportKind else { return false }
            self.transportKind = transport.kind
            self.servedFromCache = false
            self.client = Self.makeClient(transport: transport, sessionStore: self.sessionStore, relay: self.relay)
            self.onChange(self)
            return true
        }
        refreshInFlight = task
        defer { refreshInFlight = nil }
        return await task.value
    }

    /// The status-strip rule (spec §5.6): only a *successful* response on the
    /// daemon transport says anything about caching. `true` = mirror-served
    /// (`cache-control: no-store`), `false` = fresh from the backend,
    /// `nil` = leave the current flag alone (direct transport, or non-2xx).
    public static func isServedFromCache(_ response: HTTPResponse, kind: TransportKind) -> Bool? {
        guard kind == .daemon, (200..<300).contains(response.status.code) else { return nil }
        let cacheControl = response.headerFields[.cacheControl]?.lowercased() ?? ""
        return cacheControl.contains("no-store")
    }

    /// `kind` is the transport that actually produced `response`, captured at
    /// client-build time — not whatever `transportKind` is *now*. A response
    /// from a transport that has since been retired by `refreshTransport()`
    /// is a no-op rather than being (mis)classified against the new kind.
    func observe(_ response: HTTPResponse, kind: TransportKind) {
        guard kind == transportKind,
              let cached = Self.isServedFromCache(response, kind: kind),
              cached != servedFromCache
        else {
            return
        }
        servedFromCache = cached
        onChange(self)
    }

    func handleSessionExpired() {
        onSessionExpired()
    }

    /// Asks the source for a transport, but never for longer than `deadline`.
    /// A source that does not answer in time is treated as "no daemon": direct
    /// HTTPS is the arm that needs no local process, so it is the only safe
    /// fallback, and the timeout is logged so a silently degraded transport is
    /// still visible after the fact.
    private static func resolveTransport(
        from source: any HubTransportSource,
        deadline: Duration
    ) async -> APITransport {
        await withDeadline(deadline) {
            log.error("Transport resolution exceeded its deadline; falling back to direct HTTPS.")
            return APITransport.direct()
        } operation: {
            await source.makeTransport()
        }
    }

    private static func makeClient(
        transport: APITransport,
        sessionStore: any SessionStore,
        relay: EnvironmentRelay
    ) -> ADHClient {
        let kind = transport.kind
        let observed = APITransport(
            kind: transport.kind,
            serverURL: transport.serverURL,
            transport: ObservingTransport(base: transport.transport) { response in relay.observe(response, kind: kind) }
        )
        return ADHClient(transport: observed, session: sessionStore, onSessionExpired: { relay.sessionExpired() })
    }
}

/// Weakly holds the environment and forwards nonisolated callbacks to it on
/// the main actor. `@MainActor` classes are `Sendable`, so the weak reference
/// can be read from any context.
final class EnvironmentRelay: @unchecked Sendable {
    private let lock = NSLock()
    private weak var stored: HubEnvironment?

    var environment: HubEnvironment? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    func observe(_ response: HTTPResponse, kind: TransportKind) {
        guard let environment else { return }
        Task { @MainActor in environment.observe(response, kind: kind) }
    }

    func sessionExpired() {
        guard let environment else { return }
        Task { @MainActor in environment.handleSessionExpired() }
    }
}
