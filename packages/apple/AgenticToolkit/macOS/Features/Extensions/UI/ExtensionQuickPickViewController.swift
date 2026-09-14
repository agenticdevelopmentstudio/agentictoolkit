//
//  ExtensionQuickPickViewController.swift
//  AgenticToolkit
//

import AppKit
import AgenticDeveloperToolkitUI

/// The quick pick's one screen: a search field filtering a list of checkable
/// or single-select rows.
///
/// Modelled on `CommandPaletteViewController`
/// (`macOS/Features/CommandPalette/CommandPaletteViewController.swift`): an
/// `NSSearchField` over an `NSTableView`, with `PickerKeyboardController`
/// routing the arrow keys, Return and Escape out of the focused field and
/// into a list that never takes focus. The one shape the palette does not
/// have is multi-select, which this adds as a column of checkboxes rather
/// than table selection — see `handleRowClick(_:)` below, and
/// `keyboard.onChoose` (`PickerKeyboardController`'s own callback, not a
/// member of this type) for the Return path.
@MainActor
final class ExtensionQuickPickViewController: NSViewController {

    // MARK: - Callbacks

    /// Return (or a single-select click) answered with these indices into
    /// `model.request.items`.
    var onAccept: ([Int]) -> Void = { _ in }

    /// Escape, or a click outside the panel.
    var onCancel: () -> Void = {}

    /// The highlighted row moved, by arrow key or by a mouse click. Fed from
    /// exactly one place, `syncSelection()`, the same way
    /// `CommandPaletteViewController.syncSelection()` (`:210`) is the single
    /// place that updates the table's own selection.
    var onHighlight: (Int) -> Void = { _ in }

    // MARK: - State

    private let model: ExtensionQuickPickModel

    // MARK: - Views

    private var titleLabel: ThemedLabel?
    private let searchField = NSSearchField()
    private let tableView = ThemedTableView()
    private let tableScroll = NSScrollView()

    /// Shared with four other users of `PickerKeyboardController`
    /// (`ModelChooserViewController`, `ProviderPickerViewController`,
    /// `CommandPaletteViewController`, `ExtensionInputBoxViewController` —
    /// `grep -rln "PickerKeyboardController(" macOS/`, five hits including
    /// this file) rather than reimplemented — see that type's own doc
    /// comment (`dry`).
    private let keyboard = PickerKeyboardController()

    private static let itemColumnID = NSUserInterfaceItemIdentifier("extensionQuickPick.item")
    private static let itemCellID = NSUserInterfaceItemIdentifier("extensionQuickPick.itemCell")
    private static let separatorCellID = NSUserInterfaceItemIdentifier("extensionQuickPick.separatorCell")

    // MARK: - Lifecycle

    init(model: ExtensionQuickPickModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        // The brief's fixed 560×400 list size (task-5.5b-iv-brief.md:326).
        // Set in `init`, not `loadView`, so it is already in place the first
        // time `ExtensionPickerWindowController` reads
        // `preferredContentSize` — see that type's own doc comment (F1).
        preferredContentSize = NSSize(width: 560, height: 400)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        configureSearchField()
        configureTable()

        let root = NSView()
        root.wantsLayer = true

        var subviews: [NSView] = []
        var label: ThemedLabel?
        if let requestTitle = model.request.title, !requestTitle.isEmpty {
            let title = ThemedLabel(string: requestTitle, role: .primaryText, textRole: .heading)
            label = title
            subviews.append(title)
        }
        titleLabel = label
        subviews.append(contentsOf: [searchField, tableScroll])

        for subview in subviews {
            subview.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(subview)
        }

        var constraints: [NSLayoutConstraint] = []
        let topAnchorView: NSView
        if let label {
            constraints.append(contentsOf: [
                label.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
                label.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
                label.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12)
            ])
            topAnchorView = label
        } else {
            topAnchorView = root
        }

