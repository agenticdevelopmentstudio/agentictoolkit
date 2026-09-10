import AppKit
import Foundation
import Testing
import LanguageServerProtocol
@testable import AgenticToolkitLanguage
@testable import AgenticToolkitMacOS

/// Exercises both directions of the `TextDocument` <-> `TextDocumentStorage`
/// bridge, plus the reentrancy guard that keeps them from looping into each
/// other. `externalChangeApplicationCount` is `internal`, reachable here only
/// because this file `@testable import`s `AgenticToolkitMacOS`.
@Suite("TextDocumentStorage")
@MainActor
struct TextDocumentStorageTests {

    private func makeStorage(text: String = "") -> (storage: TextDocumentStorage, document: TextDocument) {
        let document = TextDocument(uri: "file:///storage-test.txt", languageId: "plaintext", text: text)
        let storage = TextDocumentStorage(document: document)
        return (storage, document)
    }

    @Test("typing through replaceCharacters updates storage and document identically, and bumps version")
    func typingUpdatesBothAndBumpsVersion() {
        let (storage, document) = makeStorage(text: "hello world")
        let versionBefore = document.version

        storage.replaceCharacters(in: NSRange(location: 5, length: 0), with: ",")

        #expect(storage.string == "hello, world")
        #expect(document.text == "hello, world")
        #expect(document.version == versionBefore + 1)
    }

    @Test("an insert in the middle of a multi-line document lands at the right offset in both")
    func midDocumentInsertLandsAtCorrectOffset() {
        let (storage, document) = makeStorage(text: "line one\nline two\nline three")

        // "line two" starts at UTF-16 offset 9; insert "TWO " right before it.
        storage.replaceCharacters(in: NSRange(location: 9, length: 0), with: "TWO ")

        let expected = "line one\nTWO line two\nline three"
        #expect(storage.string == expected)
        #expect(document.text == expected)
    }

    @Test("a multi-byte emoji insert keeps storage.string and document.text identical")
    func emojiInsertKeepsStorageAndDocumentIdentical() {
        let (storage, document) = makeStorage(text: "ab")

        // Insert between 'a' and 'b' — exercises a UTF-16-vs-Character offset
        // mistake, since an emoji like this one is two UTF-16 code units.
        storage.replaceCharacters(in: NSRange(location: 1, length: 0), with: "🎉")

        #expect(storage.string == "a🎉b")
        #expect(document.text == "a🎉b")
        #expect(storage.string.utf16.count == (storage.string as NSString).length)
    }

    @Test("a document changed from outside via replaceAll updates storage.string")
    func externalReplaceAllUpdatesStorage() {
        let (storage, document) = makeStorage(text: "original")

        document.replaceAll(with: "replaced entirely")

        #expect(storage.string == "replaced entirely")
    }

    @Test("a local edit through the storage does not re-enter the external-change handler")
    func localEditDoesNotReenterExternalHandler() {
        let (storage, document) = makeStorage(text: "hello")

        storage.replaceCharacters(in: NSRange(location: 5, length: 0), with: " world")

        #expect(document.text == "hello world")
        #expect(storage.externalChangeApplicationCount == 0)
    }

    @Test("an external change after local edits is still observed exactly once")
    func externalChangeAfterLocalEditsIsObservedOnce() {
        let (storage, document) = makeStorage(text: "hello")

        storage.replaceCharacters(in: NSRange(location: 5, length: 0), with: " world")
        #expect(storage.externalChangeApplicationCount == 0)

        document.replaceAll(with: "from outside")
        #expect(storage.externalChangeApplicationCount == 1)
        #expect(storage.string == "from outside")
    }

    @Test("changeInLength is correct for an insert")
    func changeInLengthCorrectForInsert() {
        let (storage, _) = makeStorage(text: "hello")

        storage.replaceCharacters(in: NSRange(location: 5, length: 0), with: " world")

        #expect(storage.length == (storage.string as NSString).length)
        #expect(storage.string.utf16.count == storage.length)
    }

    @Test("changeInLength is correct for a delete")
    func changeInLengthCorrectForDelete() {
        let (storage, _) = makeStorage(text: "hello world")

        storage.replaceCharacters(in: NSRange(location: 5, length: 6), with: "")

        #expect(storage.string == "hello")
        #expect(storage.length == (storage.string as NSString).length)
        #expect(storage.string.utf16.count == storage.length)
    }

    @Test("changeInLength is correct for a replace of different length")
    func changeInLengthCorrectForReplace() {
        let (storage, _) = makeStorage(text: "hello world")

        storage.replaceCharacters(in: NSRange(location: 6, length: 5), with: "there, friend")

        #expect(storage.string == "hello there, friend")
        #expect(storage.length == (storage.string as NSString).length)
        #expect(storage.string.utf16.count == storage.length)
    }

    // MARK: - The document is current before anyone is notified

    /// Captures what `document` looked like from inside the storage's own
    /// edit notification.
    ///
    /// A class rather than captured `var`s because the notification block is
    /// `@Sendable`; this is `@MainActor`, so it is implicitly `Sendable` and
    /// its fields can be written from inside `MainActor.assumeIsolated`.
    @MainActor
    private final class EditObserver {
        private(set) var text: String?
        private(set) var wholeLine: NSRange?

        func record(_ document: TextDocument) {
            text = document.text
            wholeLine = document.nsRange(for: LSPRange(
                start: Position(line: 0, character: 0),
                end: Position(line: 0, character: 9_999)
            ))
        }
    }

    /// What it catches: an `apply` that happens *after* `edited(...)`.
    /// `edited(_:range:changeInLength:)` runs `processEditing()` synchronously
    /// and notifies every layout manager and text-storage observer, and those
    /// observers — the annotation coordinator, the hover controller, the
    /// highlight provider — convert ranges through `document`. With the apply
    /// afterwards they each saw the pre-edit text while the backing store
    /// already held the post-edit one, so every conversion was one edit behind
    /// and clamped against the shorter old length near the end of the buffer.
    @Test("an observer notified during the edit sees the document already updated")
    func observerDuringEditSeesTheUpdatedDocument() {
        let (storage, document) = makeStorage(text: "hello world")
        let observer = EditObserver()
        let token = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification,
            object: storage,
            queue: nil
        ) { _ in
            MainActor.assumeIsolated { observer.record(document) }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        storage.replaceCharacters(in: NSRange(location: 5, length: 0), with: ", dear")

        #expect(observer.text == "hello, dear world")
        #expect(
            observer.wholeLine == NSRange(location: 0, length: 17),
            "a conversion made during the notification must use the post-edit length"
        )
        #expect(storage.string == "hello, dear world")
    }

    /// The narrowed guard must still do its one job: `apply` fires the
    /// document's change handler synchronously, and Direction 2 must not
    /// rewrite the buffer the user is typing into.
    @Test("typing still does not re-enter the external-change path")
    func typingDoesNotReenterTheExternalPath() {
        let (storage, _) = makeStorage(text: "hello world")
        let before = storage.externalChangeApplicationCount

        storage.replaceCharacters(in: NSRange(location: 5, length: 0), with: ", dear")

        #expect(storage.externalChangeApplicationCount == before)
    }
}
