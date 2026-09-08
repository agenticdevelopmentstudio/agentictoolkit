import AgenticToolkitCore
import Foundation
import LanguageServerProtocol
import Testing
@testable import AgenticToolkitLanguage

/// Document synchronisation: the seam between the `@MainActor` document model
/// and the `actor` sessions.
///
/// **Nothing here polls and nothing here sleeps.** Every assertion hangs off
/// `LanguageServerDocumentSync.shutdown()`, which finishes each queue and
/// awaits each drain task — so when it returns, every notification that was
/// ever going to reach a fake already has. A polled assertion on this branch
/// has been wrong every time it was tried.
@Suite("LanguageServerDocumentSync")
@MainActor
struct LanguageServerDocumentSyncTests {

    private static let swiftURI: DocumentUri = "file:///Fixture.swift"
    private static let pythonURI: DocumentUri = "file:///fixture.py"
    private static let initialText = "abcdef"

    // MARK: - Fixtures

    private func makeSettingsStore() -> SettingsStore {
        SettingsStore(
            with: InMemorySettingsStorageProvider(),
            secureSettingsProvider: InMemorySecureSettingsStorageProvider()
        )
    }

    /// A registry with no built-ins and a fake factory, exactly as
    /// `LanguageServerRegistryTests` builds one. Behaviours are keyed by
    /// configuration name so the value the factory closure captures stays
    /// `Sendable`.
    private func makeRegistry(
        settings: SettingsStore,
        log: SessionLog,
        behaviors: [String: FakeSessionBehavior] = [:]
    ) -> LanguageServerRegistry {
        LanguageServerRegistry(
            store: settings,
            workspaceURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            builtInConfigurations: [],
            sessionFactory: { configuration, secrets, rootURL in
                FakeLanguageServerSession(
                    configuration: configuration,
                    environment: configuration.environment.merging(secrets) { _, secret in secret },
                    rootURL: rootURL,
                    log: log,
                    behavior: behaviors[configuration.name] ?? FakeSessionBehavior()
                )
            }
        )
    }

    private func makeConfiguration(
        name: String = "Fake",
        languageIds: [String] = ["swift"],
        command: String = "/nonexistent/server"
    ) -> LanguageServerConfiguration {
        LanguageServerConfiguration(
            name: name,
            languageIds: languageIds,
            command: command,
            rootMarkers: [".git"]
        )
    }

    /// Options declaring a sync capability and nothing else.
    private func options(
        openClose: Bool? = nil,
        change: TextDocumentSyncKind? = nil,
        save: TwoTypeOption<Bool, SaveOptions>? = nil
    ) -> TwoTypeOption<TextDocumentSyncOptions, TextDocumentSyncKind> {
        .optionA(TextDocumentSyncOptions(openClose: openClose, change: change, save: save))
    }

    /// Replaces one character on line 0. Returns what the store produced, so a
    /// test can assert the forwarded changes are that array and not a rebuild
    /// of it.
    @discardableResult
    private func edit(
        _ document: TextDocument,
        at character: Int,
        with newText: String
    ) -> [TextDocumentContentChangeEvent] {
        document.apply([TextEdit(
            range: LSPRange(
                start: Position(line: 0, character: character),
                end: Position(line: 0, character: character + 1)
            ),
            newText: newText
        )])
    }

    private func fake(
        _ registry: LanguageServerRegistry,
        for id: UUID
    ) throws -> FakeLanguageServerSession {
        try #require(registry.session(for: id) as? FakeLanguageServerSession)
    }

    private func changes(in calls: [RecordedCall]) -> [DidChangeTextDocumentParams] {
        calls.compactMap { call in
            guard case .didChange(let params) = call else { return nil }
            return params
        }
    }

    private func opens(in calls: [RecordedCall]) -> [DidOpenTextDocumentParams] {
        calls.compactMap { call in
            guard case .didOpen(let params) = call else { return nil }
            return params
        }
    }

    // MARK: - 1. The capability table

