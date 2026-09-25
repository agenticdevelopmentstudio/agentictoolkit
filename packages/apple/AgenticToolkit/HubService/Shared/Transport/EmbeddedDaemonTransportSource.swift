import AgenticDeveloperHubClient

/// Transport source for a host that embeds the daemon in-process (iOS): every
/// request goes through it. Holds the daemon as `any EmbeddedDaemon` — this
/// module cannot link `ADHDPipeline`, which depends on agentictoolkit.
public struct EmbeddedDaemonTransportSource: HubTransportSource {
    private let daemon: any EmbeddedDaemon

    public init(daemon: any EmbeddedDaemon) {
        self.daemon = daemon
    }

    public func makeTransport() async -> APITransport {
        daemon.transport()
    }
}
