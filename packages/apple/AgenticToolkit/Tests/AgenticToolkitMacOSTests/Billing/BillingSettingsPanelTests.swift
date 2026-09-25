import XCTest
import AppKit
import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// The Billing settings pane on its own, editing the tests' own settings.
@MainActor
final class BillingSettingsPanelTests: XCTestCase {

    private let settings = BillingUserSettings.forTests

    private func makePanel() -> BillingSettingsPanel {
        let panel = BillingSettingsPanel(settings: settings)
        panel.loadViewIfNeeded()
        return panel
    }

    /// The app's "Billing Settings…" item opens the panel by this title.
    func testThePanelIsTitledBilling() {
        XCTAssertEqual(BillingSettingsPanel(settings: settings).descriptor.title, "Billing")
    }

    func testTheRateFieldRendersAndParsesCents() {
        let panel = makePanel()

        settings.defaultRateCents.value = 15_000
        XCTAssertEqual(panel.rateFieldText, "150.00")

        panel.setRateFieldText("87.5")
        XCTAssertEqual(settings.defaultRateCents.value, 8_750)
    }

    /// Typing past a decimal point momentarily leaves the field unparseable;
    /// treating that as zero would wipe the rate mid-keystroke.
    func testAnUnparseableRateLeavesTheStoredValueAlone() {
        let panel = makePanel()

        settings.defaultRateCents.value = 15_000
        panel.setRateFieldText("")
        XCTAssertEqual(settings.defaultRateCents.value, 15_000)
    }

    /// The settings rate follows the rule every other rate field does: a
    /// rate the daemon would refuse is never stored.
    func testARateTheDaemonWouldRefuseIsNotStored() {
        let panel = makePanel()
        settings.defaultRateCents.value = 15_000

        panel.setRateFieldText("150000")
        XCTAssertEqual(settings.defaultRateCents.value, 15_000, "over the ceiling")
        panel.setRateFieldText("-5")
        XCTAssertEqual(settings.defaultRateCents.value, 15_000, "negative")
    }

    func testTheCurrencyMustBeThreeLetters() {
        let panel = makePanel()
        settings.currency.value = "USD"

        panel.setCurrencyFieldText("U5D")
        XCTAssertEqual(settings.currency.value, "USD")
        panel.setCurrencyFieldText(" gbp ")
        XCTAssertEqual(settings.currency.value, "GBP")
    }

    /// Round To and Rounding only seed new projects (the daemon rounds each
    /// billable by its project's own settings), and the pane says so beneath
    /// them, where the change is made.
    func testTheRoundingSettingsSayTheyOnlySeedNewProjects() {
        let panel = makePanel()

        func texts(in view: NSView) -> [String] {
            ((view as? NSTextField).map { [$0.stringValue] } ?? []) + view.subviews.flatMap(texts)
        }
        let shown = texts(in: panel.view)
        XCTAssertEqual(shown.filter { $0 == BillingSettingsPanel.roundingSeedsNewProjects }.count, 1,
                       "drawn in the pane, not only held by a view model")
        XCTAssertTrue(BillingSettingsPanel.roundingSeedsNewProjects.contains("Existing projects"))
    }

    override func tearDown() {
        settings.currency.value = BillingDefaults.currency
        settings.defaultRateCents.value = BillingDefaults.defaultRateCents
        super.tearDown()
    }
}
