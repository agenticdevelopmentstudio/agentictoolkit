import AppKit
import OSLog
import AgenticToolkitCore
import AgenticToolkitCoreMacOS
import AgenticDeveloperToolkitUI

/// The palette's one screen: a search field over the list of commands it
/// selects.
///
/// AppKit rather than SwiftUI, and an `NSSearchField` over an `NSTableView`
/// rather than anything custom, because the hard part here is routing the arrow
/// keys out of a focused text field and into a list that never takes focus.
/// `NSSearchFieldDelegate.control(_:textView:doCommandBy:)` is exactly that
/// mechanism, and it is the same one `ModelChooserViewController` and
/// `ProviderPickerViewController` already use (`native-controls`).
///
/// The controller knows nothing about windows: it reports Return and Escape
/// through `onRun` / `onCancel` and lets whoever hosts it decide that those mean
/// "close" (`separation-of-concerns`).
@MainActor
public final class CommandPaletteViewController: NSViewController {

    // MARK: - Callbacks

    /// A command was run. The host dismisses.
    public var onRun: () -> Void = {}

    /// The user asked to leave without running anything.
    public var onCancel: () -> Void = {}

    // MARK: - State

    private let model: CommandPaletteModel

    // MARK: - Views

    private let searchField = NSSearchField()
    private let tableView = ThemedTableView()
    private let tableScroll = NSScrollView()

    /// The up/down/Return/Escape routing, and the window-level Escape monitor an
    /// `NSSearchField` otherwise swallows to clear its own text. Shared with the
    /// two pickers rather than rewritten here — this is the one piece of a
    /// filter-field-driven list that is easy to get subtly wrong (`dry`).
    private let keyboard = PickerKeyboardController()

    private var themeObserver: ThemePaletteObserver?

    private static let commandColumnID = NSUserInterfaceItemIdentifier("commandPalette.command")
    private static let cellID = NSUserInterfaceItemIdentifier("commandPalette.cell")

    // MARK: - Lifecycle

    public init(model: CommandPaletteModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    public override func loadView() {
        configureSearchField()
        configureTable()

        let root = NSView()
        root.wantsLayer = true
        for subview in [searchField, tableScroll] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),

            tableScroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            tableScroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            tableScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            tableScroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12)
        ])
        self.view = root
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        themeObserver = ThemePaletteObserver(host: view) { [weak self] palette in self?.applyTheme(palette) }
        keyboard.onMoveSelection = { [weak self] delta in self?.moveSelection(by: delta) }
        keyboard.onChoose = { [weak self] in self?.runSelection() }
        keyboard.onCancel = { [weak self] in self?.onCancel() }
        syncSelection()
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        keyboard.startEscapeMonitor(for: view.window)
    }

    public override func viewWillDisappear() {
        super.viewWillDisappear()
        keyboard.stopEscapeMonitor()
    }

    // MARK: - Public API

    /// Clear the filter, re-read the registry and rebuild the list. What a host
    /// calls each time it shows the palette, so an opening palette never shows
    /// the last visit's typing or a command set that has moved on since.
    public func reset() {
        searchField.stringValue = ""
        model.query = ""
        model.reload()
        tableView.reloadData()
        syncSelection()
    }

    /// Give the search field the keyboard. The field keeps first responder for
    /// the palette's whole life — the table is a display surface.
    public func focusSearchField() {
        view.window?.makeFirstResponder(searchField)
    }

    // MARK: - Configuration

    private func configureSearchField() {
        searchField.placeholderString = "Type a command"
        searchField.delegate = self
        searchField.sendsWholeSearchString = false
        searchField.sendsSearchStringImmediately = true
    }

    private func configureTable() {
        tableView.headerView = nil
        tableView.rowHeight = 24
        // Empty selection is reachable and real: a query that matches nothing
        // has no row to highlight.
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self
        // The search field never gives up focus, so the table must not compete
        // for it — Tab would otherwise move the caret out of the field the
        // palette is entirely driven from.
        tableView.refusesFirstResponder = true
        // Single click, not double: a palette row behaves like a menu item, and
        // a menu item runs the first time you click it.
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle

        let column = NSTableColumn(identifier: Self.commandColumnID)
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
        if delta > 0 { model.moveSelectionDown() } else { model.moveSelectionUp() }
        syncSelection()
    }

    @objc private func rowClicked() {
        let row = tableView.clickedRow
        guard row >= 0 else { return }
        model.select(index: row)
        syncSelection()
        runSelection()
    }

    private func runSelection() {
        do {
            // A disabled row answers `false` and stays put: the palette is still
            // open, still showing why nothing happened (the row is dimmed).
            guard try model.runSelection() else { return }
        } catch {
            // The selected command was unregistered between the last reload and
            // this Return. Nothing here can fix that, and a palette that closed
            // silently would look like the command had run.
            let reason = String(describing: error)
            Self.logger.error("Command palette failed to run selection: \(reason, privacy: .public)")
            return
        }
        onRun()
    }

    private func syncSelection() {
        guard let index = model.selectedIndex, index < tableView.numberOfRows else {
            tableView.deselectAll(nil)
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        tableView.scrollRowToVisible(index)
    }

    private func applyTheme(_ palette: SemanticPalette) {
        view.layer?.backgroundColor = palette.windowBackgroundColor.cgColor
        // The table paints its own `surface`; only its scroll host needs to be
        // told to match it.
        tableScroll.backgroundColor = palette.surfaceColor
        tableView.reloadData()
    }
}

