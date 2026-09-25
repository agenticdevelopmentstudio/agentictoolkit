import AppKit
import AgenticToolkitCore

/// A project's billables, their totals, and the history of the selected one:
/// three cards `ProjectDetailPanel` stacks under its repositories.
///
/// It holds entries and reports edits, like the panel it sits in; the daemon
/// is `ProjectsWindowController`'s. The rules it enforces before anything is
/// written are the task's: a locked billable is read-only, typed hours are
/// taken literally, start and end imply hours, and the amount is always
/// hours × rate.
@MainActor
public final class ProjectBillablesSection {

    public static let accessibilityPrefix = "billing.project.billables"

    /// One status's share of a project's billables. Money is kept per
    /// currency — Core's `MoneyTotals` — because adding euros to dollars makes
    /// a figure no one can bill.
    public struct Totals: Equatable {
        public var count = 0
        public var seconds = 0
        public var money = MoneyTotals()

        public init(count: Int = 0, seconds: Int = 0, money: MoneyTotals = MoneyTotals()) {
            self.count = count
            self.seconds = seconds
            self.money = money
        }
    }

    public var onAdd: (() -> Void)?
    public var onSave: ((BillingEntryDTO) -> Void)?
    /// A description edit: the entry's id and the new words, never the row.
    /// The row on screen may be a minute behind a growing entry, and saving it
    /// whole would write those stale figures back and freeze them.
    public var onSaveDescription: ((String, String) -> Void)?
    public var onRemove: ((BillingEntryDTO) -> Void)?
    public var onSetStatus: ((BillingEntryDTO, BillingStatus) -> Void)?
    /// The selected billable's id, or nil, so its history can be loaded.
    public var onSelect: ((String?) -> Void)?
    /// An edit the section would not send, and why, in a sentence.
    public var onRefused: ((String) -> Void)?

    /// Days and times are read and shown in this zone. The user's own,
    /// except in tests.
    public var timeZone: TimeZone = .current {
        didSet { billablesCard.timeZone = timeZone }
    }
    /// Times are shown on this locale's clock, 12- or 24-hour, and typed on
    /// either. The user's own, except in tests.
    public var locale: Locale = .current {
        didSet { billablesCard.locale = locale }
    }

    public let billablesCard: ComposableSettings.EditableTableCard
    public let overviewCard: ComposableSettings.GroupView
    public let auditCard: ComposableSettings.EditableTableCard
    public let unbilledRow = ComposableSettings.ValueRowView(title: "Unbilled", value: "—")
    public let billedRow = ComposableSettings.ValueRowView(title: "Billed", value: "—")
    public let paidRow = ComposableSettings.ValueRowView(title: "Paid", value: "—")

    public private(set) var markBilledButton: NSButton!
    public private(set) var markPaidButton: NSButton!
    public private(set) var markUnbilledButton: NSButton!

    public private(set) var entries: [BillingEntryDTO] = []
    private var sortColumn = "day"
    private var sortAscending = false

    public var cards: [ComposableSettings.GroupView] { [billablesCard, overviewCard, auditCard] }

    public var selectedEntry: BillingEntryDTO? {
        guard let id = billablesCard.selectedRowID else { return nil }
        return entries.first { $0.id == id }
    }

