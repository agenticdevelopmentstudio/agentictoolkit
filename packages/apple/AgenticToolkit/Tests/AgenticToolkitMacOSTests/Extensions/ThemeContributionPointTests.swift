import Testing
import Foundation
import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// An in-memory `ThemeStorage`.
///
/// Copied from `VSCodeThemeImporterTests` rather than shared: the doubles that
/// exist live in `AgenticToolkitCoreTests` and in the AgenticDeveloperToolkit
/// submodule's own test target, and neither is reachable from this bundle. The
/// protocol is three requirements on an `AnyObject`, and nothing here needs a
/// disk or a settings domain.
@MainActor
private final class InMemoryThemeStorage: ThemeStorage {
    var customThemes: [ColorTheme] = []
    var activeThemeID: String?
    /// Never invoked: `onExternalChange` fires for writes that bypass
    /// `ThemeStore`, and these tests make none.
    var onExternalChange: (() -> Void)?
}

/// The `contributes.themes` point. Every test writes real theme files into a
/// temporary directory, because the point's whole job is resolving a declared
/// path against an extension folder and handing the result to the importer —
/// a fixture that skipped the disk would test neither half.
@MainActor
@Suite
struct ThemeContributionPointTests {

    // MARK: - Fixtures

    /// A theme file the importer accepts. `editor.foreground` differs from
    /// `editor.background` (the importer refuses a theme where they match) and
    /// all sixteen ANSI keys are present, because the importer throws naming
    /// the missing ones.
    private static let goodThemeJSON = """
    {
        "name": "The Theme File's Own Name",
        "type": "dark",
        "colors": {
            "editor.foreground": "#D8DEE9",
            "editor.background": "#2E3440",
            "editorCursor.foreground": "#FF00FF",
            "editor.selectionBackground": "#4C566A",
            "terminal.ansiBlack": "#000000",
            "terminal.ansiRed": "#010000",
            "terminal.ansiGreen": "#020000",
            "terminal.ansiYellow": "#030000",
            "terminal.ansiBlue": "#040000",
            "terminal.ansiMagenta": "#050000",
            "terminal.ansiCyan": "#060000",
            "terminal.ansiWhite": "#070000",
            "terminal.ansiBrightBlack": "#080000",
            "terminal.ansiBrightRed": "#090000",
            "terminal.ansiBrightGreen": "#0A0000",
            "terminal.ansiBrightYellow": "#0B0000",
            "terminal.ansiBrightBlue": "#0C0000",
            "terminal.ansiBrightMagenta": "#0D0000",
            "terminal.ansiBrightCyan": "#0E0000",
            "terminal.ansiBrightWhite": "#0F0000"
        }
    }
    """

    /// Valid JSON, but not a theme: no `colors` at all. The point must treat
    /// this as one file's problem, never as a syntax error it could not have
    /// anticipated.
    private static let malformedThemeJSON = #"{ "name": "Broken" }"#

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThemeContributionPointTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Writes `contents` at `relativePath` under `directory`, creating any
    /// intermediate folders the path names.
    private func write(_ contents: String, to relativePath: String, in directory: URL) throws {
        // `isDirectory: true` before anything is resolved against it, for the
        // same reason the contribution points do it: `relativeTo:` resolves
        // against the base's *parent* unless the base is known to be a
        // directory, and a fixture written one level up is a fixture the code
        // under test cannot find.
        let base = URL(fileURLWithPath: directory.path, isDirectory: true)
        let url = URL(fileURLWithPath: relativePath, relativeTo: base)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// `themes` is the raw `contributes.themes` array, spelled at the call
    /// site: the declared path is the thing under test in half these cases.
    private func manifest(name: String, themes: String) throws -> ExtensionManifest {
        let json = """
        {
            "name": "\(name)",
            "publisher": "test",
            "version": "1.0.0",
            "engines": { "vscode": "^1.74.0" },
            "contributes": { "themes": \(themes) }
        }
        """
        return try JSONDecoder().decode(ExtensionManifest.self, from: Data(json.utf8))
    }

    private func themeEntry(label: String, path: String) -> String {
        #"{ "label": "\#(label)", "uiTheme": "vs-dark", "path": "\#(path)" }"#
    }

    private func apply(
        _ manifest: ExtensionManifest,
        to point: ThemeContributionPoint,
        at directory: URL
    ) throws {
        let contributions = try #require(manifest.contributes)
        try point.apply(contributions, from: manifest, at: directory)
    }

    /// A `ColorTheme` to stand in for something the user made themselves.
    /// Built by parsing the same fixture the point parses, because
    /// `ColorTheme` has no cheap literal form and inventing one here would be
    /// a second answer to what a theme is.
    private func userTheme(id: String, in directory: URL) throws -> ColorTheme {
        try write(Self.goodThemeJSON, to: "user-source.json", in: directory)
        var theme = try VSCodeThemeImporter.parse(
            contentsOf: URL(
                fileURLWithPath: "user-source.json",
                relativeTo: URL(fileURLWithPath: directory.path, isDirectory: true)),
            label: "Mine",
            uiTheme: "vs-dark"
        )
        theme.id = id
        theme.attribution = nil
        return theme
    }

    // MARK: - Applying

    @Test("apply imports every declared theme")
    func applyImportsEveryDeclaredTheme() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(Self.goodThemeJSON, to: "themes/one.json", in: directory)
        try write(Self.goodThemeJSON, to: "themes/two.json", in: directory)

        let storage = InMemoryThemeStorage()
        let point = ThemeContributionPoint(themeStore: ThemeStore(storage: storage))

        try apply(
            try manifest(name: "pack", themes: """
            [
                \(themeEntry(label: "One", path: "./themes/one.json")),
                \(themeEntry(label: "Two", path: "./themes/two.json"))
            ]
            """),
            to: point,
            at: directory
        )

        #expect(storage.customThemes.count == 2)
        let ids = storage.customThemes.map(\.id)
        #expect(ids == ["vscode.test.pack.One", "vscode.test.pack.Two"])
        // The manifest's label wins over the theme file's own `name` — both
        // files here say "The Theme File's Own Name".
        let names = storage.customThemes.map(\.name)
        #expect(names == ["One", "Two"])
        #expect(storage.customThemes.allSatisfy { $0.isImported })
        #expect(storage.customThemes.allSatisfy { $0.attribution == "extension:test.pack" })
        #expect(point.importFailures.isEmpty)
    }

