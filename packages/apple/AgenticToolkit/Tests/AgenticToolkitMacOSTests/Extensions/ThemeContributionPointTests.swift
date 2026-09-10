import Testing
import Foundation
import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// The `contributes.themes` point. Every test writes real theme files into a
/// temporary directory, because the point's whole job is resolving a declared
/// path against an extension folder and handing the result to the importer —
/// a fixture that skipped the disk would test neither half.
@MainActor
@Suite
struct ThemeContributionPointTests {

    // MARK: - Fixtures

    private func makeTempDirectory() throws -> URL {
        try ExtensionFixtures.makeTemporaryDirectory("ThemeContributionPointTests")
    }

    private func write(_ contents: String, to relativePath: String, in directory: URL) throws {
        try ExtensionFixtures.write(contents, to: relativePath, in: directory)
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

    // MARK: - Applying

    @Test("apply imports every declared theme")
    func applyImportsEveryDeclaredTheme() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(ExtensionFixtures.goodThemeJSON, to: "themes/one.json", in: directory)
        try write(ExtensionFixtures.goodThemeJSON, to: "themes/two.json", in: directory)

        let storage = ExtensionTestThemeStorage()
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
        try write(ExtensionFixtures.goodThemeJSON, to: "themes/one.json", in: directory)

        let storage = ExtensionTestThemeStorage()
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

    @Test("applying again keeps the user's theme selected")
    func applyingAgainKeepsTheActiveThemeSelected() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(ExtensionFixtures.goodThemeJSON, to: "themes/one.json", in: directory)

        let storage = ExtensionTestThemeStorage()
        let point = ThemeContributionPoint(themeStore: ThemeStore(storage: storage))
        let declaration = try manifest(
            name: "pack", themes: "[\(themeEntry(label: "One", path: "./themes/one.json"))]")

        try apply(declaration, to: point, at: directory)
        // The user picks the contributed theme, and the app is relaunched.
        storage.activeThemeID = "vscode.test.pack.One"
        try apply(declaration, to: point, at: directory)

        // `ThemeStore.delete` clears `activeThemeID`, so reconciling by
        // deleting the row and adding it back under the same id would silently
        // deselect the theme on every launch — by the code whose job is to make
        // that theme available.
        #expect(storage.activeThemeID == "vscode.test.pack.One")
        #expect(storage.customThemes.map(\.id) == ["vscode.test.pack.One"])
    }

    @Test("a renamed theme label leaves no orphan behind")
    func aRenamedThemeLabelLeavesNoOrphan() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(ExtensionFixtures.goodThemeJSON, to: "themes/one.json", in: directory)

        let storage = ExtensionTestThemeStorage()
        let point = ThemeContributionPoint(themeStore: ThemeStore(storage: storage))

        try apply(
            try manifest(name: "pack", themes: "[\(themeEntry(label: "One", path: "./themes/one.json"))]"),
            to: point,
            at: directory
        )
        // The extension updates and renames its theme. The old id matches an
        // installed extension, so `pruneOrphans` will never touch it — a
        // successful apply is the only place it can go.
        try apply(
            try manifest(name: "pack", themes: "[\(themeEntry(label: "Two", path: "./themes/one.json"))]"),
            to: point,
            at: directory
        )

