import Foundation
import LanguageServerProtocol

/// A single open text document: a URI, a language id, a monotonically
/// increasing version, and the text itself, plus a cached line-start index
/// for cheap `Position` <-> UTF-16 offset conversion.
///
/// Foundation-only — no AppKit, SwiftUI, or Combine, so this type is safe to
/// use from a daemon. The AppKit face of a `TextDocument` is
/// `TextDocumentStorage` in `AgenticToolkitMacOS`, mirroring the
/// `SemanticPalette` / `SemanticPalette+NSColor` split.
///
/// LSP's own `Position.character` and `LSPRange` are UTF-16 code-unit based
/// (not `Character`-based, not byte-based), so every offset this type deals
/// in is a UTF-16 offset — matching how a language server counts, including
/// an emoji or accented character counting as more than one unit.
@MainActor
public final class TextDocument {

    public let uri: DocumentUri
    public private(set) var languageId: String
    public private(set) var version: Int
    public private(set) var text: String
    public private(set) var isDirty: Bool

    /// UTF-16 offset of the first code unit of every line, ascending. A line
    /// ends after its terminator (`\n`, `\r\n`, or a lone `\r`); a trailing
    /// terminator therefore always produces one more, empty, final line.
    /// Rebuilt whenever `text` changes — `position(forUTF16Offset:)` and
    /// `utf16Offset(for:)` binary-search this instead of rescanning the
    /// string on every call.
    private var lineStarts: [Int]

    /// UTF-16 offset one past the last *content* code unit of every line —
    /// the line's extent with its terminator excluded, `lineStarts.count`
    /// entries, index-for-index with `lineStarts`. The final line, which has
    /// no terminator, ends at `utf16Length`.
    ///
    /// Computed in the same single scan as `lineStarts`, which is the one
    /// place a line's extent is known, so every conversion site inherits the
    /// exclusion instead of each subtracting a terminator width it would have
    /// to re-measure (`\n` is one unit, `\r\n` is two).
    ///
    /// LSP requires it: "If the character value is greater than the line
    /// length it defaults back to the line length." Clamping to the line's
    /// *extent* instead resolved a whole-line range such as (0,0)-(0,999) —
    /// the standard shape for a format or quick-fix edit — to an offset past
    /// the newline, so replacing that range deleted the terminator and joined
    /// two lines together.
    private var lineContentEnds: [Int]

    /// The UTF-16 length of `text`, cached alongside `lineStarts` from the
    /// same scan so offset/position lookups never call the (not guaranteed
    /// O(1)) `text.utf16.count` themselves.
    private var utf16Length: Int

    /// Change observers, keyed by the token that registered them. Public and
    /// multi-slot so more than one consumer can watch the same document —
    /// `TextDocumentStore` claims one slot at `open` time to raise its own
    /// `.changed` event, and `TextDocumentStorage` (in `AgenticToolkitMacOS`)
    /// claims another to keep an `NSTextStorage` in sync — without either
    /// knowing about the other, and without this type knowing either exists.
    private var changeHandlers: [UUID: (Int, [TextDocumentContentChangeEvent]) -> Void] = [:]

    /// Dirty-state observers, keyed the same way as `changeHandlers` and torn
    /// down by the same `TextDocumentObservation` token.
    ///
    /// A separate channel because `isDirty` moves on its own schedule: it goes
    /// `true` with an edit (which is also a content change) but back to `false`
    /// at `markClean()`, when a save lands and *nothing about the text has
    /// changed*. Folding that into `changeHandlers` would either lie to a
    /// content observer such as `TextDocumentStorage` — handing it an empty
    /// edit list and a version it has already seen — or leave "the file is
    /// saved now" unobservable, which is what left a dirty indicator stuck on
    /// screen forever.
    private var dirtyStateHandlers: [UUID: (Bool) -> Void] = [:]

    public init(uri: DocumentUri, languageId: String, text: String, version: Int = 0) {
        self.uri = uri
        self.languageId = languageId
        self.text = text
        self.version = version
        self.isDirty = false
        let index = TextDocument.computeLineIndex(text)
        self.lineStarts = index.starts
        self.lineContentEnds = index.contentEnds
        self.utf16Length = index.length
    }

    // MARK: - Offset <-> Position

