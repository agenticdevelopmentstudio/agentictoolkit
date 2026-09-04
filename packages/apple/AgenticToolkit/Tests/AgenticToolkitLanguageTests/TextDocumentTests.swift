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
}
