import Foundation
import AgenticToolkitMarkdown

/// `NoteStorage` over `MarkdownStore`: a note is a markdown document with a
/// live `content.notes` marker row.
///
/// Nothing above it changes. `NotesManager` already takes a `NoteStorage` and
/// `NotesCoordinator` already takes one from its caller, so replacing
/// `NotesDatabaseManager` is one conformance here and one line in Whippet —
/// which is the whole reason that seam exists.
public final class MarkdownNoteStorage: NoteStorage {

    /// Exposed so a host can reach the taxonomy and the REST queue; the four
    /// `NoteStorage` methods deliberately do not.
    public let store: MarkdownStore

    /// The frontmatter keys this class owns. adh derives `title` from the
    /// content and rejects a caller's, and there is no per-client metadata
    /// column at all — so a note's two pieces of app-level state live in the
    /// document's own text. The cost is real and worth naming: pinning edits
    /// `content`, so once a remote writer exists, pinning appends a version on
    /// the server. A local-only column would avoid that and then vanish on the
    /// first sync, which is worse.
    private static let titleKey = "title"
    private static let pinnedKey = "pinned"

    public init(store: MarkdownStore) {
        self.store = store
    }

    // MARK: - NoteStorage

    public func fetchAllNotes() throws -> [Note] {
        try store.documents(marker: .note)
            .compactMap(Self.note(from:))
            .sorted(by: Note.defaultSort)
    }

    public func insertNote(_ note: Note) throws {
        _ = try store.createDocument(
            content: Self.content(for: note),
            markers: [.note],
            id: note.id.uuidString.lowercased(),
            now: note.modifiedDate)
    }

    public func updateNote(_ note: Note) throws {
        let id = note.id.uuidString.lowercased()
        guard var document = try store.document(id: id) else {
            throw MarkdownStoreError.notFound(id)
        }
        document.content = Self.content(for: note)
        try store.updateDocument(document, now: note.modifiedDate)
    }

    public func deleteNote(id: UUID) throws {
        try store.deleteDocument(id: id.uuidString.lowercased())
    }

    // MARK: - Note ⇄ document

    /// A document whose id is not a UUID came from the server, and the Notes UI
    /// is keyed by `UUID` throughout. Skipping it keeps the list working
    /// instead of trapping on a force-unwrap; when a server-authored note needs
    /// to appear here, `Note.id` is what has to widen.
    ///
    /// `Note.content` is the document's body with its frontmatter fence
    /// stripped — the app only ever typed the body, so a round trip through
    /// this class must hand it back exactly that, never the `title`/`pinned`
    /// block `content(for:)` wrapped it in on write.
    private static func note(from document: MarkdownDocument) -> Note? {
        guard let id = UUID(uuidString: document.id) else { return nil }
        let frontmatter = document.frontmatter
        return Note(
            id: id,
            title: frontmatter[titleKey] ?? document.title,
            content: Frontmatter.split(document.content).body,
            createdDate: document.createdAt,
            modifiedDate: document.updatedAt,
            isPinned: frontmatter[pinnedKey] == "true")
    }

    /// Writes `title:` only when the user has actually renamed the note. An
    /// ordinary note — one whose title is what its first heading says — carries
    /// no frontmatter at all, so the stored text is exactly what was typed.
    private static func content(for note: Note) -> String {
        var content = note.content
        let derived = MarkdownText.deriveTitle(content)
        let storedTitle = (note.title == derived || note.title.isEmpty) ? nil : note.title
        content = Frontmatter.setting(titleKey, to: storedTitle, in: content)
        return Frontmatter.setting(pinnedKey, to: note.isPinned ? "true" : nil, in: content)
    }
}