    @Test("applying twice leaves one copy")
    func applyingTwiceLeavesOneCopy() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(Self.goodThemeJSON, to: "themes/one.json", in: directory)

        let storage = InMemoryThemeStorage()
        let point = ThemeContributionPoint(themeStore: ThemeStore(storage: storage))
        let declaration = try manifest(
            name: "pack", themes: "[\(themeEntry(label: "One", path: "./themes/one.json"))]")

        try apply(declaration, to: point, at: directory)
        try apply(declaration, to: point, at: directory)

        // `ThemeStore.add` appends with no dedup and custom themes persist, so
        // a non-deterministic id would grow the user's theme list by one copy
        // of everything on every launch.
        #expect(storage.customThemes.count == 1)
        #expect(storage.customThemes.first?.id == "vscode.test.pack.One")
    }

    // MARK: - Withdrawal

    @Test("withdraw deletes only that extension's themes")
    func withdrawDeletesOnlyThatExtensionsThemes() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(Self.goodThemeJSON, to: "themes/one.json", in: directory)

        let storage = InMemoryThemeStorage()
        let point = ThemeContributionPoint(themeStore: ThemeStore(storage: storage))
        let entry = themeEntry(label: "One", path: "./themes/one.json")
        try apply(try manifest(name: "first", themes: "[\(entry)]"), to: point, at: directory)
        try apply(try manifest(name: "second", themes: "[\(entry)]"), to: point, at: directory)
        try #require(storage.customThemes.count == 2)

        point.withdraw(extensionIdentifier: "test.first")

        let ids2 = storage.customThemes.map(\.id)
        #expect(ids2 == ["vscode.test.second.One"])
    }

    @Test("withdrawing the active theme clears the active id")
    func withdrawingTheActiveThemeClearsTheActiveID() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(Self.goodThemeJSON, to: "themes/one.json", in: directory)

        let storage = InMemoryThemeStorage()
        let point = ThemeContributionPoint(themeStore: ThemeStore(storage: storage))
        try apply(
            try manifest(name: "pack", themes: "[\(themeEntry(label: "One", path: "./themes/one.json"))]"),
            to: point,
            at: directory
        )
        storage.activeThemeID = "vscode.test.pack.One"

        point.withdraw(extensionIdentifier: "test.pack")

        // Left set, that id is a lookup nothing can ever satisfy again — and it
        // would snap back to "active" if a reinstall reused it.
        #expect(storage.activeThemeID == nil)
        #expect(storage.customThemes.isEmpty)
    }

    // MARK: - Bad theme files

    @Test("one malformed theme still imports the others")
    func oneMalformedThemeStillImportsTheOthers() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(Self.malformedThemeJSON, to: "themes/bad.json", in: directory)
        try write(Self.goodThemeJSON, to: "themes/good.json", in: directory)

        let storage = InMemoryThemeStorage()
        let point = ThemeContributionPoint(themeStore: ThemeStore(storage: storage))

        try apply(
            try manifest(name: "pack", themes: """
            [
                \(themeEntry(label: "Bad", path: "./themes/bad.json")),
                \(themeEntry(label: "Good", path: "./themes/good.json"))
            ]
            """),
            to: point,
            at: directory
        )

        let ids3 = storage.customThemes.map(\.id)
        #expect(ids3 == ["vscode.test.pack.Good"])
        #expect(point.importFailures.count == 1)
        // The declared spelling, not the resolved URL: the declared spelling is
        // what the extension's author edits.
        #expect(point.importFailures.first?.path == "./themes/bad.json")
        #expect(point.importFailures.first?.extensionIdentifier == "test.pack")
    }

    @Test("every theme malformed throws")
    func everyThemeMalformedThrows() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(Self.malformedThemeJSON, to: "themes/one.json", in: directory)
        try write(Self.malformedThemeJSON, to: "themes/two.json", in: directory)

        let storage = InMemoryThemeStorage()
        let point = ThemeContributionPoint(themeStore: ThemeStore(storage: storage))
        let declaration = try manifest(name: "pack", themes: """
        [
            \(themeEntry(label: "One", path: "./themes/one.json")),
            \(themeEntry(label: "Two", path: "./themes/two.json"))
        ]
        """)
        let contributions = try #require(declaration.contributes)

        // A contribution with nothing at all to show for itself is the one case
        // the registry should record as a refused contribution.
        #expect(throws: ThemeContributionError.everyThemeFailed(count: 2)) {
            try point.apply(contributions, from: declaration, at: directory)
        }
        #expect(storage.customThemes.isEmpty)
        #expect(point.importFailures.count == 2)
    }

    // MARK: - Pruning

    @Test("prune orphans deletes themes of an uninstalled extension")
    func pruneOrphansDeletesThemesOfAnUninstalledExtension() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(Self.goodThemeJSON, to: "themes/one.json", in: directory)

        let storage = InMemoryThemeStorage()
        let point = ThemeContributionPoint(themeStore: ThemeStore(storage: storage))
        let entry = themeEntry(label: "One", path: "./themes/one.json")
        try apply(try manifest(name: "kept", themes: "[\(entry)]"), to: point, at: directory)
        try apply(try manifest(name: "gone", themes: "[\(entry)]"), to: point, at: directory)
        try #require(storage.customThemes.count == 2)

        // What the coordinator does after `loadAll()`: "test.gone" is not among
        // the extensions that loaded this launch, so its folder was deleted
        // while the app was closed and no `withdraw` ever ran for it.
        point.pruneOrphans(installedIdentifiers: ["test.kept"])

        let ids4 = storage.customThemes.map(\.id)
        #expect(ids4 == ["vscode.test.kept.One"])
    }

    @Test("prune orphans keeps user themes with no attribution")
    func pruneOrphansKeepsUserThemesWithNoAttribution() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let storage = InMemoryThemeStorage()
        let store = ThemeStore(storage: storage)
        store.add(try userTheme(id: "user.mine", in: directory))
        let point = ThemeContributionPoint(themeStore: store)

        // No extension at all installed — the harshest input a prune can get.
        point.pruneOrphans(installedIdentifiers: [])

        let ids5 = storage.customThemes.map(\.id)
        #expect(ids5 == ["user.mine"])
    }

    // MARK: - Path resolution

    @Test("a relative theme path resolves against the extension directory")
    func relativeThemePathResolvesAgainstTheExtensionDirectory() throws {
        let parent = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let extensionDirectory = parent.appendingPathComponent("acme.pack-1.0.0")
        try FileManager.default.createDirectory(at: extensionDirectory, withIntermediateDirectories: true)
        try write(Self.goodThemeJSON, to: "themes/one.json", in: extensionDirectory)
        // A decoy one level up, at the path a base URL with no is-directory
        // flag would resolve to. It is malformed, so reading it fails loudly
        // rather than passing this test with the wrong file.
        try write(Self.malformedThemeJSON, to: "themes/one.json", in: parent)

        let storage = InMemoryThemeStorage()
        let point = ThemeContributionPoint(themeStore: ThemeStore(storage: storage))

        try apply(
            try manifest(name: "pack", themes: "[\(themeEntry(label: "One", path: "./themes/one.json"))]"),
            to: point,
            // Deliberately without `isDirectory:` — the shape the registry
            // hands over, and the one `URL(fileURLWithPath:relativeTo:)`
            // resolves against the *parent* unless the point re-makes it.
            at: URL(fileURLWithPath: extensionDirectory.path)
        )

        #expect(point.importFailures.isEmpty)
        let ids6 = storage.customThemes.map(\.id)
        #expect(ids6 == ["vscode.test.pack.One"])
    }
}
