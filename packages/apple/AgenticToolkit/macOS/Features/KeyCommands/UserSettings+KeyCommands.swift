import AgenticToolkitCore

extension UserSettings {

    /// What the user authored for each key command, keyed by
    /// ``KeyCommandDescriptor/id``.
    ///
    /// This is the **authored** state and the single source of truth. A global
    /// command is *applied* by handing its effective chord to
    /// `KeyboardShortcuts`, which keeps its own `UserDefaults` entry — that
    /// entry is derived state, and reading it back as "what the user asked for"
    /// loses the difference between a command switched off and one never bound.
    ///
    /// The key is a stable storage name: do not rename it.
    public static let keyCommandBindings = UserSetting<[String: KeyCommandBinding]>(
        "keyCommandBindings", default: [:])
}
