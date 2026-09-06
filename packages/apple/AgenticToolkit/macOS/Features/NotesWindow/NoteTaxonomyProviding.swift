import Foundation
import AgenticToolkitMarkdown

/// Storage that happens to be backed by a `MarkdownStore`, and can therefore
/// answer taxonomy questions.
///
/// `NoteStorage` deliberately does not know about categories — it is an
/// abstract note-persistence seam over "SQLite, Core Data, file system" — so
/// the folders pane asks for this capability separately and does without when
/// the host's storage cannot supply it.
public protocol NoteTaxonomyProviding {
    var store: MarkdownStore { get }
}

extension MarkdownNoteStorage: NoteTaxonomyProviding {}
