import XCTest
import AppKit
import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// The billables table on its own, with no daemon: what each cell shows, which
/// edits it accepts, and which it refuses before anything is written.
@MainActor
final class ProjectBillablesSectionTests: XCTestCase {

    private var section: ProjectBillablesSection!
    private var saved: [BillingEntryDTO] = []
    private var refused: [String] = []
    private var statuses: [(String, BillingStatus)] = []

    override func setUp() async throws {
        section = ProjectBillablesSection()
        section.timeZone = TimeZone(identifier: "UTC")!
        // A 24-hour locale, so the expectations read the same on any Mac.
        section.locale = Locale(identifier: "en_GB")
        saved = []
        refused = []
        statuses = []
        section.onSave = { [unowned self] in saved.append($0) }
        section.onRefused = { [unowned self] in refused.append($0) }
        section.onSetStatus = { [unowned self] entry, status in statuses.append((entry.id, status)) }
    }

    private func entry(
        _ id: String, day: String = "2026-09-21", seconds: Int = 3600, rate: Int = 10_000,
        status: BillingStatus = .unbilled, currency: String = "USD", supplements: String? = nil,
        startedAt: String = "", endedAt: String = ""
    ) -> BillingEntryDTO {
        BillingEntryDTO(
            id: id, projectId: "p1", day: day, groupKey: id, startedAt: startedAt, endedAt: endedAt,
            rawSeconds: seconds, billedSeconds: seconds, rateCents: rate, currency: currency,
            amountCents: Money.amountCents(seconds: seconds, rateCents: rate),
            status: status.rawValue, locked: status.locksTheEntry, supplementsEntryId: supplements
        )
    }

    private func cell(_ row: Int, _ column: String) -> String {
        return shownCell(section.billablesCard.rows[row].cells[column], timeZone: section.billablesCard.timeZone,
                         locale: section.billablesCard.locale)
    }

    private func edit(_ id: String, _ column: String, _ text: String) {
        let row = section.billablesCard.rows.firstIndex { $0.id == id }!
        section.billablesCard.commitEdit(rowIndex: row, columnID: column, newValue: text)
    }

    private func selectRow(_ id: String) {
        let row = section.billablesCard.rows.firstIndex { $0.id == id }!
        section.billablesCard.tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    private func usd(_ cents: Int) -> String { MoneyFormatter(currency: "USD").string(cents: cents) }

    // MARK: - Showing

    func testRowsShowTheEntryNewestDayFirst() {
        section.show([
            entry("old", day: "2026-09-20"),
            entry("new", day: "2026-09-21", seconds: 8100,
                  startedAt: "2026-09-21T09:00:00Z", endedAt: "2026-09-21T11:15:00Z")
        ])

        XCTAssertEqual(section.billablesCard.rows.map(\.id), ["new", "old"])
        XCTAssertEqual(cell(0, "day"), "2026-09-21")
        XCTAssertEqual(cell(0, "start"), "9:00")
        XCTAssertEqual(cell(0, "end"), "11:15")
        XCTAssertEqual(cell(0, "hours"), "2.25")
        XCTAssertEqual(cell(0, "amount"), usd(22_500))
        XCTAssertEqual(cell(0, "status"), "Unbilled")
        XCTAssertEqual(cell(0, "description"), "(Add a description)")
        XCTAssertEqual(cell(1, "start"), "(—)", "a derived day has no single start")
    }

    func testLateTimeIsFlagged() {
        section.show([entry("late", supplements: "e1"), entry("plain")])
        let late = section.billablesCard.rows.first { $0.id == "late" }!
        let plain = section.billablesCard.rows.first { $0.id == "plain" }!
        XCTAssertTrue(late.isFlagged, "time that landed after the day was billed needs a second look")
        XCTAssertFalse(plain.isFlagged)
    }

    func testSortingByAmountIsTheSectionsOwn() {
        section.show([entry("big", seconds: 7200), entry("small", seconds: 900)])
        section.billablesCard.onSort?("amount", true)
        XCTAssertEqual(section.billablesCard.rows.map(\.id), ["small", "big"])
    }

    // MARK: - Totals

    func testTotalsAreSplitByStatusAndCurrency() {
        let totals = ProjectBillablesSection.totals([
            entry("a", seconds: 3600),
            entry("b", seconds: 1800, currency: "EUR"),
            entry("c", seconds: 900, status: .paid)
        ])
        XCTAssertEqual(totals[.unbilled]?.count, 2)
        XCTAssertEqual(totals[.unbilled]?.seconds, 5400)
        XCTAssertEqual(totals[.unbilled]?.money.cents, ["USD": 10_000, "EUR": 5_000])
        XCTAssertNil(totals[.billed])
        XCTAssertEqual(totals[.paid]?.count, 1)
    }

    func testOverviewRowsDescribeEachStatus() {
        section.show([entry("a", seconds: 8100), entry("b", seconds: 900, status: .billed)])
        XCTAssertEqual(section.unbilledRow.value, "1 billable · 2.25 h · \(usd(22_500))")
        XCTAssertEqual(section.billedRow.value, "1 billable · 0.25 h · \(usd(2_500))")
        XCTAssertEqual(section.paidRow.value, "—")
    }

    func testMixedCurrenciesAreNeverAddedTogether() {
        let text = ProjectBillablesSection.describe(ProjectBillablesSection.totals([
            entry("a"), entry("b", currency: "EUR")
        ])[.unbilled])
        let euros = MoneyFormatter(currency: "EUR").string(cents: 10_000)
        XCTAssertEqual(text, "2 billables · 2.00 h · \(euros) + \(usd(10_000))")
    }

    // MARK: - Editing

    func testHoursAreTakenLiterallyAndRepriced() {
        section.show([entry("e", seconds: 3600)])
        edit("e", "hours", "1:40")

        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved[0].billedSeconds, 6000, "a typed figure is never rounded again")
        XCTAssertEqual(saved[0].amountCents, Money.amountCents(seconds: 6000, rateCents: 10_000))
        XCTAssertEqual(saved[0].rawSeconds, 3600, "tracked time is history, not an input")
    }

