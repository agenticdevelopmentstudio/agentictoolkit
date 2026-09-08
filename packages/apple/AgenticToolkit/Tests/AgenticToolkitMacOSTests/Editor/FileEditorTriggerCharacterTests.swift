//
//  FileEditorTriggerCharacterTests.swift
//  AgenticToolkit
//

import AgenticToolkitCore
import AppKit
import CodeEditSourceEditor
import Foundation
import LanguageServerProtocol
import Testing
@testable import AgenticToolkitLanguage
@testable import AgenticToolkitMacOS

/// How a language server's completion trigger characters reach the editor.
///
/// This is the path that decides whether typing `.` opens the completion
/// window at all, and it is not the obvious one: `CodeSuggestionDelegate`
/// declares `completionTriggerCharacters()`, but nothing in this version of
/// `CodeEditSourceEditor` calls it — `SuggestionTriggerCharacterModel` reads
/// `configuration.peripherals.codeSuggestionTriggerCharacters` off the
/// controller instead. So the assertion that matters is against the
/// *configuration the editor is built with*, not against the delegate.
@Suite("File editor completion trigger characters")
@MainActor
struct FileEditorTriggerCharacterTests {

    /// Only the appearance half of the configuration reads this, and no
    /// assertion here touches appearance — but `editorConfiguration(for:palette:)`
    /// needs a real one, and the environment's own default is this theme.
    private let palette = SemanticPalette(theme: BuiltInThemes.solarizedDark)

    private func makeTemporaryDirectory() throws -> URL {
        // `FileEditorState.load` builds a `CodeLanguage`, which is what needs
        // CodeEditLanguages' resource bundle located under the test host.
        ensureEditorLanguageResourcesLocated()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileEditorTriggerCharacterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("the trigger characters the server declares reach the configuration the editor is built with")
    func serverTriggerCharactersReachTheEditorConfiguration() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("A.swift")
        try "let x = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)

        // Not `.`, `(`, `:` — those are sourcekit-lsp's answer, and a
        // hardcoded default would pass a test written against them while being
        // a silent wrong answer for every other server.
        let fixture = LSPEditorFixture(
            workspaceURL: directory,
            behavior: FakeEditorSessionBehavior(
                capabilities: makeCompletingCapabilities(triggerCharacters: ["@", "#"])
            )
        )
        _ = try await fixture.startedSession()

        let store = TextDocumentStore()
        let scheduler = TextDocumentSaveScheduler(debounce: .seconds(60), write: { _ in })
        let services = ProjectLanguageServices(documentStore: store, registry: fixture.registry)
        let state = FileEditorState(
            documentStore: store,
            saveScheduler: scheduler,
            languageServices: services,
            openFile: nil
        )

        state.load(from: fileURL)
        await state.awaitPendingLoad()
        await state.awaitPendingTriggerCharacterResolution()

        let uri = fileURL.documentUri
        #expect(state.display == .text(uri: uri))
        // The live path, asserted at the object `makeEditor` hands to
        // `SourceEditor` rather than at a part of it: the peripherals are built
        // inside this call, so cutting the last link — reverting to a
        // hardcoded `.init(showGutter:showMinimap:)` — fails here.
        let configuration = state.editorConfiguration(for: uri, palette: palette)
        #expect(configuration.peripherals.codeSuggestionTriggerCharacters == ["@", "#"])
        // Resolved from the handshake, without any completion having been
        // requested — a set resolved on the first request arrives after the
        // keystroke that should have opened the window.
        #expect(!fixture.log.events.contains("completion"))
    }

    @Test("a pane with no language services builds an editor with no trigger characters")
    func noLanguageServicesMeansNoTriggerCharacters() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("A.swift")
        try "let x = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let store = TextDocumentStore()
        let scheduler = TextDocumentSaveScheduler(debounce: .seconds(60), write: { _ in })
        let state = FileEditorState(
            documentStore: store,
            saveScheduler: scheduler,
            languageServices: nil,
            openFile: nil
        )

