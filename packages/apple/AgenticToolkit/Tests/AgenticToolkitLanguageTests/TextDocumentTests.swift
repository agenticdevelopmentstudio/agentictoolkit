import Foundation
import Testing
import LanguageServerProtocol
@testable import AgenticToolkitLanguage

@Suite("TextDocument")
@MainActor
struct TextDocumentTests {

    // MARK: - Offset <-> Position

    @Test("utf16Offset(for:) and position(forUTF16Offset:) round-trip over every offset")
    func roundTripsEveryOffset() {
        // "ab\ncde\nf" — three lines, starts at 0, 3, 7, total length 8.
        let text = "ab\ncde\nf"
        let document = TextDocument(uri: "file:///roundtrip.txt", languageId: "plaintext", text: text)

        for offset in 0...(text as NSString).length {
            let position = document.position(forUTF16Offset: offset)
            #expect(document.utf16Offset(for: position) == offset)
        }
    }

    @Test("character counts UTF-16 code units, so an emoji counts as 2")
    func multiByteContentCountsUTF16Units() {
        let text = "let x = \"😀\"\nlet y = 1"
        let document = TextDocument(uri: "file:///emoji.swift", languageId: "swift", text: text)

        let nsText = text as NSString
        let emojiRange = nsText.range(of: "😀")
        #expect(emojiRange.length == 2) // the emoji is a UTF-16 surrogate pair

        let start = document.position(forUTF16Offset: emojiRange.location)
        let end = document.position(forUTF16Offset: emojiRange.location + emojiRange.length)
        #expect(start.line == 0)
        #expect(end.line == 0)
        #expect(end.character - start.character == 2)
    }

    @Test("CRLF is one terminator: 3 lines, correct starts, line 2 round-trips")
    func crlfIsOneTerminator() {
        let text = "a\r\nb\r\nc"
        let document = TextDocument(uri: "file:///crlf.txt", languageId: "plaintext", text: text)

        // Starts are [0, 3, 6]: "a\r\n" is 3 units, "b\r\n" is 3 more.
        #expect(document.position(forUTF16Offset: 0) == Position(line: 0, character: 0))
        #expect(document.position(forUTF16Offset: 3) == Position(line: 1, character: 0))
        #expect(document.position(forUTF16Offset: 6) == Position(line: 2, character: 0))

        let onLineTwo = Position(line: 2, character: 1)
        let offset = document.utf16Offset(for: onLineTwo)
        #expect(offset == 7) // one past "c", the end of the text
        #expect(document.position(forUTF16Offset: offset) == onLineTwo)
    }

    @Test("the empty string has 1 line, starting at 0")
    func emptyStringHasOneLine() {
        let document = TextDocument(uri: "file:///empty.txt", languageId: "plaintext", text: "")
        #expect(document.position(forUTF16Offset: 0) == Position(line: 0, character: 0))
        #expect(document.utf16Offset(for: Position(line: 0, character: 0)) == 0)
    }

    @Test("a trailing newline creates a final empty line, addressable one-past-the-end")
    func trailingNewlineCreatesFinalEmptyLine() {
        let document = TextDocument(uri: "file:///trailing.txt", languageId: "plaintext", text: "a\n")
        let onePastEnd = Position(line: 1, character: 0)
        #expect(document.position(forUTF16Offset: 2) == onePastEnd)
        #expect(document.utf16Offset(for: onePastEnd) == 2)
    }

    @Test("an out-of-range offset clamps to the end position rather than trapping")
    func outOfRangeOffsetClamps() {
        let document = TextDocument(uri: "file:///clamp-offset.txt", languageId: "plaintext", text: "abc")
        let clamped = document.position(forUTF16Offset: 9_999)
        #expect(clamped == Position(line: 0, character: 3))
        #expect(document.position(forUTF16Offset: -50) == Position(line: 0, character: 0))
    }

    @Test("an out-of-range Position clamps to the text's length rather than trapping")
    func outOfRangePositionClamps() {
        let document = TextDocument(uri: "file:///clamp-position.txt", languageId: "plaintext", text: "ab\ncd")
        let farBeyond = Position(line: 999, character: 999)
        #expect(document.utf16Offset(for: farBeyond) == 5) // the text's total length
        let negativeLine = Position(line: -3, character: 0)
        #expect(document.utf16Offset(for: negativeLine) == 0)
    }

    // MARK: - Mutation