    /// What it catches: any reading of `textDocumentSync` that treats an absent
    /// `openClose` as `false`, or a bare `TextDocumentSyncKind` as carrying save
    /// options it cannot carry. Both are silent — the server simply never hears
    /// about a file.
    @Test("ResolvedTextDocumentSync.resolve covers every declared shape")
    func resolveTable() {
        #expect(ResolvedTextDocumentSync.resolve(nil) == .disabled)

        #expect(ResolvedTextDocumentSync.resolve(.optionB(.incremental))
            == ResolvedTextDocumentSync(openClose: true, change: .incremental, save: nil))
        #expect(ResolvedTextDocumentSync.resolve(.optionB(.none))
            == ResolvedTextDocumentSync(openClose: true, change: .none, save: nil))

        // `openClose` absent defaults to true; present is honoured either way.
        #expect(ResolvedTextDocumentSync.resolve(options(change: .full))
            == ResolvedTextDocumentSync(openClose: true, change: .full, save: nil))
        #expect(ResolvedTextDocumentSync.resolve(options(openClose: false, change: .incremental))
            == ResolvedTextDocumentSync(openClose: false, change: .incremental, save: nil))
        #expect(ResolvedTextDocumentSync.resolve(options(openClose: true, change: .incremental))
            == ResolvedTextDocumentSync(openClose: true, change: .incremental, save: nil))

        // `change` absent means "send no didChange", not "send full".
        #expect(ResolvedTextDocumentSync.resolve(options(openClose: true))
            == ResolvedTextDocumentSync(openClose: true, change: .none, save: nil))

        // Every `save` shape.
        #expect(ResolvedTextDocumentSync.resolve(options(change: .full, save: nil)).save == nil)
        #expect(ResolvedTextDocumentSync.resolve(options(change: .full, save: .optionA(false))).save == nil)
        #expect(ResolvedTextDocumentSync.resolve(options(change: .full, save: .optionA(true))).save
            == SaveOptions(includeText: false))
        #expect(
            ResolvedTextDocumentSync.resolve(
                options(change: .full, save: .optionB(SaveOptions(includeText: true)))
            ).save == SaveOptions(includeText: true)
        )
    }

    // MARK: - 2. Ordering

    /// **This is the test that catches the unstructured-`Task` mistake.** Each
    /// event is handed to the pipeline from one synchronous MainActor turn; if
    /// the pipeline forwarded each one from its own `Task { await ... }` instead
    /// of through the single-consumer `AsyncStream`, the recorded order would
    /// vary run to run and the strictly increasing versions below would come
    /// back shuffled. Remove the FIFO and this test must fail.
    @Test("open, N edits and close reach the server in emission order")
    func forwardsInEmissionOrder() async throws {
        let settings = makeSettingsStore()
        let log = SessionLog()
        let documents = TextDocumentStore()
        let registry = makeRegistry(
            settings: settings,
            log: log,
            behaviors: ["Fake": .syncing(options(openClose: true, change: .incremental))]
        )
        let sync = LanguageServerDocumentSync(store: documents, registry: registry)
        sync.start()

        let configuration = makeConfiguration()
        settings.set([configuration], for: UserSettings.languageServerConfigurations)

        let document = documents.open(uri: Self.swiftURI, languageId: "swift", text: Self.initialText)
        edit(document, at: 0, with: "X")
        edit(document, at: 1, with: "Y")
        edit(document, at: 2, with: "Z")
        documents.close(uri: Self.swiftURI)

        await sync.shutdown()

        let session = try fake(registry, for: configuration.id)
        let calls = log.calls(forInstance: session.instanceID)

        #expect(calls.count == 6)
        #expect(calls.first == .start)
        #expect(opens(in: calls).map(\.textDocument.version) == [0])
        #expect(changes(in: calls).map(\.textDocument.version) == [1, 2, 3])
        guard case .didClose(let closeParams) = try #require(calls.last) else {
            Issue.record("expected the last call to be didClose")
            return
        }
        #expect(closeParams.textDocument.uri == Self.swiftURI)
    }

    // MARK: - 3/4/5. What travels on the wire

    /// What it catches: a pipeline that rebuilds the change list instead of
    /// forwarding the store's — the store computes offsets *before* applying,
    /// which a rebuild cannot reproduce once the text has moved.
    @Test("an incremental server receives the store's change array verbatim")
    func incrementalForwardsChangesVerbatim() async throws {
        let settings = makeSettingsStore()
        let log = SessionLog()
        let documents = TextDocumentStore()
        let registry = makeRegistry(
            settings: settings,
            log: log,
            behaviors: ["Fake": .syncing(options(openClose: true, change: .incremental))]
        )
        let sync = LanguageServerDocumentSync(store: documents, registry: registry)
        sync.start()

        let configuration = makeConfiguration()
        settings.set([configuration], for: UserSettings.languageServerConfigurations)

        let document = documents.open(uri: Self.swiftURI, languageId: "swift", text: Self.initialText)
        let produced = edit(document, at: 2, with: "QQ")

        await sync.shutdown()

        let session = try fake(registry, for: configuration.id)
        let forwarded = changes(in: log.calls(forInstance: session.instanceID))
        #expect(forwarded.count == 1)
        #expect(forwarded.first?.contentChanges == produced)
    }

    /// What it catches: a `.full` server sent an incremental change (which it
    /// will apply as if the whole buffer were that fragment), or sent the
    /// *current* text rather than the text at the version on the wire.
    @Test("a full-sync server receives one whole-document change per edit")
    func fullForwardsWholeDocument() async throws {
        let settings = makeSettingsStore()
        let log = SessionLog()
        let documents = TextDocumentStore()
        let registry = makeRegistry(
            settings: settings,
            log: log,
            behaviors: ["Fake": .syncing(options(openClose: true, change: .full))]
        )
        let sync = LanguageServerDocumentSync(store: documents, registry: registry)
        sync.start()

        let configuration = makeConfiguration()
        settings.set([configuration], for: UserSettings.languageServerConfigurations)

        let document = documents.open(uri: Self.swiftURI, languageId: "swift", text: Self.initialText)
        edit(document, at: 0, with: "X")
        let textAtVersionOne = document.text

        await sync.shutdown()

        let session = try fake(registry, for: configuration.id)
        let forwarded = changes(in: log.calls(forInstance: session.instanceID))
        let change = try #require(forwarded.first?.contentChanges.first)
        #expect(forwarded.count == 1)
        #expect(forwarded.first?.contentChanges.count == 1)
        #expect(change.range == nil)
        #expect(change.rangeLength == nil)
        #expect(change.text == textAtVersionOne)
        #expect(forwarded.first?.textDocument.version == 1)
    }

    /// D2's guarantee, and the one a naive implementation gets wrong silently.
    /// Both edits land in a single MainActor turn, so no drain can have run in
    /// between: a pipeline that read `document.text` when it got round to
    /// sending would put the *second* edit's text on both notifications, and
    /// the server's buffer would then be one version ahead of the version it
    /// was told about — permanently.
    @Test("each didChange carries the text as of its own version")
    func textAndVersionAreCapturedTogether() async throws {
        let settings = makeSettingsStore()
        let log = SessionLog()
        let documents = TextDocumentStore()
        let registry = makeRegistry(
            settings: settings,
            log: log,
            behaviors: ["Fake": .syncing(options(openClose: true, change: .full))]
        )
        let sync = LanguageServerDocumentSync(store: documents, registry: registry)
        sync.start()

        let configuration = makeConfiguration()
        settings.set([configuration], for: UserSettings.languageServerConfigurations)

        let document = documents.open(uri: Self.swiftURI, languageId: "swift", text: Self.initialText)
        edit(document, at: 0, with: "X")
        let textAtVersionOne = document.text
        edit(document, at: 1, with: "Y")
        let textAtVersionTwo = document.text
        #expect(textAtVersionOne != textAtVersionTwo)

        await sync.shutdown()

        let session = try fake(registry, for: configuration.id)
        let forwarded = changes(in: log.calls(forInstance: session.instanceID))
        #expect(forwarded.map(\.textDocument.version) == [1, 2])
        #expect(forwarded.map { $0.contentChanges.first?.text } == [textAtVersionOne, textAtVersionTwo])
    }

    // MARK: - 6. Self-heal

    /// D6 rule 2 — the whole recovery mechanism. A dropped `didOpen` must cost
    /// one extra full-text open, not a permanently stale buffer: describing an
    /// edit to a server that never heard of the document is meaningless, so the
    /// next change re-opens it instead.
    @Test("a change to a document the server never opened re-opens it")
    func changeReopensAfterAFailedOpen() async throws {
        let settings = makeSettingsStore()
        let log = SessionLog()
        let documents = TextDocumentStore()
        let behavior = FakeSessionBehavior(
            capabilities: FakeSessionBehavior.syncing(options(openClose: true, change: .incremental)).capabilities,
            didOpenErrors: [.notRunning]
        )
        let registry = makeRegistry(settings: settings, log: log, behaviors: ["Fake": behavior])
        let sync = LanguageServerDocumentSync(store: documents, registry: registry)
        sync.start()

        let configuration = makeConfiguration()
        settings.set([configuration], for: UserSettings.languageServerConfigurations)

        let document = documents.open(uri: Self.swiftURI, languageId: "swift", text: Self.initialText)
        edit(document, at: 0, with: "X")
        let textAtVersionOne = document.text

        await sync.shutdown()

        let session = try fake(registry, for: configuration.id)
        let calls = log.calls(forInstance: session.instanceID)
        let recordedOpens = opens(in: calls)

        // Two opens: the one that was refused, and the one the change turned
        // into. No didChange at all — the server could not have applied one.
        #expect(recordedOpens.count == 2)
        #expect(changes(in: calls).isEmpty)
        #expect(recordedOpens.last?.textDocument.version == 1)
        #expect(recordedOpens.last?.textDocument.text == textAtVersionOne)
        #expect(recordedOpens.last?.textDocument.languageId == "swift")
    }

    // MARK: - 7. A failed start is terminal

    /// What it catches: a pipeline that retries `start()` per event. A missing
    /// server binary would then re-spawn a failing subprocess on every
    /// keystroke.
    @Test("a session whose start fails is never started again and receives nothing")
    func failedStartIsNotRetried() async throws {
        let settings = makeSettingsStore()
        let log = SessionLog()
        let documents = TextDocumentStore()
        let behavior = FakeSessionBehavior(startError: .sessionHasBeenStopped)
        let registry = makeRegistry(settings: settings, log: log, behaviors: ["Fake": behavior])
        let sync = LanguageServerDocumentSync(store: documents, registry: registry)
        sync.start()

        let configuration = makeConfiguration()
        settings.set([configuration], for: UserSettings.languageServerConfigurations)

        let document = documents.open(uri: Self.swiftURI, languageId: "swift", text: Self.initialText)
        edit(document, at: 0, with: "X")
        edit(document, at: 1, with: "Y")
        document.markClean()
        documents.close(uri: Self.swiftURI)

        await sync.shutdown()

        let session = try fake(registry, for: configuration.id)
        // Exactly one start — the registry also starts every session it
        // creates, and a fake faithful to `LanguageServerSession` makes the
        // second call a no-op — and no traffic whatsoever.
        #expect(log.calls(forInstance: session.instanceID) == [.start])
    }

    // MARK: - 8/9. Sessions arriving and being replaced

    /// D7, and the ordinary startup path rather than an edge case: the registry
    /// reconciles from settings long after documents are open, so a session
    /// that never gets a replay never learns any file exists.
    @Test("a new session is told about the open documents it claims, and only those")
    func replaysOpenDocumentsForTheClaimedLanguage() async throws {
        let settings = makeSettingsStore()
        let log = SessionLog()
        let documents = TextDocumentStore()
        let registry = makeRegistry(
            settings: settings,
            log: log,
            behaviors: ["Fake": .syncing(options(openClose: true, change: .incremental))]
        )
        let sync = LanguageServerDocumentSync(store: documents, registry: registry)
        sync.start()

        documents.open(uri: Self.swiftURI, languageId: "swift", text: Self.initialText)
        documents.open(uri: Self.pythonURI, languageId: "python", text: "print()")

        let configuration = makeConfiguration()
        settings.set([configuration], for: UserSettings.languageServerConfigurations)

        await sync.shutdown()

        let session = try fake(registry, for: configuration.id)
        let recordedOpens = opens(in: log.calls(forInstance: session.instanceID))
        #expect(recordedOpens.count == 1)
        #expect(recordedOpens.first?.textDocument.uri == Self.swiftURI)
    }

    /// What it catches: a sync keyed on the configuration id alone. The id
    /// survives a replacement, so an id-keyed sync would keep the retired
    /// pipeline and the *new* server would never hear that any file exists —
    /// "my settings do nothing", one layer up from the registry's own version
    /// of that bug.
    @Test("replacing a session hands the new one the open documents and the old one nothing further")
    func sessionReplacementRebuildsThePipeline() async throws {
        let settings = makeSettingsStore()
        let log = SessionLog()
        let documents = TextDocumentStore()
        let registry = makeRegistry(
            settings: settings,
            log: log,
            behaviors: ["Fake": .syncing(options(openClose: true, change: .incremental))]
        )
        let sync = LanguageServerDocumentSync(store: documents, registry: registry)
        sync.start()

        var configuration = makeConfiguration()
        settings.set([configuration], for: UserSettings.languageServerConfigurations)
        let firstSession = try fake(registry, for: configuration.id)

        let document = documents.open(uri: Self.swiftURI, languageId: "swift", text: Self.initialText)

        configuration.command = "/nonexistent/second-server"
        settings.set([configuration], for: UserSettings.languageServerConfigurations)
        let secondSession = try fake(registry, for: configuration.id)
        #expect(firstSession.instanceID != secondSession.instanceID)

        // Edited only *after* the replacement, so this change can only reach a
        // pipeline that was rebuilt onto the new session.
        edit(document, at: 0, with: "X")
        let textAtVersionOne = document.text

        await sync.shutdown()

        let secondCalls = log.calls(forInstance: secondSession.instanceID)
        #expect(opens(in: secondCalls).map(\.textDocument.uri) == [Self.swiftURI])
        #expect(changes(in: secondCalls).map(\.textDocument.version) == [1])
        #expect(changes(in: secondCalls).first?.contentChanges.isEmpty == false)
        #expect(document.text == textAtVersionOne)

        // The retired session is out of the routing table, so the post-
        // replacement edit cannot have reached it. (Its own queued open may or
        // may not have landed before the registry stopped it; that race is the
        // registry's and is not what this asserts.)
        #expect(changes(in: log.calls(forInstance: firstSession.instanceID)).isEmpty)
    }

    // MARK: - 10/11. Servers that want less

    /// D6 rule 4. What it catches: tracking `openURIs` for a server that never
    /// gets an open — every change would then be turned into a `didOpen` the
    /// server did not ask for.
    @Test("openClose == false sends no didOpen or didClose but still sends didChange")
    func openCloseDisabled() async throws {
        let settings = makeSettingsStore()
        let log = SessionLog()
        let documents = TextDocumentStore()
        let registry = makeRegistry(
            settings: settings,
            log: log,
            behaviors: ["Fake": .syncing(options(openClose: false, change: .incremental))]
        )
        let sync = LanguageServerDocumentSync(store: documents, registry: registry)
        sync.start()

        let configuration = makeConfiguration()
        settings.set([configuration], for: UserSettings.languageServerConfigurations)

        let document = documents.open(uri: Self.swiftURI, languageId: "swift", text: Self.initialText)
        edit(document, at: 0, with: "X")
        documents.close(uri: Self.swiftURI)

        await sync.shutdown()

        let session = try fake(registry, for: configuration.id)
        let calls = log.calls(forInstance: session.instanceID)
        #expect(calls == [.start, .didChange(DidChangeTextDocumentParams(
            uri: Self.swiftURI,
            version: 1,
            contentChanges: [TextDocumentContentChangeEvent(
                range: LSPRange(start: Position(line: 0, character: 0), end: Position(line: 0, character: 1)),
                rangeLength: 1,
                text: "X"
            )]
        ))])
    }

    /// The mirror image: a server that only wants to know which files are open.
    @Test("change == .none sends no didChange but still sends didOpen and didClose")
    func changeNone() async throws {
        let settings = makeSettingsStore()
        let log = SessionLog()
        let documents = TextDocumentStore()
        let registry = makeRegistry(
            settings: settings,
            log: log,
            behaviors: ["Fake": .syncing(options(openClose: true, change: TextDocumentSyncKind.none))]
        )
        let sync = LanguageServerDocumentSync(store: documents, registry: registry)
        sync.start()

        let configuration = makeConfiguration()
        settings.set([configuration], for: UserSettings.languageServerConfigurations)

        let document = documents.open(uri: Self.swiftURI, languageId: "swift", text: Self.initialText)
        edit(document, at: 0, with: "X")
        documents.close(uri: Self.swiftURI)

        await sync.shutdown()

        let session = try fake(registry, for: configuration.id)
        let calls = log.calls(forInstance: session.instanceID)
        #expect(calls.count == 3)
        #expect(changes(in: calls).isEmpty)
        #expect(opens(in: calls).map(\.textDocument.version) == [0])
        guard case .didClose = try #require(calls.last) else {
            Issue.record("expected the last call to be didClose")
            return
        }
    }

    // MARK: - 12. didSave

    /// Runs one save scenario end to end and returns what the server was told.
    private func recordedSaves(
        save: TwoTypeOption<Bool, SaveOptions>?
    ) async throws -> (saves: [DidSaveTextDocumentParams], text: String) {
        let settings = makeSettingsStore()
        let log = SessionLog()
        let documents = TextDocumentStore()
        let registry = makeRegistry(
            settings: settings,
            log: log,
            behaviors: ["Fake": .syncing(options(openClose: true, change: .incremental, save: save))]
        )
        let sync = LanguageServerDocumentSync(store: documents, registry: registry)
        sync.start()

        let configuration = makeConfiguration()
        settings.set([configuration], for: UserSettings.languageServerConfigurations)

        let document = documents.open(uri: Self.swiftURI, languageId: "swift", text: Self.initialText)
        // Raises `.dirtyStateChanged(isDirty: true)`, which must produce
        // nothing at all.
        edit(document, at: 0, with: "X")
        // The only save-shaped signal the store emits.
        document.markClean()

        await sync.shutdown()

        let session = try fake(registry, for: configuration.id)
        let saves = log.calls(forInstance: session.instanceID).compactMap { call -> DidSaveTextDocumentParams? in
            guard case .didSave(let params) = call else { return nil }
            return params
        }
        return (saves, document.text)
    }

    /// D8. What it catches: a `didSave` sent on the dirty *and* the clean
    /// transition (twice the traffic, and one of them a lie), a server that
    /// asked for the text not getting it, and a server that asked for no
    /// `didSave` getting one anyway.
    @Test("didSave follows the clean transition and honours includeText")
    func didSaveHonoursSaveOptions() async throws {
        let withoutText = try await recordedSaves(save: .optionA(true))
        #expect(withoutText.saves.count == 1)
        #expect(withoutText.saves.first?.textDocument.uri == Self.swiftURI)
        #expect(withoutText.saves.first?.text == nil)

        let withText = try await recordedSaves(save: .optionB(SaveOptions(includeText: true)))
        #expect(withText.saves.count == 1)
        #expect(withText.saves.first?.text == withText.text)

        let disabledByFalse = try await recordedSaves(save: .optionA(false))
        #expect(disabledByFalse.saves.isEmpty)

        let notDeclared = try await recordedSaves(save: nil)
        #expect(notDeclared.saves.isEmpty)
    }

    // MARK: - 13. Shutdown

    /// What it catches: a `shutdown()` that cancels rather than drains (queued
    /// notifications silently lost, so the server's last state is whatever it
    /// happened to have received), and one that leaves the store observer
    /// installed so a document touched afterwards still feeds a dead pipeline.
    @Test("shutdown drains every queued event and leaves nothing running")
    func shutdownDrains() async throws {
        let settings = makeSettingsStore()
        let log = SessionLog()
        let documents = TextDocumentStore()
        let registry = makeRegistry(
            settings: settings,
            log: log,
            behaviors: ["Fake": .syncing(options(openClose: true, change: .incremental))]
        )
        let sync = LanguageServerDocumentSync(store: documents, registry: registry)
        sync.start()

        let configuration = makeConfiguration()
        settings.set([configuration], for: UserSettings.languageServerConfigurations)

        let document = documents.open(uri: Self.swiftURI, languageId: "swift", text: Self.initialText)
        for character in 0..<4 {
            edit(document, at: character, with: "X")
        }
        documents.close(uri: Self.swiftURI)

        // No poll and no sleep: this is the drain.
        await sync.shutdown()

        let session = try fake(registry, for: configuration.id)
        let afterShutdown = log.calls(forInstance: session.instanceID)
        #expect(afterShutdown.count == 7) // start + open + 4 changes + close
        #expect(changes(in: afterShutdown).map(\.textDocument.version) == [1, 2, 3, 4])

        // Nothing is left listening, so this can produce no further traffic.
        // Asserted behaviourally rather than by exposing a task handle for the
        // test to inspect.
        let reopened = documents.open(uri: Self.swiftURI, languageId: "swift", text: Self.initialText)
        edit(reopened, at: 0, with: "Q")
        documents.close(uri: Self.swiftURI)
        #expect(log.calls(forInstance: session.instanceID) == afterShutdown)
    }
}