        #expect(storage.customThemes.map(\.id) == ["vscode.test.pack.Two"])
    }

    @Test("reconciling never reaches another extension's themes")
    func reconcilingNeverReachesAnotherExtensionsThemes() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(ExtensionFixtures.goodThemeJSON, to: "themes/one.json", in: directory)

        let storage = ExtensionTestThemeStorage()
        let store = ThemeStore(storage: storage)
        // A theme from another extension, and one the user imported themselves.
        store.add(try ExtensionFixtures.colorTheme(
            id: "vscode.test.other.One", attribution: "extension:test.other", in: directory))
        store.add(try ExtensionFixtures.colorTheme(
            id: "user.mine", attribution: nil, in: directory))
        let point = ThemeContributionPoint(themeStore: store)

        try apply(
            try manifest(name: "pack", themes: "[\(themeEntry(label: "One", path: "./themes/one.json"))]"),
            to: point,
            at: directory
        )

        #expect(storage.customThemes.map(\.id)
            == ["vscode.test.other.One", "user.mine", "vscode.test.pack.One"])
    }

    @Test("a wholly failed import leaves the previous launch's themes alone")
    func aWhollyFailedImportLeavesPreviousThemesAlone() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(ExtensionFixtures.goodThemeJSON, to: "themes/one.json", in: directory)

        let storage = ExtensionTestThemeStorage()
        let point = ThemeContributionPoint(themeStore: ThemeStore(storage: storage))
        let declaration = try manifest(
            name: "pack", themes: "[\(themeEntry(label: "One", path: "./themes/one.json"))]")
        try apply(declaration, to: point, at: directory)
        storage.activeThemeID = "vscode.test.pack.One"

        // The extension's file is replaced by a broken one, and the app is
        // relaunched.
        try write(ExtensionFixtures.malformedThemeJSON, to: "themes/one.json", in: directory)
        #expect(throws: ThemeContributionError.everyThemeFailed(count: 1)) {
            try apply(declaration, to: point, at: directory)
        }

        // A working theme taken away because a new file is broken turns a
        // recoverable failure into data loss, and the user's recourse —
        // reinstall the extension — is the thing that just failed.
        #expect(storage.customThemes.map(\.id) == ["vscode.test.pack.One"])
        #expect(storage.activeThemeID == "vscode.test.pack.One")
    }

    // MARK: - Withdrawal

    @Test("withdraw deletes only that extension's themes")
    func withdrawDeletesOnlyThatExtensionsThemes() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(ExtensionFixtures.goodThemeJSON, to: "themes/one.json", in: directory)

        let storage = ExtensionTestThemeStorage()
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
        try write(ExtensionFixtures.goodThemeJSON, to: "themes/one.json", in: directory)

        let storage = ExtensionTestThemeStorage()
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
        try write(ExtensionFixtures.malformedThemeJSON, to: "themes/bad.json", in: directory)
        try write(ExtensionFixtures.goodThemeJSON, to: "themes/good.json", in: directory)

        let storage = ExtensionTestThemeStorage()
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
        try write(ExtensionFixtures.malformedThemeJSON, to: "themes/one.json", in: directory)
        try write(ExtensionFixtures.malformedThemeJSON, to: "themes/two.json", in: directory)

        let storage = ExtensionTestThemeStorage()
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

    @Test("two themes under one label keep the first and record the collision")
    func twoThemesUnderOneLabelRecordACollision() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(ExtensionFixtures.goodThemeJSON, to: "themes/one.json", in: directory)
        try write(ExtensionFixtures.goodThemeJSON, to: "themes/two.json", in: directory)

        let storage = ExtensionTestThemeStorage()
        let point = ThemeContributionPoint(themeStore: ThemeStore(storage: storage))

        try apply(
            try manifest(name: "pack", themes: """
            [
                \(themeEntry(label: "One", path: "./themes/one.json")),
                \(themeEntry(label: "One", path: "./themes/two.json"))
            ]
            """),
            to: point,
            at: directory
        )

        // The id is the label, so the second declaration would otherwise
        // replace the first quietly and count as imported — a file in the
        // folder with nothing to show for it and no failure recorded.
        #expect(storage.customThemes.map(\.id) == ["vscode.test.pack.One"])
        #expect(point.importFailures.count == 1)
        #expect(point.importFailures.first?.path == "./themes/two.json")
        #expect(point.importFailures.first?.message.contains("already uses the label") == true)
    }

    @Test("the refusal reads as a sentence, not a case name")
    func theRefusalReadsAsASentence() {
        // `ExtensionRegistry` records a refused contribution as
        // `String(describing:)`, which consults `CustomStringConvertible` and
        // never `LocalizedError` — so without that conformance the panel shows
        // "everyThemeFailed(count: 2)" to the author it is written for.
        #expect(String(describing: ThemeContributionError.everyThemeFailed(count: 2))
            == "None of the 2 declared themes could be read.")
        #expect(String(describing: ThemeContributionError.everyThemeFailed(count: 1))
            == "None of the 1 declared theme could be read.")
    }

    // MARK: - Pruning

    @Test("prune orphans deletes themes of an uninstalled extension")
    func pruneOrphansDeletesThemesOfAnUninstalledExtension() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(ExtensionFixtures.goodThemeJSON, to: "themes/one.json", in: directory)

        let storage = ExtensionTestThemeStorage()
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

    @Test("prune orphans keeps every theme this app did not contribute")
    func pruneOrphansKeepsEveryThemeThisAppDidNotContribute() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let storage = ExtensionTestThemeStorage()
        let store = ThemeStore(storage: storage)
        store.add(try ExtensionFixtures.colorTheme(id: "user.mine", attribution: nil, in: directory))
        // A non-nil attribution that is not ours. `guard let` alone catches the
        // `nil` above; only the `hasPrefix("extension:")` clause catches this
        // one, and it is the clause the comment in `pruneOrphans` is about.
        store.add(try ExtensionFixtures.colorTheme(
            id: "user.imported", attribution: "user:mike", in: directory))
        let point = ThemeContributionPoint(themeStore: store)

        // No extension at all installed — the harshest input a prune can get.
        point.pruneOrphans(installedIdentifiers: [])

        let ids5 = storage.customThemes.map(\.id)
        #expect(ids5 == ["user.mine", "user.imported"])
    }

    // MARK: - Path resolution

    @Test("a relative theme path resolves against the extension directory")
    func relativeThemePathResolvesAgainstTheExtensionDirectory() throws {
        let parent = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let extensionDirectory = parent.appendingPathComponent("acme.pack-1.0.0")
        try FileManager.default.createDirectory(at: extensionDirectory, withIntermediateDirectories: true)
        try write(ExtensionFixtures.goodThemeJSON, to: "themes/one.json", in: extensionDirectory)
        // A decoy one level up, at the path a base URL with no is-directory
        // flag would resolve to. It is malformed, so reading it fails loudly
        // rather than passing this test with the wrong file.
        try write(ExtensionFixtures.malformedThemeJSON, to: "themes/one.json", in: parent)

        let storage = ExtensionTestThemeStorage()
        let point = ThemeContributionPoint(themeStore: ThemeStore(storage: storage))

        // A base with no is-directory flag: the shape
        // `URL(fileURLWithPath:relativeTo:)` resolves against the *parent*
        // unless the point re-makes it.
        //
        // The flag is spelled out because the plain
        // `URL(fileURLWithPath: extensionDirectory.path)` cannot produce this
        // shape here: that initialiser consults the file system, this directory
        // exists, so Foundation sets the flag itself and the decoy above goes
        // out of reach — a test that looks like it covers the trap while
        // proving nothing. A URL that never met the disk — restored from stored
        // JSON, parsed from a string, built before the folder existed — is the
        // one that arrives flagless in production.
        let base = URL(fileURLWithPath: extensionDirectory.path, isDirectory: false)
        // The premise of the test, asserted rather than assumed: with the flag
        // set, every line below passes whether the point re-makes the base or
        // not.
        try #require(!base.hasDirectoryPath)

        try apply(
            try manifest(name: "pack", themes: "[\(themeEntry(label: "One", path: "./themes/one.json"))]"),
            to: point,
            at: base
        )

        #expect(point.importFailures.isEmpty)
        let ids6 = storage.customThemes.map(\.id)
        #expect(ids6 == ["vscode.test.pack.One"])
    }
}
