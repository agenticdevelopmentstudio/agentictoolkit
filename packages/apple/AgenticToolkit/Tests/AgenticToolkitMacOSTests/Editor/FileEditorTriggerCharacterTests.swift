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
}
