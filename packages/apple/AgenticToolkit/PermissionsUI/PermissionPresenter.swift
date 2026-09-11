import AppKit
import AgenticToolkitPermissions

/// Drives the most useful grant flow for a permission from a user action, and
/// falls back to opening the relevant System Settings pane when an inline grant
/// isn't possible (e.g. notifications already denied, automation declined) or
/// when the permission is already granted and the user wants it back.
@MainActor
public enum PermissionPresenter {
    /// - Parameter shownAs: the status the caller's control was offering to act
    ///   on. Passed in rather than re-read here: a re-read can disagree with
    ///   what the user actually pressed — they revoked the permission in System
    ///   Settings while the panel was open — and then a button labelled
    ///   "Revoke" fires a live consent prompt instead. It also spares the
    ///   Automation row a second synchronous Apple Event round trip per click.
    public static func present(
        _ permission: Permission,
        shownAs status: PermissionStatus,
        using checker: any PermissionChecking
    ) async {
        // Already granted: there is nothing left to ask for, and no API to hand
        // a grant back — only the user can, in System Settings. So the one
        // useful thing to do is take them to the very pane the grant flow would
        // have ended at, which is what the row's "Revoke" title promises.
        if status == .granted {
            if let pane = permission.settingsPaneURL {
                NSWorkspace.shared.open(pane)
            } else {
                // No pane does not mean nowhere to go. `.keychain` is an ACL on
                // one keychain item, and Keychain Access is the app that edits
                // it — the same handoff the pane URL is, to the only place that
                // can do what the row's "Revoke" promises. A button that leads
                // nowhere would read as broken rather than as unsupported.
                openKeychainAccess()
            }
            return
        }
        switch permission {
        case .accessibility:
            // AXIsProcessTrustedWithOptions both prompts and opens the
            // Accessibility pane, so opening the URL too would be redundant.
            _ = await checker.request(permission)
        case .notifications, .automation, .location, .keychain:
            // Only fall back to System Settings on a hard denial. An undetermined
            // result (consent dialog cancelled/dismissed, or target app not running)
            // means the inline prompt already handled it — opening the pane on top
            // would be redundant, jarring UI.
            guard await checker.request(permission) == .denied else { return }
            // …and some permissions have no pane to fall back to. `.keychain` is
            // granted by the dialog the request above already raised, and System
            // Settings does not list it anywhere, so a denial is the end of the
            // road rather than a handoff.
            guard let pane = permission.settingsPaneURL else { return }
            NSWorkspace.shared.open(pane)
        }
    }

    /// Brings up Keychain Access, where a keychain grant is taken back.
    ///
    /// Resolved by bundle id rather than by a hardcoded path: the app has moved
    /// between `/Applications/Utilities` and `/System/Applications/Utilities`
    /// across releases, and a stale path would fail silently — which is the one
    /// outcome this whole branch exists to avoid.
    private static func openKeychainAccess() {
        guard let app = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.keychainaccess"
        ) else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }
}
