import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS
import AgenticToolkitPermissions
import AgenticToolkitPermissionsUI

/// Walks the user through granting the permissions the app needs on first
/// launch, in a standard modal alert hosting the reusable
/// `PermissionsPanelView`.
///
/// An alert rather than a window of our own: this is a question the app is
/// asking before it can get on with anything, which is what an alert is for,
/// and it buys the system's own button placement, key handling and modality
/// instead of a hand-built imitation of them.
///
/// Every permission is listed, the already-granted ones included — a list that
/// showed only what is missing couldn't tell the reader whether the app has a
/// grant or never asked. The panel refreshes itself as grants change (on app
/// reactivation), so there's no polling timer; the user clicks Done when
/// finished.
///
/// It asks *once*. Done retires it whatever the user granted, and what is still
/// missing lives in Settings ▸ Permissions, which shows the same panel without
/// blocking anything.
@MainActor
public final class PermissionWalkthrough: AppFeature {

    /// The terminal whose Automation grant the walkthrough surfaces. Injectable so
    /// hosts that drive a different terminal can override it.
    public static let defaultAutomationTarget = "com.googlecode.iterm2"

    /// UserDefaults key tracking whether the walkthrough has completed.
    public static let walkthroughCompleteKey = "permission_walkthrough_complete"

    /// Whether the walkthrough has already been completed.
    public static var isComplete: Bool {
        UserDefaults.standard.bool(forKey: walkthroughCompleteKey)
    }

    /// Resets the walkthrough so it runs again on next launch.
    ///
    /// Also forgets every remembered keychain grant, since that is the one
    /// permission whose status is a record rather than a reading: leaving it
    /// behind would make the re-run skip the row the user pressed Reset to see
    /// again. The system permissions need no such clearing — they are read back
    /// from the OS every time.
    public static func reset(permissions: [AgenticToolkitPermissions.Permission] = defaultPermissions) {
        UserDefaults.standard.removeObject(forKey: walkthroughCompleteKey)
        for case .keychain(let service) in permissions {
            KeychainPermissionLedger.forget(service: service)
        }
    }

    private let permissions: [AgenticToolkitPermissions.Permission]
    private let checker: any PermissionChecking
    /// Held rather than captured, so the run-loop block below needs to capture
    /// nothing but `self` — which, being main-actor isolated, is `Sendable`.
    ///
    /// A list rather than one closure: a second `runIfNeeded` arriving while the
    /// first alert is still up must not overwrite the first caller's
    /// continuation, which would leave it waiting for a callback that no longer
    /// exists.
    private var completions: [() -> Void] = []

    /// True from the moment a presentation is scheduled until the alert closes.
    ///
    /// `RunLoop.perform(inModes: [.common])` includes the modal and
    /// event-tracking modes, so a block enqueued while the alert is up *runs*
    /// rather than waiting for the modal session to end — which without this
    /// would stack a second "Grant Permissions" alert inside the first.
    private var isPresenting = false

    /// The toolkit app's own set. Include Automation so first-launch onboarding
    /// covers the permission the terminal-activation feature actually needs
    /// (Apple Events to the terminal).
    public static let defaultPermissions: [AgenticToolkitPermissions.Permission] = [
        .accessibility,
        .notifications,
        .automation(targetBundleID: defaultAutomationTarget)
    ]

    public override init() {
        self.permissions = Self.defaultPermissions
        self.checker = SystemPermissionChecker()
    }

    /// A host with a different set — Stenographer wants Automation and Keychain
    /// and neither Accessibility nor Notifications — states it rather than
    /// walking the user through grants its app will never ask for.
    public init(permissions: [AgenticToolkitPermissions.Permission]) {
        self.permissions = permissions
        self.checker = SystemPermissionChecker()
        super.init()
    }

    /// Runs the walkthrough if it hasn't been completed and something is still
    /// missing. Calls `completion` when done.
    public func runIfNeeded(completion: @escaping () -> Void) {
        guard !Self.isComplete else {
            completion()
            return
        }

        self.completions.append(completion)
        guard !self.isPresenting else { return }
        self.isPresenting = true

        Task { @MainActor in
            // Nothing missing: the walkthrough has served its purpose without
            // ever being seen. Asking for permissions the app already holds is
            // an interruption that teaches the reader nothing.
            guard await self.allGranted() == false else {
                Self.markComplete()
                self.isPresenting = false
                self.finish()
                return
            }
            self.presentFromRunLoop()
        }
    }

