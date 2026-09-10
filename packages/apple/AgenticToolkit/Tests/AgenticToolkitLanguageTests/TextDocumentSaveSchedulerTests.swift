import Foundation
import Testing
import LanguageServerProtocol
@testable import AgenticToolkitLanguage

/// Every test here injects a recording writer — none of them writes a real
/// file. A short debounce keeps the suite fast; timing is driven by
/// `Task.sleep` rather than wall-clock assumptions.
@Suite("TextDocumentSaveScheduler")
@MainActor
struct TextDocumentSaveSchedulerTests {

    private static let testDebounce: Duration = .milliseconds(50)

    /// Long enough to be confident the debounce has elapsed and the write
    /// task has run, short enough to keep the suite fast.
    private static let settleDelay: Duration = .milliseconds(200)

    /// Records every URI it was asked to write, in order, and its calls can
    /// be made to throw for a given URI to exercise the failure path.
    ///
    /// `@MainActor` because `write(_:)` reads `document.uri`, a property of a
    /// `@MainActor` type — and because the scheduler's `write` parameter is
    /// itself `@MainActor`, so a nonisolated bound method wouldn't satisfy it.
    @MainActor
    private final class RecordingWriter {
        private(set) var writtenURIs: [DocumentUri] = []
        var urisThatThrow: Set<DocumentUri> = []

        func write(_ document: TextDocument) throws {
            if urisThatThrow.contains(document.uri) {
                throw WriteError.injected
            }
            writtenURIs.append(document.uri)
        }
    }

    private enum WriteError: Error {
        case injected
    }

    private func makeDirtyDocument(uri: DocumentUri, text: String = "content") -> TextDocument {
        let document = TextDocument(uri: uri, languageId: "plaintext", text: "")
        document.apply([TextEdit(
            range: LSPRange(start: Position(line: 0, character: 0), end: Position(line: 0, character: 0)),
            newText: text
        )])
        return document
    }

    @Test("ten schedule calls inside the debounce window produce exactly one write")
    func tenSchedulesInsideDebounceProduceOneWrite() async throws {
        let writer = RecordingWriter()
        let scheduler = TextDocumentSaveScheduler(debounce: Self.testDebounce, write: writer.write)
        let document = makeDirtyDocument(uri: "file:///ten-schedules.txt")

        for _ in 0..<10 {
            scheduler.schedule(document)
            try await Task.sleep(for: .milliseconds(5))
        }

        try await Task.sleep(for: Self.settleDelay)

        #expect(writer.writtenURIs == ["file:///ten-schedules.txt"])
        #expect(document.isDirty == false)
    }

    @Test("flushPendingSaves writes each of three pending documents exactly once")
    func flushWritesEachPendingDocumentOnce() async {
        let writer = RecordingWriter()
        let scheduler = TextDocumentSaveScheduler(debounce: .seconds(60), write: writer.write)
        let first = makeDirtyDocument(uri: "file:///flush-a.txt")
        let second = makeDirtyDocument(uri: "file:///flush-b.txt")
        let third = makeDirtyDocument(uri: "file:///flush-c.txt")

        scheduler.schedule(first)
        scheduler.schedule(second)
        scheduler.schedule(third)

        await scheduler.flushPendingSaves()

        #expect(Set(writer.writtenURIs) == Set([first.uri, second.uri, third.uri]))
        #expect(writer.writtenURIs.count == 3)
        #expect(scheduler.pendingURIs.isEmpty)
    }

    @Test("a throwing writer leaves the document dirty; a succeeding one leaves it clean")
    func throwingWriterLeavesDocumentDirty() async throws {
        let writer = RecordingWriter()
        let failingDocument = makeDirtyDocument(uri: "file:///failing.txt")
        writer.urisThatThrow.insert(failingDocument.uri)
        let succeedingDocument = makeDirtyDocument(uri: "file:///succeeding.txt")

        let scheduler = TextDocumentSaveScheduler(debounce: Self.testDebounce, write: writer.write)
        scheduler.schedule(failingDocument)
        scheduler.schedule(succeedingDocument)

        try await Task.sleep(for: Self.settleDelay)

        #expect(failingDocument.isDirty == true)
        #expect(succeedingDocument.isDirty == false)
        #expect(writer.writtenURIs == [succeedingDocument.uri])
    }

