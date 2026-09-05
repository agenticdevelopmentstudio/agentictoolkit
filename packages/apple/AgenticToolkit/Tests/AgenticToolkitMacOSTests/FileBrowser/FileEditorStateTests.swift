import AppKit
import Foundation
import SwiftUI
import Testing
import LanguageServerProtocol
@testable import AgenticToolkitLanguage
@testable import AgenticToolkitMacOS

/// A stand-in for a real `SourceEditor`. Deliberately trivial: what these
/// tests assert about the stack is object identity and `isHidden`, neither of
/// which depends on what the hosted view draws.
private func makeClearEditor(_: DocumentUri) -> AnyView {
    AnyView(Color.clear)
}

/// Stands in for whichever view happens to hold the caret. The focus rules in
/// `CachedEditorStackView.sync` turn only on whether the window's first
/// responder is a descendant of the stack, so a bare focusable view is a
/// truthful stand-in for both an editor's text view and the file tree.
private final class FocusableProbeView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

/// The behaviours the file editor's document model exists for, none of which a
/// compile can show: that a cached document survives the selection leaving it
/// and coming back, that the cache is bounded, that a pane releasing a
/// document *writes* it rather than dropping it, and that the outgoing file is
/// on disk before the incoming one is opened.
@Suite("FileEditorState")
@MainActor
struct FileEditorStateTests {

    /// Records what was written, in order, so a test can assert ordering
    /// against other observed events rather than only that a write happened.
    @MainActor
    private final class RecordingWriter {
        private(set) var events: [String] = []

        func write(_ document: TextDocument) throws {
            events.append("write:\(document.uri)")
        }

        func record(_ event: String) {
            events.append(event)
        }
    }

    /// Long enough for a `Task` spawned by an eviction or a deinit to have run.
    private static let settleDelay: Duration = .milliseconds(200)

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileEditorStateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFile(in directory: URL, named name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try "let x = 1\n".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Types into the document the way the text view does — through its
    /// storage — so the pane's own change handler fires and the autosave
    /// scheduler really is given something pending.
    private func typeText(_ text: String, into storage: TextDocumentStorage) {
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)
    }

    // MARK: - The cache survives a nil selection

    /// The claim finding 2 was about: selecting a directory (or nothing) must
    /// not throw the open editors away, because remounting a `SourceEditor`
    /// re-runs `setTextStorage`, which unconditionally clears the undo stack.
    ///
    /// A test target cannot mount the real SwiftUI hierarchy and ask a live
    /// `TextViewController` for its identity, so this asserts the layer
    /// directly under it: the cache entry — the `TextDocument` and the
    /// `TextDocumentStorage` the editor was built around — is the *same
    /// object* after the round trip, and is still listed for mounting. What
    /// the view does with that list is asserted in `CachedEditorStackViewTests`.
    @Test("a cached document survives selecting a directory and coming back, as the same objects")
    func cachedDocumentSurvivesEmptySelection() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = try makeFile(in: directory, named: "A.swift")
        let uri = fileURL.documentUri

        let writer = RecordingWriter()
        let store = TextDocumentStore()
        let scheduler = TextDocumentSaveScheduler(debounce: .seconds(60), write: writer.write)
        let state = FileEditorState(documentStore: store, saveScheduler: scheduler)

        state.load(from: fileURL)
        await state.awaitPendingLoad()
        #expect(state.display == .text(uri: uri))
        let storage = try #require(state.storage(for: uri))
        let document = try #require(state.document(for: uri))

        // The user clicks the enclosing folder.
        state.unload()
        #expect(state.display == .empty)
        #expect(state.storage(for: uri) === storage)
        #expect(state.document(for: uri) === document)
        #expect(state.openOrder == [uri])

