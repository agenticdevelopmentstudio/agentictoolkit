import Foundation
import LanguageServerProtocol

/// What changed in a `TextDocumentStore`, broadcast to every observer.
public enum TextDocumentEvent: Sendable {
    case opened(uri: DocumentUri, languageId: String, version: Int, text: String)
    case changed(uri: DocumentUri, version: Int, changes: [TextDocumentContentChangeEvent])
    case closed(uri: DocumentUri)
}

/// The reference-counted set of currently-open `TextDocument`s. Two editor
/// panes on one file is the case this exists for: `open` on a URI that is
/// already open hands back the same `TextDocument` and bumps a refcount
/// instead of re-reading or replacing its text, and `close` only tears the
/// document down once every opener has closed it.
///
/// Foundation-only, same import rules as `TextDocument`.
@MainActor
public final class TextDocumentStore {

    /// One entry in `documentsByURI`: the document plus how many opens are
    /// currently holding it.
    private final class OpenEntry {
        let document: TextDocument
        var openCount: Int

        init(document: TextDocument, openCount: Int) {
            self.document = document
            self.openCount = openCount
        }
    }

    private var documentsByURI: [DocumentUri: OpenEntry] = [:]
    private var observers: [UUID: @MainActor (TextDocumentEvent) -> Void] = [:]

    public init() {}

    /// Opens `uri`. The first open reads `text` into a new `TextDocument` and
    /// emits `.opened`; every subsequent open before a matching `close`
    /// returns the same instance, increments its open count, and emits
    /// nothing — the text already open is authoritative, not the text of a
    /// later `open` call.
    @discardableResult
    public func open(uri: DocumentUri, languageId: String, text: String) -> TextDocument {
        if let entry = documentsByURI[uri] {
            entry.openCount += 1
            return entry.document
        }

        let document = TextDocument(uri: uri, languageId: languageId, text: text)
        document.changeHandler = { [weak self] version, changes in
            self?.notify(.changed(uri: uri, version: version, changes: changes))
        }
        documentsByURI[uri] = OpenEntry(document: document, openCount: 1)
        notify(.opened(uri: uri, languageId: languageId, version: document.version, text: text))
        return document
    }

    public func document(for uri: DocumentUri) -> TextDocument? {
        documentsByURI[uri]?.document
    }

    /// Decrements the open count for `uri`; only once it reaches zero is the
    /// document actually removed and `.closed` emitted.
    public func close(uri: DocumentUri) {
        guard let entry = documentsByURI[uri] else { return }
        entry.openCount -= 1
        guard entry.openCount <= 0 else { return }
        documentsByURI.removeValue(forKey: uri)
        notify(.closed(uri: uri))
    }

    public var openDocuments: [TextDocument] {
        documentsByURI.values.map(\.document)
    }

    /// Registers `observer` and returns an opaque token that keeps it alive:
    /// dropping the token removes the observer. No `NotificationCenter`
    /// involved — this is the same "token's deinit tears down the
    /// subscription" shape as the toolkit's `ThemePaletteObserver`.
    public func addObserver(
        _ observer: @escaping @MainActor (TextDocumentEvent) -> Void
    ) -> TextDocumentStoreObservation {
        let id = UUID()
        observers[id] = observer
        return TextDocumentStoreObservation(id: id, store: self)
    }

    /// Called only by `TextDocumentStoreObservation.deinit`.
    func removeObserver(id: UUID) {
        observers.removeValue(forKey: id)
    }

    private func notify(_ event: TextDocumentEvent) {
        for observer in observers.values {
            observer(event)
        }
    }
}

/// An opaque handle to one `TextDocumentStore` observer. Hold it for as long
/// as delivery should continue — its `deinit` unregisters the observer, the
/// same shape as `ThemePaletteObserver`'s `cancellables`.
@MainActor
public final class TextDocumentStoreObservation {
    private let id: UUID
    private weak var store: TextDocumentStore?

    fileprivate init(id: UUID, store: TextDocumentStore) {
        self.id = id
        self.store = store
    }

    // Isolated explicitly (SE-0371): a MainActor class's deinit is
    // nonisolated by default, and `removeObserver` is MainActor-isolated
    // state on `store`. `isolated deinit` hops to the actor before running,
    // rather than reaching for `nonisolated(unsafe)`.
    isolated deinit {
        store?.removeObserver(id: id)
    }
}
