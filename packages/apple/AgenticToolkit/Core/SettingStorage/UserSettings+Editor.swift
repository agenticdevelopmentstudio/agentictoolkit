import Foundation

/// What every editor in the app shows unless a particular one has been told
/// otherwise.
///
/// The defaults reproduce exactly what `FileEditorState.editorConfiguration`
/// hardcoded before these settings existed -- gutter and minimap on,
/// invisibles off -- so introducing the panel changes nobody's editor on the
/// launch that first reads these keys.
extension UserSettings {

    public static var editorShowLineNumbers = UserSetting<Bool>(
        "editor.show_line_numbers",
        default: true
    )

    public static var editorShowOverview = UserSetting<Bool>(
        "editor.show_overview",
        default: true
    )

    public static var editorShowInvisibles = UserSetting<Bool>(
        "editor.show_invisibles",
        default: false
    )
}
