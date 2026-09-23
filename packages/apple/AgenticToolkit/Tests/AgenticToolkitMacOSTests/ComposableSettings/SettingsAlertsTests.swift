import XCTest
@testable import AgenticToolkitMacOS

@MainActor
final class SettingsAlertsTests: XCTestCase {
    func testAConfirmationWithNoWindowIsDeclinedWithoutShowingAnything() {
        var answer: Bool?
        ComposableSettings.Alerts.confirmDestructive("Delete it?", detail: "", on: nil) { answer = $0 }
        XCTAssertEqual(answer, false, "no window means no sheet, and no sheet means no")
    }
}
