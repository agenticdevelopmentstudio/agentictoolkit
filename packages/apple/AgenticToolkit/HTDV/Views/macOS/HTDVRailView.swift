#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AgenticDeveloperToolkitUI
import AppKit

/// One column: header (title + "+"), a single-column table of items, and loading/error/empty overlays.
public final class HTDVRailView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    public let levelIndex: Int
    public var onSelect: (String) -> Void = { _ in }
    public var onCreate: () -> Void = {}

    let titleLabel = ThemedLabel(role: .primaryText, textRole: .heading)
    let createButton = NSButton(title: "", target: nil, action: nil)
    // `windowBackground` rather than the default `surface`: a rail *is* the
    // window's plane here, sitting flush in a split view rather than floating
    // on it, so a surface fill would draw a panel edge that is not there.
    let tableView = ThemedTableView(role: .windowBackground)
    let scrollView = ThemedScrollView()
    let emptyLabel = NSTextField(wrappingLabelWithString: "")
    let errorView = HTDVErrorView(frame: .zero)
    let loadingView = HTDVLoadingView(frame: .zero)

    private var items: [HTDVItem] = []
    private var isApplyingSelection = false

    public var rowCount: Int { items.count }
    public var title: String { titleLabel.stringValue }

    public init(levelIndex: Int) {
        self.levelIndex = levelIndex
        super.init(frame: .zero)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private func build() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        // The rail's own backdrop. Without it the split view shows through
        // between the table and the header, in whatever colour AppKit last
        // painted there — the seam that made a themed window look half-themed.
        observeTheme { rail, palette in
            rail.layer?.backgroundColor = palette.windowBackgroundColor.cgColor
        }
        titleLabel.lineBreakMode = .byTruncatingTail
        createButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add")
        createButton.bezelStyle = .accessoryBarAction
        createButton.isBordered = false
        createButton.target = self
        createButton.action = #selector(createTapped)
        createButton.isHidden = true
        createButton.setAccessibilityIdentifier("htdv.rail.\(levelIndex).create")
        createButton.observeTheme { button, palette in
            button.contentTintColor = palette.accentColor
        }
        let header = NSStackView(views: [titleLabel, NSView(), createButton])
        header.orientation = .horizontal
        header.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 4, right: 6)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.usesAutomaticRowHeights = true
        tableView.style = .sourceList
        tableView.selectionHighlightStyle = .regular
        tableView.allowsEmptySelection = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.setAccessibilityIdentifier("htdv.rail.\(levelIndex)")
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        emptyLabel.alignment = .center
        // A wrapping label, which `ThemedLabel` deliberately is not.
        emptyLabel.observeTheme { label, palette in
            label.textColor = palette.secondaryTextColor
            label.font = palette.font(.body)
        }
        emptyLabel.isHidden = true
        emptyLabel.setAccessibilityIdentifier("htdv.rail.\(levelIndex).empty")
        errorView.isHidden = true
        loadingView.isHidden = true

        let content = NSView()
        for sub in [scrollView, emptyLabel, errorView, loadingView] {
            sub.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(sub)
        }
        let stack = NSStackView(views: [header, content])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            content.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: content.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 12),
            errorView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            errorView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            errorView.topAnchor.constraint(equalTo: content.topAnchor),
            errorView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            loadingView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            loadingView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            loadingView.topAnchor.constraint(equalTo: content.topAnchor),
            loadingView.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
    }

    // MARK: State

    public func apply(level: HTDVLevel, selectedID: String?) {
        titleLabel.stringValue = level.title
        createButton.isHidden = level.createAction == nil
        createButton.toolTip = level.createAction?.title
        items = level.items
        errorView.isHidden = true
        loadingView.isHidden = true
        emptyLabel.stringValue = level.emptyMessage
        emptyLabel.isHidden = !items.isEmpty
        scrollView.isHidden = false
        tableView.reloadData()
        isApplyingSelection = true
        if let selectedID, let row = items.firstIndex(where: { $0.id == selectedID }) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        } else {
            tableView.deselectAll(nil)
        }
        isApplyingSelection = false
    }

    public func showLoading() {
        loadingView.isHidden = false
        errorView.isHidden = true
        emptyLabel.isHidden = true
        scrollView.isHidden = true
    }

    public func showError(_ message: String, retry: @escaping () -> Void) {
        errorView.messageLabel.stringValue = message
        errorView.onRetry = retry
        errorView.isHidden = false
        loadingView.isHidden = true
        emptyLabel.isHidden = true
        scrollView.isHidden = true
    }

    @objc private func createTapped() { onCreate() }

    // MARK: NSTableViewDataSource / Delegate

    public func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = (
            tableView.makeView(withIdentifier: HTDVRailCellView.identifier, owner: nil) as? HTDVRailCellView
        ) ?? HTDVRailCellView(frame: .zero)
        cell.apply(HTDVCellContent(item: items[row]))
        // Reassigned on every reuse, not just creation: `items[row].id` can differ from whatever this
        // recycled cell was last showing.
        cell.setAccessibilityIdentifier("htdv.rail.\(levelIndex).row.\(items[row].id)")
        return cell
    }

    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        // `ThemedTableRowView` so a selected row is filled with the theme's
        // selection colour instead of the system's accent — the one piece of a
        // list the palette most obviously owns.
        let rowView = ThemedTableRowView(frame: .zero)
        rowView.isGroupRowStyle = false
        return rowView
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isApplyingSelection else { return }
        let row = tableView.selectedRow
        guard row >= 0, row < items.count else { return }
        onSelect(items[row].id)
    }
}
#endif