    public init() {
        billablesCard = ComposableSettings.EditableTableCard(
            title: "Billables",
            columns: [
                .init(id: "day", title: "Day", width: 88, kind: .day, isSortable: true),
                .init(id: "start", title: "Start", width: 52, kind: .time),
                .init(id: "end", title: "End", width: 52, kind: .time),
                .init(id: "hours", title: "Hours", width: 56, kind: .duration(range: 1...86_400), isSortable: true),
                .init(id: "rate", title: "Rate", width: 72, kind: .money(range: BillingLimits.defaultRateCents)),
                .init(id: "amount", title: "Amount", width: 88, isSortable: true),
                .init(id: "status", title: "Status", width: 72, isSortable: true),
                .init(id: "description", title: "Description", width: 200, kind: .text(editable: true))
            ],
            emptyMessage: "No billables yet. Tracked time appears here on its own.",
            visibleRows: 8,
            accessibilityPrefix: Self.accessibilityPrefix
        )

        overviewCard = ComposableSettings.GroupView(withTitle: "Totals")
        overviewCard.addSettingSubview(unbilledRow)
        overviewCard.addSettingSubview(billedRow)
        overviewCard.addSettingSubview(paidRow)

        auditCard = ComposableSettings.EditableTableCard(
            title: "History",
            columns: [
                .init(id: "when", title: "When", width: 110),
                .init(id: "field", title: "Changed", width: 110),
                .init(id: "from", title: "From", width: 100),
                .init(id: "to", title: "To", width: 100),
                .init(id: "by", title: "By", width: 72)
            ],
            emptyMessage: "Select a billable to see its changes.",
            visibleRows: 4,
            accessibilityPrefix: "billing.project.history"
        )
        auditCard.showsAddRemove = false

        wire()
    }

    private func wire() {
        billablesCard.onAdd = { [weak self] in self?.onAdd?() }
        billablesCard.onRemove = { [weak self] rowID in
            guard let self, let entry = self.entries.first(where: { $0.id == rowID }), !entry.locked else { return }
            self.onRemove?(entry)
        }
        billablesCard.onEdit = { [weak self] rowID, columnID, text in
            self?.editText(rowID, columnID, text)
        }
        billablesCard.onTypedEdit = { [weak self] rowID, columnID, value in
            self?.edit(rowID, columnID, value)
        }
        billablesCard.onRejectedEdit = { [weak self] rowID, _, _ in
            self?.rejected(rowID)
        }
        billablesCard.onSort = { [weak self] columnID, ascending in
            guard let self else { return }
            self.sortColumn = columnID
            self.sortAscending = ascending
            self.show(self.entries)
        }
        billablesCard.onSelectionChange = { [weak self] rowID in
            guard let self else { return }
            self.updateStatusButtons()
            self.onSelect?(rowID)
        }
        billablesCard.canRemoveRow = { [weak self] rowID in
            self?.entries.first { $0.id == rowID }.map { !$0.locked } ?? false
        }

        let prefix = Self.accessibilityPrefix
        markBilledButton = billablesCard.addFooterButton(
            title: "Mark Billed", identifier: "\(prefix).markBilled"
        ) { [weak self] in self?.setStatus(.billed) }
        markPaidButton = billablesCard.addFooterButton(
            title: "Mark Paid", identifier: "\(prefix).markPaid"
        ) { [weak self] in self?.setStatus(.paid) }
        markUnbilledButton = billablesCard.addFooterButton(
            title: "Mark Unbilled", identifier: "\(prefix).markUnbilled"
        ) { [weak self] in self?.setStatus(.unbilled) }
        updateStatusButtons()
    }

    // MARK: - Model → cards

    public func show(_ entries: [BillingEntryDTO]) {
        self.entries = entries
        billablesCard.setRows(sorted(entries).map(row(for:)))
        let totals = Self.totals(entries)
        unbilledRow.value = Self.describe(totals[.unbilled])
        billedRow.value = Self.describe(totals[.billed])
        paidRow.value = Self.describe(totals[.paid])
        updateStatusButtons()
    }

    public func showAudit(_ audits: [BillingAuditDTO]) {
        auditCard.setRows(audits.sorted { $0.at > $1.at }.enumerated().map { index, audit in
            let when = TimestampParsing.parse(audit.at).map {
                LocalTimeText.dayAndClock($0, timeZone: timeZone, locale: locale)
            }
            return ComposableSettings.EditableTableRow(id: "\(index)", cells: [
                "when": .text(when ?? audit.at),
                "field": .text(audit.field),
                "from": audit.oldValue.isEmpty ? .placeholder("—") : .text(audit.oldValue),
                "to": audit.newValue.isEmpty ? .placeholder("—") : .text(audit.newValue),
                "by": .text(audit.source == "auto" ? "Tracking" : "You")
            ])
        })
    }

