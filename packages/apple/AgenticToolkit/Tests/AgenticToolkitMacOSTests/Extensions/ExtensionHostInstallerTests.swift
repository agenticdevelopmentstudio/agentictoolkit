//
//  ExtensionHostInstallerTests.swift
//  AgenticToolkitMacOSTests
//

import Testing
import Foundation
import JavaScriptCore
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// A mutable `ExtensionWorkspaceRoots` double, so a test can move the
/// "open project" out from under a running installer the way a real project
/// switch does — synchronously, with no notification of its own.
@MainActor
private final class TestWorkspaceRoots: ExtensionWorkspaceRoots {
    var workspaceDisplayName: String?
    var workspaceRootURLs: [URL]

    init(name: String? = nil, urls: [URL] = []) {
        workspaceDisplayName = name
        workspaceRootURLs = urls
    }
}

/// A minimal `ExtensionLanguageModelProviding` double — these tests never
/// exercise `vscode.lm`, they only have to supply *something* conforming so
/// `ExtensionHostSeams` can be built.
@MainActor
private final class NullLanguageModelProvider: ExtensionLanguageModelProviding {
    let availableChatModels: [LanguageModelChatDescriptor] = []

    func streamResponse(
        for model: LanguageModelChatDescriptor, messages: [ExtensionLanguageModelMessage],
        justification: String?, extensionIdentifier: String
    ) async throws -> AsyncThrowingStream<ExtensionLanguageModelResponsePart, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

/// `ExtensionHostInstaller`, `ClosureWorkspaceRoots` and `ExtensionHostSeams`
/// — the collaborator that brings extension hosts up, and the two small
/// types either side of it. None of the three had a test before this task.
@MainActor
@Suite(.serialized)
struct ExtensionHostInstallerTests {

    // MARK: - Fixtures

    private func makeTempDirectory() throws -> URL {
        try ExtensionFixtures.makeTemporaryDirectory("ExtensionHostInstallerTests")
    }

    private func write(_ contents: String, to relativePath: String, in directory: URL) throws {
        try ExtensionFixtures.write(contents, to: relativePath, in: directory)
    }

    /// A settle time for a host's real JS to run and its promises to
    /// resolve, matching the `.milliseconds(400)` convention `ExtensionHostTests`
    /// already uses for the same kind of wait.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(400))
    }

    /// Whether `identifier`'s host ran far enough to set its own
    /// `globalThis.__activated` — the same "read a JS global back out"
    /// idiom `MainThreadLanguageModelsTests` uses, applied directly rather
    /// than through that file's private `waitForGlobal` helper.
    private func activated(_ installer: ExtensionHostInstaller, _ identifier: String) throws -> Bool {
        let installation = try #require(installer.installations[identifier])
        let context = try #require(installation.host.javaScriptContext)
        return context.evaluateScript("globalThis.__activated")?.toBool() ?? false
    }

    // MARK: - ClosureWorkspaceRoots

    /// The installer's own doc comment on `ClosureWorkspaceRoots` says why
    /// this matters: a host is built once, at launch, with no project open —
    /// snapshotting at construction would answer `nil` forever. Pinned here
    /// directly against the closure, with no host involved at all.
    @Test("ClosureWorkspaceRoots reads its answer through the closure every time, never snapshotting")
    func closureWorkspaceRootsReadsThroughEveryCall() {
        var current: ExtensionWorkspaceRoots? = TestWorkspaceRoots(
            name: "first", urls: [URL(fileURLWithPath: "/first")])
        let roots = ClosureWorkspaceRoots(current: { current })

        #expect(roots.workspaceDisplayName == "first")
        #expect(roots.workspaceRootURLs == [URL(fileURLWithPath: "/first")])

        // The same `ClosureWorkspaceRoots` instance, asked again after the
        // thing it forwards to changed underneath it.
        current = TestWorkspaceRoots(name: "second", urls: [URL(fileURLWithPath: "/second")])
        #expect(roots.workspaceDisplayName == "second")
        #expect(roots.workspaceRootURLs == [URL(fileURLWithPath: "/second")])

        // No project open at all — the no-workspace case a launch-time host
        // is built into.
        current = nil
        #expect(roots.workspaceDisplayName == nil)
        #expect(roots.workspaceRootURLs == [])
    }

