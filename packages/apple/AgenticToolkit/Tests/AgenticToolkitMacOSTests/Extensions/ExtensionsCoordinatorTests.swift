import Testing
import AppKit
import Foundation
import AgenticToolkitCore
@testable import AgenticToolkitMacOS

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
}
