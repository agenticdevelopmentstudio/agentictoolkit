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

    /// The one frontmatter key this class owns. `pinned` is already
    /// `MarkdownDocument.isPinned`/`setPinned(_:)` in ADT — reused below
    /// rather than redefined. `title` has no ADT equivalent: adh derives it
    /// from the content and rejects a caller's, and there is no per-client
    /// metadata column at all, so an explicit rename lives in this key
    /// instead. The cost is real and worth naming: pinning edits `content`,
    /// so once a remote writer exists, pinning appends a version on the
    /// server. A local-only column would avoid that and then vanish on the
    /// first sync, which is worse.
    private static let titleKey = "title"

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
        var document = try store.createDocument(
            content: Frontmatter.setting(Self.titleKey, to: Self.storedTitle(for: note), in: note.content),
            markers: [.note],
            id: note.id.uuidString.lowercased(),
            now: note.modifiedDate)
        // A freshly created document is never pinned, so this is a no-op —
        // and hence a second write — for every note except one inserted
        // already pinned, which the protocol allows but the app never does.
        guard note.isPinned else { return }
        document.setPinned(true)
        try store.updateDocument(document, now: note.modifiedDate)
    }

    /// Rewrites `title`/`pinned` in place when the caller's `content` is
    /// exactly what the last read handed back — preserving whatever position
    /// and whatever foreign keys the stored frontmatter already has, so an
    /// unmodified fetch-then-save round-trips byte for byte. Only when the
    /// caller actually edited that text does this fall back to rebuilding
    /// the block from scratch, which cannot promise the same key order.
    public func updateNote(_ note: Note) throws {
        let id = note.id.uuidString.lowercased()
        guard var document = try store.document(id: id) else {
            throw MarkdownStoreError.notFound(id)
        }
        if note.content != Self.strippedContent(of: document) {
            document.content = note.content
        }
        document.content = Frontmatter.setting(Self.titleKey, to: Self.storedTitle(for: note), in: document.content)
        document.setPinned(note.isPinned)
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
    private static func note(from document: MarkdownDocument) -> Note? {
        guard let id = UUID(uuidString: document.id) else { return nil }
        return Note(
            id: id,
            title: document.frontmatter[titleKey] ?? document.title,
            content: strippedContent(of: document),
            createdDate: document.createdAt,
            modifiedDate: document.updatedAt,
            isPinned: document.isPinned)
    }

    /// `document.content` with only `title`/`pinned` removed — every other
    /// line, including a body the user typed that itself opens with a
    /// `---`-fenced block of its own, survives untouched, in its original
    /// order. This is both what `Note.content` shows the app, and (via the
    /// equality check in `updateNote`) how a save tells "nothing changed"
    /// apart from "the user edited the body."
    private static func strippedContent(of document: MarkdownDocument) -> String {
        var withoutPin = document
        withoutPin.setPinned(false)
        return Frontmatter.setting(titleKey, to: nil, in: withoutPin.content)
    }

    /// `nil` when `note.title` is what the content would derive on its own —
    /// an ordinary, never-renamed note — or when it's still the app's
    /// untitled sentinel, which is the same thing before the note has any
    /// heading to derive from. Only an actual rename is worth a frontmatter
    /// key and the server version it costs.
    private static func storedTitle(for note: Note) -> String? {
        let derived = MarkdownText.deriveTitle(note.content)
        let isUnnamed = note.title == derived || note.title == Note.untitledTitle || note.title.isEmpty
        return isUnnamed ? nil : note.title
    }
}
