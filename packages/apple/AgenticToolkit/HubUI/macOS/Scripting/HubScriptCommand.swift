#if canImport(AppKit)
import AgenticToolkitHTDV
import AgenticToolkitScripting
import AppKit
import Foundation

/// Base class for the hub's AppleScript commands.
///
/// `ScriptWindowCommand` already handles the argument parsing common to every
/// window-driving command — a direct parameter that has to be a string, a
/// window name that has to be a registered one. This adds only the hub's own
/// preconditions on top of it: a signed-in root, a sign-in screen, and the
/// hierarchical detail view underneath the root. It stays internal: nothing
/// outside this module subclasses it.
class HubScriptCommand: ScriptWindowCommand, @unchecked Sendable {

    /// The signed-in shell, or `nil` with the error already set.
    @MainActor
    func requireRoot() -> RootViewController? {
        guard let root = HubFeature.current?.mainWindow?.root else {
            fail(NSInternalScriptError, "The signed-in window is not on screen.")
            return nil
        }
        return root
    }

    /// The sign-in screen, or `nil` with the error already set.
    @MainActor
    func requireSignIn() -> SignInViewController? {
        guard let signIn = HubFeature.current?.mainWindow?.signIn else {
            fail(NSInternalScriptError, "The sign-in screen is not on screen.")
            return nil
        }
        return signIn
    }

    /// The hierarchical detail view's controller, or `nil` with the error set.
    @MainActor
    func requireHTDV() -> HTDVController? {
        guard let root = requireRoot() else { return nil }
        guard let htdv = root.htdvViewController else {
            fail(NSInternalScriptError, "The hierarchical detail view is not on screen.")
            return nil
        }
        return htdv.controller
    }
}
#endif
