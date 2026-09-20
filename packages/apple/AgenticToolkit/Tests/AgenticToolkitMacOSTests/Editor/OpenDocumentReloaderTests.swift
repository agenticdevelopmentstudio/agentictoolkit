import Foundation
import LanguageServerProtocol
import Testing
@testable import AgenticToolkitLanguage
@testable import AgenticToolkitMacOS

/// The reload path for a file that changed underneath an open buffer.
///
/// Nothing here touches FSEvents. The watcher is injected, so a test *is* the
/// filesystem event: it writes the file, then calls the handler the reloader
/// registered. Driving the real stream would mean sleeping past its 0.5 s
/// coalescing window on every case, and coalescing would then decide how many
/// times the handler ran — which is a property of FSEvents, not of this type,
/// and not one worth spending twelve seconds of suite time re-measuring.
@Suite("OpenDocumentReloader")
@MainActor
struct OpenDocumentReloaderTests {

    /// Stands in for `FileSystemWatcher`, and records the lifecycle so a test
    /// can say the watch was torn down rather than merely that it stopped
    /// producing reloads.
    @MainActor
    private final class FakeWatcher: DirectoryWatching {
        let directoryPath: String
        let handler: @Sendable ([String]) -> Void
        private(set) var startCount = 0
        private(set) var stopCount = 0

        init(directoryPath: String, handler: @escaping @Sendable ([String]) -> Void) {
            self.directoryPath = directoryPath
            self.handler = handler
        }

        func start() { startCount += 1 }
        func stop() { stopCount += 1 }
    }

    /// Every watcher the reloader asked for, in the order it asked.
    ///
    /// Main-actor isolated because `WatcherFactory` is: a non-isolated type
    /// vending a `@MainActor` closure that captures `self` is a value crossing
    /// into the actor, which strict concurrency refuses.
    @MainActor
    private final class WatcherRecorder {
        var watchers: [FakeWatcher] = []

        var factory: OpenDocumentReloader.WatcherFactory {
            { [self] path, handler in
                let watcher = FakeWatcher(directoryPath: path, handler: handler)
                watchers.append(watcher)
                return watcher
            }
        }

        func watcher(forDirectoryOf url: URL) throws -> FakeWatcher {
            let directory = url.resolvingSymlinksInPath().deletingLastPathComponent().path
            return try #require(watchers.first { $0.directoryPath == directory })
        }
    }

    /// Counts whole-file reads, which is the cost the pre-check exists to
    /// avoid. Not `Sendable` and not synchronised, because `TextReader` is
    /// called on the main actor and nowhere else — if that ever stops being
    /// true this stops compiling, which is the right failure.
    @MainActor
    private final class ReadCounter {
        private(set) var count = 0

