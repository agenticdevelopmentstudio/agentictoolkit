import AppKit

/// A small filterable list of one directory's immediate contents, shown as
/// the content of the popover a `BreadcrumbView` crumb opens.
///
/// Not a fourth picker framework: it reuses `PickerKeyboardController` for
/// the up/down/return/escape wiring and `ProjectFilter.ranges(of:in:)` to bold
/// the matched characters — the same two pieces the provider and model
/// pickers already share. Choosing a directory row does nothing; only files
/// can be opened from here.
@MainActor
public final class BreadcrumbPopoverViewController: NSViewController {

    private let directoryURL: URL
    private let onSelect: (URL) -> Void

    /// Escape — the owning popover closes itself. Set by `BreadcrumbView`
    /// after construction, since only it holds the `NSPopover`.
    public var onCancel: (() -> Void)?

    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let keyboard = PickerKeyboardController()

    private let entries: [FileTreeNode]
    private var filtered: [FileTreeNode]

    private static let columnID = NSUserInterfaceItemIdentifier("breadcrumb.entry")

    public init(directoryURL: URL, onSelect: @escaping (URL) -> Void) {
        self.directoryURL = directoryURL
        self.onSelect = onSelect
        let children = FileTreeNode.loadChildren(for: directoryURL)
        self.entries = children
        self.filtered = children
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - View tree

    public override func loadView() {
        // A plain `NSView()` keeps `translatesAutoresizingMaskIntoConstraints`
        // true and its initial frame is `.zero`, which installs an implicit
        // 0×0 size constraint that fights the popover's own `contentSize` —
        // every subview collapses to its compression-resistance minimum (the
        // search field to a couple of points wide) instead of filling the
        // 280×320 the popover asks for. Turning it off lets the popover's
        // frame — not a leftover zero frame — govern this view's size.
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        searchField.placeholderString = "Filter"
        searchField.delegate = self
        searchField.sendsWholeSearchString = false
        searchField.sendsSearchStringImmediately = true
        searchField.accessibilityID("breadcrumb.popover.filter")

        tableView.headerView = nil
        tableView.rowHeight = 20
        tableView.allowsEmptySelection = false
        tableView.allowsMultipleSelection = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(chooseAction)
        tableView.accessibilityID("breadcrumb.popover.table")

        let column = NSTableColumn(identifier: Self.columnID)
        column.width = 248
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        for subview in [searchField, scrollView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8)
        ])

        self.view = root
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        tableView.reloadData()
        selectRow(0)
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(searchField)
        keyboard.onMoveSelection = { [weak self] delta in self?.moveSelection(by: delta) }
        keyboard.onChoose = { [weak self] in self?.chooseAction() }
        keyboard.onCancel = { [weak self] in self?.onCancel?() }
        keyboard.startEscapeMonitor(for: view.window)
    }

    public override func viewWillDisappear() {
        super.viewWillDisappear()
        keyboard.stopEscapeMonitor()
    }

    // MARK: - Selection & filtering

    private func selectRow(_ index: Int) {
        guard !filtered.isEmpty else { return }
        let clamped = max(0, min(filtered.count - 1, index))
        tableView.selectRowIndexes([clamped], byExtendingSelection: false)
        tableView.scrollRowToVisible(clamped)
    }

    private func moveSelection(by delta: Int) {
        guard !filtered.isEmpty else { return }
        let current = tableView.selectedRow < 0 ? 0 : tableView.selectedRow
        selectRow(current + delta)
    }

    private func applyFilter() {
        let query = searchField.stringValue
        filtered = query.isEmpty
            ? entries
            : entries.filter { !ProjectFilter.ranges(of: query, in: $0.name).isEmpty }
        tableView.reloadData()
        selectRow(0)
    }

    @objc private func chooseAction() {
        let row = tableView.selectedRow
        guard row >= 0, row < filtered.count else { return }
        let node = filtered[row]
        guard !node.isDirectory else { return }
        onSelect(node.url)
    }

    private func attributedTitle(for node: FileTreeNode) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let attributed = NSMutableAttributedString(string: node.name, attributes: [.font: font])
        let boldFont = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        for range in ProjectFilter.ranges(of: searchField.stringValue, in: node.name) {
            attributed.addAttribute(.font, value: boldFont, range: range)
        }
        return attributed
    }
}

// MARK: - Table data source / delegate

extension BreadcrumbPopoverViewController: NSTableViewDataSource, NSTableViewDelegate {

    public func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < filtered.count else { return nil }
        let node = filtered[row]
        let identifier = Self.columnID
        let cellView = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView ?? {
            let view = NSTableCellView()
            view.identifier = identifier
            let field = NSTextField(labelWithString: "")
            field.translatesAutoresizingMaskIntoConstraints = false
            field.lineBreakMode = .byTruncatingMiddle
            view.addSubview(field)
            view.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
                field.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
                field.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
            return view
        }()
        cellView.textField?.attributedStringValue = attributedTitle(for: node)
        return cellView
    }
}

// MARK: - Search field delegate (keyboard)

extension BreadcrumbPopoverViewController: NSSearchFieldDelegate {

    public func controlTextDidChange(_ obj: Notification) {
        applyFilter()
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        keyboard.handle(commandSelector)
    }
}
