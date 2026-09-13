import AgenticToolkitHTDV
import Foundation

/// Injection points the hub app fills at launch. Feature modules read these instead of importing app code.
public enum HubModules {
    /// The markdown editor/viewer factory used by every markdown form field. Defaults to plain text until the
    /// app installs the real markdown module.
    @MainActor public static var markdownEditing: any MarkdownEditing = PlainTextMarkdownEditing()
}
