import CodeEditSourceEditor

/// Turns one pane's resolved display options into the editor's peripherals.
///
/// The three checkboxes are the app's vocabulary; `Peripherals` is the
/// editor's. This is the single place the two are translated.
@MainActor
public enum EditorPeripherals {

    public static func make(
        from options: EditorOptionsOverride,
        triggerCharacters: Set<String>
    ) -> SourceEditorConfiguration.Peripherals {
        SourceEditorConfiguration.Peripherals(
            showGutter: options.showLineNumbers,
            showMinimap: options.showOverview,
            invisibleCharactersConfiguration: options.showInvisibles
                ? InvisibleCharactersConfiguration(showSpaces: true, showTabs: true, showLineEndings: true)
                : .empty,
            codeSuggestionTriggerCharacters: triggerCharacters
        )
    }
}
