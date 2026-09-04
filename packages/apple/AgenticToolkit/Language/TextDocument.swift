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

    public init(uri: DocumentUri, languageId: String, text: String, version: Int = 0) {
        self.uri = uri
        self.languageId = languageId
        self.text = text
        self.version = version
        self.isDirty = false
        let index = TextDocument.computeLineIndex(text)
        self.lineStarts = index.starts
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
    /// an out-of-range character within a valid line) clamps to the text's
    /// length rather than trapping.
    ///
    /// The resulting offset is rounded down to the nearest valid boundary
    /// before it is returned — see `roundedDownToValidBoundary(_:)`.
    public func utf16Offset(for position: Position) -> Int {
        let lastLine = lineStarts.count - 1
        let line = max(0, min(position.line, lastLine))
        let lineStart = lineStarts[line]
        let lineEnd = line < lastLine ? lineStarts[line + 1] : utf16Length
        let character = max(0, min(position.character, lineEnd - lineStart))
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
        let resolved: [(edit: TextEdit, start: Int, end: Int)] = edits.map { edit in
            let start = min(utf16Offset(for: edit.range.start), originalLength)
            let end = min(utf16Offset(for: edit.range.end), originalLength)
            return (edit, min(start, end), max(start, end))
        }

        for entry in resolved.sorted(by: { $0.start > $1.start }) {
            replaceUTF16Range(start: entry.start, end: entry.end, with: entry.edit.newText)
        }

        // Built from the clamped offsets that were actually mutated, using
        // `range(for:)` against the still-stale `lineStarts`/`utf16Length`
        // (this batch's line index isn't rebuilt until just below) — the
        // same pre-edit document those offsets were resolved against. This
        // must happen before that rebuild: the caller's original
        // `entry.edit.range` may not equal what was actually mutated once
        // offsets were clamped to the document's bounds, and reporting the
        // wrong range desynchronizes a language server's mirror of the
        // document.
        let events = resolved.map { entry in
            TextDocumentContentChangeEvent(
                range: range(for: NSRange(location: entry.start, length: entry.end - entry.start)),
                rangeLength: entry.end - entry.start,
                text: entry.edit.newText
            )
        }

        version += 1
        isDirty = true
        let index = TextDocument.computeLineIndex(text)
        lineStarts = index.starts
        utf16Length = index.length

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
        utf16Length = index.length
        isDirty = false
        notifyChangeHandlers(
            version: version,
            changes: [TextDocumentContentChangeEvent(range: nil, rangeLength: nil, text: newText)]
        )
    }

    /// Call after a successful save.
    public func markClean() {
        isDirty = false
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

    /// Called only by `TextDocumentObservation.deinit`.
    func removeChangeHandler(id: UUID) {
        changeHandlers.removeValue(forKey: id)
    }

    private func notifyChangeHandlers(version: Int, changes: [TextDocumentContentChangeEvent]) {
        for handler in changeHandlers.values {
            handler(version, changes)
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
    /// first unit of every line and returning the total UTF-16 length as a
    /// side effect of the same pass.
    private static func computeLineIndex(_ text: String) -> (starts: [Int], length: Int) {
        var starts: [Int] = [0]
        let units = text.utf16
        var index = units.startIndex
        var offset = 0
        while index < units.endIndex {
            let unit = units[index]
            if unit == 0x0D { // \r — a following \n makes it one terminator
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
                offset += 1
                index = units.index(after: index)
                starts.append(offset)
            } else {
                offset += 1
                index = units.index(after: index)
            }
        }
        return (starts, offset)
    }
}

/// An opaque handle to one `TextDocument` change observer: hold it for as
/// long as delivery should continue. Mirrors `TextDocumentStoreObservation`
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
    // nonisolated by default, and `removeChangeHandler` is MainActor-isolated
    // state on `document`. `isolated deinit` hops to the actor before
    // running, rather than reaching for `nonisolated(unsafe)`.
    isolated deinit {
        document?.removeChangeHandler(id: id)
    }
}
