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

    /// The two frontmatter keys this class writes.
    ///
    /// `title` has no ADT equivalent: adh derives it from the content and
    /// rejects a caller's, and there is no per-client metadata column at all,
    /// so an explicit rename lives in this key instead. `pinned` is
    /// `MarkdownDocument.isPinned`/`setPinned(_:)` in ADT and is named here as
    /// well because ownership below is keyed by name and needs the string.
    ///
    /// The cost is real and worth naming: pinning edits `content`, so once a
    /// remote writer exists, pinning appends a version on the server. A
    /// local-only column would avoid that and then vanish on the first sync,
    /// which is worse.
    private static let titleKey = "title"
    private static let pinnedKey = "pinned"

    public init(store: MarkdownStore) {
        self.store = store
    }

    // MARK: - Ownership
    //
    // Everything below turns on one fact that the document itself cannot
    // carry: for each of these two keys, did *this app* write it, or did the
    // user type it?
    //
    // Nothing in `title: Groceries` distinguishes the two. Three separate
    // defects came from three separate attempts to guess: a save overwrote a
    // hand-typed `title:` because the app assumed any title it did not
    // recognise was stale; an unpin refused to clear `pinned:` because the app
    // could not tell its own pin from a pasted one; and a foreign `pinned:
    // true` in a Hugo document silently pinned the note. Each was patched with
    // its own ad-hoc guard reading the *value*, and the guards disagreed with
    // each other, which is how the file reached the state this replaces.
    //
    // So the fact is recorded instead of inferred.
    // `MarkdownStore.ownedFrontmatterKeys` is written in the same transaction
    // as the document, and the three rules fall out of it with no special
    // cases left:
    //
    //   * a key we own is ours to rewrite, to clear, and to hide from the
    //     editor;
    //   * a key we do not own is the user's, and is never touched or acted on;
    //   * ownership is *claimed* only when we write a key that was absent (or
    //     that already reads exactly as what we were about to write, which is
    //     a claim that changes no bytes), and *released* the moment we clear
    //     it or the user edits the text it lived in.

    /// Whether this class may write `key` — either because it already owns it,
    /// or because writing would take nothing from the user: the key is absent,
    /// or writing it would change no bytes.
    ///
    /// "Changes no bytes" is asked literally, by performing the write and
    /// comparing, rather than by comparing values. `Frontmatter.value`
    /// *unquotes*, so a user's `pinned: "true"` — a YAML string, and not what
    /// this class emits — compared equal to the desired `"true"`, and the app
    /// then rewrote the line as an unquoted boolean and claimed a key it had
    /// just taken from the user. The same held for `title: "Groceries"` and
    /// for any value whose quoting, spacing or scalar style differed from what
    /// `Frontmatter.setting` produces. Comparing the rendered result catches
    /// every one of those without enumerating them.
    ///
    /// `desired` is the `FrontmatterValue` the caller is about to hand
    /// `Frontmatter.setting`, not a string, so the comparison is against the
    /// bytes that will actually be written — a `.bool(true)` and a
    /// `.string("true")` are different writes and must answer differently.
    private static func mayWrite(
        _ key: String, as desired: FrontmatterValue?, in content: String, owned: Set<String>
    ) -> Bool {
        if owned.contains(key) { return true }
        // Absent is the other allowed case, and it is not a byte comparison:
        // adding a key the document does not have changes bytes by definition,
        // and takes nothing from anyone.
        guard Frontmatter.value(key, in: content) != nil else { return true }
        return Frontmatter.setting(key, to: desired, in: content) == content
    }

    // MARK: - NoteStorage

    public func fetchAllNotes() throws -> [Note] {
        // One query for every document's owned keys rather than one per
        // document: the list is the hot path, and the ownership record is
        // small enough to read whole.
        let owned = try store.ownedFrontmatterKeysByDocument()
        return try store.documents(marker: .note)
            .compactMap { Self.note(from: $0, owned: owned[$0.id] ?? []) }
            .sorted(by: Note.defaultSort)
    }

    public func insertNote(_ note: Note) throws {
        // A create claims a key only when the note's own text does not already
        // have one, so a fresh note whose hand-typed body opens with its own
        // `title:` or `pinned:` fence keeps it, unclaimed and untouched.
        var content = note.content
        var owned: Set<String> = []
        if let desiredTitle = Self.storedTitle(for: note),
           Frontmatter.value(Self.titleKey, in: content) == nil {
            content = Frontmatter.setting(Self.titleKey, to: .string(desiredTitle), in: content)
            owned.insert(Self.titleKey)
        }
        // Only ever true for a note inserted already pinned, which the protocol
        // allows and the app never does — but it now costs one statement
        // instead of the create-then-update pair it used to take, because the
        // content and the ownership are both settled before the insert.
        if note.isPinned, Frontmatter.value(Self.pinnedKey, in: content) == nil {
            content = Frontmatter.setting(Self.pinnedKey, to: .bool(true), in: content)
            owned.insert(Self.pinnedKey)
        }
        _ = try store.createDocument(
            content: content,
            markers: [.note],
            id: note.id.uuidString.lowercased(),
            now: note.modifiedDate,
            ownedFrontmatterKeys: owned)
    }

    /// Rewrites the keys this class owns in place, preserving whatever position
    /// and whatever foreign keys the stored frontmatter already has, so an
    /// unmodified fetch-then-save round-trips byte for byte.
    ///
    /// When the caller's `content` differs from what the last read handed back,
    /// the user edited the text — and the text is then wholly theirs. Ownership
    /// is dropped in that same step: a key that survives into the new content
    /// survives because the user kept it there, and re-claiming it would be the
    /// same guess this class stopped making.
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
        var owned = try store.ownedFrontmatterKeys(forDocument: id)
        if note.content != Self.strippedContent(of: document, owned: owned) {
            document.content = note.content
            owned = []
        }

        // Each desired value is built once and used twice — asked about by
        // `mayWrite` and then written by `Frontmatter.setting` — so the write
        // that is permitted is provably the write that happens.
        let desiredTitle: FrontmatterValue? = Self.storedTitle(for: note).map { .string($0) }
        if Self.mayWrite(Self.titleKey, as: desiredTitle, in: document.content, owned: owned) {
            document.content = Frontmatter.setting(Self.titleKey, to: desiredTitle, in: document.content)
            Self.claim(Self.titleKey, wrote: desiredTitle != nil, in: &owned)
        }

        let desiredPin: FrontmatterValue? = note.isPinned ? .bool(true) : nil
        if Self.mayWrite(Self.pinnedKey, as: desiredPin, in: document.content, owned: owned) {
            document.content = Frontmatter.setting(Self.pinnedKey, to: desiredPin, in: document.content)
            Self.claim(Self.pinnedKey, wrote: note.isPinned, in: &owned)
        }

        try store.updateDocument(document, ownedFrontmatterKeys: owned, now: note.modifiedDate)
    }

    /// Ownership follows the write that just happened: we own what we wrote,
    /// and a key we cleared is a key we no longer have any claim on.
    private static func claim(_ key: String, wrote: Bool, in owned: inout Set<String>) {
        if wrote {
            owned.insert(key)
        } else {
            owned.remove(key)
        }
    }

    public func deleteNote(id: UUID) throws {
        try store.deleteDocument(id: id.uuidString.lowercased())
    }

    // MARK: - Note ⇄ document

    /// A document whose id is not a UUID came from the server, and the Notes UI
    /// is keyed by `UUID` throughout. Skipping it keeps the list working
    /// instead of trapping on a force-unwrap; when a server-authored note needs
    /// to appear here, `Note.id` is what has to widen.
    private static func note(from document: MarkdownDocument, owned: Set<String>) -> Note? {
        guard let id = UUID(uuidString: document.id) else { return nil }
        return Note(
            id: id,
            // `document.title` *is* `MarkdownText.deriveTitle`, and that is the
            // point: the list must show the same string adh will recompute on
            // its next write, whoever wrote the frontmatter.
            //
            // Reading `document.frontmatter[titleKey]` first — which this used
            // to do — looks like the same order and is not. `frontmatter` comes
            // from `Frontmatter.parse` and is every YAML value as raw,
            // untrimmed text, whereas `deriveTitle` goes through
            // `Frontmatter.stringValue`, which takes a key only when YAML would
            // type it as a string. So `title: 42`, `title: [a, b]` and
            // `title: ""` each showed here verbatim (or blank) while adh fell
            // through to `name` or to the first body line, and the list
            // disagreed with the column on exactly the documents where it
            // mattered.
            title: document.title,
            content: strippedContent(of: document, owned: owned),
            createdDate: document.createdAt,
            modifiedDate: document.updatedAt,
            // A `pinned: true` we did not write is somebody else's key that
            // happens to share our name — a Hugo or Jekyll document pasted into
            // a note — and must not silently pin it. Ours does pin it, which is
            // the whole point of recording the difference.
            isPinned: owned.contains(pinnedKey) && document.isPinned)
    }

    /// `document.content` with the keys *we* wrote removed, and nothing else
    /// touched — a `title:` or `pinned:` the user typed stays visible in the
    /// editor, where it belongs, along with every other line in its original
    /// order.
    ///
    /// This is both what `Note.content` shows the app and (via the equality
    /// check in `updateNote`) how a save tells "nothing changed" apart from
    /// "the user edited the body".
    private static func strippedContent(of document: MarkdownDocument, owned: Set<String>) -> String {
        owned.sorted().reduce(document.content) { content, key in
            Frontmatter.setting(key, to: nil, in: content)
        }
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
