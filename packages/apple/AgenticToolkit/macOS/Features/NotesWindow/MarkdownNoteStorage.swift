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
        // Nothing has ever been written by us yet on a create path, so there
        // is no key of ours to clear. Only ever *set* a title here — never
        // call `Frontmatter.setting` to remove one — so a fresh note whose
        // hand-typed body happens to open with its own `title:` fence isn't
        // stripped on its very first save.
        let desiredTitle = Self.storedTitle(for: note)
        let content = desiredTitle == nil
            ? note.content
            : Frontmatter.setting(Self.titleKey, to: desiredTitle, in: note.content)
        var document = try store.createDocument(
            content: content,
            markers: [.note],
            id: note.id.uuidString.lowercased(),
            now: note.modifiedDate)
        // A freshly created document is never pinned, so this is a no-op —
        // and hence a second write — for every note except one inserted
        // already pinned, which the protocol allows but the app never does.
        // This also never issues a clear (`setPinned(false)` is never
        // called here), so a user-typed `pinned:` fence is safe on create
        // for the same reason title is, without needing a matching guard.
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
    ///
    /// `note(from:)` strips both owned keys before a caller ever sees
    /// `content`, so an owned key present in `note.content` here was typed by
    /// hand this session, not something we wrote. When that is the case this
    /// method leaves the key entirely alone — it neither clears it nor
    /// overwrites its value. That is stronger than the rule it replaces
    /// (which withheld only the *clear*), and adh's derivation is why:
    /// frontmatter `title` is now the first thing `MarkdownText.deriveTitle`
    /// consults, so a hand-typed fence *is* the document's title as far as
    /// both ends of the wire are concerned. `note.title` at that moment is
    /// the list's older idea of the title, and writing it back would both
    /// destroy text the user just typed and disagree with the title adh will
    /// derive on its next pull.
    ///
    /// This is single-writer by assumption, not by enforcement: it reads the
    /// stored document, merges the caller's fields into it, and writes the
    /// whole row back, so a second writer that changed the same document
    /// between the read and the write loses its change with no error. That
    /// holds today because `NotesManager` is `@MainActor` and is the only
    /// caller in either app — but the store underneath is thread-safe and
    /// takes writes from anywhere, so this class is the layer where that
    /// assumption lives and the layer that would need a compare-and-swap
    /// (adh has no concurrency token either — its head is last-writer-wins)
    /// if a background sync or a second window ever became a writer.
    public func updateNote(_ note: Note) throws {
        let id = note.id.uuidString.lowercased()
        guard var document = try store.document(id: id) else {
            throw MarkdownStoreError.notFound(id)
        }
        if note.content != Self.strippedContent(of: document) {
            document.content = note.content
        }
        let userTypedTitle = Frontmatter.value(Self.titleKey, in: note.content) != nil
        if !userTypedTitle {
            document.content = Frontmatter.setting(
                Self.titleKey, to: Self.storedTitle(for: note), in: document.content)
        }
        // "pinned" is a literal, not `Self.titleKey`-style constant, because
        // ADT itself never names it as one (`MarkdownDocument.isPinned`/
        // `setPinned(_:)` both hardcode it inline) — matching that rather
        // than inventing a constant ADT doesn't have.
        let userTypedPinned = Frontmatter.value("pinned", in: note.content) != nil
        if note.isPinned || !userTypedPinned {
            document.setPinned(note.isPinned)
        }
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
    ///
    /// Returning `nil` makes `updateNote` clear a key that may already be
    /// absent, and that redundant clear is accepted knowingly. `Frontmatter
    /// .setting(_:to: nil,in:)` on content with no such key returns the same
    /// string, so the local write is a no-op and `MarkdownDocument`'s
    /// content-hash is unchanged; the cost would only ever be a wasted `PUT`
    /// once a remote writer exists, and adh dedups on `content_hash` and vends
    /// no version for an identical resave. The alternative — asking whether
    /// the key is there before clearing it — buys a branch here in exchange
    /// for two ways of expressing "no title", which is the more expensive
    /// trade the first time the two disagree.
    private static func storedTitle(for note: Note) -> String? {
        let derived = MarkdownText.deriveTitle(note.content)
        let isUnnamed = note.title == derived || note.title == Note.untitledTitle || note.title.isEmpty
        return isUnnamed ? nil : note.title
    }
}
