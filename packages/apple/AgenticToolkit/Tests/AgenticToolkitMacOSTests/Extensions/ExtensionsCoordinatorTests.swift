import Testing
import AppKit
import Foundation
import JavaScriptCore
import AgenticToolkitCore
import AgenticDeveloperToolkitUI
@testable import AgenticToolkitMacOS

/// A minimal `ExtensionLanguageModelProviding` double for the
/// `installExtensionHosts` hand-through tests below.
///
/// `MainThreadLanguageModelsTests.TestLanguageModelProvider` is `private` to
/// that file and not reusable here, so this is a second, deliberately tiny
/// copy — just enough to hand a fixed model list to `vscode.lm` and observe
/// that the exact instance `installExtensionHosts` was given is the one a
/// real extension's JS ends up talking to.
@MainActor
private final class FakeLanguageModelProvider: ExtensionLanguageModelProviding {
    let availableChatModels: [LanguageModelChatDescriptor]

    init(modelCount: Int) {
        availableChatModels = (0..<modelCount).map { index in
            LanguageModelChatDescriptor(
                name: "model-\(index)", id: "model-\(index)", vendor: "fake",
                family: "fake", version: "1", maxInputTokens: 4096)
        }
    }

    func streamResponse(
        for model: LanguageModelChatDescriptor, messages: [ExtensionLanguageModelMessage],
        justification: String?, extensionIdentifier: String
    ) async throws -> AsyncThrowingStream<ExtensionLanguageModelResponsePart, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

/// The feature that brings the extension subsystem up.
///
/// The order inside `init` is the whole contract — points registered, then
/// `install()`, then `loadAll()`, then the theme prune — and `ExtensionRegistry`
/// never replays past extensions against a point registered afterwards. So the
/// way to test the order is not to inspect it but to load a real extension that
/// contributes to every point and see whether each one has it.
///
/// Serialized: `setEnabled` and `install()` both write process-wide state
/// (`UserSettings.shared`, `CustomFileTypeMappings.contributedProvider`).
@MainActor
@Suite(.serialized)
struct ExtensionsCoordinatorTests {

    // MARK: - Fixtures

    private static let snippetJSON =
        #"{ "Log": { "prefix": "log", "body": "print(${1:value})$0", "description": "Print" } }"#

    /// One extension that contributes to all five points at once, so a single
    /// load can show that all five received it.
    private static let everythingManifestJSON = """
    {
        "name": "everything",
        "publisher": "test",
        "version": "1.0.0",
        "displayName": "Everything",
        "engines": { "vscode": "^1.74.0" },
        "contributes": {
            "themes": [{ "label": "Night", "uiTheme": "vs-dark", "path": "./themes/night.json" }],
            "snippets": [{ "language": "widget", "path": "./snippets/widget.json" }],
            "languages": [{ "id": "widget", "extensions": [".widget"] }],
            "configuration": {
                "title": "Everything",
                "properties": {
                    "everything.enabled": { "type": "boolean", "default": true, "description": "On?" }
                }
            },
            "views": { "explorer": [{ "id": "test.tree", "name": "Tree" }] }
        }
    }
    """

    /// An extension whose `engines.vscode` this host does not satisfy. It is
    /// installed, intact and on disk — a host downgrade or a raised engine
    /// floor puts any extension here — and it never reaches a contribution
    /// point, so the only trace of it this launch is a failure entry.
    private static let incompatibleManifestJSON = """
    {
        "name": "oldhost",
        "publisher": "test",
        "version": "1.0.0",
        "engines": { "vscode": "^99.0.0" },
        "contributes": {
            "themes": [{ "label": "Dark", "uiTheme": "vs-dark", "path": "./themes/dark.json" }]
        }
    }
    """

    /// An extension that declares nothing at all — no `contributes` key.
    private static let quietManifestJSON = """
    {
        "name": "quiet",
        "publisher": "test",
        "version": "1.0.0",
        "engines": { "vscode": "^1.74.0" }
    }
    """