// MARK: - Table contents

extension CommandPaletteViewController: NSTableViewDataSource, NSTableViewDelegate {

    public func numberOfRows(in tableView: NSTableView) -> Int { model.matches.count }

    /// Title on the left, category dimmed on the right.
    ///
    /// The category trails rather than prefixing the title (VS Code writes
    /// "Terminal: New Terminal Window"): every row here starts at the same x, so
    /// the eye scans one column of titles instead of re-finding where each title
    /// begins behind a category of a different length.
    public func tableView(
        _ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int
    ) -> NSView? {
        guard row >= 0, row < model.matches.count else { return nil }
        let cell = tableView.makeView(withIdentifier: Self.cellID, owner: nil) as? CommandRowCellView
            ?? CommandRowCellView(identifier: Self.cellID)
        cell.configure(with: model.matches[row])
        return cell
    }

    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ThemedTableRowView(frame: .zero)
    }
}

// MARK: - Keyboard

extension CommandPaletteViewController: NSSearchFieldDelegate {

    public func controlTextDidChange(_ obj: Notification) {
        model.query = searchField.stringValue
        tableView.reloadData()
        syncSelection()
    }

    public func control(
        _ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector
    ) -> Bool {
        keyboard.handle(commandSelector)
    }
}

extension CommandPaletteViewController: Loggable {
    public static nonisolated let logger = makeLogger()
}

// MARK: - Row

/// One palette row. Its own type rather than an `NSTableCellView` assembled
/// inline in `viewFor:` because it carries two labels whose roles change with
/// the command's enablement, and that rule is worth stating once.
@MainActor
private final class CommandRowCellView: NSTableCellView {

    private let titleLabel = ThemedLabel(role: .primaryText, textRole: .body)
    private let categoryLabel = ThemedLabel(role: .secondaryText, textRole: .caption)

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        titleLabel.lineBreakMode = .byTruncatingTail
        categoryLabel.lineBreakMode = .byTruncatingTail
        categoryLabel.alignment = .right
        // The title yields first: a long command name truncates before the
        // category it is filed under disappears, because the category is what
        // tells two similarly-named commands apart.
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        categoryLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        categoryLabel.setContentHuggingPriority(.required, for: .horizontal)

        for label in [titleLabel, categoryLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        textField = titleLabel

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            categoryLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
            categoryLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            categoryLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(with command: AppCommand) {
        titleLabel.stringValue = command.title
        categoryLabel.stringValue = command.category
        categoryLabel.isHidden = command.category.isEmpty
        // A command that cannot run right now is dimmed, not hidden — the same
        // answer `NSMenu` gives, and the reason the list does not reshuffle as
        // focus moves around the app. `tertiaryText` is the theme's own role for
        // this; `NSColor.disabledControlTextColor` would be the one colour in
        // the window a theme could not reach.
        let isEnabled = command.isEnabled()
        titleLabel.role = isEnabled ? .primaryText : .tertiaryText
        categoryLabel.role = isEnabled ? .secondaryText : .tertiaryText
    }
}
