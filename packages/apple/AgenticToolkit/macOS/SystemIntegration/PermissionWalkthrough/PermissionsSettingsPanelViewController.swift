import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS
import AgenticToolkitPermissions
import AgenticToolkitPermissionsUI

/// System panel: shows the live grant-state of each permission via the reusable
/// `PermissionsPanelView`, plus a button that runs the first-launch walkthrough
/// over those same permissions on demand.
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
            body: "The button under the list shows these same permissions in the window "
                + "the app puts up on its first launch, and takes you through them one "
                + "grant at a time. It is there whenever you want it: opening it grants "
                + "nothing and takes nothing back, and you can close it at any point."
        ))

        return ComposableSettings.PanelHelp(topics: topics)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.settingsView.addGroup(createPermissionsGroup())
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

        // In this card rather than one of its own: the walkthrough *is* these
        // permissions, shown a grant at a time, so it belongs under the list it
        // walks rather than under a second heading repeating the word.
        group.addSettingSubview(ComposableSettings.ButtonView(
            viewModel: ComposableSettings.ButtonViewModel(
                title: "Start Permissions Walkthrough",
                wasPressedCallback: { [weak self] in self?.startWalkthrough() }
            ),
            placement: .centered
        ))

        return group
    }

    /// Shows the walkthrough because the user asked for it, not because anything
    /// is missing — which is why this calls `run` and not `runIfNeeded`.
    ///
    /// The app's own instance, looked up rather than built: `AppFeature`
    /// registers itself on init, so a second one would displace the host's in
    /// the registry and would carry whatever set it was constructed with.
    /// Building one is the fallback for a host that composed no walkthrough at
    /// all, and it is given this panel's permissions so the window lists the
    /// same ones the card does.
    private func startWalkthrough() {
        let walkthrough = AppFeatureRegistry.shared.feature(PermissionWalkthrough.self)
            ?? PermissionWalkthrough(permissions: permissions)
        walkthrough.run()
    }
}