        // …and clicks the file again.
        state.load(from: fileURL)
        await state.awaitPendingLoad()
        #expect(state.display == .text(uri: uri))
        #expect(state.storage(for: uri) === storage)
        #expect(state.document(for: uri) === document)
        #expect(state.openOrder == [uri])
        #expect(store.document(for: uri) === document)
    }

    @Test("switching to a second file and back keeps both documents and reuses the first")
    func switchingBetweenTwoFilesReusesBoth() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileA = try makeFile(in: directory, named: "A.swift")
        let fileB = try makeFile(in: directory, named: "B.swift")

        let writer = RecordingWriter()
        let store = TextDocumentStore()
        let scheduler = TextDocumentSaveScheduler(debounce: .seconds(60), write: writer.write)
        let state = FileEditorState(documentStore: store, saveScheduler: scheduler)

        state.load(from: fileA)
        await state.awaitPendingLoad()
        let storageA = try #require(state.storage(for: fileA.documentUri))

        state.load(from: fileB)
        await state.awaitPendingLoad()
        #expect(state.display == .text(uri: fileB.documentUri))

        state.load(from: fileA)
        await state.awaitPendingLoad()
        #expect(state.display == .text(uri: fileA.documentUri))
        #expect(state.storage(for: fileA.documentUri) === storageA)
        #expect(state.openOrder == [fileA.documentUri, fileB.documentUri])
    }

    // MARK: - The cache is bounded

    @Test("the file past the bound evicts the least recently selected one and releases it")
    func cacheIsBoundedAndEvictsLeastRecentlySelected() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let writer = RecordingWriter()
        let store = TextDocumentStore()
        let scheduler = TextDocumentSaveScheduler(debounce: .seconds(60), write: writer.write)
        let state = FileEditorState(documentStore: store, saveScheduler: scheduler)

        let bound = FileEditorState.maximumCachedDocuments
        var urls: [URL] = []
        for index in 0...bound {
            let url = try makeFile(in: directory, named: "File\(index).swift")
            urls.append(url)
            state.load(from: url)
            await state.awaitPendingLoad()
        }

        #expect(state.openOrder.count == bound)
        // The first file visited is the least recently selected, so it goes.
        #expect(state.storage(for: urls[0].documentUri) == nil)
        #expect(state.openOrder.contains(urls[0].documentUri) == false)
        #expect(state.openOrder.contains(urls[bound].documentUri))

        // Its reference on the shared store is released too — a tick later,
        // because releasing flushes first and a flush is async.
        try await Task.sleep(for: Self.settleDelay)
        #expect(store.document(for: urls[0].documentUri) == nil)
        #expect(store.document(for: urls[bound].documentUri) != nil)
    }

    @Test("an evicted document's pending save is written, not cancelled")
    func evictionFlushesRatherThanCancels() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let writer = RecordingWriter()
        let store = TextDocumentStore()
        let scheduler = TextDocumentSaveScheduler(debounce: .seconds(60), write: writer.write)
        let state = FileEditorState(documentStore: store, saveScheduler: scheduler)

        let firstURL = try makeFile(in: directory, named: "First.swift")
        state.load(from: firstURL)
        await state.awaitPendingLoad()
        let firstStorage = try #require(state.storage(for: firstURL.documentUri))

        let secondURL = try makeFile(in: directory, named: "Second.swift")
        state.load(from: secondURL)
        await state.awaitPendingLoad()

        // Edited while it is *not* the selected file, so the flush-before-open
        // path cannot be what writes it — only eviction can.
        typeText("edited after switching away\n", into: firstStorage)
        #expect(scheduler.pendingURIs == [firstURL.documentUri])

        for index in 0..<(FileEditorState.maximumCachedDocuments - 1) {
            let url = try makeFile(in: directory, named: "Filler\(index).swift")
            state.load(from: url)
            await state.awaitPendingLoad()
        }

        #expect(state.openOrder.contains(firstURL.documentUri) == false)

        try await Task.sleep(for: Self.settleDelay)
        #expect(writer.events == ["write:\(firstURL.documentUri)"])
        #expect(scheduler.pendingURIs.isEmpty)
    }

    // MARK: - Flush before open

    @Test("the outgoing file's pending save is written before the incoming document is opened")
    func outgoingSaveIsFlushedBeforeTheNewDocumentOpens() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileA = try makeFile(in: directory, named: "A.swift")
        let fileB = try makeFile(in: directory, named: "B.swift")

        let writer = RecordingWriter()
        let store = TextDocumentStore()
        let scheduler = TextDocumentSaveScheduler(debounce: .seconds(60), write: writer.write)
        let token = store.addObserver { event in
            guard case .opened(let uri, _, _, _) = event else { return }
            writer.record("open:\(uri)")
        }
        let state = FileEditorState(documentStore: store, saveScheduler: scheduler)

        state.load(from: fileA)
        await state.awaitPendingLoad()
        typeText("unsaved\n", into: try #require(state.storage(for: fileA.documentUri)))

        state.load(from: fileB)
        await state.awaitPendingLoad()

        #expect(writer.events == [
            "open:\(fileA.documentUri)",
            "write:\(fileA.documentUri)",
            "open:\(fileB.documentUri)"
        ])
        _ = token
    }

    // MARK: - Teardown

    @Test("a pane going away writes its unsaved documents rather than dropping them")
    func paneTeardownFlushesRatherThanCancels() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = try makeFile(in: directory, named: "Closing.swift")
        let uri = fileURL.documentUri

        let writer = RecordingWriter()
        let store = TextDocumentStore()
        let scheduler = TextDocumentSaveScheduler(debounce: .seconds(60), write: writer.write)

        var state: FileEditorState? = FileEditorState(documentStore: store, saveScheduler: scheduler)
        state?.load(from: fileURL)
        await state?.awaitPendingLoad()
        typeText("the last second of typing\n", into: try #require(state?.storage(for: uri)))
        #expect(scheduler.pendingURIs == [uri])

        // The tab or window closes inside the debounce window.
        state = nil
        try await Task.sleep(for: Self.settleDelay)

        #expect(writer.events == ["write:\(uri)"])
        #expect(store.document(for: uri) == nil)
    }

    @Test("a second pane on the same file keeps it open and keeps its pending save")
    func closingOnePaneDoesNotDropAnotherPanesSave() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = try makeFile(in: directory, named: "Shared.swift")
        let uri = fileURL.documentUri

        let writer = RecordingWriter()
        let store = TextDocumentStore()
        let scheduler = TextDocumentSaveScheduler(debounce: .seconds(60), write: writer.write)

        var paneOne: FileEditorState? = FileEditorState(documentStore: store, saveScheduler: scheduler)
        let paneTwo = FileEditorState(documentStore: store, saveScheduler: scheduler)
        paneOne?.load(from: fileURL)
        await paneOne?.awaitPendingLoad()
        paneTwo.load(from: fileURL)
        await paneTwo.awaitPendingLoad()

        // One document, two references.
        #expect(paneOne?.document(for: uri) === paneTwo.document(for: uri))

        typeText("pane two is typing\n", into: try #require(paneTwo.storage(for: uri)))
        #expect(scheduler.pendingURIs == [uri])

        paneOne = nil
        try await Task.sleep(for: Self.settleDelay)

        // Pane one flushed what was pending rather than cancelling it, and the
        // document is still open for pane two.
        #expect(writer.events == ["write:\(uri)"])
        #expect(store.document(for: uri) != nil)
        #expect(paneTwo.document(for: uri) != nil)
    }
}

