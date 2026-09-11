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
    public static func reset() {
        UserDefaults.standard.removeObject(forKey: walkthroughCompleteKey)
    }

    private let permissions: [AgenticToolkitPermissions.Permission]
    private let checker: any PermissionChecking
    /// Held rather than captured, so the run-loop block below needs to capture
    /// nothing but `self` — which, being main-actor isolated, is `Sendable`.
    private var completion: (() -> Void)?

    public override init() {
        // Include Automation so first-launch onboarding covers the permission the
        // terminal-activation feature actually needs (Apple Events to the terminal).
        self.permissions = [
            .accessibility,
            .notifications,
            .automation(targetBundleID: Self.defaultAutomationTarget)
        ]
        self.checker = SystemPermissionChecker()
    }

    /// Runs the walkthrough if it hasn't been completed and something is still
    /// missing. Calls `completion` when done.
    public func runIfNeeded(completion: @escaping () -> Void) {
        guard !Self.isComplete else {
            completion()
            return
        }

        self.completion = completion

        Task { @MainActor in
            // Nothing missing: the walkthrough has served its purpose without
            // ever being seen. Asking for permissions the app already holds is
            // an interruption that teaches the reader nothing.
            guard await self.allGranted() == false else {
                Self.markComplete()
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
                // Done means "stop asking forever" only when there is nothing
                // left to ask for. Clicking it early dismisses this launch's
                // alert and the walkthrough returns next launch, rather than
                // silently suppressing itself.
                Task { @MainActor in
                    if await self.allGranted() {
                        Self.markComplete()
                    }
                    self.finish()
                }
            }
        }
    }

    private func finish() {
        completion?()
        completion = nil
    }

    private func allGranted() async -> Bool {
        for permission in permissions where await checker.status(permission) != .granted {
            return false
        }
        return true
    }

    // MARK: - The alert

    private static let explanation =
        "These permissions let the app monitor and activate your Claude Code sessions."
        + " Grant them in System Settings — this list updates automatically."

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
