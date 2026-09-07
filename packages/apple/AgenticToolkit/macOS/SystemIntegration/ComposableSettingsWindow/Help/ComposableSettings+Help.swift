import Foundation

/// Help moved to `macOS/UI/Help/` and lost the settings vocabulary, because
/// nothing about reference prose is a settings feature — the project window
/// wants the same drawer.
///
/// These aliases are why that rename cost nothing: 28 files across the settings
/// panels say `ComposableSettings.PanelHelp`, and none of them had to change. A
/// sweep would have put this task's risk in the wrong place — in 28 files that
/// were not otherwise being touched, rather than in the four that were.
///
/// Not deprecated on purpose. `PanelHelp` is still the right name from inside a
/// settings panel; the alias is a second true name, not a migration to nag
/// about.
extension ComposableSettings {

    public typealias PanelHelp = HelpContent
    public typealias HelpDrawerView = HelpContentView
}

public typealias SettingsHelpPresenting = HelpPresenting
