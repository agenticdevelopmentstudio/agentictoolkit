import Foundation
import Testing
import LanguageServerProtocol
@testable import AgenticToolkitLanguage

@Suite("TextDocumentStore")
@MainActor
struct TextDocumentStoreTests {

    @Test("open on an already-open URI returns the same document and emits one .opened")
    func openTwiceReturnsSameDocument() {
        let store = TextDocumentStore()
        var events: [TextDocumentEvent] = []
        let token = store.addObserver { events.append($0) }

        let first = store.open(uri: "file:///a.swift", languageId: "swift", text: "one")
        let second = store.open(uri: "file:///a.swift", languageId: "swift", text: "two")

        #expect(first === second)
        #expect(first.text == "one") // the second open's text is ignored, not re-read

        let openedURIs = events.compactMap { event -> DocumentUri? in
            guard case .opened(let uri, _, _, _) = event else { return nil }
            return uri
        }
        #expect(openedURIs == ["file:///a.swift"])
        _ = token
    }

    @Test("close keeps a twice-opened document alive until the matching close")
    func closeIsReferenceCounted() {
        let store = TextDocumentStore()
        var events: [TextDocumentEvent] = []
        let token = store.addObserver { events.append($0) }
        let uri: DocumentUri = "file:///b.swift"

        store.open(uri: uri, languageId: "swift", text: "x")
        store.open(uri: uri, languageId: "swift", text: "x")

        store.close(uri: uri)
        #expect(store.document(for: uri) != nil)
        #expect(events.contains { if case .closed = $0 { return true } else { return false } } == false)

        store.close(uri: uri)
        #expect(store.document(for: uri) == nil)
        #expect(events.contains { if case .closed = $0 { return true } else { return false } })
        _ = token
    }

    @Test("apply on an open document emits .changed carrying the document's new version")
    func applyEmitsChangedWithNewVersion() {
        let store = TextDocumentStore()
        var events: [TextDocumentEvent] = []
        let token = store.addObserver { events.append($0) }
        let uri: DocumentUri = "file:///c.swift"

        let document = store.open(uri: uri, languageId: "swift", text: "abc")
        document.apply([TextEdit(
            range: LSPRange(start: Position(line: 0, character: 1), end: Position(line: 0, character: 2)),
            newText: "X"
        )])

        let changed: [(uri: DocumentUri, version: Int)] = events.compactMap { event in
            guard case .changed(let eventURI, let version, _) = event else { return nil }
            return (eventURI, version)
        }
        #expect(changed.count == 1)
        #expect(changed.first?.uri == uri)
        #expect(changed.first?.version == document.version)
        _ = token
    }

    @Test("dropping the observation token stops delivery")
    func droppingTokenStopsDelivery() {
        let store = TextDocumentStore()
        var events: [TextDocumentEvent] = []
        var token: TextDocumentStoreObservation? = store.addObserver { events.append($0) }
        #expect(token != nil)

        store.open(uri: "file:///d.swift", languageId: "swift", text: "x")
        #expect(events.count == 1)

        token = nil

        store.open(uri: "file:///e.swift", languageId: "swift", text: "y")
        #expect(events.count == 1) // no event delivered after the token was dropped
    }

    @Test("a save clearing isDirty raises .dirtyStateChanged, the only signal a dirty marker can clear on")
    func markCleanRaisesDirtyStateChanged() {
        let store = TextDocumentStore()
        var dirtyStates: [(uri: DocumentUri, isDirty: Bool)] = []
        let token = store.addObserver { event in
            guard case .dirtyStateChanged(let uri, let isDirty) = event else { return }
            dirtyStates.append((uri, isDirty))
        }

        let document = store.open(uri: "file:///dirty-event.swift", languageId: "swift", text: "abc")
        #expect(dirtyStates.isEmpty)

        document.apply([TextEdit(
            range: LSPRange(start: Position(line: 0, character: 0), end: Position(line: 0, character: 1)),
            newText: "X"
        )])
        #expect(dirtyStates.count == 1)
        #expect(dirtyStates.first?.uri == "file:///dirty-event.swift")
        #expect(dirtyStates.first?.isDirty == true)

        document.markClean()

        #expect(dirtyStates.count == 2)
        #expect(dirtyStates.last?.uri == "file:///dirty-event.swift")
        #expect(dirtyStates.last?.isDirty == false)
        _ = token
    }
}