    private func makeTempDirectory() throws -> URL {
        try ExtensionFixtures.makeTemporaryDirectory("ExtensionsCoordinatorTests")
    }

    private func write(_ contents: String, to relativePath: String, in directory: URL) throws {
        try ExtensionFixtures.write(contents, to: relativePath, in: directory)
    }

    /// `AppFeature.init` registers itself with `AppFeatureRegistry.shared`, so
    /// every coordinator a test builds has to be taken back out or it outlives
    /// the test in process-wide state.
    private func withCoordinator<Result>(
        searchPaths: [URL],
        themeStorage: ExtensionTestThemeStorage = ExtensionTestThemeStorage(),
        viewRegistry: ComposableTabsViewRegistry? = nil,
        _ body: (ExtensionsCoordinator) throws -> Result
    ) rethrows -> Result {
        let coordinator = ExtensionsCoordinator(
            searchPaths: searchPaths,
            themeStore: ThemeStore(storage: themeStorage),
            viewRegistry: viewRegistry
        )
        defer { coordinator.unregister() }
        return try body(coordinator)
    }

    // MARK: - Tests

    @Test("init registers every contribution point before loading")
    func initRegistersEveryContributionPointBeforeLoading() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let extensionDirectory = root.appendingPathComponent("everything-1.0.0")
            try write(Self.everythingManifestJSON, to: "package.json", in: extensionDirectory)
            try write(ExtensionFixtures.goodThemeJSON, to: "themes/night.json", in: extensionDirectory)
            try write(Self.snippetJSON, to: "snippets/widget.json", in: extensionDirectory)

            // `install()` publishes into a process-wide static; put it back.
            let previousProvider = CustomFileTypeMappings.contributedProvider
            defer { CustomFileTypeMappings.contributedProvider = previousProvider }

            let themeStorage = ExtensionTestThemeStorage()
            let viewRegistry = ComposableTabsViewRegistry()