    func testImpossibleHoursAreRefusedWithoutAWrite() {
        section.show([entry("e")])
        edit("e", "hours", "0")
        edit("e", "hours", "25")
        edit("e", "hours", "lots")
        XCTAssertTrue(saved.isEmpty)
    }

    func testStartAndEndImplyTheHours() {
        section.show([entry("e", seconds: 3600, startedAt: "2026-09-21T09:00:00Z")])
        edit("e", "end", "10:30")

        XCTAssertEqual(saved.last?.endedAt, "2026-09-21T10:30:00Z")
        XCTAssertEqual(saved.last?.billedSeconds, 5400)
    }

    func testAnEndBeforeTheStartIsRefused() {
        section.show([entry("e", startedAt: "2026-09-21T09:00:00Z")])
        edit("e", "end", "8:00")
        XCTAssertTrue(saved.isEmpty)
    }

    func testMovingADayClearsItsTimes() {
        section.show([entry("e", startedAt: "2026-09-21T09:00:00Z", endedAt: "2026-09-21T10:00:00Z")])
        edit("e", "day", "2026-09-9")
        XCTAssertTrue(saved.isEmpty, "not a yyyy-MM-dd day")

        edit("e", "day", "2026-09-19")
        XCTAssertEqual(saved.last?.day, "2026-09-19")
        XCTAssertEqual(saved.last?.startedAt, "")
        XCTAssertEqual(saved.last?.endedAt, "")
        XCTAssertEqual(saved.last?.billedSeconds, 3600, "the hours stay as they were")
    }

    func testRateEditsReprice() {
        section.show([entry("e", seconds: 5400)])
        edit("e", "rate", MoneyFormatter(currency: "USD").editableString(cents: 15_000))
        XCTAssertEqual(saved.last?.rateCents, 15_000)
        XCTAssertEqual(saved.last?.amountCents, 22_500)
    }

    func testABilledEntryIsReadOnly() {
        section.show([entry("e", status: .billed)])
        edit("e", "hours", "3")

        XCTAssertTrue(saved.isEmpty)
        XCTAssertEqual(refused.count, 1)
        XCTAssertTrue(refused[0].contains("Mark it Unbilled"), refused[0])
    }

    // MARK: - Untouched and retyped cells

    /// A derived day: two runs with idle between them, billed well under the
    /// wall-clock span from first start to last end.
    private func derived(_ id: String = "e", billed: Int = 8100) -> BillingEntryDTO {
        entry(id, seconds: billed, startedAt: "2026-09-21T09:00:37Z", endedAt: "2026-09-21T17:12:05Z")
    }

