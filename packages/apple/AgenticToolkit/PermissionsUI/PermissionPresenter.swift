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
    ///   Settings while the panel was open — and then a button that offered to
    ///   open System Settings fires a live consent prompt instead. It also
    ///   spares the
    ///   Automation row a second synchronous Apple Event round trip per click.
    public static func present(
        _ permission: Permission,
        shownAs status: PermissionStatus,
        using checker: any PermissionChecking
    ) async {
        // Already granted: there is nothing left to ask for, and no API to hand
        // a grant back — only the user can, in System Settings. So the one
        // useful thing to do is take them to the very pane the grant flow would
        // have ended at, which is what the row's "Open Settings" title promises.
        if status == .granted {
            if let pane = permission.settingsPaneURL {
                NSWorkspace.shared.open(pane)
            } else {
                // No pane does not mean nowhere to go. `.keychain` is an ACL on
                // one keychain item, and Keychain Access is the app that edits
                // it — the same handoff the pane URL is, to the only place this
                // grant can be taken back. The row says "Open Settings" and this
                // *is* the settings for that one item; a button that led nowhere
                // would read as broken rather than as unsupported.
                openKeychainAccess()
            }
            return
        }
        switch permission {
        case .accessibility:
            // AXIsProcessTrustedWithOptions both prompts and opens the
            // Accessibility pane, so opening the URL too would be redundant.
            _ = await checker.request(permission)
        case .automation:
            // Asking means sending the target app an Apple Event, so when that
            // app isn't running there is nothing to send one to and the answer
            // is `.undetermined` — "could not ask", not "the user dismissed a
            // dialog". Treating it as a dismissal is what made this button do
            // nothing at all on a machine where the terminal happens to be
            // closed, which is the ordinary case for a permission you grant
            // before you start using the thing that needs it. So anything short
            // of a grant ends where the button's title already promises.
            guard await checker.request(permission) != .granted else { return }
            guard let pane = permission.settingsPaneURL else { return }
            NSWorkspace.shared.open(pane)
        case .notifications, .location, .microphone, .screenCapture:
            // These can always be asked — the system owns the dialog and puts it
            // up whatever else is or isn't running — so an undetermined answer
            // here really is the user declining to answer, and opening the pane
            // on top of the dialog they just dismissed would be redundant,
            // jarring UI. Only a hard denial is a handoff. Screen Recording is
            // the reason that matters beyond tidiness: it is asked once and
            // answers `.denied` from memory ever after, so the pane is the only
            // way back and the button has to reach it.
            guard await checker.request(permission) == .denied else { return }
            guard let pane = permission.settingsPaneURL else { return }
            NSWorkspace.shared.open(pane)
        case .keychain(let service):
            // Asking for this one *is* a read of the item, which gives it a
            // third outcome the permissions above do not have: the item was not
            // there to read. That is not a refusal. The ACL this row describes
            // does not exist yet, because this app has never written the item —
            // macOS creates the item and the grant together, the first time the
            // app stores something under that service. Until then there is no
            // dialog for the request to raise and no pane to hand off to, so
            // pressing the button did nothing whatsoever and read as an app with
            // a dead control. Saying so is the only honest thing left to do, and
            // pressing is the only way to find out: the ledger the row's status
            // comes from records reads that happened, and cannot distinguish an
            // item this app has never read from one that is not there at all.
            switch await checker.request(permission) {
            case .granted:
                // The read went through; the panel's refresh turns the row green.
                return
            case .denied:
                // The user answered the system's own dialog, and `.keychain` has
                // no System Settings pane to fall back to.
                return
            case .undetermined:
                presentNothingToGrantYet(service: service)
            }
        }
    }

    /// Explains a keychain row whose item does not exist yet.
    ///
    /// An alert rather than a change to the row, because this is only knowable
    /// at the moment of asking — the row's status comes from a ledger of reads
    /// that have happened, which cannot tell "never read" from "not there".
    private static func presentNothingToGrantYet(service: String) {
        let alert = NSAlert()
        alert.messageText = "Nothing to grant yet"
        alert.informativeText =
            "This app has not stored anything in your keychain under "
            + "\u{201C}\(service)\u{201D} yet. macOS creates the item and the "
            + "permission to read it at the same moment — the first time the app "
            + "saves to it, which for this app is when you sign in. There is no "
            + "dialog to show until then, and nothing you need to do here."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
