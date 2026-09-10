import AgenticToolkitCore
import AgenticToolkitCoreUI
import AppKit

/// A two-column, in-place editable table of git global configuration. It
/// owns no git knowledge: the panel feeds it entries and receives edits
/// through `onSet` / `onUnset`.
@MainActor
public final class GitGlobalConfigTableView: NSView {
    public var onSet: ((_ key: String, _ value: String) -> Void)?
    public var onUnset: ((_ key: String) -> Void)?
    public private(set) var entries: [GitConfigEntry] = []

    /// The row `beginAddingEntry` appended, if its edit has not committed yet.
    /// A placeholder is held back until both halves are non-empty (see
    /// `commitEdit`); every other row is a live entry, where the same guard
    /// would wrongly block a legitimate clear.
    private var placeholderRow: Int?

    let tableView = ThemedTableView()
    let errorLabel = ThemedLabel(role: .secondaryText, textRole: .caption)

    private let scrollView = ThemedScrollView()
    private let addButton = NSButton(
        title: "", image: NSImage(systemSymbolName: "plus", accessibilityDescription: "Add")!,
        target: nil, action: nil)
    let removeButton = NSButton(
        title: "", image: NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove")!,
        target: nil, action: nil)

    private static let keyColumn = NSUserInterfaceItemIdentifier("key")
    private static let valueColumn = NSUserInterfaceItemIdentifier("value")
    private static let cellIdentifier = NSUserInterfaceItemIdentifier("config-cell")

    public init() {
        super.init(frame: .zero)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    public var selectedKey: String? {
        let row = tableView.selectedRow
        guard row >= 0, row < entries.count else { return nil }
        return entries[row].key
    }

    public func setEntries(_ entries: [GitConfigEntry]) {
        self.entries = entries
        placeholderRow = nil
        tableView.reloadData()
        updateButtons()
    }

    public func showError(_ message: String) {
        errorLabel.stringValue = message
        errorLabel.isHidden = message.isEmpty
    }

    public func beginAddingEntry() {
        entries.append(GitConfigEntry(key: "", value: ""))
        let row = entries.count - 1
        placeholderRow = row
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.editColumn(0, row: row, with: nil, select: true)
    }

    public func removeSelectedEntry() {
        guard let key = selectedKey else { return }
        if key.isEmpty {
            entries.removeAll { $0.key.isEmpty }
            placeholderRow = nil
            tableView.reloadData()
            updateButtons()
            return
        }
        onUnset?(key)
    }

    /// Applies one edited cell.
    ///
    /// The row `beginAddingEntry` appended (`placeholderRow`) is held back
    /// until both halves are non-empty: committing it early with an empty
    /// value would write a junk key into the user's real git config the
    /// moment they tab off the key cell. Once it fully commits it stops
    /// being the placeholder.
    ///
    /// Every other row is a live entry. Renaming its key must unset the old
    /// key before setting the new one, or the old key survives in git config
    /// after vanishing from the table. Blanking its key is not a delete --
    /// the cell reverts to the stored key rather than committing an empty
    /// one. Clearing its *value* to empty, in contrast, is a legitimate
    /// clear and still fires `onSet`.
    func commitEdit(row: Int, key: String, value: String) {
        guard row >= 0, row < entries.count else { return }

        if row == placeholderRow {
            entries[row] = GitConfigEntry(key: key, value: value)
            guard !key.isEmpty, !value.isEmpty else { return }
            placeholderRow = nil
            onSet?(key, value)
            return
        }

        let oldKey = entries[row].key
        guard !key.isEmpty else {
            let keyColumn = tableView.column(withIdentifier: Self.keyColumn)
            tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: keyColumn))
            return
        }

        entries[row] = GitConfigEntry(key: key, value: value)
        if key != oldKey {
            onUnset?(oldKey)
        }
        onSet?(key, value)
    }

    private func setUp() {
        translatesAutoresizingMaskIntoConstraints = false

        let columns: [(NSUserInterfaceItemIdentifier, String, CGFloat)] = [
            (Self.keyColumn, "Key", 220),
            (Self.valueColumn, "Value", 320)
        ]
        for (identifier, title, width) in columns {
            let column = NSTableColumn(identifier: identifier)
            column.title = title
            column.width = width
            tableView.addTableColumn(column)
        }
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = false
        tableView.accessibilityID("settings.git.config-table")
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        addButton.bezelStyle = .smallSquare
        addButton.target = self
        addButton.action = #selector(addPressed)
        addButton.accessibilityID("settings.git.add-config")
        removeButton.bezelStyle = .smallSquare
        removeButton.target = self
        removeButton.action = #selector(removePressed)
        removeButton.accessibilityID("settings.git.remove-config")

        errorLabel.isHidden = true
        errorLabel.accessibilityID("settings.git.config-error")

        let buttons = NSStackView(views: [addButton, removeButton])
        buttons.orientation = .horizontal
        buttons.spacing = 4
        let footer = NSStackView(views: [buttons, errorLabel])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 12
        let stack = NSStackView(views: [scrollView, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 220)
        ])
        updateButtons()
    }

    private func updateButtons() {
        removeButton.isEnabled = selectedKey != nil
    }

    @objc private func addPressed() { beginAddingEntry() }
    @objc private func removePressed() { removeSelectedEntry() }
}

extension GitGlobalConfigTableView: NSTableViewDataSource {
    public func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
}

extension GitGlobalConfigTableView: NSTableViewDelegate {
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn else { return nil }
        let field: NSTextField
        if let reused = tableView.makeView(withIdentifier: Self.cellIdentifier, owner: self) as? NSTextField {
            field = reused
        } else {
            field = NSTextField(string: "")
            field.identifier = Self.cellIdentifier
            field.isBordered = false
            field.drawsBackground = false
            field.isEditable = true
            field.lineBreakMode = .byTruncatingTail
            field.delegate = self
        }
        let entry = entries[row]
        field.stringValue = tableColumn.identifier == Self.keyColumn ? entry.key : entry.value
        field.tag = row
        field.placeholderString = tableColumn.identifier == Self.keyColumn ? "section.key" : "value"
        return field
    }

    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ThemedTableRowView(frame: .zero)
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtons()
    }
}

extension GitGlobalConfigTableView: NSTextFieldDelegate {
    public func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        let row = field.tag
        guard row >= 0, row < entries.count else { return }
        // A `setEntries` refresh landing mid-edit can detach the field's row
        // view before this notification arrives; `column(for:)` then answers
        // -1, which must not fall through to the value branch below.
        let column = tableView.column(for: field)
        guard column >= 0 else { return }
        let isKey = column == tableView.column(withIdentifier: Self.keyColumn)
        let key = isKey ? field.stringValue : entries[row].key
        let value = isKey ? entries[row].value : field.stringValue
        // A config key cannot carry surrounding whitespace, so it is trimmed;
        // a value legitimately can, so trimming it would corrupt what the
        // user typed.
        commitEdit(row: row, key: key.trimmingCharacters(in: .whitespaces), value: value)
    }
}