    private func endEditingUntouched(_ id: String, _ column: String) throws {
        let row = try XCTUnwrap(section.billablesCard.rows.firstIndex { $0.id == id })
        let table = section.billablesCard.tableView
        let columnIndex = table.column(withIdentifier: NSUserInterfaceItemIdentifier(column))
        XCTAssertGreaterThanOrEqual(columnIndex, 0, "no \(column) column")
        let field = try XCTUnwrap(
            table.view(atColumn: columnIndex, row: row, makeIfNecessary: true) as? NSTextField
        )
        section.billablesCard.controlTextDidEndEditing(
            Notification(name: NSControl.textDidEndEditingNotification, object: field)
        )
    }

    func testLeavingAStartOrEndCellUntouchedWritesNothing() throws {
        section.show([derived()])
        try endEditingUntouched("e", "start")
        try endEditingUntouched("e", "end")
        XCTAssertTrue(saved.isEmpty, "focus alone re-priced a derived day to its wall-clock span")
    }

    func testLeavingAnHoursCellUntouchedWritesNothing() throws {
        section.show([entry("e", seconds: 7800)])
        try endEditingUntouched("e", "hours")
        XCTAssertTrue(saved.isEmpty, "7,800 s shows as 2.17, and re-reading that makes 7,812 s")
    }

    func testRetypingWhatACellShowsIsNotAnEdit() {
        section.show([entry("e", seconds: 7800, startedAt: "2026-09-21T09:04:27Z")])
        edit("e", "hours", "2.17")
        edit("e", "start", "9:04")
        XCTAssertTrue(saved.isEmpty)
    }

    // MARK: - Times: anchoring and re-pricing

    func testMovingOneEndOfADerivedDayKeepsItsIdleTime() {
        section.show([derived(billed: 8100)])
        edit("e", "start", "8:30")

        XCTAssertEqual(saved.last?.startedAt, "2026-09-21T08:30:00Z")
        XCTAssertEqual(saved.last?.billedSeconds, 8100 + 1837,
                       "the billed time grows by what the span grew, not to the whole span")
    }

    func testAnEndPastMidnightIsEditedOnItsOwnDay() {
        section.show([entry("e", day: "2026-09-23", seconds: 11_400,
                            startedAt: "2026-09-23T22:10:00Z", endedAt: "2026-09-24T01:20:00Z")])
        XCTAssertEqual(cell(0, "end"), "1:20")
        edit("e", "end", "1:45")

        XCTAssertEqual(saved.last?.endedAt, "2026-09-24T01:45:00Z")
        XCTAssertEqual(saved.last?.billedSeconds, 11_400 + 1500)
    }

    func testAnEndTypedWithOnlyAStartLandsAfterItAcrossMidnight() {
        section.show([entry("e", day: "2026-09-23", seconds: 3600, startedAt: "2026-09-23T22:10:00Z")])
        edit("e", "end", "1:20")
        XCTAssertEqual(saved.last?.endedAt, "2026-09-24T01:20:00Z")
        XCTAssertEqual(saved.last?.billedSeconds, 11_400)
    }

    func testATimeTypedInAnotherZoneStaysWithTheWorkItDescribes() {
        // Recorded in Lisbon (20:30–22:00 there), viewed from New York.
        section.timeZone = TimeZone(identifier: "America/New_York")!
        section.show([entry("e", seconds: 5400,
                            startedAt: "2026-09-21T19:30:00Z", endedAt: "2026-09-21T21:00:00Z")])
        XCTAssertEqual(cell(0, "end"), "17:00")
        edit("e", "end", "17:30")

        XCTAssertEqual(saved.last?.endedAt, "2026-09-21T21:30:00Z")
        XCTAssertEqual(saved.last?.billedSeconds, 7200, "half an hour more, not a day more")
    }

    func testAStartShownOnTheNextDayIsNotMovedBackADay() {
        // An LA morning, seen from Tokyo, where it reads as 1:04 the next day.
        section.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        section.show([entry("e", seconds: 9000,
                            startedAt: "2026-09-21T16:04:27Z", endedAt: "2026-09-21T21:51:13Z")])
        XCTAssertEqual(cell(0, "start"), "1:04")
        edit("e", "start", "1:00")

        XCTAssertEqual(saved.last?.startedAt, "2026-09-21T16:00:00Z")
        XCTAssertEqual(saved.last?.billedSeconds, 9000 + 267)
    }