/// The AppKit container that mounts one editor per cached document. What is
/// worth asserting here is object identity and `isHidden`: those are exactly
/// the two things findings 2, 3 and 4 turned on, and neither is visible from a
/// compile.
@Suite("CachedEditorStackView")
@MainActor
struct CachedEditorStackViewTests {

    private let uriA: DocumentUri = "file:///A.swift"
    private let uriB: DocumentUri = "file:///B.swift"

    @Test("the mounted editor is the same object after the selection leaves and returns")
    func mountedEditorSurvivesAnEmptySelection() throws {
        let stack = CachedEditorStackView()

        stack.sync(uris: [uriA, uriB], activeURI: uriA, makeEditor: makeClearEditor)
        let hostA = try #require(stack.host(for: uriA))
        let hostB = try #require(stack.host(for: uriB))
        #expect(hostA.isHidden == false)
        #expect(hostB.isHidden)

        // A directory is selected: nothing is shown, nothing is unmounted.
        stack.sync(uris: [uriA, uriB], activeURI: nil, makeEditor: makeClearEditor)
        #expect(stack.host(for: uriA) === hostA)
        #expect(stack.host(for: uriB) === hostB)
        #expect(hostA.isHidden)
        #expect(hostB.isHidden)

        // Back to the file: the very same editor is shown again.
        stack.sync(uris: [uriA, uriB], activeURI: uriA, makeEditor: makeClearEditor)
        #expect(stack.host(for: uriA) === hostA)
        #expect(hostA.isHidden == false)
        #expect(hostB.isHidden)
    }

