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

    /// Set by the owning `TextDocumentStore` so `apply(_:)` can raise a
    /// `.changed` event without this type knowing the store exists.
    var changeHandler: ((Int, [TextDocumentContentChangeEvent]) -> Void)?

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
    public func position(forUTF16Offset offset: Int) -> Position {
        let clamped = max(0, min(offset, utf16Length))
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
    public func utf16Offset(for position: Position) -> Int {
        let lastLine = lineStarts.count - 1
        let line = max(0, min(position.line, lastLine))
        let lineStart = lineStarts[line]
        let lineEnd = line < lastLine ? lineStarts[line + 1] : utf16Length
        let character = max(0, min(position.character, lineEnd - lineStart))
        return lineStart + character
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

        version += 1
        isDirty = true
        let index = TextDocument.computeLineIndex(text)
        lineStarts = index.starts
        utf16Length = index.length

        let events = resolved.map { entry in
            TextDocumentContentChangeEvent(
                range: entry.edit.range,
                rangeLength: entry.end - entry.start,
                text: entry.edit.newText
            )
        }
        changeHandler?(version, events)
        return events
    }

    /// A full-content reload from disk: replaces the text outright, bumps
    /// the version, and clears the dirty flag.
    public func replaceAll(with newText: String) {
        text = newText
        version += 1
        let index = TextDocument.computeLineIndex(newText)
        lineStarts = index.starts
        utf16Length = index.length
        isDirty = false
    }

    /// Call after a successful save.
    public func markClean() {
        isDirty = false
    }

    // MARK: - Private

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
