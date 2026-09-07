import AppKit
import XCTest
@testable import AgenticToolkitMacOS

/// Help is reference prose a window can show beside itself. It was spelled as
/// though it belonged to settings; these tests pin the new spelling and, just
/// as importantly, that the old one still works.
@MainActor
final class HelpContentTests: XCTestCase {

    func testHelpContentCarriesItsTopicsInOrder() {
        let content = HelpContent(topics: [
            HelpContent.Topic(title: "First", body: "One."),
            HelpContent.Topic(title: "Second", body: "Two.")
        ])
        XCTAssertEqual(content.topics.map(\.title), ["First", "Second"])
        XCTAssertEqual(content.topics.map(\.body), ["One.", "Two."])
    }

    func testHelpContentIsEquatable() {
        // swiftlint:disable:next identifier_name
        let a = HelpContent(topics: [HelpContent.Topic(title: "T", body: "B")])
        // swiftlint:disable:next identifier_name
        let b = HelpContent(topics: [HelpContent.Topic(title: "T", body: "B")])
        XCTAssertEqual(a, b)
    }

    /// The whole reason the rename is safe: 28 files still say `PanelHelp`.
    func testTheOldSettingsSpellingsStillNameTheSameTypes() {
        let viaAlias: ComposableSettings.PanelHelp = HelpContent(
            topics: [ComposableSettings.PanelHelp.Topic(title: "T", body: "B")])
        XCTAssertEqual(viaAlias.topics.count, 1)
        XCTAssertTrue(ComposableSettings.HelpDrawerView.self == HelpContentView.self)
    }

    func testEmptyContentRendersTheHonestEmptyStateRatherThanBlank() {
        let view = HelpContentView()
        view.setHelp(nil)
        XCTAssertTrue(
            Self.labels(in: view).contains("No Help Yet"),
            "A drawer that no longer closes itself on an empty panel has to say why it is empty")
    }

    func testSetHelpRendersOneGroupPerTopic() {
        let view = HelpContentView()
        view.setHelp(HelpContent(topics: [
            HelpContent.Topic(title: "Frames", body: "How panes are spaced."),
            HelpContent.Topic(title: "Tabs", body: "How tabs work.")
        ]))
        let labels = Self.labels(in: view)
        XCTAssertTrue(labels.contains("Frames"))
        XCTAssertTrue(labels.contains("Tabs"))
        XCTAssertFalse(labels.contains("No Help Yet"))
    }

    private static func labels(in view: NSView) -> [String] {
        var found: [String] = []
        if let field = view as? NSTextField { found.append(field.stringValue) }
        for subview in view.subviews { found.append(contentsOf: labels(in: subview)) }
        return found
    }
}
