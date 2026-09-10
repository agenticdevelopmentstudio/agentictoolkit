import AgenticToolkitCore
import AppKit
import XCTest
@testable import AgenticToolkitMacOS

@MainActor
final class GitSettingsPanelViewControllerTests: XCTestCase {
    func testPanelDescribesItselfAsGit() {
        let panel = GitSettingsPanelViewController(client: GitClient(configuration: .default))
        XCTAssertEqual(panel.descriptor.title, "Git")
    }

    func testLoadingTheViewInstallsTheThreeGroups() {
        let panel = GitSettingsPanelViewController(client: GitClient(configuration: .default))
        panel.loadViewIfNeeded()
        let identifiers = Self.accessibilityIdentifiers(in: panel.view)
        let expectedIdentifiers = [
            "settings.git.executable-field",
            "settings.git.choose-executable",
            "settings.git.timeout-field",
            "settings.git.include-submodules",
            "settings.git.config-table"
        ]
        for expected in expectedIdentifiers {
            XCTAssertTrue(identifiers.contains(expected), "missing \(expected)")
        }
    }

    func testExecutableStatusReflectsTheSetting() async {
        let previous = UserSettings.gitExecutablePath.value
        defer { UserSettings.gitExecutablePath.value = previous }
        let panel = GitSettingsPanelViewController(client: GitClient(configuration: .default))
        panel.loadViewIfNeeded()
        UserSettings.gitExecutablePath.value = "/nonexistent/git"
        await Self.drain()
        XCTAssertTrue(panel.executableStatusLabel.stringValue.contains("not found"))
        UserSettings.gitExecutablePath.value = "/usr/bin/git"
        await Self.drain()
        XCTAssertTrue(panel.executableStatusLabel.stringValue.contains("Found"))
    }

    private static func accessibilityIdentifiers(in view: NSView) -> Set<String> {
        var found: Set<String> = []
        let id = view.accessibilityIdentifier()
        if !id.isEmpty { found.insert(id) }
        for subview in view.subviews { found.formUnion(accessibilityIdentifiers(in: subview)) }
        return found
    }

    /// Waits for `UserSettingObserver`'s delivery, which lands on the next
    /// turn of the main queue rather than synchronously with the write (see
    /// the dispatch comment on `UserSettingObserver.init` in `UserSetting.swift`).
    /// Same technique `ExternalThemeChangeObservationTests.drain()` uses.
    private static func drain() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