    func testASpanOverADayIsRefused() {
        section.show([entry("e", seconds: 82_800,
                            startedAt: "2026-09-21T09:00:00Z", endedAt: "2026-09-22T08:00:00Z")])
        edit("e", "end", "10:00")
        XCTAssertTrue(saved.isEmpty, "25 hours in one billable")
    }

    // MARK: - The viewer's clock

    func testTimesFollowATwelveHourLocale() {
        section.locale = Locale(identifier: "en_US")
        section.show([entry("e", seconds: 3600,
                            startedAt: "2026-09-21T09:00:00Z", endedAt: "2026-09-21T14:00:00Z")])
        XCTAssertEqual(cell(0, "start"), "9:00 AM")
        XCTAssertEqual(cell(0, "end"), "2:00 PM")

        edit("e", "end", "2:05 PM")
        XCTAssertEqual(saved.last?.endedAt, "2026-09-21T14:05:00Z")

        edit("e", "end", "2:30")
        XCTAssertEqual(saved.last?.endedAt, "2026-09-21T14:30:00Z",
                       "a bare time on a 12-hour clock is the one nearest what was shown")

        edit("e", "end", "15:10")
        XCTAssertEqual(saved.last?.endedAt, "2026-09-21T15:10:00Z", "a 24-hour time is still read")
    }

    func testHistoryFollowsATwelveHourLocale() {
        section.locale = Locale(identifier: "en_US")
        section.showAudit([BillingAuditDTO(entryId: "e", at: "2026-09-21T13:00:00Z", field: "status",
                                           oldValue: "", newValue: "billed", source: "user")])
        guard case .text(let when) = section.auditCard.rows.first?.cells["when"] else {
            return XCTFail("history cells are text")
        }
        XCTAssertEqual(when, "Sep 21, 1:00 PM")
    }

    // MARK: - Buttons

    func testRemoveIsOnlyLiveForAnUnlockedBillable() {
        section.show([entry("open"), entry("paid", day: "2026-09-20", status: .paid)])
        selectRow("open")
        XCTAssertTrue(section.billablesCard.removeButton.isEnabled)
        selectRow("paid")
        XCTAssertFalse(section.billablesCard.removeButton.isEnabled)
    }

    func testStatusButtonsFollowTheSelection() {
        section.show([entry("u"), entry("b", day: "2026-09-20", status: .billed)])
        XCTAssertFalse(section.markBilledButton.isEnabled, "nothing selected")

        selectRow("u")
        XCTAssertTrue(section.markBilledButton.isEnabled)
        XCTAssertFalse(section.markPaidButton.isEnabled)
        XCTAssertFalse(section.markUnbilledButton.isEnabled)

        selectRow("b")
        XCTAssertFalse(section.markBilledButton.isEnabled)
        XCTAssertTrue(section.markPaidButton.isEnabled)
        XCTAssertTrue(section.markUnbilledButton.isEnabled)

        section.markPaidButton.performClick(nil)
        XCTAssertEqual(statuses.map(\.0), ["b"])
        XCTAssertEqual(statuses.map(\.1), [.paid])
    }

    func testHistoryRowsReadAsSentences() {
        section.showAudit([
            BillingAuditDTO(entryId: "e", at: "2026-09-21T12:00:00Z", field: "status",
                            oldValue: "unbilled", newValue: "billed", source: "user"),
            BillingAuditDTO(entryId: "e", at: "2026-09-21T13:00:00Z", field: "billed_seconds",
                            oldValue: "", newValue: "3600", source: "auto")
        ])
        let rows = section.auditCard.rows
        XCTAssertEqual(rows.count, 2)
        guard case .text(let when) = rows[0].cells["when"], case .text(let doneBy) = rows[0].cells["by"] else {
            return XCTFail("history cells are text")
        }
        XCTAssertEqual(when, "21 Sep, 13:00", "newest first, in the locale's order")
        XCTAssertEqual(doneBy, "Tracking")
        XCTAssertTrue(section.auditCard.addButton.isHidden, "history is not edited")
    }
}
