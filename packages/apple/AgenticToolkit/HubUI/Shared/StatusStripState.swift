import AgenticToolkitHubService
import AgenticDeveloperHubClient

/// Spec §5.6: the strip at the bottom of the window. Pure so it is testable;
/// the view controllers just render `message`.
public enum StatusStripState: Equatable, Sendable {
    case hidden
    case daemonOffline
    case backendOffline

    public static let daemonOfflineMessage = "Daemon offline — direct mode"
    public static let backendOfflineMessage = "Offline — showing cached data"

    public var message: String? {
        switch self {
        case .hidden: nil
        case .daemonOffline: Self.daemonOfflineMessage
        case .backendOffline: Self.backendOfflineMessage
        }
    }

    /// `expectsDaemon` is true on macOS (a separately running adh-daemon is
    /// the normal state) and false on iOS (the daemon is in-process, so the
    /// transport kind is always `.daemon`).
    public static func resolve(
        transportKind: TransportKind,
        servedFromCache: Bool,
        expectsDaemon: Bool
    ) -> StatusStripState {
        if servedFromCache { return .backendOffline }
        if transportKind == .direct && expectsDaemon { return .daemonOffline }
        return .hidden
    }
}