    public func select(entryId: String) {
        billablesCard.selectRow(id: entryId)
    }

    private func row(for entry: BillingEntryDTO) -> ComposableSettings.EditableTableRow {
        let money = MoneyFormatter(currency: entry.currency)
        let start = TimestampParsing.parse(entry.startedAt)
        let end = TimestampParsing.parse(entry.endedAt)
        // A time typed into an empty end lands nearest the other end, or the
        // middle of the entry's day, so an End past midnight edits in place.
        let anchor = noon(of: entry.day)
        return ComposableSettings.EditableTableRow(
            id: entry.id,
            cells: [
                "day": .day(entry.day),
                "start": .time(start, reference: end ?? anchor),
                "end": .time(end, reference: start ?? anchor),
                "hours": .duration(entry.billedSeconds),
                "rate": .money(entry.rateCents, currency: entry.currency),
                "amount": .text(money.string(cents: entry.amountCents)),
                "status": .text(Self.statusTitle(entry.status)),
                "description": entry.description.isEmpty
                    ? .placeholder("Add a description") : .text(entry.description)
            ],
            // Time that arrived after its day was billed: a second look before
            // it goes on another invoice.
            isFlagged: entry.supplementsEntryId != nil,
            // Billed and paid time is what the user has sent; it changes only
            // after Mark Unbilled.
            isReadOnly: entry.locked
        )
    }

    /// Newest day first by default. Ties fall back to start then id, so the
    /// order never shuffles between reloads.
    private func sorted(_ entries: [BillingEntryDTO]) -> [BillingEntryDTO] {
        let ascending = sortAscending
        func inOrder<T: Comparable>(_ lhs: T, _ rhs: T) -> Bool? {
            lhs == rhs ? nil : (ascending ? lhs < rhs : lhs > rhs)
        }
        return entries.sorted { lhs, rhs in
            let primary: Bool?
            switch sortColumn {
            case "hours": primary = inOrder(lhs.billedSeconds, rhs.billedSeconds)
            case "amount": primary = inOrder(lhs.amountCents, rhs.amountCents)
            case "status": primary = inOrder(Self.statusRank(lhs.status), Self.statusRank(rhs.status))
            default: primary = inOrder(lhs.day, rhs.day)
            }
            return primary ?? ((lhs.startedAt, lhs.id) > (rhs.startedAt, rhs.id))
        }
    }

    private func updateStatusButtons() {
        let status = selectedEntry.flatMap { BillingStatus(rawValue: $0.status) }
        markBilledButton?.isEnabled = status == .unbilled
        markPaidButton?.isEnabled = status == .billed
        markUnbilledButton?.isEnabled = status == .billed || status == .paid
    }

    // MARK: - Cards → model

    private func setStatus(_ status: BillingStatus) {
        guard let entry = selectedEntry, entry.status != status.rawValue else { return }
        onSetStatus?(entry, status)
    }

