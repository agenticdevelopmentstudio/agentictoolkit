import AppKit

import AgenticToolkitCore
import AgenticToolkitCoreMacOS

/// A record a ``ComposableSettings/RecordDetailWindowController`` can list.
///
/// `id` is the record's own identity — a database id, not a row number — because
/// the sidebar is rebuilt on every push from the daemon and a position means
/// something different each time.
///
/// Not `@MainActor`: the records are `Sendable` DTOs that arrive from the
/// daemon, and isolating the protocol would isolate them.
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

        public var onAddRecord: (() -> Void)?
        public var onRemoveRecord: ((Record) -> Void)?
        public var onSelectRecord: ((Record?) -> Void)?

        // MARK: State

        public private(set) var records: [Record] = []

        public private(set) var selectedRecordID: String?

        public var selectedRecord: Record? {
            selectedRecordID.flatMap { id in records.first { $0.id == id } }
        }

        /// Shown beside the `+`/`−` while the list is empty — a window with one
        /// live button and no other mark on it does not say what to do with it.
        public var emptyMessage: String? {
            didSet { emptyLabel.stringValue = emptyMessage ?? "" }
        }

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
                guard let self, let record = self.selectedRecord else { return }
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
            footer.isRemoveEnabled = current != nil
            // Every rebuild ends in a navigation notification, so without this
            // guard a window that reloads on a timer tick would re-announce its
            // selection once a second and the detail pane would reload under
            // the reader.
            guard current != selectedRecordID else { return }
            selectedRecordID = current
            onSelectRecord?(selectedRecord)
        }
    }
}