    /// Shows the alert from a run-loop block rather than from the task that
    /// decided to show it.
    ///
    /// `runModal()` blocks the main thread and spins a nested run loop, and
    /// everything inside the alert depends on main-thread work continuing to
    /// run underneath it: each row reads its status asynchronously, and the
    /// panel re-reads them when the user comes back from System Settings.
    /// Dispatch will not re-enter the main *queue* while a block of its own is
    /// still on the stack — and a main-actor task is such a block — so an alert
    /// run straight from the task above freezes exactly the work it is waiting
    /// for, and every row sits on "Checking…" for good. A run-loop block is not
    /// a main-queue block, so the queue stays drainable underneath this one.
    private func presentFromRunLoop() {
        RunLoop.main.perform(inModes: [.common]) {
            MainActor.assumeIsolated {
                self.present(self.permissions)
                // Done retires the walkthrough, whatever the user granted —
                // including nothing. Gating it on every permission reading
                // `.granted` looked stricter and was in fact unsatisfiable: an
                // Automation grant cannot be proven while its target app is not
                // running, because `AEDeterminePermissionToAutomateTarget`
                // answers `procNotFound` and the checker can only report that
                // as `undetermined`. A menubar app launching at login will
                // usually find iTerm2 closed, so the flag was never written and
                // this app-modal alert came back at every launch with nothing
                // the user could do to stop it. Onboarding asks once; Settings ▸
                // Permissions is where the state lives afterwards, and "Reset
                // Permission Walkthrough" there brings this back.
                Self.markComplete()
                self.isPresenting = false
                self.finish()
            }
        }
    }

    /// Drains the queue before calling, so a completion that itself calls
    /// `runIfNeeded` again can't see its own entry still pending.
    private func finish() {
        let pending = completions
        completions = []
        for completion in pending {
            completion()
        }
    }

    private func allGranted() async -> Bool {
        for permission in permissions where await checker.status(permission) != .granted {
            return false
        }
        return true
    }

    // MARK: - The alert

    private static let explanation =
        "These permissions let the app find and activate terminal windows, open new"
        + " ones, and post notifications. Grant them in System Settings — this list"
        + " updates automatically."

    /// The width the permission cards are laid out at. An alert sizes itself
    /// around its accessory view, and a view laid out by constraints has no
    /// width of its own to offer it, so one is named here.
    private static let accessoryWidth: CGFloat = 420

    private func present(_ permissions: [AgenticToolkitPermissions.Permission]) {
        let alert = NSAlert()
        alert.messageText = "Grant Permissions"
        alert.informativeText = Self.explanation
        alert.alertStyle = .informational
        alert.accessoryView = Self.accessory(
            hosting: PermissionsPanelView(permissions: permissions, checker: checker))
        // One button, so AppKit makes it the default and puts it where every
        // other alert on the system puts it. Nothing here positions it — that
        // is the point of using an alert rather than building a window.
        alert.addButton(withTitle: "Done").accessibilityID("permission-walkthrough.done")
        // An alert is app-modal, not system-modal, and this runs at launch —
        // before a menubar app has a window of its own to have been activated
        // by. Without this the modal session can begin behind whatever app is
        // frontmost, and the user meets an app that has stopped answering its
        // status item with nothing on screen to say why.
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// Wraps a constraint-driven view in a frame-based one of a known size,
    /// which is the shape `NSAlert.accessoryView` expects.
    private static func accessory(hosting panel: PermissionsPanelView) -> NSView {
        panel.widthAnchor.constraint(equalToConstant: accessoryWidth).isActive = true
        panel.layoutSubtreeIfNeeded()
        let container = NSView(frame: NSRect(
            origin: .zero,
            size: NSSize(width: accessoryWidth, height: panel.fittingSize.height)))
        container.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            panel.topAnchor.constraint(equalTo: container.topAnchor),
            panel.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private static func markComplete() {
        UserDefaults.standard.set(true, forKey: walkthroughCompleteKey)
    }
}