        var reader: OpenDocumentReloader.TextReader {
            { [self] url in
                count += 1
                return try String(contentsOf: url, encoding: .utf8)
            }
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("reloader-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Delivers the event the real watcher would, and returns once the
    /// reloader's main-actor hop has run.
    ///
    /// The `Task { @MainActor }` inside the reloader is why this is `async`:
    /// the handler returns before the reload happens, so an assertion made
    /// straight after it would read the buffer one hop too early.
    private func deliver(_ url: URL, to watcher: FakeWatcher) async {
        watcher.handler([url.resolvingSymlinksInPath().path])
        await Task.yield()
    }

    // MARK: - 1. The reload itself

    /// What it catches: the whole of open item 5 — a buffer read once at open
    /// and never again, which then saves its stale text back over whatever
    /// arrived in the meantime.
    @Test("a clean buffer takes on the text that arrived on disk")
    func cleanBufferReloads() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Reloaded.swift")
        try write("original", to: file)

        let store = TextDocumentStore()
        let recorder = WatcherRecorder()
        let reloader = OpenDocumentReloader(store: store, makeWatcher: recorder.factory)
        reloader.start()

        let document = store.open(uri: file.documentUri, languageId: "swift", text: "original")
        let versionBeforeReload = document.version

        try write("from somewhere else", to: file)
        await deliver(file, to: try recorder.watcher(forDirectoryOf: file))

        #expect(document.text == "from somewhere else")
        // A new version, not a silent substitution: every observer — language
        // servers included — is told, which is the difference between the
        // buffer being right and everything downstream being right.
        #expect(document.version > versionBeforeReload)
        // And clean: what the buffer holds is what the file holds, so there is
        // nothing unsaved about it.
        #expect(document.isDirty == false)
    }

    /// What it catches: a reloader that reacts to the event rather than to the
    /// content. Every save this app makes comes straight back through the
    /// watcher, so one that did not compare would answer each autosave with a
    /// fresh version, a full-text `didChange` to every language server, and a
    /// reset selection.
    @Test("a save echoing back changes nothing")
    func identicalDiskTextIsNotAReload() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Echo.swift")
        try write("same", to: file)

        let store = TextDocumentStore()
        let recorder = WatcherRecorder()
        let reloader = OpenDocumentReloader(store: store, makeWatcher: recorder.factory)
        reloader.start()

        let document = store.open(uri: file.documentUri, languageId: "swift", text: "same")
        var changeCount = 0
        // Retained: the token is what keeps the handler registered, so an
        // `_ =` here would make the assertion below pass unconditionally.
        let observation = document.addChangeHandler { _, _ in changeCount += 1 }
        let versionBefore = document.version

        await deliver(file, to: try recorder.watcher(forDirectoryOf: file))

        #expect(document.version == versionBefore)
        #expect(changeCount == 0)
        withExtendedLifetime(observation) {}
    }

    // MARK: - 2. Refusing to destroy work

    /// What it catches: the obvious implementation, which reloads whenever the
    /// disk and the buffer differ. That is exactly the case where they differ
    /// *because the user has been typing*, and reloading discards the typing
    /// with no undo — a worse outcome than the staleness the reload cures.
    @Test("a dirty buffer is left alone")
    func dirtyBufferIsNotClobbered() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Editing.swift")
        try write("original", to: file)

        let store = TextDocumentStore()
        let recorder = WatcherRecorder()
        let reloader = OpenDocumentReloader(store: store, makeWatcher: recorder.factory)
        reloader.start()

        let document = store.open(uri: file.documentUri, languageId: "swift", text: "original")
        // Through `apply(_:)`, the ordinary edit path: it is what raises the
        // dirty flag, and a test-only setter on the production type would be
        // testing the setter.
        document.apply([TextEdit(
            range: LSPRange(
                start: Position(line: 0, character: 0),
                end: Position(line: 0, character: 8)
            ),
            newText: "what the user typed"
        )])
        #expect(document.isDirty)

        try write("from somewhere else", to: file)
        await deliver(file, to: try recorder.watcher(forDirectoryOf: file))

        #expect(document.text == "what the user typed")
    }

    /// What it catches: a reader whose failure path empties the buffer. An
    /// open editor over a deleted file is ordinary — a branch switch — and the
    /// buffer is then the only copy of the text that exists.
    @Test("a deleted file leaves the buffer intact")
    func deletedFileLeavesTheBufferAlone() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Doomed.swift")
        try write("still here", to: file)

        let store = TextDocumentStore()
        let recorder = WatcherRecorder()
        let reloader = OpenDocumentReloader(store: store, makeWatcher: recorder.factory)
        reloader.start()

        let document = store.open(uri: file.documentUri, languageId: "swift", text: "still here")
        try FileManager.default.removeItem(at: file)
        await deliver(file, to: try recorder.watcher(forDirectoryOf: file))

