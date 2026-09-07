import AppKit
import AgenticToolkitCore
import AgenticToolkitDatabase

/// General app-startup panel. The launch-at-login coachmark renders inline
/// until the user dismisses it via "Got It".
@MainActor
public final class GeneralSettingsPanelViewController: ComposableSettings.SettingsPanelViewController {

    public init() {
        super.init(with: ComposableSettings.SettingsPanelDescriptor(
            title: "General",
            icon: NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        ))
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var helpContent: ComposableSettings.PanelHelp? {
        ComposableSettings.PanelHelp(topics: [
            .init(
                title: "Launch at Login",
                body: "Registers the app with macOS so it starts when you log in. This uses "
                    + "the system's own login-items service, so macOS lists it under General "
                    + "› Login Items and can turn it off there too — which is where to look "
                    + "if the checkbox here keeps coming back unchecked."
            ),
            .init(
                title: "Restoring Windows",
                body: "What happens to the windows you had open when the app next starts: "
                    + "reopen them all, reopen none, or ask. Restoring reopens the documents "
                    + "themselves, with their pane layout, not just empty frames."
            ),
            .init(
                title: "Recent Documents",
                body: "How many entries the recent-documents list keeps. Zero switches it "
                    + "off entirely, which is the setting to use on a shared machine — the "
                    + "list is a record of what you have opened."
            )
        ])
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.settingsView.addGroup(createStartupGroup())
        self.settingsView.addGroup(createWindowBehaviorGroup())
    }

    private func createStartupGroup() -> ComposableSettings.GroupView {
        let group = ComposableSettings.GroupView(withTitle: "Startup")

        group.addSettingSubview(ComposableSettings.CheckboxView(
            with: ComposableSettings.ViewModel<Bool>(
                title: "Launch at Login",
                setting: UserSettings.launchAtLogin
            )
        ))

        group.addSettingSubview(ComposableSettings.DismissibleHintView(
            text: "\(AppStorageLocation.displayName) works best when it starts automatically "
                + "with your Mac. "
                + "Enable launch at login so you never miss a Claude Code session.",
            dismissedSetting: UserSettings.launchAtLoginHintDismissed
        ))

        return group
    }

    private func createWindowBehaviorGroup() -> ComposableSettings.GroupView {
        let group = ComposableSettings.GroupView(withTitle: "Window Behavior")

        let policyChoices = ReopenOnLaunchPolicy.allCases.map {
            ComposableSettings.ChoiceViewModel<ReopenOnLaunchPolicy>.Choice(
                label: $0.displayName,
                value: $0
            )
        }
        group.addSettingSubview(ComposableSettings.PopupMenuChoiceView<ReopenOnLaunchPolicy>(
            viewModel: ComposableSettings.ChoiceViewModel<ReopenOnLaunchPolicy>(
                title: "Restore windows on launch:",
                setting: UserSettings.reopenOnLaunchPolicy,
                choices: policyChoices
            )
        ))

        group.addSettingSubview(ComposableSettings.StepperView(
            viewModel: ComposableSettings.RangeViewModel<Int>(
                title: "Number of recent documents:",
                setting: UserSettings.recentWindowsCount,
                minValue: 0,
                maxValue: 50
            )
        ))

        return group
    }
}