        constraints.append(contentsOf: [
            searchField.topAnchor.constraint(
                equalTo: label == nil ? topAnchorView.topAnchor : topAnchorView.bottomAnchor,
                constant: 12
            ),
            searchField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),

            tableScroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            tableScroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            tableScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            tableScroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12)
        ])
        NSLayoutConstraint.activate(constraints)
        self.view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        keyboard.onMoveSelection = { [weak self] delta in self?.moveSelection(by: delta) }
        keyboard.onChoose = { [weak self] in self?.choose() }
        keyboard.onCancel = { [weak self] in self?.onCancel() }
        syncSelection()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        keyboard.startEscapeMonitor(for: view.window)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        keyboard.stopEscapeMonitor()
    }

    // MARK: - Public API

    /// Give the search field the keyboard. The field keeps first responder
    /// for the panel's whole life — the table is a display surface, exactly
    /// as in `CommandPaletteViewController`.
    func focusSearchField() {
        view.window?.makeFirstResponder(searchField)
    }

    // MARK: - Configuration

    private func configureSearchField() {
        searchField.placeholderString = model.request.placeHolder ?? ""
        searchField.accessibilityID("extension-quick-pick.search-field")
        searchField.delegate = self
        searchField.sendsWholeSearchString = false
        searchField.sendsSearchStringImmediately = true
    }

    private func configureTable() {
        tableView.accessibilityID("extension-quick-pick.table")
        tableView.headerView = nil
        tableView.rowHeight = 24
        tableView.allowsEmptySelection = true
        // Stays false even when `canPickMany` is true: multi-select here is a
        // set of checkboxes, not a table selection, so the highlight stays
        // single and means "the row the arrow keys are on" (part 5).
        tableView.allowsMultipleSelection = false
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self
        tableView.refusesFirstResponder = true
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle

        let column = NSTableColumn(identifier: Self.itemColumnID)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        tableScroll.documentView = tableView
        tableScroll.hasVerticalScroller = true
        tableScroll.autohidesScrollers = true
        tableScroll.borderType = .noBorder
        tableScroll.drawsBackground = true
    }

    // MARK: - Actions

    private func moveSelection(by delta: Int) {
        model.moveHighlight(by: delta)
        syncSelection()
    }

    /// Return. A nil answer means nothing is highlighted (an empty
    /// single-select list has nothing to accept) and the panel stays up; a
    /// non-nil answer — including an empty array in multi-select — is a real
    /// answer and is reported.
    private func choose() {
        guard let indices = model.acceptedIndices() else { return }
        onAccept(indices)
    }

    @objc private func rowClicked() {
        handleRowClick(tableView.clickedRow)
    }

    /// The click-handling logic `rowClicked()` forwards to, taking a row
    /// number directly rather than reading `tableView.clickedRow` itself —
    /// the seam a test drives, since `NSTableView.clickedRow` is only ever
    /// set by AppKit during a real mouse event.
    ///
    /// A click on a separator must do nothing: `model.highlightRow(row)` is
    /// already a no-op on a separator row (it leaves `highlightedIndex`
    /// alone), but the single-select branch used to call `choose()`
    /// unconditionally afterwards, which accepted whatever was still
    /// highlighted from before the click — a click on a section heading was
    /// silently accepting the previous item (F3). The guard here, shared by
    /// both branches, is what stops that.
    func handleRowClick(_ row: Int) {
        guard row >= 0,
              model.visibleIndices.indices.contains(row),
              !model.request.items[model.visibleIndices[row]].isSeparator else { return }
        if model.request.canPickMany {
            // A click in multi-select toggles that row's check and accepts
            // nothing — Return is the only accept there, because a list you
            // are ticking several boxes in must not close on the first tick
            // (part 5).
            model.toggleCheck(row: row)
            tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
        } else {
            // Single-select: a click highlights and accepts, the way
            // `CommandPaletteViewController.rowClicked()` (`:174`) does.
            model.highlightRow(row)
            syncSelection()
            choose()
        }
    }

    private func syncSelection() {
        guard let highlightedIndex = model.highlightedIndex,
              let row = model.visibleIndices.firstIndex(of: highlightedIndex),
              row < tableView.numberOfRows else {
            tableView.deselectAll(nil)
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        onHighlight(highlightedIndex)
    }
}

// MARK: - Table contents

extension ExtensionQuickPickViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { model.visibleIndices.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < model.visibleIndices.count else { return nil }
        let itemIndex = model.visibleIndices[row]
        let item = model.request.items[itemIndex]

        if item.isSeparator {
            let cell = tableView.makeView(withIdentifier: Self.separatorCellID, owner: nil) as? SeparatorRowCellView
                ?? SeparatorRowCellView(identifier: Self.separatorCellID)
            cell.configure(with: item)
            return cell
        }

