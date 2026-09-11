import AppKit
import AgenticToolkitPermissions

/// Drives the most useful grant flow for a permission from a user action, and
/// falls back to opening the relevant System Settings pane when an inline grant
/// isn't possible (e.g. notifications already denied, automation declined) or
/// when the permission is already granted and the user wants it back.
@MainActor
public enum PermissionPresenter {
    public static func present(_ permission: Permission, using checker: any PermissionChecking) async {
        // Already granted: there is nothing left to ask for, and no API to hand
        // a grant back — only the user can, in System Settings. So the one
        // useful thing to do is take them to the very pane the grant flow would
        // have ended at, which is what the row's "Revoke" title promises.
        if await checker.status(permission) == .granted {
            NSWorkspace.shared.open(permission.settingsPaneURL)
            return
        }
        switch permission {
        case .accessibility:
            // AXIsProcessTrustedWithOptions both prompts and opens the
            // Accessibility pane, so opening the URL too would be redundant.
            _ = await checker.request(permission)
        case .notifications, .automation, .location:
            // Only fall back to System Settings on a hard denial. An undetermined
            // result (consent dialog cancelled/dismissed, or target app not running)
            // means the inline prompt already handled it — opening the pane on top
            // would be redundant, jarring UI.
            if await checker.request(permission) == .denied {
                NSWorkspace.shared.open(permission.settingsPaneURL)
            }
        }
    }
}
