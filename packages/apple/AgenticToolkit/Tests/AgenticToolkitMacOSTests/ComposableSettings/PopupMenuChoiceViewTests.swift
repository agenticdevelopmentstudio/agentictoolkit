import AppKit
import XCTest
import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// A popup whose choices are records: the menu follows `choices`, and the
/// selection follows the *value*, never the row number it used to sit at.
@MainActor
final class PopupMenuChoiceViewTests: XCTestCase {

    private func makeView(value: String) -> (ComposableSettings.ChoiceViewModel<String>,
                                             ComposableSettings.PopupMenuChoiceView<String>) {
        var backing = value
        let model = ComposableSettings.ChoiceViewModel<String>(
            title: "Client",
            choices: [.init(label: "A", value: "a"), .init(label: "B", value: "b")],
            get: { backing },
            set: { backing = $0 }
        )
        return (model, ComposableSettings.PopupMenuChoiceView(viewModel: model))
    }

    func testReplacingChoicesRepopulatesAndKeepsTheSelectedValue() {
        let (model, view) = makeView(value: "b")
        XCTAssertEqual(view.popUpButton.titleOfSelectedItem, "B")

        model.choices = [
            .init(label: "Zed", value: "z"), .init(label: "B", value: "b"), .init(label: "A", value: "a")
        ]

        XCTAssertEqual(view.popUpButton.itemTitles, ["Zed", "B", "A"])
        XCTAssertEqual(view.popUpButton.titleOfSelectedItem, "B",
                       "the value is kept, not the index it used to sit at")
    }

    /// Review V8-c: two records may share a name. Each is its own item, and the
    /// popup shows the one the setting holds — not whatever sits at its index.
    func testChoicesWithTheSameLabelAreEachOfferedAndSelectedByValue() {
        // `sendAction` is routed through `NSApp`, which is nil until something
        // asks for the shared application — run first, the click went nowhere.
        _ = NSApplication.shared
        var backing = "id2"
        let model = ComposableSettings.ChoiceViewModel<String>(
            title: "Project",
            choices: [
                .init(label: "Acme", value: "id1"),
                .init(label: "Acme", value: "id3"),
                .init(label: "Beta", value: "id2")
            ],
            get: { backing },
            set: { backing = $0 }
        )
        let view = ComposableSettings.PopupMenuChoiceView(viewModel: model)

        XCTAssertEqual(view.popUpButton.numberOfItems, 3, "an equal title must not merge two choices")
        XCTAssertEqual(view.popUpButton.selectedItem?.representedObject as? String, "id2")

        // The user picks the second Acme.
        view.popUpButton.selectItem(at: 1)
        view.popUpButton.sendAction(view.popUpButton.action, to: view.popUpButton.target)
        XCTAssertEqual(backing, "id3")

        model.onChange?("id3")
        XCTAssertEqual(view.popUpButton.indexOfSelectedItem, 1)
        XCTAssertEqual(view.popUpButton.selectedItem?.representedObject as? String, "id3",
                       "the popup must show the project Assign Run will use")
    }

    func testAValueNoLongerOfferedSelectsNothing() {
        let (model, view) = makeView(value: "b")

        model.choices = [.init(label: "A", value: "a")]

        XCTAssertNil(view.popUpButton.selectedItem,
                     "showing A would claim a value the setting does not hold")
    }
}