        let cell = tableView.makeView(withIdentifier: Self.itemCellID, owner: nil) as? ItemRowCellView
            ?? ItemRowCellView(identifier: Self.itemCellID)
        cell.configure(
            with: item,
            isChecked: model.checkedIndices.contains(itemIndex),
            showsCheckbox: model.request.canPickMany
        ) { [weak self] in
            guard let self else { return }
            self.model.toggleCheck(row: row)
            self.tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: 0))
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ThemedTableRowView(frame: .zero)
    }

    /// Belt-and-braces: the model already refuses to highlight a separator,
    /// and this stops a mouse click doing what the arrow keys cannot.
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard row >= 0, row < model.visibleIndices.count else { return false }
        return !model.request.items[model.visibleIndices[row]].isSeparator
    }
}

// MARK: - Keyboard

extension ExtensionQuickPickViewController: NSSearchFieldDelegate {

    func controlTextDidChange(_ obj: Notification) {
        model.query = searchField.stringValue
        tableView.reloadData()
        syncSelection()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        keyboard.handle(commandSelector)
    }
}

// MARK: - Separator row

/// A heading row: the separator item's `label` in `tertiaryText`, or a plain
/// divider when the label is empty. Private to this file, the way
/// `CommandRowCellView` is private to `CommandPaletteViewController.swift`
/// (`:282`).
@MainActor
private final class SeparatorRowCellView: NSTableCellView {

    private let label = ThemedLabel(role: .tertiaryText, textRole: .caption)

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        textField = label

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(with item: ExtensionQuickPickItem) {
        label.stringValue = item.label
        label.isHidden = item.label.isEmpty
    }
}

// MARK: - Item row

/// One selectable row: label on the left, `description` trailing it dimmed,
/// `detail` on a second line when non-empty, and — only when `canPickMany` —
/// a leading checkbox whose state follows `model.checkedIndices`.
@MainActor
private final class ItemRowCellView: NSTableCellView {

    private let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let titleLabel = ThemedLabel(role: .primaryText, textRole: .body)
    private let descriptionLabel = ThemedLabel(role: .secondaryText, textRole: .caption)
    private let detailLabel = ThemedLabel(role: .tertiaryText, textRole: .caption)

    private var onToggle: (() -> Void)?
    private var checkboxLeading: NSLayoutConstraint?
    private var titleLeadingToSuperview: NSLayoutConstraint?
    private var titleLeadingToCheckbox: NSLayoutConstraint?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        titleLabel.lineBreakMode = .byTruncatingTail
        descriptionLabel.lineBreakMode = .byTruncatingTail
        detailLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        descriptionLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        descriptionLabel.setContentHuggingPriority(.required, for: .horizontal)

        checkbox.target = self
        checkbox.action = #selector(checkboxToggled)
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        addSubview(checkbox)

        for label in [titleLabel, descriptionLabel, detailLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        textField = titleLabel

        let checkboxLeading = checkbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4)
        self.checkboxLeading = checkboxLeading
        let titleLeadingToSuperview = titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4)
        self.titleLeadingToSuperview = titleLeadingToSuperview
        let titleLeadingToCheckbox = titleLabel.leadingAnchor.constraint(
            equalTo: checkbox.trailingAnchor, constant: 4)
        self.titleLeadingToCheckbox = titleLeadingToCheckbox

        NSLayoutConstraint.activate([
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),

            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            descriptionLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
            descriptionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            descriptionLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),

            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            detailLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -2)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(
        with item: ExtensionQuickPickItem, isChecked: Bool, showsCheckbox: Bool, onToggle: @escaping () -> Void
    ) {
        self.onToggle = onToggle
        checkbox.isHidden = !showsCheckbox
        checkbox.state = isChecked ? .on : .off
        checkboxLeading?.isActive = showsCheckbox
        titleLeadingToCheckbox?.isActive = showsCheckbox
        titleLeadingToSuperview?.isActive = !showsCheckbox

        titleLabel.stringValue = item.label
        descriptionLabel.stringValue = item.description ?? ""
        descriptionLabel.isHidden = (item.description ?? "").isEmpty
        detailLabel.stringValue = item.detail ?? ""
        detailLabel.isHidden = (item.detail ?? "").isEmpty
    }

    @objc private func checkboxToggled() {
        onToggle?()
    }
}
