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
}
