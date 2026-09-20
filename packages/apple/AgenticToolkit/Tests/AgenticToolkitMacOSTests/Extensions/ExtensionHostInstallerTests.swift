//
//  ExtensionHostInstallerTests.swift
//  AgenticToolkitMacOSTests
//

import Testing
import AppKit
import Foundation
import JavaScriptCore
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// A flag a command can set from wherever `CommandRegistry` runs it.
///
/// `AppCommand.run` is a plain escaping closure, so what it captures has to be
/// `Sendable`; a lock around one `Bool` is the whole of it.
private final class DisposalMarker: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var wasPressed: Bool { lock.withLock { value } }
    func press() { lock.withLock { value = true } }
}

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

/// The `frontWindow` seam under a test's control: it answers with whatever
/// `window` currently holds and counts how many times it was asked, which is
/// what separates "read fresh at presentation time" from "snapshotted when
/// the presenter was built".
@MainActor
private final class WindowSeamProbe {
    var window: NSWindow?
    private(set) var asked = 0

    func answer() -> NSWindow? {
        asked += 1
        return window
    }
}

/// A `FileSystemServicing` double that records the path of every write it is
/// handed, so a test can ask *which* service two different extensions' `fs`
/// calls arrived at. Only `writeFile` is implemented: nothing here calls the
/// other six, and giving them behavior would invite a future test to lean on
/// something this double does not exist to provide.
private actor RecordingFileSystemService: FileSystemServicing {
    private struct Unused: Error {}

    private(set) var writtenPaths: [String] = []

    func writeFile(atPath path: String, contents: Data, create: Bool, overwrite: Bool) async throws {
        writtenPaths.append(path)
    }

    func readFile(atPath path: String) async throws -> Data { throw Unused() }

    func readDirectory(atPath path: String) async throws -> [FileSystemService.DirectoryEntry] {
        throw Unused()
    }

    func stat(atPath path: String) async throws -> FileSystemService.FileStat { throw Unused() }

    func createDirectory(atPath path: String) async throws { throw Unused() }

    func delete(atPath path: String, recursive: Bool, useTrash: Bool) async throws { throw Unused() }

    func rename(fromPath: String, toPath: String, overwrite: Bool) async throws { throw Unused() }
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
    ///
    /// **No context is an answer, not a missing one.** `ExtensionHost` builds
    /// its `JSContext` inside `performActivation()`, so a host whose
    /// activation was never started has none — which is the strongest form of
    /// "did not activate" there is. Requiring one here would have turned the
    /// negative cases into failures reading `Expectation failed:
    /// installation.host.javaScriptContext`, which says nothing about the
    /// behaviour under test.
    private func activated(_ installer: ExtensionHostInstaller, _ identifier: String) throws -> Bool {
        let installation = try #require(installer.installations[identifier])
        guard let context = installation.host.javaScriptContext else { return false }
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
            placeWebviewPanel: { _ in nil },
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
            placeWebviewPanel: { _ in nil },
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

    // MARK: - One file system, shared by every host

    /// `MainThreadWorkspace`'s own doc on `fileSystemService` says why this
    /// has to be one instance: "an instance per extension is a serial queue
    /// per extension, which is no write ordering between two extensions at
    /// all." Nothing pinned it, because the installer built the service
    /// itself and no test could see which one any host got.
    ///
    /// It is a seam now, so the claim is checkable from outside: two real
    /// extensions each write a file through `vscode.workspace.fs`, and the
    /// single injected service is asked what it saw. Both writes, or the
    /// hosts are not sharing it.
    ///
    /// Pinned through the JavaScript boundary rather than by comparing object
    /// identity on a stored property: identity would pass just as happily if
    /// the adaptor stopped routing `fs` through the service it was handed.
    @Test("every host's vscode.workspace.fs reaches the one injected file system")
    func everyHostSharesOneFileSystemService() async throws {
        // Inlined for the same reason as the tests above: this one awaits
        // real JS settling, and `withInMemorySettings`'s body is not `async`.
        let previousSettings = UserSettings.shared
        UserSettings.shared = UserSettings(with: InMemorySettingsStorageProvider())
        defer { UserSettings.shared = previousSettings }

        let extensionsRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: extensionsRoot) }

        // Two extensions, each activating at startup and writing one path
        // only it writes — so what the service recorded says *which*
        // extensions reached it, not merely how many writes did.
        for name in ["extone", "exttwo"] {
            let directory = extensionsRoot.appendingPathComponent("\(name)-1.0.0")
            try write(
                """
                {
                    "name": "\(name)", "publisher": "test", "version": "1.0.0",
                    "displayName": "Ext \(name)", "engines": { "vscode": "^1.74.0" },
                    "activationEvents": ["*"], "browser": "dist/web.js"
                }
                """,
                to: "package.json", in: directory)
            // The path is never touched on disk — the recording double is
            // what answers `writeFile` — so `/tmp` here names nothing real.
            try write(
                """
                var vscode = require('vscode');
                exports.activate = function () {
                    vscode.workspace.fs.writeFile(
                        vscode.Uri.file('/tmp/\(name)-wrote-this'), new Uint8Array([1]));
                    globalThis.__activated = true;
                };
                """,
                to: "dist/web.js", in: directory)
        }

        let registry = ExtensionRegistry(
            searchPaths: [extensionsRoot], hostVersion: ExtensionRegistry.declaredVSCodeVersion)
        registry.loadAll()
        try #require(registry.extensions.count == 2)

        let fileSystem = RecordingFileSystemService()
        let seams = ExtensionHostSeams(
            commandRegistry: CommandRegistry(), languageModelProvider: NullLanguageModelProvider(),
            frontWindow: { nil }, footers: { [] }, workspaceRoots: { nil },
            placeWebviewPanel: { _ in nil },
            openDocumentLanguageIDs: { [] }, fileSystemService: fileSystem)
        let installer = ExtensionHostInstaller(
            registry: registry, notImplementedLedger: NotImplementedLedger(),
            languagePoint: LanguageContributionPoint(), seams: seams)
        defer { installer.disposeAll() }

        installer.reconcile()
        try await settle()
        try #require(try activated(installer, "test.extone"))
        try #require(try activated(installer, "test.exttwo"))

        let written = await fileSystem.writtenPaths
        #expect(written.contains("/tmp/extone-wrote-this"))
        #expect(written.contains("/tmp/exttwo-wrote-this"))
    }

    // MARK: - The frontWindow seam

    /// Where an extension's `show*Message` sheet attaches is the
    /// `frontWindow` seam's whole job, and nothing pinned that it is wired
    /// into the presenter at all — the installer builds the presenter
    /// privately, and the only other way to find out is to show an alert,
    /// which is a sheet on somebody's screen.
    ///
    /// So the check is made against `NSAlertMessagePresenter.sheetWindow()`,
    /// the window decision split out of `presentedResponse(for:)` for exactly
    /// this, and it pins both halves of the seam's contract: the installer
    /// routes it into the message presenter, and the presenter asks it at
    /// presentation time rather than snapshotting an answer when it was
    /// built. A cached seam is the failure this catches — a menu-bar app
    /// spends most of its life with no window at all, so the window a host
    /// was constructed against is routinely the wrong one by the time an
    /// extension speaks.
    @Test("the frontWindow seam is what the installer's message sheets attach to, read fresh every time")
    func frontWindowSeamReachesTheMessagePresenterAndIsReadFresh() throws {
        let extensionsRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: extensionsRoot) }

        // Never ordered front, never made visible: `sheetWindow()` answers
        // from the closure, and nothing here shows anything.
        let probe = WindowSeamProbe()
        let first = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.titled], backing: .buffered, defer: true)
        probe.window = first

        let registry = ExtensionRegistry(
            searchPaths: [extensionsRoot], hostVersion: ExtensionRegistry.declaredVSCodeVersion)
        let seams = ExtensionHostSeams(
            commandRegistry: CommandRegistry(), languageModelProvider: NullLanguageModelProvider(),
            frontWindow: { probe.answer() }, footers: { [] }, workspaceRoots: { nil },
            placeWebviewPanel: { _ in nil },
            openDocumentLanguageIDs: { [] })
        let installer = ExtensionHostInstaller(
            registry: registry, notImplementedLedger: NotImplementedLedger(),
            languagePoint: LanguageContributionPoint(), seams: seams)
        defer { installer.disposeAll() }

        // Building the installer must not have asked yet: an answer taken
        // here is an answer from before any window existed.
        #expect(probe.asked == 0)

        let presenter = installer.collaborators.messagePresenter
        #expect(presenter.sheetWindow() === first)
        #expect(probe.asked == 1)

        // The front window changed, as it does whenever someone switches
        // projects. The next message follows it.
        let second = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.titled], backing: .buffered, defer: true)
        probe.window = second
        #expect(presenter.sheetWindow() === second)
        #expect(probe.asked == 2)
    }
    // MARK: - The order teardown runs in

    /// What an extension pushes onto `context.subscriptions` is, by design,
    /// the things that reach back into the app, and they can only do anything
    /// while the adaptors they reach through are still standing.
    ///
    /// `ExtensionHost.dispose()` is what runs them — upstream's
    /// `dispose(context.subscriptions)` — and it was called **last**, after all
    /// eight adaptors had already been swept. So every one of those `dispose`
    /// blocks ran against an adaptor that had finished tearing down, and the
    /// work in them was dropped.
    ///
    /// Pinned on the one withdrawal that is observable from here: a command the
    /// extension registered through `vscode.commands.registerCommand`. That is
    /// exactly what `MainThreadCommands.dispose()` withdraws, so an extension
    /// whose teardown calls its own command — a "flush my state" command, which
    /// is the ordinary shape of this — finds it already gone and its flush
    /// never runs. Nothing reports that: `executeCommand` on an id nobody
    /// answers is a rejected promise, and a `dispose` block does not await.
    ///
    /// The extension's command reaches back out through a second command the
    /// *test* registered on `CommandRegistry` directly. That one is not the
    /// extension's, so no adaptor withdraws it, and it is the marker that says
    /// the extension's own command was still live when its teardown ran.
    @Test("an extension's context.subscriptions are disposed while the adaptors still work")
    func subscriptionsAreDisposedBeforeTheAdaptors() async throws {
        let previousSettings = UserSettings.shared
        UserSettings.shared = UserSettings(with: InMemorySettingsStorageProvider())
        defer { UserSettings.shared = previousSettings }

        let extensionsRoot = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: extensionsRoot) }

        let directory = extensionsRoot.appendingPathComponent("teardown-1.0.0")
        try write(
            """
            {
                "name": "teardown", "publisher": "test", "version": "1.0.0",
                "displayName": "Teardown", "engines": { "vscode": "^1.74.0" },
                "activationEvents": ["*"], "browser": "dist/web.js"
            }
            """,
            to: "package.json", in: directory)
        try write(
            """
            var vscode = require('vscode');
            exports.activate = function (context) {
                // Pushed before the registration it calls: subscriptions are
                // disposed in push order, so an extension whose cleanup uses
                // its own command has to put the cleanup first or unregister
                // the command out from under itself. That is the extension's
                // rule to follow, and this one follows it.
                context.subscriptions.push({
                    dispose: function () {
                        vscode.commands.executeCommand('test.teardown.flush');
                    }
                });
                context.subscriptions.push(
                    vscode.commands.registerCommand('test.teardown.flush', function () {
                        vscode.commands.executeCommand('test.disposal-marker');
                    }));
                globalThis.__activated = true;
            };
            """,
            to: "dist/web.js", in: directory)

        let registry = ExtensionRegistry(
            searchPaths: [extensionsRoot], hostVersion: ExtensionRegistry.declaredVSCodeVersion)
        registry.loadAll()
        try #require(registry.extensions.count == 1)

        let marker = DisposalMarker()
        let commandRegistry = CommandRegistry()
        _ = commandRegistry.register(
            AppCommand(id: "test.disposal-marker", title: "Disposal marker") {
                marker.press()
            })

        let seams = ExtensionHostSeams(
            commandRegistry: commandRegistry, languageModelProvider: NullLanguageModelProvider(),
            frontWindow: { nil }, footers: { [] }, workspaceRoots: { nil },
            placeWebviewPanel: { _ in nil },
            openDocumentLanguageIDs: { [] })
        let installer = ExtensionHostInstaller(
            registry: registry, notImplementedLedger: NotImplementedLedger(),
            languagePoint: LanguageContributionPoint(), seams: seams)

        installer.reconcile()
        try await settle()
        try #require(try activated(installer, "test.teardown"))
        try #require(!marker.wasPressed)

        installer.disposeAll()
        try await settle()
        #expect(marker.wasPressed)
    }
}
