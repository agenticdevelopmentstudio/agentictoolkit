import Foundation
import AgenticToolkitMarkdown

/// `NoteStorage` over `MarkdownStore`: a note is a markdown document with a
/// live `content.notes` marker row.
///
/// Nothing above it changes. `NotesManager` already takes a `NoteStorage` and
/// `NotesCoordinator` already takes one from its caller, so replacing
/// `NotesDatabaseManager` is one conformance here and one line in Whippet —
/// which is the whole reason that seam exists.
///
/// `Sendable` as written: `store` is a `let MarkdownStore`, itself
/// `@unchecked Sendable`, and `pinnedKey` is a `static let` constant — there
/// is no other stored state, so the compiler-derived conformance below costs
/// nothing (M1(b) in the review this fixes).
public final class MarkdownNoteStorage: NoteStorage, Sendable {

    /// Exposed so a host can reach the taxonomy and the REST queue; the four
    /// `NoteStorage` methods deliberately do not.
    public let store: MarkdownStore

    /// The one frontmatter key this class writes.
    ///
    /// `pinned` is `MarkdownDocument.isPinned`/`setPinned(_:)` in ADT and is
    /// named here because ownership below is keyed by name and needs the
    /// string. There is no `title` key any more: a note's title is
    /// `MarkdownText.deriveTitle(content)`, the same derivation adh applies,
    /// and this class never writes one — a hand-typed `title:` fence is read
    /// like any other frontmatter and is never this class's to claim.
    ///
    /// The cost is real and worth naming: pinning edits `content`, so once a
    /// remote writer exists, pinning appends a version on the server. A
    /// local-only column would avoid that and then vanish on the first sync,
    /// which is worse.
    private static let pinnedKey = "pinned"

    public init(store: MarkdownStore) {
        self.store = store
    }

    // MARK: - Ownership
    //
    // Everything below turns on one fact that the document itself cannot
    // carry: for `pinned`, did *this app* write it, or did the user type it?
    //
    // Nothing in `pinned: true` distinguishes the two. Two separate defects
    // came from two separate attempts to guess: an unpin refused to clear
    // `pinned:` because the app could not tell its own pin from a pasted one,
    // and a foreign `pinned: true` in a Hugo document silently pinned the
    // note. (A third, sibling defect lived on the `title` key this class used
    // to also own — a save overwrote a hand-typed `title:` because the app
    // assumed any title it did not recognise was stale — and is moot now that
    // this class writes no title at all.) Each was patched with its own
    // ad-hoc guard reading the *value*, and the guards disagreed with each
    // other, which is how the file reached the state this replaces.
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
    /// just taken from the user. The same holds for any value whose quoting,
    /// spacing or scalar style differs from what `Frontmatter.setting`
    /// produces. Comparing the rendered result catches every one of those
    /// without enumerating them.
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
        // `pinned:` fence keeps it, unclaimed and untouched.
        var content = note.content
        var owned: Set<String> = []
        // Only ever true for a note inserted already pinned, which the protocol
        // allows and the app never does — but it now costs one statement
        // instead of the create-then-update pair it used to take, because the
        // content and the ownership are both settled before the insert.
        if note.isPinned, Frontmatter.value(Self.pinnedKey, in: content) == nil {
            content = Frontmatter.setting(Self.pinnedKey, to: .bool(true), in: content)
            owned.insert(Self.pinnedKey)
        }
        // Both stamps, separately. `now:` dates the write; `createdAt:` is the
        // note's own birthday, which `Note` already carries and which nothing
        // else in the row records — passing only `now:` stamped `created_at`
        // with the modification date, so every note appeared to have been
        // created when it was last edited, irrecoverably.
        _ = try store.createDocument(
            content: content,
            markers: [.note],
            id: note.id.uuidString.lowercased(),
            now: note.modifiedDate,
            createdAt: note.createdDate,
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
    /// The read, the merge and the write are **one** transaction
    /// (`MarkdownStore.mutateDocument`), not three calls.
    ///
    /// The merge below writes the whole row back, so a writer landing between
    /// a separate read and write would have its change overwritten with no
    /// error. Today nothing can: `NotesCoordinator` builds one `NotesManager`
    /// and hands the same instance to both the notes window and Quick Note,
    /// and that manager issues its storage calls one at a time. This is
    /// defence for the writer that is not here yet — a background sync pull,
    /// a second coordinator — and it is cheap enough to be worth having
    /// before that writer arrives, because the layer that reads and writes
    /// together is the only layer that can make the pair indivisible.
    ///
    /// It buys atomicity, not ordering. Two concurrent writers still resolve
    /// last-writer-wins over the whole note, matching adh (whose head has no
    /// concurrency token either): the merge assigns `document.content =
    /// note.content` outright, so a stale snapshot still clobbers a newer one
    /// — atomically. A compare-and-swap would be a different feature, and
    /// would need a token adh does not send.
    public func updateNote(_ note: Note) throws {
        let id = note.id.uuidString.lowercased()
        try store.mutateDocument(id: id, now: note.modifiedDate) { document, owned in
            if note.content != Self.strippedContent(of: document, owned: owned) {
                document.content = note.content
                owned = []
            }

            // The desired value is built once and used twice — asked about by
            // `mayWrite` and then written by `Frontmatter.setting` — so the
            // write that is permitted is provably the write that happens.
            let desiredPin: FrontmatterValue? = note.isPinned ? .bool(true) : nil
            if Self.mayWrite(Self.pinnedKey, as: desiredPin, in: document.content, owned: owned) {
                document.content = Frontmatter.setting(
                    Self.pinnedKey, to: desiredPin, in: document.content)
                Self.claim(Self.pinnedKey, wrote: note.isPinned, in: &owned)
            }
        }
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
        // Neither `title:` nor `excerpt:` is passed here — both are `Note`
        // properties computed from `content`, exactly as `MarkdownDocument`
        // computes `document.title` and `document.excerpt` from its own
        // content, and `Note.content` below is what the two derive from.
        return Note(
            id: id,
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
    /// touched — a `pinned:` the user typed stays visible in the editor,
    /// where it belongs, along with every other line in its original order.
    ///
    /// This is both what `Note.content` shows the app and (via the equality
    /// check in `updateNote`) how a save tells "nothing changed" apart from
    /// "the user edited the body".
    private static func strippedContent(of document: MarkdownDocument, owned: Set<String>) -> String {
        owned.sorted().reduce(document.content) { content, key in
            Frontmatter.setting(key, to: nil, in: content)
        }
    }
}