    @Test("apply with two edits on the same line applies back-to-front and bumps version by exactly 1")
    func applyTwoEditsBackToFront() {
        let document = TextDocument(uri: "file:///apply.txt", languageId: "plaintext", text: "abcdef")
        let insertAtOne = TextEdit(
            range: LSPRange(start: Position(line: 0, character: 1), end: Position(line: 0, character: 1)),
            newText: "XY"
        )
        let replaceAtFour = TextEdit(
            range: LSPRange(start: Position(line: 0, character: 4), end: Position(line: 0, character: 5)),
            newText: "Z"
        )
        let startVersion = document.version

        // Passed in ascending order; correct application requires processing
        // the higher-offset edit first so the insert's shift never disturbs
        // an offset already resolved against the original text.
        let events = document.apply([insertAtOne, replaceAtFour])

        #expect(document.text == "aXYbcdZf")
        #expect(document.version == startVersion + 1)
        #expect(events.count == 2)
    }

    @Test("a batch whose edits overlap clamps the second splice instead of trapping")
    func applyOverlappingEditsDoesNotTrap() {
        // A server is not supposed to send overlapping edits, but nothing in
        // the transport stops one, and the whole batch is clamped against the
        // *pre-batch* length. Here the high-offset edit deletes eight of the
        // twelve units first, leaving four — and the low-offset edit's end
        // offset, a legal 8 against the original document, is then past the
        // end of the shortened text. `index(_:offsetBy:)` traps on that,
        // taking the editor down; `limitedBy:` clamps it to the text that is
        // actually there.
        let document = TextDocument(uri: "file:///overlap.txt", languageId: "plaintext", text: "abcdefghijkl")
        let deleteTail = TextEdit(
            range: LSPRange(start: Position(line: 0, character: 4), end: Position(line: 0, character: 12)),
            newText: ""
        )
        let replaceAcrossIt = TextEdit(
            range: LSPRange(start: Position(line: 0, character: 0), end: Position(line: 0, character: 8)),
            newText: "X"
        )

        let events = document.apply([deleteTail, replaceAcrossIt])

        #expect(document.text == "X")
        #expect(events.count == 2)
    }

    @Test("an edit whose range starts past the end of the document is clamped to the end")
    func applyEditBeyondEndIsClamped() {
        // `apply` clamps both offsets to `originalLength`, so this degenerates
        // to an append rather than reaching `replaceUTF16Range` with an
        // out-of-bounds offset at all — the assertion is that it stays an
        // append and does not trap.
        let document = TextDocument(uri: "file:///beyond.txt", languageId: "plaintext", text: "abc")
        document.apply([TextEdit(
            range: LSPRange(start: Position(line: 0, character: 40), end: Position(line: 0, character: 90)),
            newText: "!"
        )])

        #expect(document.text == "abc!")
    }

    @Test("version never decreases across a sequence of apply and replaceAll calls")
    func versionNeverDecreases() {
        let document = TextDocument(uri: "file:///version.txt", languageId: "plaintext", text: "abc")
        let versionAtInit = document.version

        document.apply([TextEdit(
            range: LSPRange(start: Position(line: 0, character: 0), end: Position(line: 0, character: 1)),
            newText: "X"
        )])
        let versionAfterApply = document.version
        #expect(versionAfterApply > versionAtInit)

        document.replaceAll(with: "reloaded from disk")
        let versionAfterReplaceAll = document.version
        #expect(versionAfterReplaceAll > versionAfterApply)

        document.apply([TextEdit(
            range: LSPRange(start: Position(line: 0, character: 0), end: Position(line: 0, character: 0)),
            newText: "!"
        )])
        let versionAfterSecondApply = document.version
        #expect(versionAfterSecondApply > versionAfterReplaceAll)
    }

    @Test("isDirty is false after init, true after apply, false after markClean and after replaceAll")
    func isDirtyLifecycle() {
        let document = TextDocument(uri: "file:///dirty.txt", languageId: "plaintext", text: "abc")
        #expect(document.isDirty == false)

        document.apply([TextEdit(
            range: LSPRange(start: Position(line: 0, character: 0), end: Position(line: 0, character: 1)),
            newText: "X"
        )])
        #expect(document.isDirty == true)

        document.markClean()
        #expect(document.isDirty == false)

        document.apply([TextEdit(
            range: LSPRange(start: Position(line: 0, character: 0), end: Position(line: 0, character: 1)),
            newText: "Y"
        )])
        #expect(document.isDirty == true)

        document.replaceAll(with: "fresh from disk")
        #expect(document.isDirty == false)
    }

