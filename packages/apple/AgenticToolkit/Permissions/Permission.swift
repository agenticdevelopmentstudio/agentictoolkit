import Foundation

/// A macOS privacy permission a host app may need.
///
/// Extensible by design — add a case here (and its metadata in the extension
/// below) to support a new permission. The package intentionally models only
/// what current consumers need; Full Disk Access is not modeled yet (YAGNI),
/// but adding it is a localized change.
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
    /// Microphone input. macOS raises its own consent dialog the first time this
    /// app opens an audio device, and the answer afterwards lives in Privacy &
    /// Security → Microphone.
    case microphone
    /// Reading the contents of the display — what taking a screenshot or
    /// recording the screen needs. There is no second chance at the dialog: a
    /// refusal is remembered and answered without asking again, so the way back
    /// is Privacy & Security → Screen Recording.
    case screenCapture
    /// Reading a keychain item guarded by an ACL, named by its service string
    /// (e.g. `"Claude Code-credentials"`). Unlike the cases above this is not a
    /// TCC permission: the grant is the per-item dialog macOS puts up the first
    /// time this app reads that item, and it is remembered per item, per app.
    /// So each service is its own grant and gets its own row, the way each
    /// automation target does.
    case keychain(service: String)
}

extension Permission {
    /// Short, user-facing name for the permission.
    public var displayName: String {
        switch self {
        case .accessibility: "Accessibility"
        case .notifications: "Notifications"
        case .automation: "Automation"
        case .location: "Location"
        case .microphone: "Microphone"
        case .screenCapture: "Screen Capture"
        case .keychain: "Keychain"
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
        case .microphone: "microphone"
        case .screenCapture: "screen-capture"
        case .keychain(let service):
            "keychain-" + service.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: "-")
        }
    }

    /// SF Symbol name representing the permission.
    public var systemImageName: String {
        switch self {
        case .accessibility: "hand.raised"
        case .notifications: "bell.badge"
        case .automation: "gearshape.2"
        case .location: "location"
        case .microphone: "mic"
        case .screenCapture: "display"
        case .keychain: "key.fill"
        }
    }

    /// One-line explanation of why the permission is needed.
    ///
    /// An Automation target is named by its bundle id here. A caller that can
    /// turn one into the name a person recognises should use
    /// `explanation(namingAutomationTarget:)` instead — see it for why that
    /// caller is not this type.
    public var explanation: String {
        explanation { $0 }
    }

    /// `explanation`, with an Automation target named by whatever the caller
    /// can resolve a bundle id to.
    ///
    /// Two Automation grants are two different grants, exactly as two keychain
    /// items are, so each row has to say which app it is about. Resolving
    /// `com.googlecode.iterm2` to "iTerm" takes `NSWorkspace`, and this target
    /// is Foundation-only so a daemon can link it — so the resolving is the
    /// caller's and the sentence stays here, rather than the sentence being
    /// written out a second time wherever a resolver happens to exist.
    public func explanation(namingAutomationTarget name: (String) -> String) -> String {
        switch self {
        case .accessibility:
            "Required to discover and activate terminal windows for your sessions."
        case .notifications:
            "Allows notifications when sessions start, end, or become stale."
        case .automation(let targetBundleID):
            "Needed to find, raise and open windows in \(name(targetBundleID))."
        case .location:
            "Records where you are and which Wi-Fi network you're on, so activity can be grouped by place."
        case .microphone:
            "Lets this app record audio from your microphone."
        case .screenCapture:
            "Lets this app read what is on your screen, to capture a still of it or record it."
        case .keychain(let service):
            "Lets this app read the \u{201C}\(service)\u{201D} item in your keychain "
                + "directly, instead of asking another tool for it."
        }
    }

    /// The `x-apple.systempreferences:` URL string for this permission's System
    /// Settings pane, or `nil` for a permission System Settings does not list.
    /// Pure data — actually opening it needs AppKit's `NSWorkspace`, which lives
    /// in the UI layer, keeping this target daemon-safe.
    ///
    /// Optional because `.keychain` is not a TCC permission: there is no pane
    /// that lists it, and sending the user to Privacy & Security to look for one
    /// would be worse than sending them nowhere.
    var settingsPaneURLString: String? {
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
        case .microphone:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .screenCapture:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .keychain:
            nil
        }
    }

    /// The System Settings pane URL for this permission, or `nil` when there is
    /// no pane to open.
    public var settingsPaneURL: URL? {
        guard let string = settingsPaneURLString else { return nil }
        guard let url = URL(string: string) else {
            preconditionFailure("Invalid settings pane URL: \(string)")
        }
        return url
    }

    /// Every title a control offering to act on a permission can show.
    ///
    /// Named here rather than inlined at the one call site because two
    /// different readers need them: the control that picks one, and the
    /// control that must size itself to the widest so switching between them
    /// doesn't reflow its row. Wording is already this type's job — see
    /// `displayName` and `explanation` — so `all` can be exhaustive by
    /// construction instead of by a comment asking someone to keep it so.
    public enum ActionTitle {
        /// System Settings owns the grant — whichever direction the user is
        /// about to move it in. There is no revoke API, so a granted permission
        /// is taken back in the same pane it was given in, and a second title
        /// for that would name a destination it does not lead to.
        public static let openSettings = "Open Settings"
        /// Not granted, and this app raises the consent dialog itself.
        public static let allow = "Allow…"
        /// For a caller measuring how wide the control has to be.
        public static let all = [openSettings, allow]
    }

    /// What the row's button should say while the permission is *not* granted.
    ///
    /// A permission with a System Settings pane is granted *there*, so the
    /// button's job is to take the user to it. `.keychain` is granted by a
    /// dialog this app raises itself, so the button is the grant and says so.
    public var actionTitle: String {
        settingsPaneURLString == nil ? ActionTitle.allow : ActionTitle.openSettings
    }
}
