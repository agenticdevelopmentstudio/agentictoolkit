import Testing
import AppKit
import Foundation
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// Records withdrawals, so a toggle can be shown to reach the contribution
/// points and not only the setting.
@MainActor
private final class WithdrawalSpy: ContributionPoint {
    let contributionKey = "spy"
    private(set) var withdrawnIdentifiers: [String] = []

    func apply(
        _ contributions: ExtensionManifest.Contributions,
        from manifest: ExtensionManifest,
        at directory: URL
    ) throws {}

    func withdraw(extensionIdentifier: String) {
        withdrawnIdentifiers.append(extensionIdentifier)
    }
}

/// The Extensions settings panel.
///
/// Every test forces the view to load (`_ = panel.view`) and none presents a
/// window: `viewDidLoad` is where the panels are built, and a window would put
/// a modal-capable sheet host on screen during a test run.
///
/// Serialized: enabling and disabling writes `UserSettings.shared`.
@MainActor
@Suite(.serialized)
struct ExtensionsSettingsPanelTests {

    // MARK: - Fixtures

    private func makeTempDirectory() throws -> URL {
        try ExtensionFixtures.makeTemporaryDirectory("ExtensionsSettingsPanelTests")
    }

    private func write(_ contents: String, to relativePath: String, in directory: URL) throws {
        try ExtensionFixtures.write(contents, to: relativePath, in: directory)
    }

    private func manifestJSON(name: String, contributes: String = #"{ "commands": [] }"#) -> String {
        """
        {
            "name": "\(name)",
            "publisher": "test",
            "version": "1.0.0",
            "displayName": "\(name.capitalized)",
            "engines": { "vscode": "^1.74.0" },
            "contributes": \(contributes)
        }
        """
    }

    /// Writes one extension folder named after `name` into `root`.
    private func installExtension(
        named name: String,
        contributes: String = #"{ "commands": [] }"#,
        in root: URL
    ) throws {
        try write(
            manifestJSON(name: name, contributes: contributes),
            to: "package.json",
            in: root.appendingPathComponent("\(name)-1.0.0")
        )
    }

    /// Builds the coordinator and its panel, loads the panel's view, and takes
    /// the coordinator back out of `AppFeatureRegistry.shared` afterwards.
    ///
    /// `viewRegistry` defaults to `nil` — the headless shape most of these tests
    /// want — but the Views group only exists when the host supplied one, so the
    /// test that reads that group passes a real registry rather than a double.
    private func withPanel<Result>(
        searchPaths: [URL],
        viewRegistry: ComposableTabsViewRegistry? = nil,
        _ body: (ExtensionsCoordinator, ExtensionsSettingsPanelViewController) throws -> Result
    ) rethrows -> Result {
        let coordinator = ExtensionsCoordinator(
            searchPaths: searchPaths,
            themeStore: ThemeStore(storage: ExtensionTestThemeStorage()),
            viewRegistry: viewRegistry
        )
        defer { coordinator.unregister() }
        let panel = coordinator.settingsPanel()
        // Panels are built in `viewDidLoad`; nothing below exists until the
        // view is loaded, and no test here needs a window for that.
        _ = panel.view
        return try body(coordinator, panel)
    }

    /// Every `NSTextField` in a loaded view tree, in depth-first order — the
    /// only way to read what an `ExplanationView` ended up saying.
    private func labels(in view: NSView) -> [String] {
        var found: [String] = []
        if let field = view as? NSTextField {
            found.append(field.stringValue)
        }
        for subview in view.subviews {
            found.append(contentsOf: labels(in: subview))
        }
        return found
    }

    private func failure(_ reason: ExtensionLoadError) -> ExtensionLoadFailure {
        ExtensionLoadFailure(
            directory: URL(fileURLWithPath: "/tmp/extensions/alpha-1.0.0", isDirectory: true),
            reason: reason
        )
    }

    private func contributions(_ json: String) throws -> ExtensionManifest.Contributions {
        let manifest = try JSONDecoder().decode(
            ExtensionManifest.self, from: Data(manifestJSON(name: "pack", contributes: json).utf8))
        return try #require(manifest.contributes)
    }

