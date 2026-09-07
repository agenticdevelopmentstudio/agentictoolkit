import Foundation

/// Where a pane remembers itself, one string key at a time.
///
/// The pane therefore knows nothing about SQLite, a repo id, or a
/// `layout_nodes` row: a project window supplies a store that reads and writes
/// `pane_state`, and a container with nothing to persist supplies
/// `EphemeralPaneStateStore`. That is the whole reason a pane can be deployed
/// somewhere that has no database (`dependency-injection`).
///
/// Writing `nil` deletes the key. A pane resetting its spacing override deletes
/// the row rather than freezing today's global into it, so a later change to
/// the global still reaches the pane — and that only works if `nil` means gone.
@MainActor
public protocol PaneStateStore: AnyObject {
    func paneStateValue(forKey key: String) -> String?
    func setPaneStateValue(_ value: String?, forKey key: String)
}

/// A store that forgets when the pane goes away.
///
/// For containers with nothing to persist, and for tests. The alternative — an
/// optional store, `nil` for "don't remember" — would put a `guard let` at
/// every read and write in `PaneViewController` for a case that has a perfectly
/// good object (`explicit-over-implicit`).
@MainActor
public final class EphemeralPaneStateStore: PaneStateStore {

    private var values: [String: String] = [:]

    public init() {}

    public func paneStateValue(forKey key: String) -> String? {
        values[key]
    }

    public func setPaneStateValue(_ value: String?, forKey key: String) {
        if let value {
            values[key] = value
        } else {
            values.removeValue(forKey: key)
        }
    }
}

/// The keys a pane stores itself under.
///
/// These are the `pane_state.key` column's values, so they are storage
/// contract: renaming one orphans everything already saved under the old
/// spelling. Constants rather than an enum because the protocol takes a
/// `String` — a pane's content is free to store its own keys alongside these,
/// and an enum would make it convert at every call.
@MainActor
public enum PaneStateKey {
    /// The edge the pane is minimized toward. Absent means restored.
    public static let minimizeEdge = "minimize.edge"
    /// `"1"` when this pane is the tab's zoomed one. Absent means not zoomed.
    public static let zoomed = "zoomed"
    /// The per-pane frame spacing override, JSON. Absent means inherit.
    public static let spacingOverride = "spacing.override"
}
