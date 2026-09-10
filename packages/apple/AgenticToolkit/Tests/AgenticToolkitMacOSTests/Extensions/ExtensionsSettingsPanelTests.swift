import Testing
import AppKit
import Foundation
import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// An in-memory `ThemeStorage`. See the note in `ThemeContributionPointTests`:
/// the doubles that exist are in test targets this bundle cannot reach.
@MainActor
private final class PanelThemeStorage: ThemeStorage {
    var customThemes: [ColorTheme] = []
    var activeThemeID: String?
    var onExternalChange: (() -> Void)?
}

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
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExtensionsSettingsPanelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

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

    private func withInMemorySettings<Result>(_ body: () throws -> Result) rethrows -> Result {
        let previous = UserSettings.shared
        UserSettings.shared = UserSettings(with: InMemorySettingsStorageProvider())
        defer { UserSettings.shared = previous }
        return try body()
    }

    /// Builds the coordinator and its panel, loads the panel's view, and takes
    /// the coordinator back out of `AppFeatureRegistry.shared` afterwards.
    private func withPanel<Result>(
        searchPaths: [URL],
        _ body: (ExtensionsCoordinator, ExtensionsSettingsPanelViewController) throws -> Result
    ) rethrows -> Result {
        let coordinator = ExtensionsCoordinator(
            searchPaths: searchPaths,
            themeStore: ThemeStore(storage: PanelThemeStorage()),
            viewRegistry: nil
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

    // MARK: - Tests

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
}