        state.load(from: fileURL)
        await state.awaitPendingLoad()
        await state.awaitPendingTriggerCharacterResolution()

        // Empty, not a default set: with no server there is nobody to have
        // declared one, and the package still opens the window on any letter
        // or digit.
        let configuration = state.editorConfiguration(for: fileURL.documentUri, palette: palette)
        #expect(configuration.peripherals.codeSuggestionTriggerCharacters.isEmpty)
    }

    // MARK: - Fix round 2: a session that appears after the slot is open

    /// What it catches: resolving once, at slot-open, and never again.
    ///
    /// The reachable trigger is not exotic. A window opens on a project whose
    /// language server is added or enabled in settings a moment later — or, on
    /// a first run, before the user has configured one at all — and the file on
    /// screen keeps `[]` for as long as its tab stays cached. That is the
    /// completion window never opening on `.`, which is the defect the eager
    /// resolution exists to prevent.
    @Test("a slot opened before its server exists picks up the trigger characters when it appears")
    func aSessionAppearingLaterReachesAnOpenSlot() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("A.swift")
        try "let x = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)

        // No configuration registered, so the registry has no session at all —
        // the only way it can have none.
        let fixture = LSPEditorFixture(
            workspaceURL: directory,
            behavior: FakeEditorSessionBehavior(
                capabilities: makeCompletingCapabilities(triggerCharacters: ["@", "#"])
            ),
            registersConfiguration: false
        )

        let store = TextDocumentStore()
        let scheduler = TextDocumentSaveScheduler(debounce: .seconds(60), write: { _ in })
        let services = ProjectLanguageServices(documentStore: store, registry: fixture.registry)
        let state = FileEditorState(
            documentStore: store,
            saveScheduler: scheduler,
            languageServices: services,
            openFile: nil
        )

        state.load(from: fileURL)
        await state.awaitPendingLoad()
        await state.awaitPendingTriggerCharacterResolution()

        let uri = fileURL.documentUri
        #expect(state.editorConfiguration(for: uri, palette: palette)
            .peripherals.codeSuggestionTriggerCharacters.isEmpty)

        // The user adds the server. The registry reconciles synchronously off
        // the settings publisher, so by the time this returns the session
        // exists and `$sessions` has fired.
        fixture.settings.set([fixture.configuration], for: UserSettings.languageServerConfigurations)
        await state.awaitPendingTriggerCharacterResolution()

        #expect(state.editorConfiguration(for: uri, palette: palette)
            .peripherals.codeSuggestionTriggerCharacters == ["@", "#"])
        // Still from the handshake, not from a completion request.
        #expect(!fixture.log.events.contains("completion"))
    }

    // MARK: - Re-resolution driven by a session's state, not its identity

    /// A state transition reaches this pane by a route with two hops no test
    /// can await — the registry's per-session reader task, and then the
    /// `$sessionStates` sink that task wakes — so unlike the cases above there
    /// is no single in-flight task `awaitPendingTriggerCharacterResolution()`
    /// could cover.
    private func poll(
        seconds: TimeInterval = 3,
        until condition: () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }

    /// Builds the pane over `fixture`, with its session parked mid-handshake in
    /// `.starting` and its slot open and already resolved to nothing.
    ///
    /// Both tests below need the same starting point, and it is four objects
    /// and two awaits of setup that says nothing about either (`dry`). What
    /// each test does *after* this is the test.
    private func openSlotDuringHandshake(
        directory: URL,
        fixture: LSPEditorFixture
    ) async throws -> (state: FileEditorState, fake: FakeEditorLanguageServerSession, uri: DocumentUri) {
        let fileURL = directory.appendingPathComponent("A.swift")
        try "let x = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let session = fixture.registry.session(forLanguageId: "swift")
        let fake = try #require(session as? FakeEditorLanguageServerSession)
        // Moved off `.idle` before the slot opens. The resolution calls
        // `start()` itself, and against an `.idle` session held by
        // `holdsStart` that call parks — the capability read below would never
        // be reached and the test would pass for the wrong reason. From
        // `.starting`, `start()` returns at its "already under way" branch.
        await fake.transition(to: .starting)

        let store = TextDocumentStore()
        let scheduler = TextDocumentSaveScheduler(debounce: .seconds(60), write: { _ in })
        let services = ProjectLanguageServices(documentStore: store, registry: fixture.registry)
        let state = FileEditorState(
            documentStore: store,
            saveScheduler: scheduler,
            languageServices: services,
            openFile: nil
        )

        state.load(from: fileURL)
        await state.awaitPendingLoad()
        await state.awaitPendingTriggerCharacterResolution()

        let uri = fileURL.documentUri
        // Mid-handshake a server has no capabilities to read, so the slot
        // resolves to nothing. This is the state the pane used to be stuck in
        // permanently.
        #expect(state.editorConfiguration(for: uri, palette: palette)
            .peripherals.codeSuggestionTriggerCharacters.isEmpty)
        return (state, fake, uri)
    }

    /// What it catches: `$sessions` as the only trigger for re-resolution. The
    /// registry installs a session and *then* starts it, so nothing about the
    /// handshake finishing touches `sessions` — a slot opened while the server
    /// was still starting keeps the empty set it resolved, forever, and `.`
    /// never opens the completion window in that buffer.
    @Test("a slot resolved mid-handshake picks up the trigger characters when the session starts running")
    func triggerCharactersAreReResolvedWhenASessionReachesRunning() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fixture = LSPEditorFixture(
            workspaceURL: directory,
            behavior: FakeEditorSessionBehavior(
                capabilities: makeCompletingCapabilities(triggerCharacters: ["@", "#"]),
                holdsStart: true
            )
        )
        let (state, fake, uri) = try await openSlotDuringHandshake(directory: directory, fixture: fixture)

        await fake.transition(to: .running)

        let resolved = await poll {
            state.editorConfiguration(for: uri, palette: palette)
                .peripherals.codeSuggestionTriggerCharacters == ["@", "#"]
        }
        #expect(resolved)
        // Still resolved from the handshake rather than from a completion
        // request, as the eager path promises.
        #expect(!fixture.log.events.contains("completion"))
    }

    /// The same wire, in the direction that produces no visible change.
    ///
    /// A start that threw leaves the session in `sessions` looking exactly like
    /// a live one, so `$sessions` is silent here too. The assertion is that the
    /// pane *asked again*: `LSPCompletionDelegate` caches a resolved answer
    /// against the session's identity, and a failure does not change identity,
    /// so a re-resolution against a failed server can only ever produce the
    /// empty set it already had. Counting the capability reads is what
    /// distinguishes "asked and got nothing" from "never asked".
    @Test("a slot re-resolves when its session fails rather than keeping a stale answer")
    func triggerCharactersAreReResolvedWhenASessionFails() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fixture = LSPEditorFixture(
            workspaceURL: directory,
            behavior: FakeEditorSessionBehavior(
                capabilities: makeCompletingCapabilities(triggerCharacters: ["@", "#"]),
                holdsStart: true
            )
        )
        let (state, fake, uri) = try await openSlotDuringHandshake(directory: directory, fixture: fixture)
        let readsBeforeFailure = await fake.capabilityRequestCount

        await fake.transition(to: .failed(LanguageServerFailure(
            error: LanguageServerSessionError.serverExited(status: 1),
            standardErrorText: "error: no such module\n"
        )))

        let askedAgain = await poll { await fake.capabilityRequestCount > readsBeforeFailure }
        #expect(askedAgain)
        #expect(state.editorConfiguration(for: uri, palette: palette)
            .peripherals.codeSuggestionTriggerCharacters.isEmpty)
    }
}