    // MARK: - Dirty-state observation
    //
    // `markClean()` changes no text, so a content-change observer never hears
    // about a save landing. Without its own channel the file browser's dirty
    // dot had no event to clear itself on and stayed lit indefinitely.

    @Test("markClean notifies dirty-state observers even though no content changed")
    func markCleanNotifiesDirtyStateObservers() {
        let document = TextDocument(uri: "file:///clean-event.txt", languageId: "plaintext", text: "abc")
        var dirtyStates: [Bool] = []
        var contentChangeCount = 0
        let dirtyToken = document.addDirtyStateHandler { dirtyStates.append($0) }
        let changeToken = document.addChangeHandler { _, _ in contentChangeCount += 1 }

        document.apply([TextEdit(
            range: LSPRange(start: Position(line: 0, character: 0), end: Position(line: 0, character: 1)),
            newText: "X"
        )])
        #expect(dirtyStates == [true])
        #expect(contentChangeCount == 1)

        document.markClean()

        #expect(dirtyStates == [true, false])
        // The save changed nothing about the text, and says so.
        #expect(contentChangeCount == 1)
        _ = dirtyToken
        _ = changeToken
    }

    @Test("only transitions are reported: a second markClean and a second edit notify nobody")
    func onlyDirtyStateTransitionsAreReported() {
        let document = TextDocument(uri: "file:///transitions.txt", languageId: "plaintext", text: "abc")
        var dirtyStates: [Bool] = []
        let token = document.addDirtyStateHandler { dirtyStates.append($0) }

        document.markClean() // already clean
        #expect(dirtyStates.isEmpty)

        for character in ["X", "Y", "Z"] {
            document.apply([TextEdit(
                range: LSPRange(start: Position(line: 0, character: 0), end: Position(line: 0, character: 1)),
                newText: character
            )])
        }
        #expect(dirtyStates == [true]) // three keystrokes, one transition

        document.markClean()
        document.markClean()
        #expect(dirtyStates == [true, false])
        _ = token
    }

    @Test("replaceAll reports the clean transition to dirty-state observers")
    func replaceAllReportsCleanTransition() {
        let document = TextDocument(uri: "file:///reload.txt", languageId: "plaintext", text: "abc")
        var dirtyStates: [Bool] = []
        let token = document.addDirtyStateHandler { dirtyStates.append($0) }

        document.apply([TextEdit(
            range: LSPRange(start: Position(line: 0, character: 0), end: Position(line: 0, character: 1)),
            newText: "X"
        )])
        document.replaceAll(with: "fresh from disk")

        #expect(dirtyStates == [true, false])
        _ = token
    }

    @Test("dropping a dirty-state token stops delivery without touching change handlers")
    func droppingDirtyStateTokenStopsOnlyThatDelivery() {
        let document = TextDocument(uri: "file:///two-tokens.txt", languageId: "plaintext", text: "abc")
        var dirtyStates: [Bool] = []
        var contentChangeCount = 0
        var dirtyToken: TextDocumentObservation? = document.addDirtyStateHandler { dirtyStates.append($0) }
        let changeToken = document.addChangeHandler { _, _ in contentChangeCount += 1 }
        #expect(dirtyToken != nil)

        dirtyToken = nil

        document.apply([TextEdit(
            range: LSPRange(start: Position(line: 0, character: 0), end: Position(line: 0, character: 1)),
            newText: "X"
        )])

        #expect(dirtyStates.isEmpty)
        #expect(contentChangeCount == 1)
        _ = changeToken
    }

    // MARK: - Part 0 carried-over fixes

    @Test("apply reports the range it actually mutated, not the caller's out-of-range request")
    func applyReportsTheClampedRangeNotTheRequestedRange() {
        let document = TextDocument(uri: "file:///clamp-apply.txt", languageId: "plaintext", text: "abc")
        let requestedRange = LSPRange(start: Position(line: 0, character: 10), end: Position(line: 0, character: 20))

        let events = document.apply([TextEdit(range: requestedRange, newText: "X")])

        #expect(events.count == 1)
        let clampedRange = LSPRange(start: Position(line: 0, character: 3), end: Position(line: 0, character: 3))
        #expect(events.first?.range == clampedRange)
        #expect(events.first?.range != requestedRange)
    }

