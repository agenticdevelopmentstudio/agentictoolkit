import AgenticToolkitCore
import AgenticToolkitCoreUI
import AppKit

/// Settings › Editor: what every editor in the app draws around the text.
///
/// Each of the three is also overridable per editor pane, from that pane's
/// gear. This panel sets what a pane follows when it has no opinion of its
/// own -- which is every pane, until someone touches a gear.
@MainActor
public final class EditorSettingsPanelViewController: ComposableSettings.SettingsPanelViewController {

    public init() {
        super.init(with: ComposableSettings.SettingsPanelDescriptor(
            title: "Editor",
            icon: NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: nil)
        ))
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { nil }

    public override var helpContent: ComposableSettings.PanelHelp? {
        ComposableSettings.PanelHelp(topics: [
            .init(
                title: "Display",
                body: "These apply to every editor. A single editor can override any of them from "
                    + "the gear in its pane header, and its Reset to Defaults button hands it back "
                    + "to these -- including later changes made here."
            )
        ])
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        settingsView.addGroup(makeDisplayGroup())
    }

    private func makeDisplayGroup() -> ComposableSettings.GroupView {
        let group = ComposableSettings.GroupView(withTitle: "Display")

        let lineNumbers = ComposableSettings.ViewModel<Bool>(
            title: "Show line numbers",
            setting: UserSettings.editorShowLineNumbers,
            explanation: "The gutter down the left edge."
        )
        let lineNumbersView = ComposableSettings.CheckboxView(with: lineNumbers)
        lineNumbersView.toggle.accessibilityID("settings.editor.show-line-numbers")
        group.addSettingSubview(lineNumbersView)

        let overview = ComposableSettings.ViewModel<Bool>(
            title: "Show overview",
            setting: UserSettings.editorShowOverview,
            explanation: "The miniature of the whole file down the right edge."
        )
        let overviewView = ComposableSettings.CheckboxView(with: overview)
        overviewView.toggle.accessibilityID("settings.editor.show-overview")
        group.addSettingSubview(overviewView)

        let invisibles = ComposableSettings.ViewModel<Bool>(
            title: "Show invisibles",
            setting: UserSettings.editorShowInvisibles,
            explanation: "Draw spaces, tabs and line endings."
        )
        let invisiblesView = ComposableSettings.CheckboxView(with: invisibles)
        invisiblesView.toggle.accessibilityID("settings.editor.show-invisibles")
        group.addSettingSubview(invisiblesView)

        return group
    }
}
