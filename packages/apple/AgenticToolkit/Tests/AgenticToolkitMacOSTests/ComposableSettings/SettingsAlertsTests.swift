import XCTest
@testable import AgenticToolkitMacOS

@MainActor
final class SettingsAlertsTests: XCTestCase {
    func testAConfirmationWithNoWindowIsDeclinedWithoutShowingAnything() {
        var answer: Bool?
        ComposableSettings.Alerts.confirmDestructive("Delete it?", detail: "", on: nil) { answer = $0 }
        XCTAssertEqual(answer, false, "no window means no sheet, and no sheet means no")
    }

    /// Review V8-d: Return stays on Cancel, and Esc must still dismiss the
    /// sheet as a no — it did before Cancel was given Return.
    func testEscapeStillCancelsADestructiveConfirmation() throws {
        let alert = ComposableSettings.Alerts.makeDestructiveAlert("Delete it?", detail: "", actionTitle: "Delete")
        let cancel = try XCTUnwrap(alert.buttons.last)
        XCTAssertEqual(cancel.title, "Cancel")
        XCTAssertEqual(cancel.keyEquivalent, "\r", "Return must never reach Delete")
        XCTAssertEqual(alert.buttons.first?.keyEquivalent, "")

        func buttons(in view: NSView) -> [NSButton] {
            view.subviews.flatMap { ($0 as? NSButton).map { [$0] } ?? [] + buttons(in: $0) }
        }
        let content = try XCTUnwrap(alert.window.contentView)
        let escape = try XCTUnwrap(buttons(in: content).first { $0.keyEquivalent == "\u{1b}" },
                                   "nothing on the sheet answers Esc")
        XCTAssertFalse(escape.isHidden, "a hidden button never sees its key equivalent")
        XCTAssertTrue(escape.target === cancel)
        XCTAssertEqual(escape.action, #selector(NSButton.performClick(_:)))
    }
}
