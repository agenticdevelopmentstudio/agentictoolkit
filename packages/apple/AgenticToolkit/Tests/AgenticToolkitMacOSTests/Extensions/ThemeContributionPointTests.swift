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

    @Test("a theme whose file broke keeps its previous copy, and the selection")
    func aThemeWhoseFileBrokeKeepsItsPreviousCopy() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(ExtensionFixtures.goodThemeJSON, to: "themes/night.json", in: directory)
        try write(ExtensionFixtures.goodThemeJSON, to: "themes/day.json", in: directory)

        let storage = ExtensionTestThemeStorage()
        let point = ThemeContributionPoint(themeStore: ThemeStore(storage: storage))
        let declaration = try manifest(name: "pack", themes: """
        [
            \(themeEntry(label: "Night", path: "./themes/night.json")),
            \(themeEntry(label: "Day", path: "./themes/day.json"))
        ]
        """)
        try apply(declaration, to: point, at: directory)
        storage.activeThemeID = "vscode.test.pack.Night"

        // Night's file is replaced by a broken one and the app is relaunched.
        // Day still parses, so `imported == 1` and Ruling GO's wholesale throw
        // never fires — this is the gap GO does not cover.
        try write(ExtensionFixtures.malformedThemeJSON, to: "themes/night.json", in: directory)
        try apply(declaration, to: point, at: directory)

        // Night is still *declared*, so reconciliation has no business deleting
        // it (Ruling GS): a declaration is evidence of what the extension
        // provides, a failed load is evidence about nothing. Reconciling
        // against the ids written this call instead would delete the previous
        // launch's working copy of exactly the theme whose file just broke —
        // and take the user's selection with it, because `delete(id:)` clears
        // `activeThemeID`.
        #expect(storage.customThemes.map(\.id)
            == ["vscode.test.pack.Night", "vscode.test.pack.Day"])
        #expect(storage.activeThemeID == "vscode.test.pack.Night")
        // …and the breakage is still reported, so keeping the theme is not the
        // same as pretending nothing happened.
        #expect(point.importFailures.map(\.path) == ["./themes/night.json"])
    }

    @Test("a theme dropped from the manifest goes away, and its sibling stays")
    func aThemeDroppedFromTheManifestGoesAway() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(ExtensionFixtures.goodThemeJSON, to: "themes/night.json", in: directory)
        try write(ExtensionFixtures.goodThemeJSON, to: "themes/day.json", in: directory)

        let storage = ExtensionTestThemeStorage()
        let point = ThemeContributionPoint(themeStore: ThemeStore(storage: storage))
        try apply(
            try manifest(name: "pack", themes: """
            [
                \(themeEntry(label: "Night", path: "./themes/night.json")),
                \(themeEntry(label: "Day", path: "./themes/day.json"))
            ]
            """),
            to: point,
            at: directory
        )

        // The update ships without Night. Its file is still on disk — being
        // undeclared is the whole signal, and `pruneOrphans` cannot see it
        // because the extension is still installed.
        try apply(
            try manifest(
                name: "pack", themes: "[\(themeEntry(label: "Day", path: "./themes/day.json"))]"),
            to: point,
            at: directory
        )

        #expect(storage.customThemes.map(\.id) == ["vscode.test.pack.Day"])
    }

    @Test("applying twice lists a broken theme once, not twice")
    func applyingTwiceListsABrokenThemeOnce() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(ExtensionFixtures.malformedThemeJSON, to: "themes/night.json", in: directory)
        try write(ExtensionFixtures.goodThemeJSON, to: "themes/day.json", in: directory)

        let storage = ExtensionTestThemeStorage()
        let point = ThemeContributionPoint(themeStore: ThemeStore(storage: storage))
        let declaration = try manifest(name: "pack", themes: """
        [
            \(themeEntry(label: "Night", path: "./themes/night.json")),
            \(themeEntry(label: "Day", path: "./themes/day.json"))
        ]
        """)

        // Nothing changed between the two calls — this is a reload, or a
        // disable/enable, or any caller that does not know the registry
        // withdraws first. `apply` is public API on a public class and the
        // ordering is the caller's to get wrong.
        try apply(declaration, to: point, at: directory)
        try apply(declaration, to: point, at: directory)

        // One broken file is one line in the Decisions group. Accumulating
        // would print it twice, since `decisionLines()` emits one line per
        // element and reads none of these as a history.
        #expect(point.importFailures.map(\.path) == ["./themes/night.json"])
        // And the clear is narrowed to the diagnostics: Day survives being
        // applied a second time, because the fix is not a `withdraw` at the top.
        #expect(storage.customThemes.map(\.id) == ["vscode.test.pack.Day"])
    }

    @Test("an extension that stops declaring themes loses all of them")
    func anExtensionThatStopsDeclaringThemesLosesThemAll() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(ExtensionFixtures.goodThemeJSON, to: "themes/night.json", in: directory)
        try write(ExtensionFixtures.goodThemeJSON, to: "themes/day.json", in: directory)

        let storage = ExtensionTestThemeStorage()
        let point = ThemeContributionPoint(themeStore: ThemeStore(storage: storage))
        try apply(
            try manifest(name: "pack", themes: """
            [
                \(themeEntry(label: "Night", path: "./themes/night.json")),
                \(themeEntry(label: "Day", path: "./themes/day.json"))
            ]
            """),
            to: point,
            at: directory
        )
        storage.activeThemeID = "vscode.test.pack.Night"

        // The update stops shipping themes altogether. Both files are still on
        // disk; being undeclared is the whole signal, exactly as when *one* is
        // dropped. Zero is the case an `isEmpty` early return let escape — and
        // it escaped permanently, because `pruneOrphans` cannot see these
        // either: the extension is still installed.
        try apply(try manifest(name: "pack", themes: "[]"), to: point, at: directory)

        #expect(storage.customThemes.isEmpty)
        // `delete(id:)` clears the selection with the theme, so storage is never
        // left pointing at an id that no longer resolves.
        #expect(storage.activeThemeID == nil)
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

    @Test("a theme row left under an unfolded attribution is pruned, not left as a duplicate")
    func pruneOrphansHealsAThemeRowWrittenBeforeIdentifiersWereFolded() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(ExtensionFixtures.goodThemeJSON, to: "themes/one.json", in: directory)

        let storage = ExtensionTestThemeStorage()
        let store = ThemeStore(storage: storage)
        // The row a build from before identifiers were case-folded (F39) would
        // have persisted for this same extension: the manifest's own
        // capitalisation, straight into both the id and the attribution.
        store.add(try ExtensionFixtures.colorTheme(
            id: "vscode.Test.Kept.One", attribution: "extension:Test.Kept", in: directory))
        let point = ThemeContributionPoint(themeStore: store)
        let entry = themeEntry(label: "One", path: "./themes/one.json")
        try apply(try manifest(name: "kept", themes: "[\(entry)]"), to: point, at: directory)
        // Two rows for one theme: `apply` reconciles against *its* attribution
        // only, and the stale row does not carry it.
        try #require(storage.customThemes.count == 2)

        // The comparison in `pruneOrphans` is exact, and that is the clause
        // that heals this: no installed extension answers to "Test.Kept" in
        // that spelling any more, so the stale row is an orphan and goes.
        // Folding the comparison would make it match the installed
        // "test.kept" and leave the user two copies of one theme forever.
        point.pruneOrphans(installedIdentifiers: ["test.kept"])

        #expect(storage.customThemes.map(\.id) == ["vscode.test.kept.One"])
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

        // No extension at all installed — the harshest *instruction* a prune
        // can be given, and a legitimate one: a scan that read every folder
        // and found nothing says exactly this. Its opposite is `nil`, in the
        // test below.
        point.pruneOrphans(installedIdentifiers: [])

        let ids5 = storage.customThemes.map(\.id)
        #expect(ids5 == ["user.mine", "user.imported"])
    }

    @Test("prune orphans does nothing at all when the scan could not name everyone")
    func pruneOrphansDoesNothingWhenTheScanCouldNotNameEveryone() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(ExtensionFixtures.goodThemeJSON, to: "themes/one.json", in: directory)

        let storage = ExtensionTestThemeStorage()
        let point = ThemeContributionPoint(themeStore: ThemeStore(storage: storage))
        let entry = themeEntry(label: "One", path: "./themes/one.json")
        try apply(try manifest(name: "gone", themes: "[\(entry)]"), to: point, at: directory)
        try #require(storage.customThemes.count == 1)

        // `nil`, not `[]`, and the difference is the whole point: one
        // `package.json` in a search path would not parse, so this launch
        // cannot tell an extension that was deleted while the app was closed
        // from the one it could not read — and must therefore take nothing
        // away. The empty set above says "delete them all"; this says "I do
        // not know" (I1/I2).
        point.pruneOrphans(installedIdentifiers: nil)

        #expect(storage.customThemes.map(\.id) == ["vscode.test.gone.One"])
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

    // MARK: - Containment

    @Test("a theme path that escapes the extension directory is refused")
    func escapingThemePathIsRefused() throws {
        // The decoy is a real, readable, *valid* theme file outside the
        // extension folder — written and located by a route the point does not
        // use. Without the containment check any readable JSON on the machine
        // carrying a `colors` object becomes a theme in the user's picker, and
        // anything else becomes a failure row that confirms the file exists.
        let parent = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let extensionDirectory = parent.appendingPathComponent("ext", isDirectory: true)
        try FileManager.default.createDirectory(at: extensionDirectory, withIntermediateDirectories: true)
        try write(ExtensionFixtures.goodThemeJSON, to: "outside/secret.json", in: parent)

        let decoy = parent.appendingPathComponent("outside/secret.json")
        #expect(FileManager.default.isReadableFile(atPath: decoy.path))
        let escaped = URL(fileURLWithPath: "../outside/secret.json", relativeTo: extensionDirectory)
            .resolvingSymlinksInPath().standardizedFileURL
        #expect(escaped.path == decoy.resolvingSymlinksInPath().standardizedFileURL.path)

        let storage = ExtensionTestThemeStorage()
        let point = ThemeContributionPoint(themeStore: ThemeStore(storage: storage))

        // Every declared theme failed, so the point's own wholesale refusal
        // fires — which is the honest report, and is what the registry records.
        #expect(throws: ThemeContributionError.everyThemeFailed(count: 1)) {
            try apply(
                try manifest(
                    name: "escaper",
                    themes: "[\(themeEntry(label: "Stolen", path: "../outside/secret.json"))]"
                ),
                to: point,
                at: extensionDirectory
            )
        }

        #expect(storage.customThemes.isEmpty)
        #expect(point.importFailures.map(\.path) == ["../outside/secret.json"])
    }

    @Test("a sibling directory sharing a name prefix does not count as inside")
    func siblingWithSharedNamePrefixIsRefused() throws {
        // A containment check written on string prefixes lets this through,
        // and the attacker picks the sibling directory's name.
        let parent = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let extensionDirectory = parent.appendingPathComponent("ext", isDirectory: true)
        try FileManager.default.createDirectory(at: extensionDirectory, withIntermediateDirectories: true)
        try write(ExtensionFixtures.goodThemeJSON, to: "ext-evil/secret.json", in: parent)

        let decoy = parent.appendingPathComponent("ext-evil/secret.json")
        #expect(decoy.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(
            extensionDirectory.resolvingSymlinksInPath().standardizedFileURL.path))

        let storage = ExtensionTestThemeStorage()
        let point = ThemeContributionPoint(themeStore: ThemeStore(storage: storage))

        #expect(throws: ThemeContributionError.everyThemeFailed(count: 1)) {
            try apply(
                try manifest(
                    name: "sibling",
                    themes: "[\(themeEntry(label: "Stolen", path: "../ext-evil/secret.json"))]"
                ),
                to: point,
                at: extensionDirectory
            )
        }

        #expect(storage.customThemes.isEmpty)
        #expect(point.importFailures.map(\.path) == ["../ext-evil/secret.json"])
    }

    // MARK: - Include inheritance

    /// The variant half of a base-plus-variants theme pack: it inherits
    /// everything and overrides one colour.
    private static let variantThemeJSON = """
    {
        "include": "../base.json",
        "colors": { "editor.background": "#111111" }
    }
    """

    @Test("a theme that includes a base file one directory up imports")
    func includeResolvesAgainstTheThemeFileAndImports() throws {
        // The shape many packs ship: `themes/dark.json` inheriting from a
        // shared `base.json` beside it or above it. Parsed on its own the
        // variant declares one colour, `editor.foreground` is missing, and a
        // well-formed pack reports as broken.
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(ExtensionFixtures.goodThemeJSON, to: "base.json", in: directory)
        try write(Self.variantThemeJSON, to: "themes/variant.json", in: directory)

        let storage = ExtensionTestThemeStorage()
        let point = ThemeContributionPoint(themeStore: ThemeStore(storage: storage))

        try apply(
            try manifest(name: "pack", themes: "[\(themeEntry(label: "Variant", path: "./themes/variant.json"))]"),
            to: point,
            at: directory
        )

        #expect(point.importFailures.isEmpty)
        let theme = try #require(storage.customThemes.first)
        // The base supplied the foreground; the variant overrode the
        // background, and only the background.
        #expect(theme.foreground.hexString == "#D8DEE9FF")
        #expect(theme.background.hexString == "#111111FF")
    }

    @Test("an include that escapes the extension directory is refused")
    func escapingIncludeIsRefused() throws {
        // An `include` is an extension-controlled path with exactly the escape
        // hazard the manifest's own `path` has, and it reaches the file system
        // one hop later where nothing was watching.
        let parent = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let extensionDirectory = parent.appendingPathComponent("ext", isDirectory: true)
        try FileManager.default.createDirectory(at: extensionDirectory, withIntermediateDirectories: true)
        try write(ExtensionFixtures.goodThemeJSON, to: "outside/secret.json", in: parent)
        try write(
            ##"{ "include": "../../outside/secret.json", "colors": { "editor.background": "#111111" } }"##,
            to: "themes/variant.json",
            in: extensionDirectory
        )

        #expect(FileManager.default.isReadableFile(
            atPath: parent.appendingPathComponent("outside/secret.json").path))

        let storage = ExtensionTestThemeStorage()
        let point = ThemeContributionPoint(themeStore: ThemeStore(storage: storage))

        #expect(throws: ThemeContributionError.everyThemeFailed(count: 1)) {
            try apply(
                try manifest(
                    name: "escaper",
                    themes: "[\(themeEntry(label: "Variant", path: "./themes/variant.json"))]"
                ),
                to: point,
                at: extensionDirectory
            )
        }

        #expect(storage.customThemes.isEmpty)
        #expect(point.importFailures.map(\.path) == ["./themes/variant.json"])
    }
}