    @Test("switching between two mounted editors rebuilds neither")
    func switchingBetweenEditorsRebuildsNeither() throws {
        let stack = CachedEditorStackView()

        stack.sync(uris: [uriA, uriB], activeURI: uriA, makeEditor: makeClearEditor)
        let hostA = try #require(stack.host(for: uriA))
        let hostB = try #require(stack.host(for: uriB))

        for active in [uriB, uriA, uriB, uriA] {
            stack.sync(uris: [uriA, uriB], activeURI: active, makeEditor: makeClearEditor)
            #expect(stack.host(for: uriA) === hostA)
            #expect(stack.host(for: uriB) === hostB)
            #expect(hostA.isHidden == (active != uriA))
            #expect(hostB.isHidden == (active != uriB))
        }
    }

    /// With nothing to show, the container must be out of `hitTest` as well as
    /// out of sight. It is mounted unconditionally on top of everything else
    /// the pane draws, and a plain `NSView` claims any point inside its bounds
    /// that no subview takes — so a QuickLook preview underneath rendered but
    /// could not be scrolled.
    @Test("with nothing shown the container hides itself, so it cannot claim clicks meant for QuickLook")
    func inactiveContainerIsHiddenSoItCannotClaimHits() throws {
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let stack = CachedEditorStackView(frame: parent.bounds)
        parent.addSubview(stack)
        let point = NSPoint(x: 200, y: 150)

        stack.sync(uris: [uriA], activeURI: uriA, makeEditor: makeClearEditor)
        #expect(stack.isHidden == false)

        // A PDF, a movie, a directory, or a load still in flight: no editor is
        // shown, so nothing of this stack may be hit.
        stack.sync(uris: [uriA], activeURI: nil, makeEditor: makeClearEditor)
        #expect(stack.isHidden)
        #expect(parent.hitTest(point) === parent)
        // …and hiding is all that happened: the editor is still mounted.
        #expect(stack.host(for: uriA) != nil)

        stack.sync(uris: [uriA], activeURI: uriA, makeEditor: makeClearEditor)
        #expect(stack.isHidden == false)
        #expect(parent.hitTest(point) !== parent)
    }

    /// AppKit does not resign a first responder because an ancestor became
    /// hidden, so clearing the selection while the caret was in the editor
    /// left keystrokes reaching a text view the user cannot see.
    @Test("clearing the selection takes first responder out of the hidden editor")
    func clearingTheSelectionResignsFocus() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let stack = CachedEditorStackView(frame: window.contentLayoutRect)
        window.contentView?.addSubview(stack)

        stack.sync(uris: [uriA], activeURI: uriA, makeEditor: makeClearEditor)

        // Stands in for the editor's text view: what matters to `sync` is only
        // that the window's first responder is a descendant of the stack.
        let caret = FocusableProbeView()
        stack.addSubview(caret)
        #expect(window.makeFirstResponder(caret))
        #expect(window.firstResponder === caret)

        stack.sync(uris: [uriA], activeURI: nil, makeEditor: makeClearEditor)

        #expect(window.firstResponder !== caret)
    }

    @Test("a selection change elsewhere in the window keeps its own first responder")
    func focusOutsideTheStackIsLeftAlone() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let stack = CachedEditorStackView(frame: window.contentLayoutRect)
        window.contentView?.addSubview(stack)

        // Stands in for the file tree, which reselects on every arrow key.
        let tree = FocusableProbeView()
        window.contentView?.addSubview(tree)
        #expect(window.makeFirstResponder(tree))

        stack.sync(uris: [uriA], activeURI: uriA, makeEditor: makeClearEditor)
        #expect(window.firstResponder === tree)

        stack.sync(uris: [uriA], activeURI: nil, makeEditor: makeClearEditor)
        #expect(window.firstResponder === tree)
    }

    @Test("an evicted document's editor is removed from the view hierarchy")
    func evictedEditorIsUnmounted() throws {
        let stack = CachedEditorStackView()

        stack.sync(uris: [uriA, uriB], activeURI: uriA, makeEditor: makeClearEditor)
        let hostA = try #require(stack.host(for: uriA))
        let hostB = try #require(stack.host(for: uriB))
        #expect(stack.subviews.count == 2)

        stack.sync(uris: [uriB], activeURI: uriB, makeEditor: makeClearEditor)

        #expect(stack.host(for: uriA) == nil)
        #expect(stack.host(for: uriB) === hostB)
        #expect(stack.mountedURIs == [uriB])
        #expect(hostA.superview == nil)
        #expect(stack.subviews.count == 1)
    }
}
