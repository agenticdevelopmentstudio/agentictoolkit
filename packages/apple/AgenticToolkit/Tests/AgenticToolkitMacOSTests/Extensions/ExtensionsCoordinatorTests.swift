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
}
