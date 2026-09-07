import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS
import AgenticToolkitPermissions
import AgenticToolkitPermissionsUI

/// Walks the user through granting each required permission on first launch by
/// presenting a single window hosting the reusable `PermissionsPanelView` for
/// the not-yet-granted permissions. The panel refreshes itself as permissions
/// are granted (on app reactivation), so there's no polling timer; the user
/// clicks Done when finished.
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
    private let windowController = PermissionWalkthroughWindowController()
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

    /// Runs the walkthrough if it hasn't been completed, skipping permissions
    /// already granted. Calls `completion` when done.
    public func runIfNeeded(completion: @escaping () -> Void) {
        guard !Self.isComplete else {
            completion()
            return
        }
        self.completion = completion

        Task { @MainActor in
            var pending: [AgenticToolkitPermissions.Permission] = []
            for permission in permissions where await checker.status(permission) != .granted {
                pending.append(permission)
            }
            guard !pending.isEmpty else {
                Self.markComplete()
                finish()
                return
            }
            self.present(pending: pending)
        }
    }

    private func present(pending: [AgenticToolkitPermissions.Permission]) {
        let container = windowController.contentContainer
        container.subviews.forEach { $0.removeFromSuperview() }

        let title = ThemedLabel(string: "Grant Permissions", role: .primaryText, textRole: .title)

        let explanation = ThemedLabel(
            string: "These permissions let the app monitor and activate your Claude Code sessions."
                + " Grant them in System Settings — this list updates automatically.",
            role: .secondaryText,
            textRole: .caption
        )
        explanation.usesSingleLineMode = false
        explanation.lineBreakMode = .byWordWrapping
        explanation.translatesAutoresizingMaskIntoConstraints = false

        let panel = PermissionsPanelView(permissions: pending, checker: checker)

        let doneButton = NSButton(title: "Done", target: self, action: #selector(doneClicked))
        doneButton.bezelStyle = .rounded
        doneButton.controlSize = .large
        doneButton.keyEquivalent = "\r"
        doneButton.accessibilityID("permission-walkthrough.done")

        let stack = NSStackView(views: [title, explanation, panel, doneButton])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            explanation.widthAnchor.constraint(equalTo: stack.widthAnchor),
            panel.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        windowController.present()
    }

    @objc private func doneClicked() {
        // Mark the walkthrough permanently complete only once everything is granted.
        // Clicking Done early just dismisses for this launch (the walkthrough
        // re-runs next launch) rather than silently suppressing it forever.
        Task { @MainActor in
            var allGranted = true
            for permission in permissions where await checker.status(permission) != .granted {
                allGranted = false
            }
            if allGranted {
                Self.markComplete()
            }
            windowController.dismiss()
            finish()
        }
    }

    private func finish() {
        completion?()
        completion = nil
    }

    private static func markComplete() {
        UserDefaults.standard.set(true, forKey: walkthroughCompleteKey)
    }
}