    /// The one free-text column. Sent as the id and the words, never the
    /// row: see `onSaveDescription`.
    private func editText(_ rowID: String, _ columnID: String, _ text: String) {
        guard columnID == "description", let entry = entries.first(where: { $0.id == rowID }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != entry.description { onSaveDescription?(entry.id, trimmed) }
    }

    /// A typed value the card has already parsed and range-checked. What
    /// stays here is the billing arithmetic: the amount is always hours ×
    /// rate, and start and end imply hours.
    private func edit(_ rowID: String, _ columnID: String, _ value: ComposableSettings.EditableTableEditValue) {
        guard let entry = entries.first(where: { $0.id == rowID }), !entry.locked else { return }
        let edited: BillingEntryDTO?
        switch (columnID, value) {
        case ("day", .day(let day)):
            // Times belong to their day; moved, they would claim hours on the old one.
            edited = day == entry.day ? entry : entry.replacing(day: day, startedAt: "", endedAt: "")
        case ("start", .time(let date)), ("end", .time(let date)):
            edited = editTime(entry, editsStart: columnID == "start", date)
        case ("hours", .duration(let seconds)):
            edited = entry.repriced(billedSeconds: seconds, rateCents: entry.rateCents)
        case ("rate", .money(let cents?)):
            edited = entry.repriced(billedSeconds: entry.billedSeconds, rateCents: cents)
        default:
            return
        }
        // The cell still shows what was typed; the stored rows put it back.
        guard let edited else { return show(entries) }
        guard edited != entry else { return }
        onSave?(edited)
    }

    /// The card refused an edit. On a locked billable, say why.
    private func rejected(_ rowID: String) {
        guard let entry = entries.first(where: { $0.id == rowID }), entry.locked else { return }
        onRefused?("This billable is \(entry.status), so it can't be changed. Mark it Unbilled to change it.")
    }

    /// A typed Start or End, already placed on the day nearest what the cell
    /// showed (or the other end, or the entry's day), so an End past midnight
    /// and a billable recorded in another zone both edit in place. When both
    /// ends were already set, the billed time moves by what the span moved —
    /// a derived day's idle gaps and rounding are not replaced by the raw
    /// wall-clock span.
    private func editTime(_ entry: BillingEntryDTO, editsStart: Bool, _ date: Date?) -> BillingEntryDTO? {
        let oldStart = TimestampParsing.parse(entry.startedAt)
        let oldEnd = TimestampParsing.parse(entry.endedAt)
        let instant = date.map(UTCTimestamp.string(from:)) ?? ""
        let start = editsStart ? instant : entry.startedAt
        let end = editsStart ? entry.endedAt : instant
        let edited = entry.replacing(startedAt: start, endedAt: end)
        guard let from = TimestampParsing.parse(start), let until = TimestampParsing.parse(end) else { return edited }
        let span = LocalTimeText.seconds(from: from, to: until)
        guard (1...86_400).contains(span) else { return nil }
        var billed = span
        if let oldStart, let oldEnd {
            let moved = entry.billedSeconds + span - LocalTimeText.seconds(from: oldStart, to: oldEnd)
            if moved > 0 { billed = min(moved, span) }
        }
        return edited.repriced(billedSeconds: billed, rateCents: entry.rateCents)
    }

    /// Midday of a `yyyy-MM-dd` day in `timeZone`: the anchor for a time typed
    /// into a billable with neither end set.
    private func noon(of day: String) -> Date? {
        guard let midnight = localFormatter("yyyy-MM-dd").date(from: day) else { return nil }
        return midnight.addingTimeInterval(12 * 3600)
    }

    // MARK: - Arithmetic and formatting

    public static func totals(_ entries: [BillingEntryDTO]) -> [BillingStatus: Totals] {
        var totals: [BillingStatus: Totals] = [:]
        for entry in entries {
            guard let status = BillingStatus(rawValue: entry.status) else { continue }
            totals[status, default: Totals()].count += 1
            totals[status, default: Totals()].seconds += entry.billedSeconds
            totals[status, default: Totals()].money.add(cents: entry.amountCents, currency: entry.currency)
        }
        return totals
    }

    /// `"2 billables · 2.25 h · $250.00"`, currencies in code order joined
    /// with " + ", or "—" for none.
    public static func describe(_ totals: Totals?) -> String {
        guard let totals, totals.count > 0 else { return "—" }
        let noun = totals.count == 1 ? "billable" : "billables"
        let hours = DurationFormatter.decimalHours(seconds: totals.seconds)
        return "\(totals.count) \(noun) · \(hours) h · \(totals.money.description)"
    }

    private func localFormatter(_ pattern: String) -> DateFormatter {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = timeZone
        format.dateFormat = pattern
        format.isLenient = false
        return format
    }

    private static func statusTitle(_ status: String) -> String {
        BillingStatus(rawValue: status).map { $0.rawValue.capitalized } ?? status
    }

    private static func statusRank(_ status: String) -> Int {
        BillingStatus.allCases.firstIndex { $0.rawValue == status } ?? BillingStatus.allCases.count
    }
}
