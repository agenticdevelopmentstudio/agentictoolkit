import Foundation

/// A macOS privacy permission a host app may need.
///
/// Extensible by design — add a case here (and its metadata in the extension
/// below) to support a new permission. The package intentionally models only
/// what current consumers need; Screen Recording / Full Disk Access are not
/// modeled yet (YAGNI), but adding them is a localized change.
public enum Permission: Sendable, Hashable {
    /// Accessibility (AX) — read window titles and move/raise other apps' windows.
    case accessibility
    /// User notifications for this app.
    case notifications
    /// Automation (Apple Events) to control a specific app, identified by its
    /// bundle identifier (e.g. `"com.googlecode.iterm2"`). Each target app is a
    /// distinct grant in System Settings → Privacy & Security → Automation.
    case automation(targetBundleID: String)
    /// Core Location — needed both for physical location itself and for the
    /// Wi-Fi SSID, which macOS gates behind location authorization.
    case location
}

extension Permission {
    /// Short, user-facing name for the permission.
    public var displayName: String {
        switch self {
        case .accessibility: "Accessibility"
        case .notifications: "Notifications"
        case .automation: "Automation"
        case .location: "Location"
        }
    }

    /// Stable kebab-case token identifying this permission, for accessibility
    /// identifiers and anything else that needs to name one permission and be
    /// matched on later. Not `displayName`: that is user-facing copy, free to
    /// be reworded or localized, and it collapses every `.automation` grant
    /// onto the one string "Automation" — while each target app is a separate
    /// grant in System Settings and gets its own row.
    public var identifierToken: String {
        switch self {
        case .accessibility: "accessibility"
        case .notifications: "notifications"
        case .automation(let targetBundleID):
            "automation-" + targetBundleID.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: "-")
        case .location: "location"
        }
    }

    /// SF Symbol name representing the permission.
    public var systemImageName: String {
        switch self {
        case .accessibility: "hand.raised"
        case .notifications: "bell.badge"
        case .automation: "gearshape.2"
        case .location: "location"
        }
    }

    /// One-line explanation of why the permission is needed.
    public var explanation: String {
        switch self {
        case .accessibility:
            "Required to discover and activate terminal windows for your sessions."
        case .notifications:
            "Allows notifications when sessions start, end, or become stale."
        case .automation:
            "Needed to control terminal apps like iTerm2, Terminal, and Warp."
        case .location:
            "Records where you are and which Wi-Fi network you're on, so activity can be grouped by place."
        }
    }

    /// The `x-apple.systempreferences:` URL string for this permission's System
    /// Settings pane. Pure data — actually opening it needs AppKit's
    /// `NSWorkspace`, which lives in the UI layer, keeping this target
    /// daemon-safe.
    var settingsPaneURLString: String {
        switch self {
        case .accessibility:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .notifications:
            // Append the app id only when we have one; an empty `?id=` would open
            // the Notifications pane scoped to a nonexistent app. With no id the
            // bare extension URL opens the Notifications pane root.
            if let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty {
                "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleID)"
            } else {
                "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
            }
        case .automation:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        case .location:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        }
    }

    /// The System Settings pane URL for this permission.
    public var settingsPaneURL: URL {
        guard let url = URL(string: settingsPaneURLString) else {
            preconditionFailure("Invalid settings pane URL: \(settingsPaneURLString)")
        }
        return url
    }
}
