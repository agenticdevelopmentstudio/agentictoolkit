import AppKit

import AgenticToolkitCore
import AgenticToolkitCoreMacOS

/// A record a ``ComposableSettings/RecordDetailWindowController`` can list.
///
/// `id` is the record's own identity — a database id, not a row number — because
/// the sidebar is rebuilt on every push from the model and a position means
/// something different each time.
///
/// Not `@MainActor`: the records are `Sendable` values that may arrive from
/// another process or a background queue, and isolating the protocol would
/// isolate them.
public protocol RecordDetailItem: Identifiable where ID == String {
    /// What the sidebar row reads.
    var recordTitle: String { get }
}

extension ComposableSettings {

    /// A settings window whose sidebar is a list of records rather than a list
    /// of destinations: searchable, with a `+`/`−` under it, and a detail pane
    /// of ordinary settings cards for the selected row.
    ///
    /// Everything about the window — chrome, sidebar, search, help drawer,
    /// navigation arrows — is `SettingsWindow`'s. What is added here is that
    /// the panels come and go with a model.
    @MainActor
    open class RecordDetailWindowController<Record: RecordDetailItem>: SettingsWindow {

        // MARK: Callbacks

        /// `+` was clicked. The owner creates the record and calls `setRecords`.
        public var onAddRecord: (() -> Void)?
        /// `−` was clicked on a record `canRemoveRecord` allows.
        public var onRemoveRecord: ((Record) -> Void)?
        /// The selected record changed; nil when the list is empty.
        public var onSelectRecord: ((Record?) -> Void)?

        /// Asked whether the selected record may be removed. `−` is disabled
        /// when it answers false, and a remove is refused even if the button
        /// is bypassed. Nil allows every record. A built-in row — a catch-all
        /// bucket rather than a record anyone made — answers false.
        public var canRemoveRecord: ((Record) -> Bool)? {
            didSet { updateRemoveButton() }
        }

        // MARK: State

        /// The records in the sidebar, in the owner's order.
        public private(set) var records: [Record] = []

        /// The id of the record whose pane is on screen.
        public private(set) var selectedRecordID: String?

        /// The record whose pane is on screen.
        public var selectedRecord: Record? {
            selectedRecordID.flatMap { id in records.first { $0.id == id } }
        }

        /// Shown beside the `+`/`−` while the list is empty — a window with one
        /// live button and no other mark on it does not say what to do with it.
        public var emptyMessage: String? {
            didSet { emptyLabel.stringValue = emptyMessage ?? "" }
        }

        /// The `+`/`−` bar under the sidebar.
        public let footer: AddRemoveFooterView

        private let makeDetailPanel: (Record) -> any ComposableSettingsPanel
        private let updateDetailPanel: (any ComposableSettingsPanel, Record) -> Void
        private let emptyLabel = ThemedLabel(role: .secondaryText, textRole: .caption)
        private var panelsByRecordID: [String: any ComposableSettingsPanel] = [:]
        private var recordIDsByPanel: [ObjectIdentifier: String] = [:]

        /// - Parameters:
        ///   - makeDetailPanel: builds the pane for a record seen for the first
        ///     time. Called once per record, not once per update.
        ///   - updateDetailPanel: hands a pane its record's current values. Runs
        ///     for every record on every `setRecords`, new or not.
        public init(
            windowID: String,
            title: String,
            accessibilityPrefix: String,
            makeDetailPanel: @escaping (Record) -> any ComposableSettingsPanel,
            updateDetailPanel: @escaping (any ComposableSettingsPanel, Record) -> Void
        ) {
            self.footer = AddRemoveFooterView(accessibilityPrefix: accessibilityPrefix)
            self.makeDetailPanel = makeDetailPanel
            self.updateDetailPanel = updateDetailPanel
            super.init(windowID: windowID)
            self.windowTitle = title

            footer.trailingView = emptyLabel
            footer.onAdd = { [weak self] in self?.onAddRecord?() }
            footer.onRemove = { [weak self] in
                guard let self, let record = self.selectedRecord,
                      self.canRemoveRecord?(record) ?? true else { return }
                self.onRemoveRecord?(record)
            }
            viewController?.listViewController.setFooterView(footer)
            // The model's order, not the window's. These rows are renameable,
            // and an alphabetical sidebar moves the row out from under the
            // cursor mid-edit; the owner sorts once, where it can also decide
            // that "Unassigned" belongs at the bottom.
            viewController?.sortsPanelsByTitle = false
        }

        // MARK: - Content

        /// Replaces the list, keeping each surviving record's pane and the
        /// selection.
        public func setRecords(_ records: [Record]) {
            let previousIndex = selectedRecordID.flatMap { id in
                self.records.firstIndex { $0.id == id }
            }
            self.records = records

            var panels: [any ComposableSettingsPanel] = []
            var surviving: [String: any ComposableSettingsPanel] = [:]
            recordIDsByPanel.removeAll(keepingCapacity: true)
            for record in records {
                let panel = panelsByRecordID[record.id] ?? makeDetailPanel(record)
                updateDetailPanel(panel, record)
                surviving[record.id] = panel
                recordIDsByPanel[ObjectIdentifier(panel as AnyObject)] = record.id
                panels.append(panel)
            }
            // Dropped panels go here, not in a `removePanel` loop: `setPanels`
            // is one rebuild, and the split restores the selection by panel
            // identity across it — which is why reusing the objects is what
            // keeps the selected row selected.
            panelsByRecordID = surviving
            viewController?.setPanels(panels)

            emptyLabel.isHidden = !records.isEmpty
            restoreSelection(previousIndex: previousIndex)
        }

        /// Selects a record by id. A id no longer in the list is ignored, which
        /// is what lets a caller re-select after a save without checking first.
        public func selectRecord(id: String) {
            guard let index = records.firstIndex(where: { $0.id == id }) else { return }
            viewController?.selectPanel(at: index)
            // Not left to `onNavigationChange`: that closure is wired by
            // `installToolbar(on:)`, which only runs once the window has
            // actually been loaded. A caller selecting a record before the
            // window is ever shown — or a test that never shows it — would
            // otherwise see `selectedRecord` and the footer's remove button
            // silently stay on the previous selection.
            syncSelection()
        }

        private func restoreSelection(previousIndex: Int?) {
            guard !records.isEmpty else {
                syncSelection()
                return
            }
            // The split has already restored the selection if the selected
            // panel survived. It did not if the record was just deleted — so
            // take its place in the list, or the last row if it was the last.
            if viewController?.selectedPanel == nil {
                let target = min(previousIndex ?? 0, records.count - 1)
                viewController?.selectPanel(at: target)
            }
            syncSelection()
        }

        // MARK: - Selection

        open override func navigationDidChange() {
            super.navigationDidChange()
            syncSelection()
        }

        private func syncSelection() {
            let current = viewController?.selectedPanel
                .flatMap { recordIDsByPanel[ObjectIdentifier($0 as AnyObject)] }
            let changed = current != selectedRecordID
            selectedRecordID = current
            // A reload can change whether the same record may be removed, so
            // the button is re-asked every time, not only when the selection moves.
            updateRemoveButton()
            // Every rebuild ends in a navigation notification, so without this
            // guard a window that reloads on a timer tick would re-announce its
            // selection once a second and the detail pane would reload under
            // the reader.
            guard changed else { return }
            onSelectRecord?(selectedRecord)
        }

        private func updateRemoveButton() {
            footer.isRemoveEnabled = selectedRecord.map { canRemoveRecord?($0) ?? true } ?? false
        }
    }
}
