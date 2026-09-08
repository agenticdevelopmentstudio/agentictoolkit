//
//  FileEditorTriggerCharacterTests.swift
//  AgenticToolkit
//

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
        // The live path: this is the object `FileEditorContentView.makeEditor`
        // hands to `SourceEditorConfiguration`.
        #expect(state.peripherals(for: uri).codeSuggestionTriggerCharacters == ["@", "#"])
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
        #expect(state.peripherals(for: fileURL.documentUri).codeSuggestionTriggerCharacters.isEmpty)
    }
}