    /// An offset past the end of the text clamps to the end position; this
    /// never traps — a language server can and does send a stale range after
    /// a fast edit.
    ///
    /// An offset landing strictly inside a UTF-16 surrogate pair or between
    /// the `\r` and `\n` of a CRLF is rounded down to the nearest valid
    /// boundary before it is resolved — see `roundedDownToValidBoundary(_:)`.
    public func position(forUTF16Offset offset: Int) -> Position {
        let clamped = roundedDownToValidBoundary(max(0, min(offset, utf16Length)))
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= clamped {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return Position(line: low, character: clamped - lineStarts[low])
    }

    /// A `Position` past the end of the text (either an out-of-range line or
    /// an out-of-range character within a valid line) clamps rather than
    /// trapping: an out-of-range line clamps to the last line, and an
    /// out-of-range character to the end of that line's *content* — before
    /// its terminator, as LSP specifies.
    ///
    /// The resulting offset is rounded down to the nearest valid boundary
    /// before it is returned — see `roundedDownToValidBoundary(_:)`.
    public func utf16Offset(for position: Position) -> Int {
        let lastLine = lineStarts.count - 1
        let line = max(0, min(position.line, lastLine))
        let lineStart = lineStarts[line]
        // The line's *content* end, not its extent: a `character` past the
        // end of a line resolves to the end of that line's text, never past
        // its terminator. See `lineContentEnds`.
        let lineEnd = lineContentEnds[line]
        let character = max(0, min(position.character, max(0, lineEnd - lineStart)))
        return roundedDownToValidBoundary(lineStart + character)
    }

    public func range(for nsRange: NSRange) -> LSPRange {
        LSPRange(
            start: position(forUTF16Offset: nsRange.location),
            end: position(forUTF16Offset: nsRange.location + nsRange.length)
        )
    }

    public func nsRange(for range: LSPRange) -> NSRange {
        let start = utf16Offset(for: range.start)
        let end = utf16Offset(for: range.end)
        return NSRange(location: start, length: max(0, end - start))
    }

    // MARK: - Mutation

    /// Applies a batch of edits as one version bump. Every edit's `Position`s
    /// are resolved against the pre-edit document up front — the line index
    /// isn't rebuilt until the whole batch lands, so a later edit's offset
    /// must not be computed against a partially-mutated string — then the
    /// edits are applied back-to-front (descending start offset) so an
    /// earlier edit's offset stays valid while a later one is spliced in.
    @discardableResult
    public func apply(_ edits: [TextEdit]) -> [TextDocumentContentChangeEvent] {
        guard !edits.isEmpty else { return [] }

        let originalLength = utf16Length
        let resolved: [(edit: TextEdit, start: Int, end: Int, order: Int)] =
            edits.enumerated().map { order, edit in
                let start = min(utf16Offset(for: edit.range.start), originalLength)
                let end = min(utf16Offset(for: edit.range.end), originalLength)
                return (edit, min(start, end), max(start, end), order)
            }

        // **One order, used twice.** Descending start offset so an earlier
        // edit's offset stays valid while a later one is spliced in, with the
        // caller's own index as a tiebreak so the comparator is *total*:
        // `sorted(by:)` gives no stability guarantee and introsort actively
        // reorders equal elements once the array is large enough, so two
        // edits sharing a start offset — an opening "(" and its argument
        // text, which servers routinely emit as separate `TextEdit`s —
        // otherwise landed in either order depending on element count and
        // memory layout.
        //
        // The tiebreak is *descending* index, which is the direction that
        // preserves the caller's declared order **in the resulting text**.
        // Every splice happens at the same absolute offset, so each one lands
        // in front of the one before it: running `["(", "foo"]` index-ascending
        // produces "foo(", the exact inversion of what the caller asked for,
        // while index-descending produces "(foo". For a co-located insert and
        // replacement the difference is not cosmetic — index-ascending splices
        // the insert first and the replacement then eats it.
        let ordered = resolved.sorted { lhs, rhs in
            lhs.start == rhs.start ? lhs.order > rhs.order : lhs.start > rhs.start
        }

        // Built *before* the mutation loop and from `ordered`, not from the
        // caller's original array.
        //
        // From `ordered`, because LSP requires each change to be applied to
        // the document produced by the change before it: emitting the
        // caller's order while mutating in descending order left a server
        // applying a low-offset insert first, shifting every later offset,
        // and replacing the wrong range from then on — client and server
        // silently disagreeing about the text under every subsequent
        // diagnostic, hover and completion. Descending order is what makes
        // the sequence self-consistent: a change at a higher offset cannot
        // move a lower one, so each event's range stays valid as the previous
        // one is applied.
        //
        // Before the loop, because these ranges describe the pre-edit
        // document — the same document the offsets were resolved against —
        // and `range(for:)` reads `text` as well as the line index. Computing
        // them afterwards read a `text` that the loop had already mutated
        // while `lineStarts`/`utf16Length` still described the old one.
        //
        // The clamped offsets rather than `entry.edit.range`: what was
        // actually mutated may differ from what the caller asked for once
        // offsets were clamped to the document's bounds, and reporting the
        // range that was asked for rather than the one that was mutated
        // desynchronizes the server's mirror just as surely.
        let events = ordered.map { entry in
            TextDocumentContentChangeEvent(
                range: range(for: NSRange(location: entry.start, length: entry.end - entry.start)),
                rangeLength: entry.end - entry.start,
                text: entry.edit.newText
            )
        }

        for entry in ordered {
            replaceUTF16Range(start: entry.start, end: entry.end, with: entry.edit.newText)
        }

        version += 1
        let index = TextDocument.computeLineIndex(text)
        lineStarts = index.starts
        lineContentEnds = index.contentEnds
        utf16Length = index.length

        setDirty(true)
        notifyChangeHandlers(version: version, changes: events)
        return events
    }

    /// A full-content reload from disk: replaces the text outright, bumps
    /// the version, and clears the dirty flag.
    ///
    /// Raises the same change notification as `apply(_:)`, as a single
    /// full-document `TextDocumentContentChangeEvent` (`range` and
    /// `rangeLength` both `nil` is LSP's own wire form for "the document is
    /// now this text") — an observer such as `TextDocumentStorage` must see
    /// this change the same way it sees any other.
    public func replaceAll(with newText: String) {
        text = newText
        version += 1
        let index = TextDocument.computeLineIndex(newText)
        lineStarts = index.starts
        lineContentEnds = index.contentEnds
        utf16Length = index.length
        setDirty(false)
        notifyChangeHandlers(
            version: version,
            changes: [TextDocumentContentChangeEvent(range: nil, rangeLength: nil, text: newText)]
        )
    }

    /// Call after a successful save.
    ///
    /// Notifies dirty-state observers, which is the *only* signal that a
    /// document stopped being dirty: nothing about the text changed here, so
    /// no content-change notification is raised and a content observer would
    /// never hear about it. Without this the file browser's dirty dot had no
    /// event to clear itself on and stayed lit until some unrelated subsystem
    /// happened to redraw the row.
    public func markClean() {
        setDirty(false)
    }

    // MARK: - Change observation

    /// Registers `handler` and returns an opaque token that keeps it alive:
    /// dropping the token removes the handler. Mirrors
    /// `TextDocumentStore.addObserver`/`TextDocumentStoreObservation` —
    /// same UUID-keyed-dictionary-plus-token-deinit shape, one level down.
    public func addChangeHandler(
        _ handler: @escaping (Int, [TextDocumentContentChangeEvent]) -> Void
    ) -> TextDocumentObservation {
        let id = UUID()
        changeHandlers[id] = handler
        return TextDocumentObservation(id: id, document: self)
    }

    /// Registers `handler` to be called whenever `isDirty` *changes* value,
    /// with the new value. Same token lifetime as `addChangeHandler`.
    ///
    /// Only transitions are delivered: setting `isDirty` to the value it
    /// already has notifies nobody, so a second save of an already-clean
    /// document does not repaint anything.
    public func addDirtyStateHandler(
        _ handler: @escaping (Bool) -> Void
    ) -> TextDocumentObservation {
        let id = UUID()
        dirtyStateHandlers[id] = handler
        return TextDocumentObservation(id: id, document: self)
    }

    /// Called only by `TextDocumentObservation.deinit`. One token can only
    /// ever have registered one handler, and the UUIDs are drawn from the same
    /// space, so removing from both maps is unambiguous — it is exactly the
    /// one handler that token registered.
    func removeHandler(id: UUID) {
        changeHandlers.removeValue(forKey: id)
        dirtyStateHandlers.removeValue(forKey: id)
    }

    private func notifyChangeHandlers(version: Int, changes: [TextDocumentContentChangeEvent]) {
        for handler in changeHandlers.values {
            handler(version, changes)
        }
    }

    private func setDirty(_ newValue: Bool) {
        guard isDirty != newValue else { return }
        isDirty = newValue
        for handler in dirtyStateHandlers.values {
            handler(newValue)
        }
    }

    // MARK: - Private

    /// Rounds a UTF-16 offset already clamped to `[0, utf16Length]` down to
    /// the nearest boundary that does not split a UTF-16 surrogate pair or a
    /// CRLF line terminator.
    ///
    /// Neither case traps on its own — converting such an offset into a
    /// `String.Index` and using it to slice `text` rounds it down silently
    /// and implicitly, because a `String.Index` can only address a Unicode
    /// scalar boundary. That behavior is accidental, not chosen, so this
    /// makes the same choice explicitly: an offset arrives here from a
    /// language server working against a slightly stale mirror of the
    /// document, and rounding toward the earlier boundary keeps an edit
    /// inside the region the server meant rather than spilling past it.
    private func roundedDownToValidBoundary(_ clampedOffset: Int) -> Int {
        guard clampedOffset > 0, clampedOffset < utf16Length else { return clampedOffset }
        let units = text.utf16
        // `utf16Length` can be stale relative to `text` for a brief window
        // inside `apply(_:)` (mutated `text`, not-yet-rebuilt `utf16Length` —
        // see the comment on the `events` computation there), so passing the
        // guard above does not guarantee `clampedOffset` is still a
        // dereferenceable index into the *current* `text.utf16`. Requiring
        // `currentIndex < units.endIndex` (rather than merely resolving via
        // `limitedBy`, which also accepts landing exactly on `endIndex`)
        // catches that case before the subscripts below run — `endIndex`
        // resolves fine as an `Index` but traps on subscript. This also
        // guarantees `previousIndex < units.endIndex`, since it is always one
        // position before `currentIndex`.
        guard
            let previousIndex = units.index(units.startIndex, offsetBy: clampedOffset - 1, limitedBy: units.endIndex),
            let currentIndex = units.index(units.startIndex, offsetBy: clampedOffset, limitedBy: units.endIndex),
            currentIndex < units.endIndex
        else {
            return clampedOffset
        }
        let previousUnit = units[previousIndex]
        let currentUnit = units[currentIndex]
        let splitsSurrogatePair = (0xD800...0xDBFF).contains(previousUnit) && (0xDC00...0xDFFF).contains(currentUnit)
        let splitsCRLF = previousUnit == 0x0D && currentUnit == 0x0A
        return (splitsSurrogatePair || splitsCRLF) ? clampedOffset - 1 : clampedOffset
    }

    /// Replaces the UTF-16 code units `[start, end)` of `text` with
    /// `newText`. Callers are responsible for offsets that are valid against
    /// the *current* `text` at the time of the call — `apply(_:)` guarantees
    /// this by resolving every offset before mutating anything and then
    /// working back-to-front.
    private func replaceUTF16Range(start: Int, end: Int, with newText: String) {
        let units = text.utf16
        let startIndex = units.index(units.startIndex, offsetBy: start)
        let endIndex = units.index(units.startIndex, offsetBy: end)
        text.replaceSubrange(startIndex..<endIndex, with: newText)
    }

    /// Scans `text` once, in UTF-16 code units, recording the offset of the
    /// first unit of every line, the offset one past each line's last
    /// *content* unit (its terminator excluded), and the total UTF-16 length —
    /// all three as a side effect of the same pass.
    ///
    /// `starts` and `contentEnds` always have the same count: the terminator
    /// that closes a line is what appends the next start, and the final line
    /// (which has none) closes at the end of the text.
    private static func computeLineIndex(_ text: String) -> (starts: [Int], contentEnds: [Int], length: Int) {
        var starts: [Int] = [0]
        var contentEnds: [Int] = []
        let units = text.utf16
        var index = units.startIndex
        var offset = 0
        while index < units.endIndex {
            let unit = units[index]
            if unit == 0x0D { // \r — a following \n makes it one terminator
                contentEnds.append(offset)
                offset += 1
                let next = units.index(after: index)
                if next < units.endIndex, units[next] == 0x0A {
                    offset += 1
                    index = units.index(after: next)
                } else {
                    index = next
                }
                starts.append(offset)
            } else if unit == 0x0A { // \n
                contentEnds.append(offset)
                offset += 1
                index = units.index(after: index)
                starts.append(offset)
            } else {
                offset += 1
                index = units.index(after: index)
            }
        }
        contentEnds.append(offset)
        return (starts, contentEnds, offset)
    }
}

/// An opaque handle to one `TextDocument` observer — a content-change handler
/// or a dirty-state handler: hold it for as long as delivery should continue.
/// Mirrors `TextDocumentStoreObservation`
/// one level down — its `deinit` unregisters the handler the same way.
@MainActor
public final class TextDocumentObservation {
    private let id: UUID
    private weak var document: TextDocument?

    fileprivate init(id: UUID, document: TextDocument) {
        self.id = id
        self.document = document
    }

    // Isolated explicitly (SE-0371): a MainActor class's deinit is
    // nonisolated by default, and `removeHandler` is MainActor-isolated
    // state on `document`. `isolated deinit` hops to the actor before
    // running, rather than reaching for `nonisolated(unsafe)`.
    isolated deinit {
        document?.removeHandler(id: id)
    }
}
