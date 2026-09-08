import AgenticToolkitCore
import Foundation
import LanguageServerProtocol
import Testing
@testable import AgenticToolkitLanguage

/// The workspace-scope filter: which documents a project's servers are told
/// about at all.
///
/// With several project windows sharing one `TextDocumentStore`, an unscoped
/// sync sends every project's files to every other project's servers. Those
/// servers cannot resolve a file outside their own root, answer nothing useful
/// for it, and index it anyway — so the filter is a correctness fix rather than
/// a limitation.
///
/// Every test here builds real directories, because the guard resolves symlinks
/// and macOS's own `/var` → `/private/var` symlink is exactly what a naive
/// string comparison gets wrong.
///
/// **Nothing here polls and nothing here sleeps**, for the same reason as
/// `LanguageServerDocumentSyncTests`: `shutdown()` finishes every queue and
/// awaits every drain, so when it returns, everything that was ever going to
/// reach a fake already has.
@Suite("LanguageServerDocumentSync workspace scope")
@MainActor
struct LanguageServerDocumentSyncScopeTests {

    // MARK: - Fixtures

    /// A directory that exists on disk, removed when the test ends.
    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lsp-scope-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeSettingsStore() -> SettingsStore {
        SettingsStore(
            with: InMemorySettingsStorageProvider(),
            secureSettingsProvider: InMemorySecureSettingsStorageProvider()
        )
    }

    private func makeRegistry(
        settings: SettingsStore,
        log: SessionLog,
        workspaceURL: URL
    ) -> LanguageServerRegistry {
        LanguageServerRegistry(
            store: settings,
            workspaceURL: workspaceURL,
            builtInConfigurations: [],
            sessionFactory: { configuration, secrets, rootURL in
                FakeLanguageServerSession(
                    configuration: configuration,
                    environment: configuration.environment.merging(secrets) { _, secret in secret },
                    rootURL: rootURL,
                    log: log,
                    // A server that opens, changes and closes: anything the
                    // filter lets through must be visible in the log.
                    behavior: .syncing(.optionA(TextDocumentSyncOptions(
                        openClose: true,
                        change: .incremental,
                        save: nil
                    )))
                )
            }
        )
    }

    private func makeConfiguration() -> LanguageServerConfiguration {
        LanguageServerConfiguration(
            name: "Fake",
            languageIds: ["swift"],
            command: "/nonexistent/server",
            rootMarkers: [".git"]
        )
    }

    private func fake(
        _ registry: LanguageServerRegistry,
        for id: UUID
    ) throws -> FakeLanguageServerSession {
        try #require(registry.session(for: id) as? FakeLanguageServerSession)
    }

    /// The URIs the session was told to open, in order.
    private func openedURIs(in calls: [RecordedCall]) -> [DocumentUri] {
        calls.compactMap { call in
            guard case .didOpen(let params) = call else { return nil }
            return params.textDocument.uri
        }
    }

    private func kinds(in calls: [RecordedCall]) -> [String] {
        calls.map { call in
            switch call {
            case .start: "start"
            case .stop: "stop"
            case .didOpen: "didOpen"
            case .didChange: "didChange"
            case .didSave: "didSave"
            case .didClose: "didClose"
            }
        }
    }

    /// Replaces one character on line 0.
    private func edit(_ document: TextDocument, at character: Int, with newText: String) {
        document.apply([TextEdit(
            range: LSPRange(
                start: Position(line: 0, character: character),
                end: Position(line: 0, character: character + 1)
            ),
            newText: newText
        )])
    }

    // MARK: - 1. In scope

    @Test("a document under the workspace root reaches a claiming session")
    func inScopeDocumentIsForwarded() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let settings = makeSettingsStore()
        let log = SessionLog()
        let documents = TextDocumentStore()
        let registry = makeRegistry(settings: settings, log: log, workspaceURL: root)
        let sync = LanguageServerDocumentSync(store: documents, registry: registry)
        sync.start()

        let configuration = makeConfiguration()
        settings.set([configuration], for: UserSettings.languageServerConfigurations)

        let uri = root.appendingPathComponent("Inside.swift").documentUri
        _ = documents.open(uri: uri, languageId: "swift", text: "abcdef")

        await sync.shutdown()