    // MARK: - Panels

    @Test("a panel is built for every loaded extension")
    func apanelIsBuiltForEveryLoadedExtension() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            try installExtension(named: "alpha", in: root)
            try installExtension(named: "beta", in: root)

            try withPanel(searchPaths: [root]) { coordinator, panel in
                try #require(coordinator.registry.extensions.count == 2)
                let identifiers = Set(panel.extensionPanels.map(\.extensionIdentifier))
                #expect(identifiers == ["test.alpha", "test.beta"])
                // No failures and no empty state, so the sidebar is exactly the
                // two extensions.
                #expect(panel.panels.count == 2)
            }
        }
    }

    @Test("a refused contribution is not reported as a failed load")
    func contributionPointFailedIsNotReportedAsAFailedLoad() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            // The theme file is never written, so every declared theme fails to
            // parse and the themes point refuses the contribution wholesale.
            // The extension itself is fine and stays installed.
            try installExtension(
                named: "themed",
                contributes: #"""
                { "themes": [{ "label": "Night", "uiTheme": "vs-dark", "path": "./themes/missing.json" }] }
                """#,
                in: root
            )

            try withPanel(searchPaths: [root]) { coordinator, panel in
                let failures = coordinator.registry.failures
                try #require(failures.count == 1)
                #expect(ExtensionLoadProblemsPanel.isRefusedContribution(failures[0]))

                // The extension still has its own row: it is installed, and
                // everything it declares besides the themes is in force.
                let extensionIdentifiers = panel.extensionPanels.map(\.extensionIdentifier)
                #expect(extensionIdentifiers == ["test.themed"])

                // And the problems panel says "refused", not "failed to load".
                let problems = try #require(panel.panels.compactMap { $0 as? ExtensionLoadProblemsPanel }.first)
                #expect(problems.descriptor.title == "1 contribution refused")
                #expect(ExtensionLoadProblemsPanel.summaryTitle(for: failures) == "1 contribution refused")
                let line = ExtensionLoadProblemsPanel.refusedLine(for: failures[0])
                #expect(line.contains("installed, but its themes contribution was refused"))
                #expect(!line.contains("did not load"))
                // The registry records the refusal as `String(describing:)`, so
                // the sentence the error writes for the author is what reaches
                // this row — not the compiler's spelling of the case.
                #expect(line.contains("None of the 1 declared theme could be read."))
            }
        }
    }

    @Test("no extensions renders the empty state, not a blank pane")
    func noExtensionsRendersTheEmptyStateNotABlankPane() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            try withPanel(searchPaths: [root]) { _, panel in
                #expect(panel.extensionPanels.isEmpty)
                let empty = try #require(panel.panels.compactMap { $0 as? ExtensionsEmptyStatePanel }.first)
                _ = empty.view

                let text = labels(in: empty.view)
                // The one thing a user in this state can act on is where to put
                // an extension, so the path has to be on screen verbatim.
                #expect(text.contains(root.path))
                #expect(text.contains { $0.contains("relaunch") })
            }
        }
    }

    @Test("toggling the switch routes through setEnabled")
    func togglingTheSwitchRoutesThroughSetEnabled() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            try installExtension(named: "alpha", in: root)

            try withPanel(searchPaths: [root]) { coordinator, panel in
                // Registered after `loadAll()` on purpose: this point is here to
                // observe withdrawal, and `setEnabled(false)` withdraws through
                // every registered point regardless of when it joined.
                let spy = WithdrawalSpy()
                coordinator.registry.register(spy)

                let detail = try #require(panel.extensionPanels.first)
                _ = detail.view
                let toggle = try #require(detail.enableSwitch)
                #expect(toggle.state == .on)

                toggle.state = .off
                let action = try #require(toggle.action)
                let target = try #require(toggle.target as? NSObject)
                _ = target.perform(action, with: toggle)

                // The setting alone would prove nothing: the whole point of
                // routing through `setEnabled` is that the live contributions
                // go with it.
                #expect(!coordinator.registry.isEnabled("test.alpha"))
                #expect(spy.withdrawnIdentifiers == ["test.alpha"])
            }
        }
    }

    @Test("search keywords cover the documented terms")
    func searchKeywordsCoverTheDocumentedTerms() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            withPanel(searchPaths: [root]) { _, panel in
                let keywords = Set(panel.searchKeywords)
                // The words a person types when they are looking for this panel
                // and do not know it is called "Extensions".
                for term in ["extension", "extensions", "vscode", "vsix", "marketplace",
                             "theme", "snippet", "plugin", "contributes", "package.json"] {
                    #expect(keywords.contains(term))
                }
            }
        }
    }

    // MARK: - The Views group

    @Test("the Views group says what a pane does, once, whatever kind it is")
    func theViewsGroupSaysWhatAPaneDoesOnceWhateverKindItIs() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            // The overwhelming majority: one tree view, which produces no note
            // of any kind.
            try installExtension(
                named: "treeonly",
                contributes: #"{ "views": { "explorer": [{ "id": "test.tree", "name": "Tree" }] } }"#,
                in: root
            )
            try installExtension(
                named: "mixed",
                contributes: #"""
                {
                    "views": {
                        "explorer": [
                            { "id": "test.tree", "name": "Tree" },
                            { "id": "test.web", "name": "Web", "type": "webview" }
                        ]
                    }
                }
                """#,
                in: root
            )

            // A real registry, not a double: without one the coordinator builds
            // no views point at all and this group does not exist, so a test
            // that skipped it would pass on an empty screen.
            try withPanel(searchPaths: [root], viewRegistry: ComposableTabsViewRegistry()) { _, panel in
                let panels = Dictionary(
                    uniqueKeysWithValues: panel.extensionPanels.map { ($0.extensionIdentifier, $0) })

                let treeOnly = try #require(panels["test.treeonly"])
                _ = treeOnly.view
                let treeText = labels(in: treeOnly.view)
                #expect(treeText.contains("Tree (test.tree)"))
                // Ruling GE. This extension's views generate no notes at all, so
                // a sentence derived from the notes would leave this list of
                // panes unexplained — and a reader would conclude they work.
                #expect(treeText.contains { $0.contains("These panes are registered and can be opened") })
                #expect(!treeText.contains { $0.contains("is a webview") })

                let mixed = try #require(panels["test.mixed"])
                _ = mixed.view
                let mixedText = labels(in: mixed.view)
                #expect(mixedText.contains("Tree (test.tree)"))
                #expect(mixedText.contains("Web (test.web)"))
                // Exactly once, not at least once: the note is rendered under
                // the view it is about, and the Decisions group deliberately
                // does not repeat it (Ruling FW). Twice is the regression.
                #expect(mixedText.filter { $0.contains("is a webview") }.count == 1)
            }
        }
    }

    // MARK: - Decisions

    @Test("an entry the manifest decoder dropped reaches the Decisions group")
    func anEntryTheManifestDecoderDroppedReachesTheDecisionsGroup() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            // A themes entry with no `path`, and a views container that is not
            // an array. The decoder is lenient, so the extension loads and both
            // entries are simply gone — and the Contributes summary counts what
            // survived, so this is the only route the drop has to a screen.
            try installExtension(
                named: "pathless",
                contributes: #"""
                {
                    "themes": [{ "label": "Night", "uiTheme": "vs-dark" }],
                    "views": { "explorer": {} }
                }
                """#,
                in: root
            )

            try withPanel(searchPaths: [root]) { coordinator, panel in
                let loaded = try #require(coordinator.registry.extensions.first)
                try #require(loaded.manifest.contributes?.decodingFailures.count == 2)

                let detail = try #require(panel.extensionPanels.first)
                _ = detail.view
                let text = labels(in: detail.view)
                // One element of an array is named by its index, because that is
                // what the author has to go and count.
                #expect(text.contains { $0.hasPrefix("contributes.themes[0] could not be read:") })
                // A keyed container carries no index, and "[nil]" or "[0]" would
                // both be a lie about a value that is not in an array at all.
                #expect(text.contains(
                    "contributes.views.explorer could not be read: expected an array"))
            }
        }
    }

    @Test("a dropped language matcher is described by what was dropped")
    func aDroppedLanguageMatcherIsDescribedByWhatWasDropped() {
        func line(
            keys: [String] = [], skipped: [String] = [], declaredNoMatcher: Bool = false
        ) -> String {
            ExtensionDetailPanel.line(for: DroppedLanguageMatcher(
                extensionIdentifier: "test.pack",
                languageID: "widget",
                keys: keys,
                skippedExtensions: skipped,
                declaredNoMatcher: declaredNoMatcher
            ))
        }

        #expect(line(keys: ["mimetypes"])
            == "Language widget: this app cannot match files by mimetypes, so it was ignored.")
        // Plural agreement and the comma/"and" list, which is the whole reason
        // that helper exists.
        #expect(line(keys: ["filenames", "mimetypes", "icon"])
            == "Language widget: this app cannot match files by filenames, mimetypes and icon, "
            + "so they were ignored.")
        #expect(line(declaredNoMatcher: true)
            == "Language widget: the entry declares no file extension, filename or pattern, "
            + "so it matches no file here or in VS Code.")
        #expect(line(keys: ["mimetypes"], declaredNoMatcher: true)
            == "Language widget: this app cannot match files by mimetypes, so it was ignored, "
            + "and the entry declares no file extension, filename or pattern, "
            + "so it matches no file here or in VS Code.")

        // `keys` gains "extensions" when individual *values* were unusable, and
        // that is not a key this app cannot match by — it is the one thing this
        // point does. Rendered as one, the sentence contradicts itself two
        // clauses later, and the clause that names the values never runs.
        #expect(line(keys: ["extensions"], skipped: [""])
            == "Language widget: The file extension “” could not be used.")
        #expect(line(keys: ["mimetypes", "extensions"], skipped: [".Widget", ".W"])
            == "Language widget: this app cannot match files by mimetypes, so it was ignored. "
            + "The file extensions “.Widget” and “.W” could not be used.")
    }

    @Test("a conflict is told from the panel it is shown on")
    func aConflictIsToldFromThePanelItIsShownOn() {
        let across = LanguageContributionConflict(
            fileExtension: ".widget", winner: "test.alpha", loser: "test.beta",
            losingLanguageID: "widget"
        )
        // The loser needs to know its mapping did not take effect…
        #expect(ExtensionDetailPanel.line(for: across, viewedFrom: "test.beta")
            == ".widget is mapped by test.alpha; test.beta's widget does not apply to it.")
        // …and the winner is shown the same conflict, so that sentence has to be
        // rewritten or it reads as somebody else's problem on the winner's page.
        #expect(ExtensionDetailPanel.line(for: across, viewedFrom: "test.alpha")
            == ".widget is mapped by this extension; test.beta's widget does not apply to it.")

        let within = LanguageContributionConflict(
            fileExtension: ".widget", winner: "test.pack", loser: "test.pack",
            losingLanguageID: "widget2"
        )
        // One manifest claiming it twice: naming the extension on its own page
        // as if it were a rival would be nonsense.
        #expect(ExtensionDetailPanel.line(for: within, viewedFrom: "test.pack")
            == "This extension claims .widget more than once; widget2 does not apply to it.")
    }

    // MARK: - The problems panel

    @Test("every load failure has a sentence, and none of them says nothing")
    func everyLoadFailureHasASentence() {
        func line(_ reason: ExtensionLoadError) -> String {
            ExtensionLoadProblemsPanel.didNotLoadLine(for: failure(reason))
        }

        #expect(line(.manifestMissing)
            == "alpha-1.0.0: did not load — the folder has no package.json.")
        #expect(line(.manifestUnreadable("permission denied"))
            == "alpha-1.0.0: did not load — its package.json could not be read: permission denied")
        #expect(line(.manifestMalformed("unexpected token"))
            == "alpha-1.0.0: did not load — its package.json could not be parsed: unexpected token")
        #expect(line(.engineRangeUnparsable("^wat"))
            == "alpha-1.0.0: did not load — its engines.vscode range “^wat” could not be understood.")
        #expect(line(.engineIncompatible(required: "^99.0.0", host: "1.74.0"))
            == "alpha-1.0.0: did not load — it requires VS Code ^99.0.0; this app reports 1.74.0.")
        // The only question a user staring at a duplicate install has is which
        // copy is live, so the surviving path is the whole sentence.
        #expect(line(.duplicateIdentifier(existing: "/Users/me/.vscode/extensions/alpha-0.9.0"))
            == "alpha-1.0.0: did not load — another copy of the same extension is already "
            + "loaded from /Users/me/.vscode/extensions/alpha-0.9.0.")
        // Never shown by this panel — a refused contribution is sorted into the
        // other group — but `reason(for:)` is a total switch and a case with no
        // sentence would be a silent empty row if that sorting ever changed.
        #expect(line(.contributionPointFailed(key: "themes", message: "no."))
            == "alpha-1.0.0: did not load — its themes contribution was refused — no.")
    }

    @Test("the problems panel's title counts the two kinds separately")
    func theProblemsPanelTitleCountsTheTwoKindsSeparately() {
        let refused = failure(.contributionPointFailed(key: "themes", message: "no."))
        let didNotLoad = failure(.manifestMissing)

        #expect(ExtensionLoadProblemsPanel.summaryTitle(for: [refused]) == "1 contribution refused")
        #expect(ExtensionLoadProblemsPanel.summaryTitle(for: [refused, refused])
            == "2 contributions refused")
        #expect(ExtensionLoadProblemsPanel.summaryTitle(for: [didNotLoad])
            == "1 extension failed to load")
        #expect(ExtensionLoadProblemsPanel.summaryTitle(for: [didNotLoad, didNotLoad])
            == "2 extensions failed to load")
        // Mixed: neither sentence is true of the whole list, and picking one
        // would tell a user their working extension failed to load.
        #expect(ExtensionLoadProblemsPanel.summaryTitle(for: [refused, didNotLoad])
            == "2 extension problems")
    }

    // MARK: - The Contributes summary

    @Test("the contributes summary counts and names every non-empty key")
    func theContributesSummaryCountsAndNamesEveryNonEmptyKey() throws {
        let one = try contributions(#"""
        {
            "themes": [{ "label": "Night", "uiTheme": "vs-dark", "path": "./a.json" }],
            "viewsContainers": {
                "activitybar": [{ "id": "pack", "title": "Pack", "icon": "./i.png" }]
            }
        }
        """#)
        // Singular, and the camel-case key split into words: `viewsContainers`
        // is rendered, never a hand-kept list of nouns that a key added in a
        // later stage would silently miss.
        #expect(ExtensionDetailPanel.contributionSummaryLines(for: one)
            == ["1 theme", "1 views container"])

        let many = try contributions(#"""
        {
            "themes": [
                { "label": "Night", "uiTheme": "vs-dark", "path": "./a.json" },
                { "label": "Day", "uiTheme": "vs", "path": "./b.json" }
            ],
            "views": {
                "explorer": [{ "id": "a", "name": "A" }],
                "scm": [{ "id": "b", "name": "B" }]
            }
        }
        """#)
        // A keyed container counts its values across every key, not the number
        // of keys — two containers holding one view each is two views.
        #expect(ExtensionDetailPanel.contributionSummaryLines(for: many)
            == ["2 themes", "2 views"])

        // An entry that did not decode is not a contribution, so the diagnostic
        // array must never be counted as one.
        let dropped = try contributions(#"{ "themes": [{ "label": "Night" }] }"#)
        try #require(dropped.decodingFailures.count == 1)
        #expect(ExtensionDetailPanel.contributionSummaryLines(for: dropped).isEmpty)
    }
}
