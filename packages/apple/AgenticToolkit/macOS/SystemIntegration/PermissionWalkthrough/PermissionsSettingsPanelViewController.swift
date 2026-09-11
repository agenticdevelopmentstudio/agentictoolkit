import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS
import AgenticToolkitPermissions
import AgenticToolkitPermissionsUI

/// System panel: shows the live grant-state of each permission via the reusable
/// `PermissionsPanelView`, plus a button to reset the first-launch walkthrough.
/// This panel doesn't bind any `UserSetting`s — it's a status/action surface,
/// not a preferences surface.
@MainActor
public final class PermissionsSettingsPanelViewController: ComposableSettings.SettingsPanelViewController {

    /// Permissions the panel surfaces. Automation is per target app; the default
    /// uses iTerm2, the common terminal for Claude Code sessions.
    public static let defaultPermissions: [AgenticToolkitPermissions.Permission] = [
        .accessibility,
        .notifications,
        .automation(targetBundleID: "com.googlecode.iterm2")
    ]

    private let permissions: [AgenticToolkitPermissions.Permission]
    private weak var panel: PermissionsPanelView?

    public init(
        permissions: [AgenticToolkitPermissions.Permission] =
            PermissionsSettingsPanelViewController.defaultPermissions
    ) {
        self.permissions = permissions
        super.init(with: ComposableSettings.SettingsPanelDescriptor(
            title: "Permissions",
            icon: NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil)
        ))
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var helpContent: ComposableSettings.PanelHelp? {
        var topics: [ComposableSettings.PanelHelp.Topic] = [
            .init(
                title: "What These Are For",
                body: "macOS gates a few abilities behind an explicit grant. Accessibility "
                    + "lets the app find and raise another app's windows; Notifications lets "
                    + "it tell you about something that finished while you were elsewhere; "
                    + "Automation lets it drive a specific other app, named per target."
            ),
            .init(
                title: "Granting and Revoking",
                body: "The grant itself is made in System Settings › Privacy & Security, not "
                    + "here — this panel shows the live state and takes you there. A grant "
                    + "revoked while the app is running is picked up when the window comes "
                    + "back to the front, so you do not have to relaunch to see it."
            )
        ]

        // Only when this host actually asks for one: Keychain is the odd
        // permission out in every respect, and explaining it to an app that
        // never touches the keychain would be noise.
        if permissions.contains(where: { if case .keychain = $0 { true } else { false } }) {
            topics.append(.init(
                title: "Keychain",
                body: "Keychain is not a Privacy & Security setting and has no pane to open. "
                    + "macOS grants it per item, per app, through a dialog it puts up the "
                    + "first time this app reads that item — which is why the button here "
                    + "says Allow and does the reading itself. The dialog names this app "
                    + "because the app reads the item in its own process, with no helper "
                    + "tool standing in between.\n\nThere is also no way to ask macOS what "
                    + "the answer was, so this row reports what actually happened the last "
                    + "time the app read the item, rather than a guess. Click Allow to find "
                    + "out now; you can revoke it later in the Keychain Access app, under "
                    + "the item's Access Control tab."
            ))
        }

        topics.append(.init(
            title: "Walkthrough",
            body: "Resetting re-runs the first-launch permission walkthrough the next "
                + "time the app starts. It changes nothing that has already been "
                + "granted — it only clears the record that you have been shown the "
                + "walkthrough, and the record of which keychain items the app has "
                + "already read."
        ))

        return ComposableSettings.PanelHelp(topics: topics)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.settingsView.addGroup(createPermissionsGroup())
        self.settingsView.addGroup(createWalkthroughGroup())
    }

    public override func viewWillAppear() {
        super.viewWillAppear()
        // ComposableSettings may keep this panel in the window hierarchy across
        // tab switches, so the panel's own viewDidMoveToWindow doesn't re-fire.
        // Refresh on every appearance so re-selecting the Permissions tab shows
        // current status.
        let panel = self.panel
        Task { @MainActor in await panel?.refresh() }
    }

    private func createPermissionsGroup() -> ComposableSettings.GroupView {
        let group = ComposableSettings.GroupView(withTitle: "Permissions")

        // PermissionsPanelView refreshes itself on appear and on app
        // reactivation (e.g. returning from System Settings) — no polling timer.
        let panel = PermissionsPanelView(permissions: permissions)
        self.panel = panel
        group.addSettingSubview(panel)

        return group
    }

    private func createWalkthroughGroup() -> ComposableSettings.GroupView {
        let group = ComposableSettings.GroupView(withTitle: "Walkthrough")

        group.addSettingSubview(ComposableSettings.ButtonView(
            viewModel: ComposableSettings.ButtonViewModel(
                title: "Reset Permission Walkthrough",
                wasPressedCallback: { [weak self] in self?.resetWalkthrough() }
            ),
            // One act, not a choice between two: sized to its own title at the
            // leading edge rather than stretched across the card.
            fillsWidth: false
        ))

        return group
    }

    private func resetWalkthrough() {
        // This panel's own set, not the walkthrough's default: the keychain
        // grants to forget are the ones shown here.
        PermissionWalkthrough.reset(permissions: permissions)

        let alert = NSAlert()
        alert.messageText = "Permission Walkthrough Reset"
        alert.informativeText = "The permission walkthrough will run again the next time the app launches."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
