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

    func testAValueNoLongerOfferedSelectsNothing() {
        let (model, view) = makeView(value: "b")

        model.choices = [.init(label: "A", value: "a")]

        XCTAssertNil(view.popUpButton.selectedItem,
                     "showing A would claim a value the setting does not hold")
    }
}
