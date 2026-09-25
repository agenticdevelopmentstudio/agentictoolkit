import AppKit
import Foundation
import Testing
import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// Typed columns: a cell's text is parsed by its column's kind and reported
/// as a value, refused when it isn't one, and not reported at all when it is
/// what the cell already showed. A read-only row refuses every edit.
@Suite(.serialized)
@MainActor
struct EditableTableCardTypedEditTests {

    private typealias Card = ComposableSettings.EditableTableCard
    private typealias Column = ComposableSettings.EditableTableColumn
    private typealias Row = ComposableSettings.EditableTableRow
    private typealias Value = ComposableSettings.EditableTableEditValue

    private static let nine = ISO8601DateFormatter().date(from: "2026-09-21T09:00:00Z")!

    private final class Log {
        var edits: [(String, String, Value)] = []
        var rejected: [(String, String, String)] = []
    }

    private func makeCard(readOnly: Bool = false) -> (Card, Log) {
        let card = Card(
            title: "Billables",
            columns: [
                Column(id: "day", title: "Day", width: 88, kind: .day),
                Column(id: "start", title: "Start", width: 52, kind: .time),
                Column(id: "hours", title: "Hours", width: 56, kind: .duration(range: 1...86_400)),
                Column(id: "rate", title: "Rate", width: 72, kind: .money(range: 0...100_000, allowsBlank: true))
            ],
            emptyMessage: "None.", accessibilityPrefix: "tests.typed")
        card.timeZone = TimeZone(identifier: "UTC")!
        card.locale = Locale(identifier: "en_US")
        card.setRows([Row(id: "e1", cells: [
            "day": .day("2026-09-21"),
            "start": .time(Self.nine, reference: nil),
            "hours": .duration(3_601),
            "rate": .money(12_000, currency: "USD")
        ], isReadOnly: readOnly)])
        let log = Log()
        card.onTypedEdit = { log.edits.append(($0, $1, $2)) }
        card.onRejectedEdit = { log.rejected.append(($0, $1, $2)) }
        return (card, log)
    }

    @Test func eachKindReportsItsValue() {
        let (card, log) = makeCard()
        card.commitEdit(rowID: "e1", columnID: "day", newValue: "2026-09-20")
        card.commitEdit(rowID: "e1", columnID: "start", newValue: "10:30 AM")
        card.commitEdit(rowID: "e1", columnID: "hours", newValue: "2")
        card.commitEdit(rowID: "e1", columnID: "rate", newValue: "150")

        #expect(log.rejected.isEmpty)
        #expect(log.edits.map(\.1) == ["day", "start", "hours", "rate"])
        #expect(log.edits.map(\.2) == [
            .day("2026-09-20"),
            .time(ISO8601DateFormatter().date(from: "2026-09-21T10:30:00Z")!),
            .duration(7_200),
            .money(15_000)
        ])
    }

    @Test func aBlankMoneyCellMeansTheFallback() {
        let (card, log) = makeCard()
        card.commitEdit(rowID: "e1", columnID: "rate", newValue: "")
        #expect(log.edits.map(\.2) == [.money(nil)])
    }

    @Test func textThatIsNotAValueIsRefused() {
        let (card, log) = makeCard()
        card.commitEdit(rowID: "e1", columnID: "day", newValue: "2026-09-31")
        card.commitEdit(rowID: "e1", columnID: "hours", newValue: "lots")
        card.commitEdit(rowID: "e1", columnID: "rate", newValue: "5000")

        #expect(log.edits.isEmpty)
        #expect(log.rejected.map(\.1) == ["day", "hours", "rate"])
    }

    /// 3601 seconds shows as a rounded figure; reading that figure back
    /// would move the value to 3600, so the untouched text is no edit at all.
    @Test func theShownTextUntouchedIsNotAnEdit() {
        let (card, log) = makeCard()
        card.commitEdit(rowID: "e1", columnID: "hours",
                        newValue: DurationFormatter.decimalHours(seconds: 3_601))
        card.commitEdit(rowID: "e1", columnID: "rate",
                        newValue: MoneyFormatter(currency: "USD").editableString(cents: 12_000))
        card.commitEdit(rowID: "e1", columnID: "day", newValue: "2026-09-21")

        #expect(log.edits.isEmpty)
        #expect(log.rejected.isEmpty)
    }

    @Test func aReadOnlyRowRefusesEveryEdit() {
        let (card, log) = makeCard(readOnly: true)
        card.commitEdit(rowID: "e1", columnID: "hours", newValue: "2")

        #expect(log.edits.isEmpty)
        #expect(log.rejected.map(\.0) == ["e1"])
    }
}
