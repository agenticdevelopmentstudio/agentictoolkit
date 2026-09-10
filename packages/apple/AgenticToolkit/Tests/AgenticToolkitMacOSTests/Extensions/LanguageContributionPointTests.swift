import AgenticToolkitCore
import Foundation
import Testing
@testable import AgenticToolkitMacOS

/// The `contributes.languages` contribution point.
///
/// Every manifest here is decoded from JSON through the real parser rather
/// than assembled from a memberwise initializer the type does not offer: the
/// parse is half of what these tests pin, and a hand-built `Contributions`
/// would agree with a decoder that had stopped carrying `extensions` at all.
///
/// `.serialized` because three of these tests write
/// `CustomFileTypeMappings`' global state — the active defaults key, the
/// persisted array and the contributed provider — and swift-testing would
/// otherwise run them concurrently.
@MainActor
@Suite(.serialized)
struct LanguageContributionPointTests {

    // MARK: - Fixtures

    /// Handed to `apply` and never opened. This point resolves no paths, and
    /// a directory that does not exist is the cheapest way to keep that true:
    /// anything that started reading files would fail here immediately.
    private static let unusedDirectory = URL(fileURLWithPath: "/var/empty/agentic-tests-nonexistent")

    private func manifest(name: String, languages: String) throws -> ExtensionManifest {
        let json = """
        {
            "name": "\(name)",
            "publisher": "acme",
            "version": "1.0.0",
            "engines": { "vscode": "^1.74.0" },
            "contributes": { "languages": \(languages) }
        }
        """
        return try JSONDecoder().decode(ExtensionManifest.self, from: Data(json.utf8))
    }

    private func apply(_ manifest: ExtensionManifest, to point: LanguageContributionPoint) throws {
        let contributions = try #require(manifest.contributes)
        try point.apply(contributions, from: manifest, at: Self.unusedDirectory)
    }

    /// Runs `body` against a per-test UserDefaults key, then restores every
    /// piece of global state it touched.
    ///
    /// The real user's mappings are never read or written: the key is unique
    /// per call. The final `save([])` runs while the test key is still active
    /// — it is what invalidates the store's cache, and doing it after the key
    /// was restored would write an empty array over the user's own.
    private func withIsolatedDefaults(_ body: () throws -> Void) rethrows {
        let previousKey = CustomFileTypeMappings.activeDefaultsKey
        let testKey = "LanguageContributionPointTests.\(UUID().uuidString)"
        CustomFileTypeMappings.activeDefaultsKey = testKey
        CustomFileTypeMappings.contributedProvider = nil
        CustomFileTypeMappings.save([])
        defer {
            CustomFileTypeMappings.contributedProvider = nil
            CustomFileTypeMappings.save([])
            UserDefaults.standard.removeObject(forKey: testKey)
            CustomFileTypeMappings.activeDefaultsKey = previousKey
        }
        try body()
    }

    // MARK: - Identity

    @Test("the point consumes the languages key")
    func contributionKey() {
        #expect(LanguageContributionPoint().contributionKey == "languages")
    }

    // MARK: - Normalisation

    @Test("a dotted extension and a dotless one produce the same mapping")
    func dottedAndDotlessAgree() throws {
        let point = LanguageContributionPoint()
        try apply(
            manifest(
                name: "dots",
                languages: """
                [
                    { "id": "ruby", "extensions": [".rb"] },
                    { "id": "perl", "extensions": ["pl"] }
                ]
                """
            ),
            to: point
        )

        #expect(point.mapping(for: "rb")?.fileExtension == "rb")
        #expect(point.mapping(for: "rb")?.languageName == "ruby")
        #expect(point.mapping(for: "pl")?.fileExtension == "pl")
        #expect(point.mapping(for: "pl")?.languageName == "perl")
        #expect(point.dropped.isEmpty)
    }