            try withCoordinator(
                searchPaths: [root], themeStorage: themeStorage, viewRegistry: viewRegistry
            ) { coordinator in
                try #require(coordinator.registry.extensions.count == 1)
                #expect(coordinator.registry.failures.isEmpty)

                // One assertion per point. A point registered after `loadAll()`
                // would be empty here while everything else passed.
                let ids = themeStorage.customThemes.map(\.id)
                #expect(ids == ["vscode.test.everything.Night"])
                #expect(coordinator.snippetStore.snippets(forLanguage: "widget").count == 1)
                #expect(coordinator.languagePoint.mapping(for: "widget") != nil)
                #expect(coordinator.configurationPoint.panel(for: "test.everything") != nil)
                #expect(viewRegistry.isRegistered("extension.test.everything.test.tree"))
                #expect(coordinator.contributedViews.count == 1)

                // `languagePoint.install()` too: registering the point makes it
                // *receive* language entries, but nothing *reads* them until
                // the static provider is published. Miss it and every icon in
                // the tree is unchanged, with no error anywhere.
                #expect(CustomFileTypeMappings.mapping(for: "widget") != nil)
            }
        }
    }

    @Test("the theme prune runs after the load, not before it")
    func theThemePruneRunsAfterTheLoadNotBeforeIt() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let extensionDirectory = root.appendingPathComponent("everything-1.0.0")
            try write(Self.everythingManifestJSON, to: "package.json", in: extensionDirectory)
            try write(ExtensionFixtures.goodThemeJSON, to: "themes/night.json", in: extensionDirectory)
            try write(Self.snippetJSON, to: "snippets/widget.json", in: extensionDirectory)

            let previousProvider = CustomFileTypeMappings.contributedProvider
            defer { CustomFileTypeMappings.contributedProvider = previousProvider }

            // What a previous launch left behind: the theme this extension is
            // about to write again, one from an extension since deleted, and
            // the user's own. The user is looking at the first.
            let themeStorage = ExtensionTestThemeStorage()
            let seed = ThemeStore(storage: themeStorage)
            seed.add(try ExtensionFixtures.colorTheme(
                id: "vscode.test.everything.Night",
                attribution: "extension:test.everything",
                in: root
            ))
            seed.add(try ExtensionFixtures.colorTheme(
                id: "vscode.test.gone.Old", attribution: "extension:test.gone", in: root))
            seed.add(try ExtensionFixtures.colorTheme(
                id: "user.mine", attribution: nil, in: root))
            themeStorage.activeThemeID = "vscode.test.everything.Night"

            try withCoordinator(searchPaths: [root], themeStorage: themeStorage) { coordinator in
                try #require(coordinator.registry.extensions.count == 1)

                // The deleted extension's theme is the only casualty.
                let ids = themeStorage.customThemes.map(\.id)
                #expect(ids == ["vscode.test.everything.Night", "user.mine"])

                // And the ordering assertion. `pruneOrphans` before `loadAll()`
                // would see *no* installed extensions, delete this theme —
                // clearing `activeThemeID` on the way out — and then `apply`
                // would put an identical row back, leaving a list that looks
                // right and a selection that is gone.
                #expect(themeStorage.activeThemeID == "vscode.test.everything.Night")
            }
        }
    }

    @Test("an empty search path loads nothing and does not throw")
    func anEmptySearchPathLoadsNothingAndDoesNotThrow() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            withCoordinator(searchPaths: [root]) { coordinator in
                #expect(coordinator.registry.extensions.isEmpty)
                #expect(coordinator.registry.failures.isEmpty)
                #expect(coordinator.contributedViews.isEmpty)
                // No extensions is the normal case on every install today, so
                // it must be a quiet one, not an error state.
                #expect(coordinator.themePoint.importFailures.isEmpty)
            }
        }
    }

    @Test("a missing search path directory is not a failure")
    func aMissingSearchPathDirectoryIsNotAFailure() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let missing = root.appendingPathComponent("never-created")

            withCoordinator(searchPaths: [missing]) { coordinator in
                #expect(coordinator.registry.extensions.isEmpty)
                #expect(coordinator.registry.failures.isEmpty)
            }

            // Bringing the feature up must not create the folder. A directory
            // that appears in `~` because the app launched is litter, and the
            // empty-state panel names the path either way — it does not need
            // the folder to exist to tell a user where to put an extension.
            #expect(!FileManager.default.fileExists(atPath: missing.path))
        }
    }

    // MARK: - Pruning against a scan that may be incomplete

    @Test("one unreadable manifest anywhere in a search path prunes nothing")
    func aManifestThatDidNotParseStopsTheWholePrune() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let extensionDirectory = root.appendingPathComponent("everything-1.0.0")
            try write(Self.everythingManifestJSON, to: "package.json", in: extensionDirectory)
            try write(ExtensionFixtures.goodThemeJSON, to: "themes/night.json", in: extensionDirectory)
            try write(Self.snippetJSON, to: "snippets/widget.json", in: extensionDirectory)
            // The folder this launch cannot name. Its own themes are what is
            // at stake: the file that names them is the file that would not
            // parse, and no folder name recovers it.
            try write(
                "{ not valid json",
                to: "package.json",
                in: root.appendingPathComponent("themed-ext")
            )

            let previousProvider = CustomFileTypeMappings.contributedProvider
            defer { CustomFileTypeMappings.contributedProvider = previousProvider }

            let themeStorage = ExtensionTestThemeStorage()
            let seed = ThemeStore(storage: themeStorage)
            seed.add(try ExtensionFixtures.colorTheme(
                id: "vscode.test.themed.Dark", attribution: "extension:test.themed", in: root))
            themeStorage.activeThemeID = "vscode.test.themed.Dark"

            try withCoordinator(searchPaths: [root], themeStorage: themeStorage) { coordinator in
                try #require(coordinator.registry.failures.count == 1)
                #expect(coordinator.registry.establishedIdentifiers == nil)

                // Nothing pruned, and nothing deselected. Reconciling against
                // the identifiers that *decoded* would have read "I could not
                // read its manifest" as "it is gone" and deleted the user's
                // themes, permanently, with the folder still on disk (I1).
                let ids = themeStorage.customThemes.map(\.id)
                #expect(ids == ["vscode.test.themed.Dark", "vscode.test.everything.Night"])
                #expect(themeStorage.activeThemeID == "vscode.test.themed.Dark")
            }
        }
    }

    @Test("an extension this host cannot run keeps its themes, and a departed one still loses them")
    func anIncompatibleExtensionKeepsItsThemesWhileTheDepartedOneLosesThem() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let extensionDirectory = root.appendingPathComponent("everything-1.0.0")
            try write(Self.everythingManifestJSON, to: "package.json", in: extensionDirectory)
            try write(ExtensionFixtures.goodThemeJSON, to: "themes/night.json", in: extensionDirectory)
            try write(Self.snippetJSON, to: "snippets/widget.json", in: extensionDirectory)
            try write(
                Self.incompatibleManifestJSON,
                to: "package.json",
                in: root.appendingPathComponent("oldhost-1.0.0")
            )

            let previousProvider = CustomFileTypeMappings.contributedProvider
            defer { CustomFileTypeMappings.contributedProvider = previousProvider }

            // What a previous launch left: a theme from the extension this
            // host has since stopped satisfying, one from an extension really
            // deleted while the app was closed, and the user's own.
            let themeStorage = ExtensionTestThemeStorage()
            let seed = ThemeStore(storage: themeStorage)
            seed.add(try ExtensionFixtures.colorTheme(
                id: "vscode.test.oldhost.Dark", attribution: "extension:test.oldhost", in: root))
            seed.add(try ExtensionFixtures.colorTheme(
                id: "vscode.test.gone.Old", attribution: "extension:test.gone", in: root))
            seed.add(try ExtensionFixtures.colorTheme(id: "user.mine", attribution: nil, in: root))

            try withCoordinator(searchPaths: [root], themeStorage: themeStorage) { coordinator in
                try #require(coordinator.registry.failures.count == 1)

                // Both halves in one list. The incompatible extension keeps
                // its theme because the scan can name it (I2) — it is
                // installed, just not applicable — and the genuinely departed
                // one still loses its theme, which is what says the prune ran
                // at all rather than being switched off by the failure.
                let ids = themeStorage.customThemes.map(\.id)
                #expect(ids == [
                    "vscode.test.oldhost.Dark", "user.mine", "vscode.test.everything.Night"
                ])
            }
        }
    }

    @Test("an extension that stops declaring contributes entirely loses the themes it shipped")
    func anExtensionThatDropsContributesLosesTheThemesItShipped() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            // The update: same identifier, same folder, no `contributes` key
            // at all where the previous version declared a theme.
            try write(
                Self.quietManifestJSON,
                to: "package.json",
                in: root.appendingPathComponent("quiet-1.0.0")
            )

            let themeStorage = ExtensionTestThemeStorage()
            let seed = ThemeStore(storage: themeStorage)
            seed.add(try ExtensionFixtures.colorTheme(
                id: "vscode.test.quiet.Night", attribution: "extension:test.quiet", in: root))
            themeStorage.activeThemeID = "vscode.test.quiet.Night"

            try withCoordinator(searchPaths: [root], themeStorage: themeStorage) { coordinator in
                try #require(coordinator.registry.extensions.count == 1)

                // The composed case Ruling GV exists for, end to end: the
                // registry hands the point `Contributions.empty` rather than
                // skipping it, and the point reconciles against an empty
                // declaration. `pruneOrphans` could never reach this theme —
                // the extension is still installed — so an apply that was
                // never called would orphan it for good.
                #expect(themeStorage.customThemes.isEmpty)
                // And the selection goes with it, rather than pointing at an
                // id that no longer resolves.
                #expect(themeStorage.activeThemeID == nil)
            }
        }
    }

    // MARK: - Document layout

    /// The registry id `ViewsContributionPoint` gives the one view
    /// `everythingManifestJSON` contributes.
    private static let contributedViewID =
        ComposableTabsViewID("extension.test.everything.test.tree")

    /// How many allowances in the installed layout's root name that view.
    /// A count rather than a `contains`, because the hazard on the other side
    /// of this fix is a *duplicate* allowance: `widened(for:)` appends, so a
    /// widening that re-reads the installed layout instead of the base one
    /// grows the spec by one entry every time contributions change.
    private func installedAllowancesForContributedView() -> Int {
        (ComposableTabsLayout.current?.spec.allows ?? [])
            .filter { $0.viewID == Self.contributedViewID }
            .count
    }

    /// Builds the everything extension, installs `base` as the app layout, and
    /// runs `body` with a coordinator already maintaining that layout — the
    /// wiring site's shape, minus the host app no toolkit test can reach.
    private func withMaintainedLayout(
        _ body: (ExtensionsCoordinator) throws -> Void
    ) throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let extensionDirectory = root.appendingPathComponent("everything-1.0.0")
            try write(Self.everythingManifestJSON, to: "package.json", in: extensionDirectory)
            try write(ExtensionFixtures.goodThemeJSON, to: "themes/night.json", in: extensionDirectory)
            try write(Self.snippetJSON, to: "snippets/widget.json", in: extensionDirectory)

            let previousProvider = CustomFileTypeMappings.contributedProvider
            defer { CustomFileTypeMappings.contributedProvider = previousProvider }
            let previousLayout = ComposableTabsLayout.current
            defer { ComposableTabsLayout.install(previousLayout) }

            let viewRegistry = ComposableTabsViewRegistry()
            let base = try ComposableTabsLayout(registry: viewRegistry, spec: .placeholders)
            ComposableTabsLayout.install(base)

            try withCoordinator(searchPaths: [root], viewRegistry: viewRegistry) { coordinator in
                coordinator.maintainDocumentLayout(basedOn: base)
                try body(coordinator)
            }
        }
    }

    @Test("enabling an extension after launch makes its view placeable")
    func enablingAnExtensionAfterLaunchWidensTheLayout() throws {
        try withMaintainedLayout { coordinator in
            // At launch the extension is enabled, so the one-shot widening the
            // wiring site used to do is enough for this much.
            try #require(installedAllowancesForContributedView() == 1)

            coordinator.registry.setEnabled(false, for: "test.everything")
            #expect(installedAllowancesForContributedView() == 0)

            // The defect: the view is registered again, but nothing re-widened
            // the layout, so no allowance names it and the user sees nothing
            // until the app is restarted.
            coordinator.registry.setEnabled(true, for: "test.everything")
            #expect(installedAllowancesForContributedView() == 1)
        }
    }

    @Test("a disable/enable cycle does not accumulate duplicate allowances")
    func aDisableEnableCycleDoesNotAccumulateAllowances() throws {
        try withMaintainedLayout { coordinator in
            let baseAllowances = try #require(ComposableTabsLayout.current?.spec.allows.count) - 1

            for _ in 0..<3 {
                coordinator.registry.setEnabled(false, for: "test.everything")
                coordinator.registry.setEnabled(true, for: "test.everything")
            }

            #expect(installedAllowancesForContributedView() == 1)
            #expect(ComposableTabsLayout.current?.spec.allows.count == baseAllowances + 1)
        }
    }

    @Test("uninstalling an extension takes its allowance back out of the layout")
    func uninstallingAnExtensionNarrowsTheLayout() throws {
        try withMaintainedLayout { coordinator in
            try #require(installedAllowancesForContributedView() == 1)

            try coordinator.registry.uninstall("test.everything")

            // A stale allowance here is worse than a missing one: the id is no
            // longer registered, so the *next* widening fails validation and
            // every later contribution is stranded behind it.
            #expect(installedAllowancesForContributedView() == 0)
            #expect(ComposableTabsLayout.current?.spec.allows.contains {
                !(ComposableTabsLayout.current?.registry.isRegistered($0.viewID) ?? false)
            } == false)
        }
    }

    /// How many allowances in the installed layout's root name the identifier
    /// every extension webview pane is laid out under.
    private func installedAllowancesForWebviewPanes() -> Int {
        (ComposableTabsLayout.current?.spec.allows ?? [])
            .filter { $0.viewID == WebviewPanelSerializer.viewID }
            .count
    }

    /// A webview panel is created at runtime by an extension that is already
    /// running, so no manifest declares it and `widened(for:)` — which reads
    /// contributions — can never name it. Without an allowance of its own, a
    /// stored webview pane comes back as a leaf whose view id the spec does not
    /// allow, and `ComposableTabLayoutSpec.reconcile(_:)` rewrites it to a
    /// placeholder on the way in: no log line, no error, the panel simply gone.
    @Test("installing the hosts makes an extension webview pane placeable")
    func installingTheHostsWidensTheLayoutForWebviewPanes() throws {
        try withMaintainedLayout { coordinator in
            // Nothing has registered the identifier yet, so an allowance here
            // would name an unregistered view and fail validation.
            try #require(installedAllowancesForWebviewPanes() == 0)

            coordinator.installExtensionHosts(
                commandRegistry: CommandRegistry(),
                languageModelProvider: FakeLanguageModelProvider(modelCount: 0),
                frontWindow: { nil }, footers: { [] }, workspaceRoots: { nil },
                openDocumentLanguageIDs: { [] })

            #expect(installedAllowancesForWebviewPanes() == 1)

            // Every later rebuild derives from the base spec again, so the
            // allowance has to be re-added rather than survive — and exactly
            // once, for `aDisableEnableCycleDoesNotAccumulateAllowances`' reason.
            coordinator.registry.setEnabled(false, for: "test.everything")
            coordinator.registry.setEnabled(true, for: "test.everything")
            #expect(installedAllowancesForWebviewPanes() == 1)
        }
    }

    // MARK: - installExtensionHosts

    /// An eagerly-activating (`"*"`) extension with a `browser` entry point,
    /// so `reconcile()` brings its host up and runs its real JS without any
    /// activation trigger from the test.
    private func eagerManifestJSON(name: String) -> String {
        """
        {
            "name": "\(name)", "publisher": "test", "version": "1.0.0",
            "displayName": "\(name)", "engines": { "vscode": "^1.74.0" },
            "activationEvents": ["*"], "browser": "dist/web.js"
        }
        """
    }

    /// A fixed settle time for a host's real JS to activate and finish
    /// running, matching the `.milliseconds(400)` convention already
    /// established in `ExtensionHostTests` for the same kind of wait.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(400))
    }

    /// `installExtensionHosts` builds one `ExtensionHost` per enabled
    /// extension, not one host shared across all of them — pinned by loading
    /// two extensions that each register a *different* real command from
    /// inside their own `activate()`, then showing both commands are
    /// reachable and each runs its own extension's code, not the other's.
    @Test("installExtensionHosts builds one host per extension and runs each one's real code")
    func installExtensionHostsBuildsOneHostPerExtensionAndRunsEachOnesRealCode() async throws {
        // Not `withInMemorySettings`/`withCoordinator`: both take a
        // non-async `throws` closure, and this test has to `await` a real
        // host's JS settling before it can tear anything down — so the swap
        // and the coordinator are built inline instead, with their own
        // `defer`s doing exactly what those two helpers do internally.
        let previousSettings = UserSettings.shared
        UserSettings.shared = UserSettings(with: InMemorySettingsStorageProvider())
        defer { UserSettings.shared = previousSettings }

        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try write(eagerManifestJSON(name: "exta"), to: "package.json", in: root.appendingPathComponent("exta-1.0.0"))
        try write(
            """
            var vscode = require('vscode');
            exports.activate = function () {
                vscode.commands.registerCommand('exta.hello', function () { return 'real-a'; });
            };
            """,
            to: "dist/web.js", in: root.appendingPathComponent("exta-1.0.0"))

        try write(eagerManifestJSON(name: "extb"), to: "package.json", in: root.appendingPathComponent("extb-1.0.0"))
        try write(
            """
            var vscode = require('vscode');
            exports.activate = function () {
                vscode.commands.registerCommand('extb.hello', function () { return 'real-b'; });
            };
            """,
            to: "dist/web.js", in: root.appendingPathComponent("extb-1.0.0"))

        let previousProvider = CustomFileTypeMappings.contributedProvider
        defer { CustomFileTypeMappings.contributedProvider = previousProvider }

        let coordinator = ExtensionsCoordinator(
            searchPaths: [root], themeStore: ThemeStore(storage: ExtensionTestThemeStorage()), viewRegistry: nil)
        defer { coordinator.unregister() }

        try #require(coordinator.registry.extensions.count == 2)

        let commandRegistry = CommandRegistry()
        coordinator.installExtensionHosts(
            commandRegistry: commandRegistry,
            languageModelProvider: FakeLanguageModelProvider(modelCount: 0),
            frontWindow: { nil }, footers: { [] }, workspaceRoots: { nil },
            openDocumentLanguageIDs: { [] })

        try await settle()

        // Read back as `JSValue`, the idiom `MainThreadCommandsTests` uses:
        // `CommandRegistry.execute(id:arguments:)` carries an extension
        // callback's return value **unconverted** on purpose (see its doc), so
        // what comes back is the callback's own `JSValue` and never a bridged
        // `String`.
        let resultA = try #require(try commandRegistry.execute(id: "exta.hello", arguments: []) as? JSValue)
        let resultB = try #require(try commandRegistry.execute(id: "extb.hello", arguments: []) as? JSValue)
        #expect(resultA.toString() == "real-a")
        #expect(resultB.toString() == "real-b")
    }

    /// The `footers` seam reaches a real `WindowFooterStatusBarPresenter`
    /// wired to the actual `WindowFooterBar` `installExtensionHosts` was
    /// given — pinned by an extension that calls the real
    /// `vscode.window.createStatusBarItem()` / `.show()` from its own
    /// `activate()`, then checking the footer itself for a rendered item.
    @Test("installExtensionHosts wires the given footers into a real status bar item")
    func installExtensionHostsWiresTheGivenFootersIntoARealStatusBarItem() async throws {
        let previousSettings = UserSettings.shared
        UserSettings.shared = UserSettings(with: InMemorySettingsStorageProvider())
        defer { UserSettings.shared = previousSettings }

        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let extensionDirectory = root.appendingPathComponent("extc-1.0.0")
        try write(eagerManifestJSON(name: "extc"), to: "package.json", in: extensionDirectory)
        try write(
            """
            var vscode = require('vscode');
            exports.activate = function () {
                var item = vscode.window.createStatusBarItem();
                item.text = 'hi';
                item.show();
            };
            """,
            to: "dist/web.js", in: extensionDirectory)

        let previousProvider = CustomFileTypeMappings.contributedProvider
        defer { CustomFileTypeMappings.contributedProvider = previousProvider }

        let coordinator = ExtensionsCoordinator(
            searchPaths: [root], themeStore: ThemeStore(storage: ExtensionTestThemeStorage()), viewRegistry: nil)
        defer { coordinator.unregister() }

        try #require(coordinator.registry.extensions.count == 1)

        let footer = WindowFooterBar(accessibilityPrefix: "test")
        coordinator.installExtensionHosts(
            commandRegistry: CommandRegistry(),
            languageModelProvider: FakeLanguageModelProvider(modelCount: 0),
            frontWindow: { nil }, footers: { [footer] }, workspaceRoots: { nil },
            openDocumentLanguageIDs: { [] })

        try await settle()

        let container = try #require(footer.trailingAccessories.first as? NSStackView)
        #expect(container.arrangedSubviews.count == 1)
    }

    /// The `languageModelProvider` seam reaches the real
    /// `vscode.lm.selectChatModels()` — pinned by an extension that awaits
    /// that real call and reports the model count back out through a
    /// command the test registered on the same `CommandRegistry` before
    /// installing the hosts, so the count observed is the exact
    /// `FakeLanguageModelProvider` instance `installExtensionHosts` was
    /// given, round-tripped through real JS.
    @Test("installExtensionHosts wires the given languageModelProvider into vscode.lm")
    func installExtensionHostsWiresTheGivenLanguageModelProviderIntoVscodeLm() async throws {
        let previousSettings = UserSettings.shared
        UserSettings.shared = UserSettings(with: InMemorySettingsStorageProvider())
        defer { UserSettings.shared = previousSettings }

        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let extensionDirectory = root.appendingPathComponent("extd-1.0.0")
        try write(eagerManifestJSON(name: "extd"), to: "package.json", in: extensionDirectory)
        try write(
            """
            var vscode = require('vscode');
            exports.activate = function () {
                vscode.lm.selectChatModels().then(function (models) {
                    vscode.commands.executeCommand('test.report', models.length);
                });
            };
            """,
            to: "dist/web.js", in: extensionDirectory)

        let previousProvider = CustomFileTypeMappings.contributedProvider
        defer { CustomFileTypeMappings.contributedProvider = previousProvider }

        let coordinator = ExtensionsCoordinator(
            searchPaths: [root], themeStore: ThemeStore(storage: ExtensionTestThemeStorage()), viewRegistry: nil)
        defer { coordinator.unregister() }

        try #require(coordinator.registry.extensions.count == 1)

        var reportedCount: Int32?
        let commandRegistry = CommandRegistry()
        commandRegistry.register(AppCommand(id: "test.report", title: "Report", run: { arguments in
            // A `JSValue`, not a bridged `Int`: an argument an extension passed
            // to `executeCommand` reaches the registry unconverted, for the
            // reason `CommandRegistry.execute(id:arguments:)` documents.
            reportedCount = (arguments.first as? JSValue)?.toInt32()
            return nil
        }))

        coordinator.installExtensionHosts(
            commandRegistry: commandRegistry,
            languageModelProvider: FakeLanguageModelProvider(modelCount: 3),
            frontWindow: { nil }, footers: { [] }, workspaceRoots: { nil },
            openDocumentLanguageIDs: { [] })

        try await settle()

        #expect(reportedCount == 3)
    }

    /// `installExtensionHosts` subscribes to `registry.contributionsDidChange`
    /// by *chaining* whatever handler was already there, not replacing it —
    /// pinned by assigning a recorder before installing, then triggering a
    /// real later change (`setEnabled`) and checking the recorder still ran
    /// alongside the coordinator's own handling of that change.
    @Test("installExtensionHosts chains the previous contributionsDidChange rather than replacing it")
    func installExtensionHostsChainsThePreviousContributionsDidChangeRatherThanReplacingIt() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let extensionDirectory = root.appendingPathComponent("everything-1.0.0")
            try write(Self.everythingManifestJSON, to: "package.json", in: extensionDirectory)
            try write(ExtensionFixtures.goodThemeJSON, to: "themes/night.json", in: extensionDirectory)
            try write(Self.snippetJSON, to: "snippets/widget.json", in: extensionDirectory)

            let previousProvider = CustomFileTypeMappings.contributedProvider
            defer { CustomFileTypeMappings.contributedProvider = previousProvider }

            try withCoordinator(searchPaths: [root]) { coordinator in
                try #require(coordinator.registry.extensions.count == 1)

                var priorHandlerRuns = 0
                coordinator.registry.contributionsDidChange = { priorHandlerRuns += 1 }

                coordinator.installExtensionHosts(
                    commandRegistry: CommandRegistry(),
                    languageModelProvider: FakeLanguageModelProvider(modelCount: 0),
                    frontWindow: { nil }, footers: { [] }, workspaceRoots: { nil },
                    openDocumentLanguageIDs: { [] })

                // A real, later contribution change — not a direct call to
                // the closure, which would prove nothing about chaining.
                coordinator.registry.setEnabled(false, for: "test.everything")

                #expect(priorHandlerRuns == 1)
            }
        }
    }
}