        let session = try fake(registry, for: configuration.id)
        #expect(openedURIs(in: log.calls(forInstance: session.instanceID)) == [uri])
    }

    // MARK: - 2. Out of scope

    /// What it catches: a guard placed only on `.opened` that lets later events
    /// through anyway. `.changed` is gated on the URI having been recorded when
    /// it opened, so the open guard has to keep it *out of the table*, not merely
    /// skip one notification.
    @Test("a document outside the workspace root produces no notification, not even after an edit")
    func outOfScopeDocumentIsSilent() async throws {
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appendingPathComponent("root", isDirectory: true)
        let elsewhere = parent.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)

        let settings = makeSettingsStore()
        let log = SessionLog()
        let documents = TextDocumentStore()
        let registry = makeRegistry(settings: settings, log: log, workspaceURL: root)
        let sync = LanguageServerDocumentSync(store: documents, registry: registry)
        sync.start()

        let configuration = makeConfiguration()
        settings.set([configuration], for: UserSettings.languageServerConfigurations)

        let uri = elsewhere.appendingPathComponent("Outside.swift").documentUri
        let document = documents.open(uri: uri, languageId: "swift", text: "abcdef")
        edit(document, at: 0, with: "X")
        documents.close(uri: uri)

        await sync.shutdown()

        let session = try fake(registry, for: configuration.id)
        // The session is still started — the registry owns that, not the filter.
        #expect(kinds(in: log.calls(forInstance: session.instanceID)) == ["start"])
    }

    // MARK: - 3. Path components, not string prefixes

    /// What it catches: `uri.hasPrefix(root.path)`. `…/proj-old` starts with
    /// `…/proj` as a string and is a completely different project as a path.
    @Test("a sibling directory whose path is a string prefix of the root is out of scope")
    func siblingSharingAStringPrefixIsOutOfScope() async throws {
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appendingPathComponent("proj", isDirectory: true)
        let sibling = parent.appendingPathComponent("proj-old", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)

        let settings = makeSettingsStore()
        let log = SessionLog()
        let documents = TextDocumentStore()
        let registry = makeRegistry(settings: settings, log: log, workspaceURL: root)
        let sync = LanguageServerDocumentSync(store: documents, registry: registry)
        sync.start()

        let configuration = makeConfiguration()
        settings.set([configuration], for: UserSettings.languageServerConfigurations)

        let insideURI = root.appendingPathComponent("Inside.swift").documentUri
        let siblingURI = sibling.appendingPathComponent("Inside.swift").documentUri
        _ = documents.open(uri: siblingURI, languageId: "swift", text: "abcdef")
        _ = documents.open(uri: insideURI, languageId: "swift", text: "abcdef")

        await sync.shutdown()

        let session = try fake(registry, for: configuration.id)
        #expect(openedURIs(in: log.calls(forInstance: session.instanceID)) == [insideURI])
    }

    // MARK: - 4. Replay

    /// The replay path is the ordinary startup path: documents are open long
    /// before settings produce a session. It has its own loop over
    /// `store.openDocuments`, so it needs its own guard.
    @Test("a document already open outside the root is not replayed to a new session")
    func replaySkipsOutOfScopeDocuments() async throws {
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appendingPathComponent("root", isDirectory: true)
        let elsewhere = parent.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)

        let settings = makeSettingsStore()
        let log = SessionLog()
        let documents = TextDocumentStore()

        // Both open *before* anything is watching, which is what makes the
        // session's arrival a replay rather than a live open.
        let insideURI = root.appendingPathComponent("Inside.swift").documentUri
        let outsideURI = elsewhere.appendingPathComponent("Outside.swift").documentUri
        _ = documents.open(uri: outsideURI, languageId: "swift", text: "abcdef")
        _ = documents.open(uri: insideURI, languageId: "swift", text: "abcdef")

        let registry = makeRegistry(settings: settings, log: log, workspaceURL: root)
        let sync = LanguageServerDocumentSync(store: documents, registry: registry)
        sync.start()

        let configuration = makeConfiguration()
        settings.set([configuration], for: UserSettings.languageServerConfigurations)

        await sync.shutdown()

        let session = try fake(registry, for: configuration.id)
        #expect(openedURIs(in: log.calls(forInstance: session.instanceID)) == [insideURI])
    }

    // MARK: - 5. Symlinks

    /// What it catches: comparing unresolved paths. A project opened through a
    /// symlinked path — which on macOS includes anything under `/tmp` — would
    /// otherwise have every one of its own files judged out of scope.
    @Test("a workspace root given through a symlink admits a document under its resolved path")
    func symlinkedRootAdmitsResolvedPaths() async throws {
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let realRoot = parent.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: realRoot, withIntermediateDirectories: true)
        let linkedRoot = parent.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: realRoot)

        let settings = makeSettingsStore()
        let log = SessionLog()
        let documents = TextDocumentStore()
        // The registry — and therefore the filter — knows only the link.
        let registry = makeRegistry(settings: settings, log: log, workspaceURL: linkedRoot)
        let sync = LanguageServerDocumentSync(store: documents, registry: registry)
        sync.start()

        let configuration = makeConfiguration()
        settings.set([configuration], for: UserSettings.languageServerConfigurations)

        // The document arrives under the resolved path, the way a file browser
        // rooted at the real directory would open it.
        let uri = realRoot.appendingPathComponent("Inside.swift").documentUri
        _ = documents.open(uri: uri, languageId: "swift", text: "abcdef")

        await sync.shutdown()

        let session = try fake(registry, for: configuration.id)
        #expect(openedURIs(in: log.calls(forInstance: session.instanceID)) == [uri])
    }
}
