import AppKit
import XCTest
@testable import AgenticToolkitMacOS

/// Scaffolding shared by the project-window suites.
///
/// Two helpers had been copied into `ProjectWindowSearchTests` and
/// `ProjectDrawerTests` verbatim, and a third suite is where a copy stops
/// being a compromise (`dry`). Only the parts that are genuinely the same are
/// here: each suite still installs its own layout, because what its panes are
/// made of is the thing each suite is actually varying.
@MainActor
enum ProjectWindowTestSupport {

    /// AppKit only asks the delegate for its items once a toolbar is on a
    /// window, and a custom-view item is the only place an accessibility
    /// identifier — or an `NSSearchField` — can live, so the test does the
    /// asking itself.
    ///
    /// Nothing is refreshed afterwards: the field has to be right the moment it
    /// exists. A test that hand-ordered a refresh after the ask would be
    /// arranging an ordering production only probably achieves.
    @discardableResult
    static func buildToolbarItems(
        _ controller: ComposableTabsWindowController
    ) -> [NSToolbarItem.Identifier] {
        let toolbar = controller.toolbarDelegate.makeToolbar(identifier: "test.toolbar")
        let identifiers = controller.toolbarDelegate.toolbarDefaultItemIdentifiers(toolbar)
        for identifier in identifiers {
            _ = controller.toolbarDelegate.toolbar(
                toolbar, itemForItemIdentifier: identifier, willBeInsertedIntoToolbar: false)
        }
        return identifiers
    }

    /// A workspace on its own temporary database, so two tests never share a
    /// remembered anything.
    ///
    /// The repo is registered before the workspace is made: every row keyed to
    /// a project carries a foreign key onto `git_repo`, so a workspace over an
    /// unregistered repo silently persists nothing — and every "the project
    /// remembered it" assertion reads back as a brand-new project.
    ///
    /// - Parameters:
    ///   - label: names the temporary directory, so a failure names its suite.
    ///   - registered: pass `false` for the one case that wants a workspace
    ///     whose repo is *not* in `git_repo` — the state in which the chrome
    ///     still has to work while `setSetting` swallows every failure.
    ///   - languageServices: `nil` by default, matching every existing
    ///     caller. A suite proving something about per-window language-server
    ///     teardown passes its own instance rather than this helper building
    ///     one every caller would otherwise pay for.
    static func makeProject(
        label: String,
        named name: String = "api-server",
        registered: Bool = true,
        languageServices: ProjectLanguageServices? = nil
    ) -> ProjectWorkspace {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(label)-\(UUID().uuidString)")
            .appendingPathComponent("Test.db").path
        let repo = GitRepo(path: NSTemporaryDirectory(), name: name)
        // swiftlint:disable:next force_try
        let database = try! ProjectDatabase(path: path)
        if registered {
            // swiftlint:disable:next force_try
            try! database.insert(repo)
        }
        return ProjectWorkspace(repo: repo, database: database, languageServices: languageServices)
    }
}