    // MARK: - A failed write does not lose the edit
    //
    // The scheduler used to remove the document from its pending map *before*
    // attempting the write and only log on failure. A full disk, a revoked
    // network volume or a file gone read-only therefore dropped the edit on
    // the floor: nothing re-armed, nothing re-inserted it, and the
    // termination flush reported success over an empty map. These two tests
    // fail against that shape.

    @Test("a write that throws leaves the document pending, so the edit is not lost")
    func failedWriteLeavesTheDocumentPending() async throws {
        let writer = RecordingWriter()
        let document = makeDirtyDocument(uri: "file:///disk-full.txt", text: "the user's work")
        writer.urisThatThrow.insert(document.uri)

        let scheduler = TextDocumentSaveScheduler(debounce: Self.testDebounce, write: writer.write)
        scheduler.schedule(document)
        try await Task.sleep(for: Self.settleDelay)

        #expect(writer.writtenURIs.isEmpty)
        #expect(document.isDirty, "a write that never landed must not mark the buffer clean")
        #expect(
            scheduler.pendingURIs == [document.uri],
            "a failed write must leave something for the next flush to retry"
        )
        #expect(document.text == "the user's work")
    }

    @Test("the edit survives a failed write and reaches disk on a later successful flush")
    func failedWriteIsRetriedByALaterFlush() async throws {
        let writer = RecordingWriter()
        let document = makeDirtyDocument(uri: "file:///comes-back.txt", text: "the user's work")
        writer.urisThatThrow.insert(document.uri)

        let scheduler = TextDocumentSaveScheduler(debounce: Self.testDebounce, write: writer.write)
        scheduler.schedule(document)
        try await Task.sleep(for: Self.settleDelay)
        #expect(writer.writtenURIs.isEmpty)

        // The volume comes back — a reconnected share, or the user freeing
        // space — and the app is now quitting.
        writer.urisThatThrow.remove(document.uri)
        let stillUnsaved = await scheduler.flushPendingSaves()

        #expect(writer.writtenURIs == [document.uri])
        #expect(document.isDirty == false)
        #expect(stillUnsaved.isEmpty)
        #expect(scheduler.pendingURIs.isEmpty)
    }

    @Test("flushPendingSaves names the documents whose write still failed")
    func flushReportsDocumentsThatStillFailed() async {
        let writer = RecordingWriter()
        let saved = makeDirtyDocument(uri: "file:///saved.txt")
        let lost = makeDirtyDocument(uri: "file:///still-failing.txt")
        writer.urisThatThrow.insert(lost.uri)

        let scheduler = TextDocumentSaveScheduler(debounce: .seconds(60), write: writer.write)
        scheduler.schedule(saved)
        scheduler.schedule(lost)

        let stillUnsaved = await scheduler.flushPendingSaves()

        #expect(stillUnsaved == [lost.uri])
        #expect(writer.writtenURIs == [saved.uri])
    }

    @Test("a write that suspends while the user types again does not mark the buffer clean")
    func typingDuringASuspendedWriteKeepsTheDocumentDirty() async throws {
        let document = makeDirtyDocument(uri: "file:///still-typing.txt", text: "one")
        var released: (@MainActor () -> Void)?
        let scheduler = TextDocumentSaveScheduler(debounce: Self.testDebounce) { _ in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                released = { continuation.resume() }
            }
        }

        scheduler.schedule(document)
        try await Task.sleep(for: .milliseconds(120))
        #expect(released != nil, "the write should be suspended by now")

        // The user types while the bytes are still on their way to the disk.
        document.apply([TextEdit(
            range: LSPRange(
                start: Position(line: 0, character: 3),
                end: Position(line: 0, character: 3)
            ),
            newText: " two"
        )])
        released?()
        try await Task.sleep(for: .milliseconds(120))

        #expect(document.isDirty, "the buffer is newer than the file that was just written")
        #expect(document.text == "one two")
    }

    @Test("cancel before the debounce elapses produces no write at all")
    func cancelBeforeDebounceProducesNoWrite() async throws {
        let writer = RecordingWriter()
        let scheduler = TextDocumentSaveScheduler(debounce: Self.testDebounce, write: writer.write)
        let document = makeDirtyDocument(uri: "file:///cancelled.txt")

        scheduler.schedule(document)
        scheduler.cancel(uri: document.uri)

        try await Task.sleep(for: Self.settleDelay)

        #expect(writer.writtenURIs.isEmpty)
        #expect(scheduler.pendingURIs.isEmpty)
    }

    @Test("schedule on a clean document produces no write")
    func scheduleOnCleanDocumentProducesNoWrite() async throws {
        let writer = RecordingWriter()
        let scheduler = TextDocumentSaveScheduler(debounce: Self.testDebounce, write: writer.write)
        let cleanDocument = TextDocument(uri: "file:///clean.txt", languageId: "plaintext", text: "already saved")
        #expect(cleanDocument.isDirty == false)

        scheduler.schedule(cleanDocument)

        try await Task.sleep(for: Self.settleDelay)

        #expect(writer.writtenURIs.isEmpty)
        #expect(scheduler.pendingURIs.isEmpty)
    }

    @Test("flushPendingSaves with nothing pending completes without writing")
    func flushWithNothingPendingCompletesWithoutWriting() async {
        let writer = RecordingWriter()
        let scheduler = TextDocumentSaveScheduler(debounce: Self.testDebounce, write: writer.write)

        await scheduler.flushPendingSaves()

        #expect(writer.writtenURIs.isEmpty)
    }

    // MARK: - Per-URI flush
    //
    // The scheduler is one instance for the whole app, so a file switch must
    // be able to write out the file being switched away from *without*
    // writing every other window's dirty documents at the same time.

    @Test("flushPendingSave writes only the named document and leaves the rest pending")
    func perURIFlushWritesOnlyThatDocument() async {
        let writer = RecordingWriter()
        let scheduler = TextDocumentSaveScheduler(debounce: Self.testDebounce, write: writer.write)
        let outgoing = makeDirtyDocument(uri: "file:///outgoing.txt")
        let otherWindow = makeDirtyDocument(uri: "file:///other-window.txt")
        let alsoOther = makeDirtyDocument(uri: "file:///also-other.txt")

        scheduler.schedule(outgoing)
        scheduler.schedule(otherWindow)
        scheduler.schedule(alsoOther)

        await scheduler.flushPendingSave(uri: "file:///outgoing.txt")

        #expect(writer.writtenURIs == ["file:///outgoing.txt"])
        #expect(outgoing.isDirty == false)
        #expect(otherWindow.isDirty)
        #expect(alsoOther.isDirty)
        #expect(Set(scheduler.pendingURIs) == ["file:///other-window.txt", "file:///also-other.txt"])
    }

    @Test("flushPendingSave then the elapsed debounce still writes only once")
    func perURIFlushDoesNotRaceItsOwnPendingTask() async throws {
        let writer = RecordingWriter()
        let scheduler = TextDocumentSaveScheduler(debounce: Self.testDebounce, write: writer.write)
        let document = makeDirtyDocument(uri: "file:///flush-once.txt")

        scheduler.schedule(document)
        await scheduler.flushPendingSave(uri: "file:///flush-once.txt")
        try await Task.sleep(for: Self.settleDelay)

        #expect(writer.writtenURIs == ["file:///flush-once.txt"])
    }

    @Test("flushPendingSave for a uri with nothing pending writes nothing")
    func perURIFlushOfUnknownURIWritesNothing() async {
        let writer = RecordingWriter()
        let scheduler = TextDocumentSaveScheduler(debounce: Self.testDebounce, write: writer.write)
        let document = makeDirtyDocument(uri: "file:///still-typing.txt")
        scheduler.schedule(document)

        await scheduler.flushPendingSave(uri: "file:///never-scheduled.txt")

        #expect(writer.writtenURIs.isEmpty)
        #expect(scheduler.pendingURIs == ["file:///still-typing.txt"])
    }
}
