import Foundation
import AgenticToolkitCore

extension UserSettings {

    /// Whether the Notes window's folders pane is showing.
    ///
    /// Defaults to `true`: it is how a note gets organized in the first place,
    /// and hiding it by default would bury the feature nobody found.
    public static let notesFoldersVisible = UserSetting<Bool>("notesFoldersVisible", default: true)

    /// Whether the Notes window's markdown syntax help pane is showing.
    ///
    /// Defaults to `false`, as the Settings help drawer's own preference does —
    /// it is a slide-out reference, not something every notes window should
    /// open with.
    public static let notesHelpVisible = UserSetting<Bool>("notesHelpVisible", default: false)
}