    @Test("an offset inside a surrogate pair rounds down and round-trips stably")
    func surrogatePairOffsetRoundsDownAndRoundTrips() {
        // "a😀b" — 'a' at unit 0, the emoji's surrogate pair at units 1-2, 'b' at unit 3.
        let document = TextDocument(uri: "file:///surrogate.txt", languageId: "plaintext", text: "a😀b")

        let midSurrogatePosition = document.position(forUTF16Offset: 2)
        let roundedDownPosition = Position(line: 0, character: 1)
        #expect(midSurrogatePosition == roundedDownPosition)

        let roundTrippedOffset = document.utf16Offset(for: midSurrogatePosition)
        #expect(roundTrippedOffset == 1)
        #expect(document.position(forUTF16Offset: roundTrippedOffset) == midSurrogatePosition)
    }

    @Test("an offset between a CRLF's \\r and \\n rounds down and round-trips stably")
    func crlfSplitOffsetRoundsDownAndRoundTrips() {
        // "a\r\nb" — 'a' at unit 0, '\r' at unit 1, '\n' at unit 2, 'b' at unit 3.
        let document = TextDocument(uri: "file:///crlf-split.txt", languageId: "plaintext", text: "a\r\nb")

        let midCRLFPosition = document.position(forUTF16Offset: 2)
        let roundedDownPosition = Position(line: 0, character: 1)
        #expect(midCRLFPosition == roundedDownPosition)

        let roundTrippedOffset = document.utf16Offset(for: midCRLFPosition)
        #expect(roundTrippedOffset == 1)
        #expect(document.position(forUTF16Offset: roundTrippedOffset) == midCRLFPosition)
    }

    // MARK: - The edit-application contract
    //
    // `apply(_:)` has one ordering contract with two halves: the splices run
    // back-to-front so an earlier offset stays valid, and the emitted events
    // have to describe *that* sequence, because LSP requires each change to
    // be applied to the document the previous change produced. The round-trip
    // below is the real assertion — it re-derives the server's view by
    // replaying the events onto a second document and compares it with the
    // client buffer. Per-edit unit tests cannot catch an ordering bug.

    /// Replays `events` onto a fresh document seeded with `original`, exactly
    /// as a language server applies `didChange` — one change at a time, each
    /// against the text the previous one produced.
    private func serverView(
        of original: String,
        after events: [TextDocumentContentChangeEvent]
    ) throws -> String {
        let mirror = TextDocument(uri: "file:///mirror.txt", languageId: "plaintext", text: original)
        for event in events {
            let range = try #require(event.range, "an incremental change must carry a range")
            mirror.apply([TextEdit(range: range, newText: event.text)])
        }
        return mirror.text
    }

    private func edit(
        _ startLine: Int, _ startCharacter: Int,
        _ endLine: Int, _ endCharacter: Int,
        _ newText: String
    ) -> TextEdit {
        TextEdit(
            range: LSPRange(
                start: Position(line: startLine, character: startCharacter),
                end: Position(line: endLine, character: endCharacter)
            ),
            newText: newText
        )
    }

    @Test("a batch given in ascending order replays onto the server as the same text")
    func ascendingBatchRoundTripsToTheServer() throws {
        let original = "alpha beta gamma"
        let document = TextDocument(uri: "file:///ascending.txt", languageId: "plaintext", text: original)

        // Deliberately handed to `apply` low-offset-first, which is the order
        // a formatter emits and the order that used to be echoed to the
        // server while the splices ran the other way.
        let events = document.apply([
            edit(0, 0, 0, 5, "ALPHA"),
            edit(0, 6, 0, 10, "BETA"),
            edit(0, 11, 0, 16, "GAMMA")
        ])

        #expect(document.text == "ALPHA BETA GAMMA")
        #expect(try serverView(of: original, after: events) == document.text)
    }

    @Test("co-located edits land in the caller's order, and the server agrees")
    func coLocatedEditsKeepTheCallersOrder() throws {
        let original = "foo\n"
        let document = TextDocument(uri: "file:///colocated.txt", languageId: "plaintext", text: original)

        // Three inserts at the identical offset — an opening paren, the
        // argument, the closing paren, which is how servers emit a call
        // completion. Nothing but the caller's own index distinguishes them,
        // so a non-total comparator is free to reorder them and `sorted(by:)`
        // does exactly that once the array is big enough. The array order is
        // the order the caller means the text to read in, and the assertion
        // below is that the buffer reads that way — not merely that it comes
        // out the same twice.
        let events = document.apply([
            edit(0, 3, 0, 3, "("),
            edit(0, 3, 0, 3, "bar"),
            edit(0, 3, 0, 3, ")")
        ])

        #expect(document.text == "foo(bar)\n")
        #expect(try serverView(of: original, after: events) == document.text)
    }

