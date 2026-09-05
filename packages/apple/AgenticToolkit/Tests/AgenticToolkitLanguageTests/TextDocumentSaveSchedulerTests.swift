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
