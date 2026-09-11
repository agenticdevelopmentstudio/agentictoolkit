import XCTest

import AgenticToolkitCore
@testable import AgenticToolkitMacOS

@MainActor
final class EditorSettingsPanelViewControllerTests: XCTestCase {

    /// The defaults are not a preference — they are what
    /// `FileEditorState.editorConfiguration` hardcoded before there was a
    /// setting to read. Anything else changes every existing user's editor on
    /// the launch that introduces the panel.
    func testDefaultsMatchTheEditorsPreviousHardcodedBehaviour() {
        XCTAssertTrue(UserSettings.editorShowLineNumbers.defaultValue)
        XCTAssertTrue(UserSettings.editorShowOverview.defaultValue)
        XCTAssertFalse(UserSettings.editorShowInvisibles.defaultValue)
    }

    func testPanelIsTitledEditor() {
        let panel = EditorSettingsPanelViewController()
        XCTAssertEqual(panel.descriptor.title, "Editor")
    }

    func testPanelShowsTheThreeDisplayOptions() {
        let panel = EditorSettingsPanelViewController()
        panel.loadViewIfNeeded()
        panel.viewDidLoad()

        let toggles = panel.view.allSubviewsForTesting.compactMap { $0 as? NSSwitch }
            .filter { $0.identifier?.rawValue.hasPrefix("settings.editor.") == true }

        XCTAssertEqual(
            Set(toggles.compactMap { $0.identifier?.rawValue }),
            [
                "settings.editor.show-line-numbers",
                "settings.editor.show-overview",
                "settings.editor.show-invisibles"
            ]
        )
    }
}

private extension NSView {

    /// Every descendant, depth-first. The panel builds its rows into a stack
    /// of groups, so a checkbox is several levels down from the panel's view.
    var allSubviewsForTesting: [NSView] {
        subviews + subviews.flatMap(\.allSubviewsForTesting)
    }
}