    @Test("a co-located insert and replacement round-trip to the server")
    func coLocatedInsertAndReplacementRoundTrip() throws {
        let original = "value = old\n"
        let document = TextDocument(uri: "file:///colocated-mixed.txt", languageId: "plaintext", text: original)

        let events = document.apply([
            edit(0, 8, 0, 8, "// "),
            edit(0, 8, 0, 11, "new")
        ])

        // The insert is declared first, so it reads first; the replacement it
        // shares a start with still consumes the three units it was given
        // rather than the text the insert put there.
        #expect(document.text == "value = // new\n")
        #expect(try serverView(of: original, after: events) == document.text)
    }

    @Test("a large scrambled batch replays onto the server as the same text")
    func largeScrambledBatchRoundTrips() throws {
        // Twenty-plus elements, because the reordering that a non-total
        // comparator permits only shows up once `sorted(by:)` switches out of
        // its small-array path.
        let original = (0..<24).map { "line \($0) here" }.joined(separator: "\n")
        let document = TextDocument(uri: "file:///scrambled.txt", languageId: "plaintext", text: original)

        var edits: [TextEdit] = []
        for line in 0..<24 {
            // Two edits per line, one of them co-located with the other's
            // start, handed over in an order that matches neither the splice
            // order nor the emission order.
            edits.append(edit(line, 0, line, 4, "LINE"))
            edits.append(edit(line, 0, line, 0, "\(line % 3)"))
        }
        edits.reverse()

        let events = document.apply(edits)

        #expect(try serverView(of: original, after: events) == document.text)
        #expect(events.count == edits.count)
    }

    @Test("an out-of-bounds edit reports the range it actually mutated")
    func clampedEditReportsTheMutatedRange() throws {
        let original = "short"
        let document = TextDocument(uri: "file:///clamped.txt", languageId: "plaintext", text: original)

        let events = document.apply([edit(0, 2, 9, 99, "!")])

        #expect(document.text == "sh!")
        #expect(try serverView(of: original, after: events) == document.text)
    }

    // MARK: - A character past a line's end stops at the terminator

    @Test("a character past the end of a line resolves before the newline, not past it")
    func characterPastLineEndStopsBeforeTheNewline() {
        // "ab\ncd" — 'a' 0, 'b' 1, '\n' 2, 'c' 3, 'd' 4.
        let document = TextDocument(uri: "file:///line-end.txt", languageId: "plaintext", text: "ab\ncd")

        // LSP's own idiom for "to the end of this line".
        #expect(document.utf16Offset(for: Position(line: 0, character: 999)) == 2)
        #expect(document.utf16Offset(for: Position(line: 1, character: 999)) == 5)
    }

    @Test("a whole-line replacement does not eat the line's newline")
    func wholeLineReplacementKeepsTheNewline() {
        let document = TextDocument(uri: "file:///whole-line.txt", languageId: "plaintext", text: "ab\ncd")

        document.apply([TextEdit(
            range: LSPRange(
                start: Position(line: 0, character: 0),
                end: Position(line: 0, character: 999)
            ),
            newText: "XY"
        )])

        #expect(document.text == "XY\ncd", "the replacement must not swallow the line terminator")
    }

    @Test("a whole-line replacement keeps a CRLF terminator intact")
    func wholeLineReplacementKeepsCRLF() {
        let document = TextDocument(uri: "file:///whole-line-crlf.txt", languageId: "plaintext", text: "ab\r\ncd")

        document.apply([TextEdit(
            range: LSPRange(
                start: Position(line: 0, character: 0),
                end: Position(line: 0, character: 999)
            ),
            newText: "XY"
        )])

        #expect(document.text == "XY\r\ncd", "neither half of the CRLF may be consumed")
    }

    @Test("a character past the end of the last line clamps to the document end")
    func characterPastTheLastLineClampsToTheEnd() {
        let document = TextDocument(uri: "file:///last-line.txt", languageId: "plaintext", text: "ab\ncd")
        #expect(document.utf16Offset(for: Position(line: 99, character: 99)) == 5)
    }
}