        #expect(document.text == "still here")
    }

    // MARK: - 3. Which files are watched

    /// What it catches: matching on the directory instead of on the file. The
    /// watch is necessarily on the parent directory, so every sibling's events
    /// arrive too — and a reloader that acted on them would read files nobody
    /// has open.
    @Test("an event for a sibling nobody has open is ignored")
    func siblingChangesAreIgnored() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let opened = directory.appendingPathComponent("Open.swift")
        let sibling = directory.appendingPathComponent("Sibling.swift")
        try write("open", to: opened)
        try write("sibling", to: sibling)

        let store = TextDocumentStore()
        let recorder = WatcherRecorder()
        let reloader = OpenDocumentReloader(store: store, makeWatcher: recorder.factory)
        reloader.start()

        let document = store.open(uri: opened.documentUri, languageId: "swift", text: "open")
        var changeCount = 0
        let observation = document.addChangeHandler { _, _ in changeCount += 1 }

        try write("sibling edited", to: sibling)
        await deliver(sibling, to: try recorder.watcher(forDirectoryOf: opened))

        #expect(changeCount == 0)
        #expect(document.text == "open")
        withExtendedLifetime(observation) {}
    }

    /// What it catches: one FSEvent stream per open tab. Two files from one
    /// directory is the ordinary case, and a second stream over the same
    /// directory is a kernel resource for no additional information.
    @Test("two documents in one directory share a single watcher, released only when both close")
    func oneWatcherPerDirectory() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("First.swift")
        let second = directory.appendingPathComponent("Second.swift")
        try write("first", to: first)
        try write("second", to: second)

        let store = TextDocumentStore()
        let recorder = WatcherRecorder()
        let reloader = OpenDocumentReloader(store: store, makeWatcher: recorder.factory)
        reloader.start()

        _ = store.open(uri: first.documentUri, languageId: "swift", text: "first")
        _ = store.open(uri: second.documentUri, languageId: "swift", text: "second")
        #expect(recorder.watchers.count == 1)

        let watcher = try recorder.watcher(forDirectoryOf: first)
        #expect(watcher.startCount == 1)

        store.close(uri: first.documentUri)
        // One document still open under it: stopping here would leave that one
        // unwatched, which is the bug this refcount exists to prevent.
        #expect(watcher.stopCount == 0)

        store.close(uri: second.documentUri)
        #expect(watcher.stopCount == 1)
    }

    /// What it catches: a reloader that only ever hears about documents opened
    /// after it started. The editor can perfectly well have opened a file
    /// before anything constructed this, and that file would then never be
    /// watched at all.
    @Test("a document already open when start() runs is watched")
    func alreadyOpenDocumentsAreSeeded() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Early.swift")
        try write("original", to: file)

        let store = TextDocumentStore()
        let document = store.open(uri: file.documentUri, languageId: "swift", text: "original")

        let recorder = WatcherRecorder()
        let reloader = OpenDocumentReloader(store: store, makeWatcher: recorder.factory)
        reloader.start()

        try write("changed before anyone was listening", to: file)
        await deliver(file, to: try recorder.watcher(forDirectoryOf: file))

        #expect(document.text == "changed before anyone was listening")
    }

    /// What it catches: `stop()` unsubscribing without tearing the watchers
    /// down, which leaves live FSEvent streams behind after the coordinator
    /// has finished with them.
    @Test("stop() releases every watcher")
    func stopReleasesWatchers() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Stopped.swift")
        try write("original", to: file)

        let store = TextDocumentStore()
        let recorder = WatcherRecorder()
        let reloader = OpenDocumentReloader(store: store, makeWatcher: recorder.factory)
        reloader.start()
        let document = store.open(uri: file.documentUri, languageId: "swift", text: "original")

        reloader.stop()
        let watcher = try recorder.watcher(forDirectoryOf: file)
        #expect(watcher.stopCount == 1)

        // And no longer reloading: the handler is still reachable from the
        // test, so this is the reloader refusing rather than the event failing
        // to arrive.
        try write("after the stop", to: file)
        await deliver(file, to: watcher)
        #expect(document.text == "original")
    }

    // MARK: - 6. Not reading the file

    /// What it catches: a reload path that answers "did the bytes change?" by
    /// reading every byte, on the actor drawing the window.
    ///
    /// The watcher is created with `kFSEventStreamCreateFlagFileEvents`, which
    /// reports metadata as readily as content — a chmod, an xattr written by
    /// Spotlight or a Finder tag, the ownership change a restore makes — and
    /// coalescing means one write can arrive as several callbacks. Every one
    /// of those used to be a full synchronous read of a file that is byte for
    /// byte what it was, and on a branch switch that is once per open document
    /// in the tree.
    @Test("a second event for a file that did not change reads nothing")
    func anUnchangedFileIsNotReadTwice() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Quiet.swift")
        try write("original", to: file)

        let store = TextDocumentStore()
        let recorder = WatcherRecorder()
        let counter = ReadCounter()
        let reloader = OpenDocumentReloader(
            store: store, makeWatcher: recorder.factory, readText: counter.reader)
        reloader.start()
        _ = store.open(uri: file.documentUri, languageId: "swift", text: "original")

        let watcher = try recorder.watcher(forDirectoryOf: file)
        await deliver(file, to: watcher)
        let afterFirst = counter.count
        await deliver(file, to: watcher)
        await deliver(file, to: watcher)

        // The first event has nothing to compare against and reads; every
        // event after it finds the same size and the same modification date
        // and stops there.
        #expect(afterFirst == 1)
        #expect(counter.count == 1)
    }

    /// And the gate is a gate, not a latch: a file that really did change is
    /// read again and reloaded.
    @Test("a file that changed since the last read is read again")
    func aChangedFileIsReadAgain() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Changing.swift")
        try write("original", to: file)

        let store = TextDocumentStore()
        let recorder = WatcherRecorder()
        let counter = ReadCounter()
        let reloader = OpenDocumentReloader(
            store: store, makeWatcher: recorder.factory, readText: counter.reader)
        reloader.start()
        let document = store.open(uri: file.documentUri, languageId: "swift", text: "original")

        let watcher = try recorder.watcher(forDirectoryOf: file)
        await deliver(file, to: watcher)

        try write("from somewhere else, and longer", to: file)
        await deliver(file, to: watcher)

        #expect(counter.count == 2)
        #expect(document.text == "from somewhere else, and longer")
    }

    /// What it catches: a stamp kept across a deletion. The file that comes
    /// back may be the same length at the same second — a branch switched away
    /// and back — and a reloader that still believed the old stamp would leave
    /// the buffer showing the other branch's text forever.
    @Test("a file that went away is read again when it returns")
    func aDeletedFileForgetsItsStamp() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Vanishing.swift")
        try write("original", to: file)

        let store = TextDocumentStore()
        let recorder = WatcherRecorder()
        let counter = ReadCounter()
        let reloader = OpenDocumentReloader(
            store: store, makeWatcher: recorder.factory, readText: counter.reader)
        reloader.start()
        let document = store.open(uri: file.documentUri, languageId: "swift", text: "original")

        let watcher = try recorder.watcher(forDirectoryOf: file)
        await deliver(file, to: watcher)
        #expect(counter.count == 1)

        let stampBefore = try #require(
            FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date)
        try FileManager.default.removeItem(at: file)
        await deliver(file, to: watcher)
        // The buffer is the only copy now, and it keeps what it had.
        #expect(document.text == "original")

        // Restored with exactly the stamp it had before it went: "restored" is
        // the same eight bytes long as "original", and the modification date
        // is put back by hand. Nothing short of having noticed the deletion
        // can tell this from the file that was there.
        try write("restored", to: file)
        try FileManager.default.setAttributes(
            [.modificationDate: stampBefore], ofItemAtPath: file.path)
        await deliver(file, to: watcher)
        #expect(counter.count == 2)
        #expect(document.text == "restored")
    }
}
