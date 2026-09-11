//
//  ProjectLanguageServicesTests.swift
//  AgenticToolkit
//

import Foundation
import LanguageServerProtocol
import Testing
@testable import AgenticToolkitLanguage
@testable import AgenticToolkitMacOS

/// The per-window language-server stack.
///
/// The one behaviour worth a test is the teardown order. Everything else this
/// type does is delegation, and the order is the part that is invisible when it
/// is wrong: shutting the registry down first kills the subprocesses underneath
/// the drains, and every `didClose`/`didSave` still queued fails against a dead
/// pipe — a leak that only shows up as a server that never released its files.
@Suite("ProjectLanguageServices")
@MainActor
struct ProjectLanguageServicesTests {

    @Test("shutdown drains the document sync before it stops the servers")
    func shutdownDrainsTheSyncFirst() async throws {
        // A real directory: the sync's workspace-scope filter compares resolved
        // paths, so a document has to genuinely live under the root to be
        // forwarded at all.
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ProjectLanguageServicesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fixture = LSPEditorFixture(
            workspaceURL: root,
            behavior: FakeEditorSessionBehavior(capabilities: makeSyncingCapabilities())
        )
        let store = TextDocumentStore()
        let services = ProjectLanguageServices(documentStore: store, registry: fixture.registry)
        services.start()
        _ = try await fixture.startedSession()

        let uri = root.appendingPathComponent("Inside.swift").documentUri
        store.open(uri: uri, languageId: "swift", text: "let x = 1")
        store.close(uri: uri)

        await services.shutdown()

        let events = fixture.log.events
        let didOpen = try #require(events.firstIndex(of: "didOpen(\(uri))"))
        let didClose = try #require(events.firstIndex(of: "didClose(\(uri))"))
        let stop = try #require(events.firstIndex(of: "stop"))

        #expect(didOpen < didClose)
        // The assertion that matters: the close reached a *running* server. The
        // fake throws `.notRunning` after `stop()`, so a registry-first shutdown
        // would not merely reorder this — the `didClose` would never be logged
        // at all, and the `#require` above would fail.
        #expect(didClose < stop)
    }

    @Test("shutdown is idempotent, and start after it does nothing")
    func shutdownIsIdempotent() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ProjectLanguageServicesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fixture = LSPEditorFixture(
            workspaceURL: root,
            behavior: FakeEditorSessionBehavior(capabilities: makeSyncingCapabilities())
        )
        let store = TextDocumentStore()
        let services = ProjectLanguageServices(documentStore: store, registry: fixture.registry)
        services.start()
        _ = try await fixture.startedSession()

        await services.shutdown()
        await services.shutdown()
        // A window closing races its own teardown; a second `start()` must not
        // resurrect a stack whose sessions are gone.
        services.start()

        let uri = root.appendingPathComponent("Inside.swift").documentUri
        store.open(uri: uri, languageId: "swift", text: "let x = 1")

        #expect(fixture.log.events.filter { $0 == "stop" }.count == 1)
        #expect(!fixture.log.events.contains("didOpen(\(uri))"))
    }

    /// ★ F42, the wiring half. The store's pruning is only a behaviour if
    /// something calls it, and `ProjectLanguageServices` is the only object
    /// that holds both the document store and the diagnostic store — so a
    /// `clear(uri:)` with no caller is exactly as much of a defect as no
    /// `clear(uri:)` at all.
    ///
    /// Asserted through the real stack rather than on the store alone, because
    /// the thing that was missing is the wire, not the method.
    @Test("closing a document prunes its diagnostics from the project's store")
    func closingADocumentPrunesItsDiagnostics() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ProjectLanguageServicesTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fixture = LSPEditorFixture(
            workspaceURL: root,
            behavior: FakeEditorSessionBehavior(capabilities: makeSyncingCapabilities())
        )
        let store = TextDocumentStore()
        let services = ProjectLanguageServices(documentStore: store, registry: fixture.registry)
        services.start()
        let session = try await fixture.startedSession()

        let uri = root.appendingPathComponent("Inside.swift").documentUri
        store.open(uri: uri, languageId: "swift", text: "let x = 1")
        session.publish(PublishDiagnosticsParams(
            uri: uri,
            version: 1,
            diagnostics: [
                Diagnostic(
                    range: LSPRange(start: Position(line: 0, character: 0), end: Position(line: 0, character: 3)),
                    severity: .error,
                    message: "no"
                )
            ]
        ))
        #expect(await poll { services.diagnostics.diagnostics(for: uri).count == 1 })

        // A split view on the same file: one document, two opens.
        store.open(uri: uri, languageId: "swift", text: "let x = 1")
        store.close(uri: uri)
        #expect(services.diagnostics.diagnostics(for: uri).count == 1)

        store.close(uri: uri)
        #expect(services.diagnostics.diagnostics(for: uri).isEmpty)

        await services.shutdown()
    }

    /// Ceiling on the one poll here: the publish lands from an unstructured
    /// `Task` draining an `AsyncStream`, so it is not visible on the statement
    /// after the push.
    private func poll(seconds: TimeInterval = 5, until condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}