    @Test("an uppercase extension in the manifest is found by a lowercase lookup")
    func uppercaseIsNormalised() throws {
        let point = LanguageContributionPoint()
        try apply(
            manifest(name: "upper", languages: #"[{ "id": "markdown", "extensions": [".MD"] }]"#),
            to: point
        )

        #expect(point.mapping(for: "md")?.languageName == "markdown")
    }

    @Test("individual unrepresentable extension values are skipped and reported")
    func multiSegmentAndGlobValuesAreSkipped() throws {
        let point = LanguageContributionPoint()
        try apply(
            manifest(
                name: "skips",
                languages: #"[{ "id": "ruby", "extensions": [".rb", "cspell.json", "*.log.?", ""] }]"#
            ),
            to: point
        )

        #expect(point.mapping(for: "rb")?.languageName == "ruby")
        #expect(point.mapping(for: "cspell.json") == nil)
        let row = try #require(point.dropped.first)
        #expect(point.dropped.count == 1)
        #expect(row.languageID == "ruby")
        #expect(row.keys == ["extensions"])
        #expect(row.skippedExtensions == ["cspell.json", "*.log.?", ""])
    }

    // MARK: - Display name

    @Test("the first alias is the display name, and the id is the fallback")
    func displayNameComesFromAliasesThenID() throws {
        let point = LanguageContributionPoint()
        try apply(
            manifest(
                name: "names",
                languages: """
                [
                    { "id": "typescriptreact", "aliases": ["TypeScript React", "tsx"], "extensions": [".tsx"] },
                    { "id": "conf", "extensions": [".conf"] }
                ]
                """
            ),
            to: point
        )

        #expect(point.mapping(for: "tsx")?.languageName == "TypeScript React")
        #expect(point.mapping(for: "conf")?.languageName == "conf")
    }

    @Test("a claimed extension the file browser already knows keeps its icon")
    func aKnownExtensionKeepsItsBuiltInIcon() throws {
        let point = LanguageContributionPoint()
        try apply(
            manifest(name: "mdx", languages: #"[{ "id": "mdx", "extensions": [".md"] }]"#),
            to: point
        )

        // The name is the contribution; the icon is not the extension's to
        // take away. Stamping the placeholder here would turn every Markdown
        // file in the tree into a blank page the moment an MDX or a linter
        // extension was installed.
        #expect(point.mapping(for: "md")?.languageName == "mdx")
        #expect(point.mapping(for: "md")?.iconName == FileTypeIcons.builtInIcon(for: "md"))
        #expect(point.mapping(for: "md")?.iconName == "doc.richtext")
    }

    @Test("a claimed extension nothing knows falls back to the placeholder icon")
    func anUnknownExtensionGetsThePlaceholderIcon() throws {
        let point = LanguageContributionPoint()
        try apply(manifest(name: "icons", languages: #"[{ "id": "ruby", "extensions": [".rb"] }]"#), to: point)

        #expect(FileTypeIcons.builtInIcon(for: "rb") == nil)
        #expect(point.mapping(for: "rb")?.iconName == "doc.text")
    }

    // MARK: - Dropped matchers

    @Test("an entry matched only by filenames maps nothing and is reported")
    func filenamesOnlyIsReported() throws {
        let point = LanguageContributionPoint()
        try apply(
            manifest(name: "docker", languages: #"[{ "id": "dockerfile", "filenames": ["Dockerfile"] }]"#),
            to: point
        )

        #expect(point.mapping(for: "dockerfile") == nil)
        let row = try #require(point.dropped.first)
        #expect(point.dropped.count == 1)
        #expect(row.extensionIdentifier == "acme.docker")
        #expect(row.languageID == "dockerfile")
        #expect(row.keys == ["filenames"])
        #expect(row.skippedExtensions.isEmpty)
        // Declared *a* matcher, just not one this host can key on — a
        // different row from an entry that declared none at all.
        #expect(row.declaredNoMatcher == false)
    }

    @Test("an entry declaring no matcher at all is still reported")
    func anEntryWithNoMatcherIsReported() throws {
        let point = LanguageContributionPoint()
        try apply(
            manifest(name: "empty", languages: #"[{ "id": "ghost", "aliases": ["Ghost"] }]"#),
            to: point
        )

        let row = try #require(point.dropped.first)
        #expect(point.dropped.count == 1)
        #expect(row.languageID == "ghost")
        #expect(row.keys.isEmpty)
        #expect(row.declaredNoMatcher)
    }

    @Test("mimetypes is reported, and an entry carrying only mimetypes still declared no matcher")
    func mimetypesIsReported() throws {
        let point = LanguageContributionPoint()
        try apply(
            manifest(
                name: "mime",
                languages: """
                [
                    { "id": "jsonl", "mimetypes": ["application/x-ndjson"] },
                    { "id": "ruby", "extensions": [".rb"], "mimetypes": ["text/x-ruby"] }
                ]
                """
            ),
            to: point
        )

        #expect(point.dropped.count == 2)
        let mimeOnly = try #require(point.dropped.first)
        #expect(mimeOnly.languageID == "jsonl")
        #expect(mimeOnly.keys == ["mimetypes"])
        // A MIME type labels a document; it never picks a language for a file
        // on disk, here or in VS Code. So this entry declared no matcher.
        #expect(mimeOnly.declaredNoMatcher)

        let alongsideExtensions = point.dropped[1]
        #expect(alongsideExtensions.languageID == "ruby")
        #expect(alongsideExtensions.keys == ["mimetypes"])
        #expect(alongsideExtensions.declaredNoMatcher == false)
        #expect(point.mapping(for: "rb")?.languageName == "ruby")
    }

    @Test("every dropped key at once is reported in VS Code's schema order")
    func droppedKeysFollowTheSchemaOrder() throws {
        let point = LanguageContributionPoint()
        try apply(
            manifest(
                name: "everything",
                languages: """
                [
                    {
                        "id": "kitchen-sink",
                        "extensions": [".rb", "cspell.json"],
                        "filenames": ["Rakefile"],
                        "filenamePatterns": ["*.gemspec"],
                        "firstLine": "^#!.*\\bruby\\b",
                        "mimetypes": ["text/x-ruby"],
                        "configuration": "./nowhere/language-configuration.json",
                        "icon": { "light": "./icons/light.svg", "dark": "./icons/dark.svg" }
                    }
                ]
                """
            ),
            to: point
        )

        // Asserted as one literal, in order: `DroppedLanguageMatcher.keys`
        // promises the order VS Code's `contributes.languages` schema lists
        // the keys in, and a per-key assertion would let any of them move.
        // `extensions` is last because it means "some individual values were
        // skipped", not "the key was dropped".
        let row = try #require(point.dropped.first)
        #expect(point.dropped.count == 1)
        #expect(row.keys == [
            "filenames",
            "filenamePatterns",
            "firstLine",
            "mimetypes",
            "icon",
            "configuration",
            "extensions"
        ])
        #expect(row.skippedExtensions == ["cspell.json"])
        #expect(row.declaredNoMatcher == false)
        #expect(point.mapping(for: "rb")?.languageName == "kitchen-sink")
    }

    @Test("dropped rows are replaced on re-apply, not accumulated")
    func droppedRowsAreReplacedNotAccumulated() throws {
        let point = LanguageContributionPoint()
        let docker = try manifest(
            name: "docker",
            languages: #"[{ "id": "dockerfile", "filenames": ["Dockerfile"] }]"#
        )
        try apply(docker, to: point)
        try apply(docker, to: point)

        #expect(point.dropped.count == 1)
    }

    @Test("withdrawing clears that extension's dropped rows and leaves another's")
    func withdrawingClearsOnlyItsOwnDroppedRows() throws {
        let point = LanguageContributionPoint()
        try apply(
            manifest(name: "docker", languages: #"[{ "id": "dockerfile", "filenames": ["Dockerfile"] }]"#),
            to: point
        )
        try apply(
            manifest(name: "shell", languages: #"[{ "id": "shellscript", "firstLine": "^#!" }]"#),
            to: point
        )
        #expect(point.dropped.count == 2)

        point.withdraw(extensionIdentifier: "acme.docker")

        #expect(point.dropped.count == 1)
        #expect(point.dropped.first?.extensionIdentifier == "acme.shell")
    }

    @Test("filenamePatterns and firstLine are reported together, in manifest order")
    func patternsAndFirstLineAreReported() throws {
        let point = LanguageContributionPoint()
        try apply(
            manifest(
                name: "shell",
                languages: """
                [
                    {
                        "id": "shellscript",
                        "filenamePatterns": ["*.bashrc"],
                        "firstLine": "^#!.*\\\\bsh\\\\b"
                    }
                ]
                """
            ),
            to: point
        )

        let row = try #require(point.dropped.first)
        #expect(point.dropped.count == 1)
        #expect(row.keys == ["filenamePatterns", "firstLine"])
    }

    @Test("an icon is reported and the entry still maps its extension")
    func iconIsReportedWithoutCostingTheMapping() throws {
        let point = LanguageContributionPoint()
        try apply(
            manifest(
                name: "iconic",
                languages: """
                [
                    {
                        "id": "ruby",
                        "extensions": [".rb"],
                        "icon": { "light": "./icons/light.svg", "dark": "./icons/dark.svg" }
                    }
                ]
                """
            ),
            to: point
        )

        #expect(point.mapping(for: "rb")?.languageName == "ruby")
        let row = try #require(point.dropped.first)
        #expect(row.keys == ["icon"])
    }

    @Test("a configuration path is reported, never opened, and costs the entry nothing")
    func configurationIsReportedWithoutBeingRead() throws {
        let point = LanguageContributionPoint()
        try apply(
            manifest(
                name: "configured",
                languages: """
                [
                    {
                        "id": "ruby",
                        "extensions": [".rb"],
                        "configuration": "./nowhere/language-configuration.json"
                    }
                ]
                """
            ),
            to: point
        )

        #expect(point.mapping(for: "rb")?.languageName == "ruby")
        let row = try #require(point.dropped.first)
        #expect(point.dropped.count == 1)
        #expect(row.keys == ["configuration"])
    }

    // MARK: - Conflicts

    @Test("one entry spelling the same extension twice does not conflict with itself")
    func anEntryCannotConflictWithItself() throws {
        let point = LanguageContributionPoint()
        try apply(
            manifest(name: "dupes", languages: #"[{ "id": "ruby", "extensions": [".rb", "rb", ".RB"] }]"#),
            to: point
        )

        #expect(point.mapping(for: "rb")?.languageName == "ruby")
        #expect(point.conflicts.isEmpty)
        #expect(point.dropped.isEmpty)
    }

    @Test("within one manifest the first entry claiming an extension wins")
    func firstEntryInAManifestWins() throws {
        let point = LanguageContributionPoint()
        try apply(
            manifest(
                name: "twice",
                languages: """
                [
                    { "id": "first", "extensions": [".foo"] },
                    { "id": "second", "extensions": [".foo"] }
                ]
                """
            ),
            to: point
        )

        #expect(point.mapping(for: "foo")?.languageName == "first")
        let conflict = try #require(point.conflicts.first)
        #expect(point.conflicts.count == 1)
        #expect(conflict.fileExtension == "foo")
        #expect(conflict.winner == "acme.twice")
        #expect(conflict.loser == "acme.twice")
        #expect(conflict.losingLanguageID == "second")
    }

    @Test("across extensions the lowest identifier wins, whichever order they were applied in")
    func lowestIdentifierWinsRegardlessOfApplyOrder() throws {
        // Load order is `contentsOfDirectory` order — nobody chose it and
        // nothing preserves it — so it must not decide which language a file
        // is labelled with.
        for reversed in [false, true] {
            let point = LanguageContributionPoint()
            let alpha = try manifest(name: "alpha", languages: #"[{ "id": "alpha", "extensions": [".foo"] }]"#)
            let omega = try manifest(name: "omega", languages: #"[{ "id": "omega", "extensions": [".foo"] }]"#)
            for pending in (reversed ? [omega, alpha] : [alpha, omega]) {
                try apply(pending, to: point)
            }

            #expect(point.mapping(for: "foo")?.languageName == "alpha")
            let conflict = try #require(point.conflicts.first)
            #expect(point.conflicts.count == 1)
            #expect(conflict.winner == "acme.alpha")
            #expect(conflict.loser == "acme.omega")
            #expect(conflict.losingLanguageID == "omega")
        }
    }

    @Test("toggling an extension off and on does not hand a contested extension to a competitor")
    func disablingAndReenablingKeepsTheWinner() throws {
        let point = LanguageContributionPoint()
        let alpha = try manifest(name: "alpha", languages: #"[{ "id": "alpha", "extensions": [".foo"] }]"#)
        try apply(alpha, to: point)
        try apply(manifest(name: "omega", languages: #"[{ "id": "omega", "extensions": [".foo"] }]"#), to: point)

        // What `ExtensionRegistry.setEnabled` does to disable and re-enable.
        point.withdraw(extensionIdentifier: "acme.alpha")
        try apply(alpha, to: point)

        #expect(point.mapping(for: "foo")?.languageName == "alpha")
        #expect(point.conflicts.count == 1)
        #expect(point.conflicts.first?.winner == "acme.alpha")
    }

    // MARK: - Withdrawal

    @Test("withdrawing the winner lets the loser's mapping take effect")
    func withdrawingTheWinnerPromotesTheLoser() throws {
        let point = LanguageContributionPoint()
        try apply(manifest(name: "early", languages: #"[{ "id": "early", "extensions": [".foo"] }]"#), to: point)
        try apply(manifest(name: "late", languages: #"[{ "id": "late", "extensions": [".foo"] }]"#), to: point)

        point.withdraw(extensionIdentifier: "acme.early")

        #expect(point.mapping(for: "foo")?.languageName == "late")
        #expect(point.conflicts.isEmpty)
    }

    @Test("withdrawing an identifier that contributed nothing is a no-op")
    func withdrawingAnUnknownIdentifierIsANoOp() throws {
        let point = LanguageContributionPoint()
        try apply(manifest(name: "only", languages: #"[{ "id": "ruby", "extensions": [".rb"] }]"#), to: point)

        point.withdraw(extensionIdentifier: "acme.never-applied")

        #expect(point.mapping(for: "rb")?.languageName == "ruby")
    }

    @Test("applying twice leaves one copy")
    func reapplyingIsIdempotent() throws {
        let point = LanguageContributionPoint()
        let alpha = try manifest(name: "alpha", languages: #"[{ "id": "alpha", "extensions": [".foo"] }]"#)
        try apply(alpha, to: point)
        try apply(manifest(name: "omega", languages: #"[{ "id": "omega", "extensions": [".foo"] }]"#), to: point)
        try apply(alpha, to: point)

        #expect(point.mapping(for: "foo")?.languageName == "alpha")
        #expect(point.conflicts.count == 1)
        #expect(point.dropped.isEmpty)
    }

    @Test("re-applying with a shorter extensions list stops resolving the dropped value")
    func shrinkingTheExtensionsListLosesTheDroppedValue() throws {
        let point = LanguageContributionPoint()
        try apply(
            manifest(name: "shrink", languages: #"[{ "id": "both", "extensions": [".aaa", ".bbb"] }]"#),
            to: point
        )
        #expect(point.mapping(for: "bbb")?.languageName == "both")

        try apply(
            manifest(name: "shrink", languages: #"[{ "id": "both", "extensions": [".aaa"] }]"#),
            to: point
        )

        // A merge-shaped `apply` would leave `.bbb` answering forever.
        #expect(point.mapping(for: "aaa")?.languageName == "both")
        #expect(point.mapping(for: "bbb") == nil)
    }

    // MARK: - Precedence through CustomFileTypeMappings

    @Test("a user mapping outranks a contributed one, and the contribution returns when it is deleted")
    func theUserAlwaysWins() throws {
        try withIsolatedDefaults {
            let point = LanguageContributionPoint()
            try apply(
                manifest(name: "md", languages: #"[{ "id": "markdown", "extensions": [".md"] }]"#),
                to: point
            )
            point.install()

            CustomFileTypeMappings.save([
                CustomFileTypeMapping(fileExtension: "md", languageName: "The user's own", iconName: "doc.richtext")
            ])
            #expect(CustomFileTypeMappings.mapping(for: "md")?.languageName == "The user's own")

            CustomFileTypeMappings.save([])
            #expect(CustomFileTypeMappings.mapping(for: "md")?.languageName == "markdown")
        }
    }

    @Test("two user rows differing only in case resolve to the first rather than trapping")
    func duplicateUserKeysDoNotTrap() {
        withIsolatedDefaults {
            CustomFileTypeMappings.save([
                CustomFileTypeMapping(fileExtension: "MD", languageName: "First", iconName: "doc.text"),
                CustomFileTypeMapping(fileExtension: "md", languageName: "Second", iconName: "doc.text")
            ])

            #expect(CustomFileTypeMappings.mapping(for: "md")?.languageName == "First")
        }
    }

    @Test("with no provider installed the store behaves exactly as it did before")
    func noProviderMeansNoChange() throws {
        try withIsolatedDefaults {
            let point = LanguageContributionPoint()
            try apply(
                manifest(name: "md", languages: #"[{ "id": "markdown", "extensions": [".md"] }]"#),
                to: point
            )

            // No `install()`, so no provider: the store answers only from
            // the user's own array, exactly as it did before this task.
            #expect(CustomFileTypeMappings.mapping(for: "md") == nil)

            CustomFileTypeMappings.save([
                CustomFileTypeMapping(fileExtension: "md", languageName: "The user's own", iconName: "doc.richtext")
            ])
            #expect(CustomFileTypeMappings.mapping(for: "md")?.languageName == "The user's own")
        }
    }
}