    // MARK: - ExtensionHostSeams

    /// `openDocumentLanguageIDs` is read once per extension brought up
    /// (`bringUp`'s own replay loop), not just stored — pinned by an
    /// `onLanguage:swift` extension that activates at `reconcile()` with no
    /// explicit `documentDidOpen` call, purely because the seam's closure
    /// already reports `"swift"` as open.
    ///
    /// If this seam were dropped in wiring (an installer built with an
    /// always-empty closure) this extension would never activate and this
    /// test would fail — which is the whole point of pinning it this way
    /// rather than by inspecting `ExtensionHostSeams`'s stored properties.
    @Test("the openDocumentLanguageIDs seam activates an onLanguage: extension already open at bringUp")
    func openDocumentLanguageIDsSeamActivatesAnAlreadyOpenLanguage() async throws {
        // Not `withInMemorySettings`: its body closure is a non-async
        // `() throws -> Result`, and this test has to `await` a real host's
        // JS settling — so the swap is inlined instead, exactly as
        // `ExtensionsCoordinatorTests`'s async `installExtensionHosts` tests
        // already do for the same reason.
        let previousSettings = UserSettings.shared
        UserSettings.shared = UserSettings(with: InMemorySettingsStorageProvider())
        defer { UserSettings.shared = previousSettings }

        let extensionsRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: extensionsRoot) }
        let extensionDirectory = extensionsRoot.appendingPathComponent("extlang-1.0.0")
        try write(
            """
            {
                "name": "extlang", "publisher": "test", "version": "1.0.0",
                "displayName": "Ext Lang", "engines": { "vscode": "^1.74.0" },
                "activationEvents": ["onLanguage:swift"], "browser": "dist/web.js"
            }
            """,
            to: "package.json", in: extensionDirectory)
        try write(
            """
            var vscode = require('vscode');
            exports.activate = function () { globalThis.__activated = true; };
            """,
            to: "dist/web.js", in: extensionDirectory)

        let registry = ExtensionRegistry(
            searchPaths: [extensionsRoot], hostVersion: ExtensionRegistry.declaredVSCodeVersion)
        registry.loadAll()
        try #require(registry.extensions.count == 1)

        let seams = ExtensionHostSeams(
            commandRegistry: CommandRegistry(), languageModelProvider: NullLanguageModelProvider(),
            frontWindow: { nil }, footers: { [] }, workspaceRoots: { nil },
            openDocumentLanguageIDs: { ["swift"] })
        let installer = ExtensionHostInstaller(
            registry: registry, notImplementedLedger: NotImplementedLedger(),
            languagePoint: LanguageContributionPoint(), seams: seams)
        defer { installer.disposeAll() }

        installer.reconcile()
        try await settle()

        #expect(try activated(installer, "test.extlang"))
    }

    // MARK: - The workspace-roots scan guard

    /// The exact race `startWorkspaceScanIfNeeded`'s own doc comment
    /// describes: roots A, then B, then back to A while B's walk is still
    /// running. The guard's job is to make sure B's now-stale result can
    /// never freeze in over A merely because it finishes last — pinned end
    /// to end with two real extensions, each `workspaceContains:` a marker
    /// file only its own root has.
    ///
    /// The sequencing that actually exercises the race (not just "A, then
    /// B, then A" back to back) is load-bearing: A's scan must *complete*
    /// before B starts, so `completedScan.roots == A` by the time the test
    /// moves to B — that is what makes the guard in `startWorkspaceScanIfNeeded`
    /// refuse a fresh scan on the return to A (`completedScan?.roots != roots`
    /// is false) rather than simply starting a third scan that would
    /// coincidentally also answer A.
    @Test("a workspace that moves A to B and back to A while B is still scanning never activates B's extension")
    func workspaceRootsAToBToAGuardNeverFreezesInTheStaleMiddleScan() async throws {
        // Inlined for the same reason as the seam test above: this test
        // awaits between calls, and `withInMemorySettings`'s body is not
        // `async`.
        let previousSettings = UserSettings.shared
        UserSettings.shared = UserSettings(with: InMemorySettingsStorageProvider())
        defer { UserSettings.shared = previousSettings }

        let extensionsRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: extensionsRoot) }

        try write(
            """
            {
                "name": "exta", "publisher": "test", "version": "1.0.0",
                "displayName": "Ext A", "engines": { "vscode": "^1.74.0" },
                "activationEvents": ["workspaceContains:a-marker.txt"], "browser": "dist/web.js"
            }
            """,
            to: "package.json", in: extensionsRoot.appendingPathComponent("exta-1.0.0"))
        try write(
            """
            var vscode = require('vscode');
            exports.activate = function () { globalThis.__activated = true; };
            """,
            to: "dist/web.js", in: extensionsRoot.appendingPathComponent("exta-1.0.0"))

        try write(
            """
            {
                "name": "extb", "publisher": "test", "version": "1.0.0",
                "displayName": "Ext B", "engines": { "vscode": "^1.74.0" },
                "activationEvents": ["workspaceContains:b-marker.txt"], "browser": "dist/web.js"
            }
            """,
            to: "package.json", in: extensionsRoot.appendingPathComponent("extb-1.0.0"))
        try write(
            """
            var vscode = require('vscode');
            exports.activate = function () { globalThis.__activated = true; };
            """,
            to: "dist/web.js", in: extensionsRoot.appendingPathComponent("extb-1.0.0"))

        // Two *workspace* roots, distinct from the extensions root above:
        // one directory `workspaceContains:a-marker.txt` can actually
        // match against, and one for `b-marker.txt`.
        let workspaceA = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: workspaceA) }
        try write("a", to: "a-marker.txt", in: workspaceA)

        let workspaceB = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: workspaceB) }
        try write("b", to: "b-marker.txt", in: workspaceB)

        let registry = ExtensionRegistry(
            searchPaths: [extensionsRoot], hostVersion: ExtensionRegistry.declaredVSCodeVersion)
        registry.loadAll()
        try #require(registry.extensions.count == 2)

        let testRoots = TestWorkspaceRoots(urls: [workspaceA])
        let seams = ExtensionHostSeams(
            commandRegistry: CommandRegistry(), languageModelProvider: NullLanguageModelProvider(),
            frontWindow: { nil }, footers: { [] }, workspaceRoots: { testRoots },
            openDocumentLanguageIDs: { [] })
        let installer = ExtensionHostInstaller(
            registry: registry, notImplementedLedger: NotImplementedLedger(),
            languagePoint: LanguageContributionPoint(), seams: seams)
        defer { installer.disposeAll() }

        // Bring both hosts up and let workspace A's scan run to
        // completion — `completedScan.roots` now reads A.
        installer.reconcile()
        try await settle()
        #expect(try activated(installer, "test.exta"))
        #expect(try activated(installer, "test.extb") == false)

        // Move to B (starts B's scan; `scanningRoots == B`), then
        // immediately back to A — *before* B's walk has had any chance
        // to run, since nothing here has awaited yet.
        testRoots.workspaceRootURLs = [workspaceB]
        installer.workspaceDidChange()
        testRoots.workspaceRootURLs = [workspaceA]
        installer.workspaceDidChange()

        // Let B's already-started walk finish. If the guard's live-roots
        // recheck were missing, B's result would land here, extb would
        // activate on a workspace that is showing A, and a later return
        // to B would find `completedScan.roots` wrongly already reading
        // B and never rescan it.
        try await settle()

        #expect(try activated(installer, "test.extb") == false)
    }
}
