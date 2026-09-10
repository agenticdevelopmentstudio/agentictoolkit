import AgenticToolkitCore
import AgenticToolkitCoreUI
import AppKit

/// A two-column, in-place editable table of git global configuration. It
/// owns no git knowledge: the panel feeds it entries and receives edits
/// through `onSet` / `onUnset` / `onRename`.
@MainActor
public final class GitGlobalConfigTableView: NSView {
    public var onSet: ((_ key: String, _ value: String) -> Void)?
    public var onUnset: ((_ key: String) -> Void)?
    /// Fired when a live row's key changes, instead of a separate `onUnset`
    /// followed by `onSet`. Carries both halves' key *and* value so the
    /// panel can restore `oldKey`/`oldValue` if setting `newKey`/`newValue`
    /// fails after the unset half already succeeded -- see `commitEdit`.
    public var onRename: ((_ oldKey: String, _ oldValue: String, _ newKey: String, _ newValue: String) -> Void)?
    public private(set) var entries: [GitConfigEntry] = []

    /// The row `beginAddingEntry` appended, if its edit has not committed yet.
    /// A placeholder is held back until both halves are non-empty (see
    /// `commitEdit`); every other row is a live entry, where the same guard
    /// would wrongly block a legitimate clear.
    private var placeholderRow: Int?

    /// True between `controlTextDidBeginEditing` and `controlTextDidEndEditing`
    /// for any cell in this table. `setEntries` checks it before touching
    /// `entries`: that call assigns `entries` before `tableView.reloadData()`,
    /// so a `controlTextDidEndEditing` landing mid-reload would read the
    /// *new* entries at the field's *old* row index and commit the user's
    /// half-typed text against a setting they never touched.
    private var isEditingField = false

    /// A reload that arrived while `isEditingField` was true, applied once
    /// the in-flight edit finishes.
    private var pendingEntries: [GitConfigEntry]?

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

    /// Replaces the displayed entries and reloads the table -- unless a cell
    /// is currently being edited, in which case the replacement is held back
    /// until that edit commits (see `isEditingField`'s doc comment for why).
    public func setEntries(_ entries: [GitConfigEntry]) {
        guard !isEditingField else {
            pendingEntries = entries
            return
        }
        applyEntries(entries)
    }

    private func applyEntries(_ entries: [GitConfigEntry]) {
        self.entries = entries
        placeholderRow = nil
        tableView.reloadData()
        updateButtons()
    }

    public func showError(_ message: String) {
        errorLabel.stringValue = message
        errorLabel.isHidden = message.isEmpty
    }

    /// Appends a new placeholder row and begins editing its key cell.
    ///
    /// A second call while the previous placeholder has not committed
    /// re-focuses that same row instead of appending another. Two outstanding
    /// placeholders used to demote the first one to an ordinary live row --
    /// `placeholderRow` can only ever point at one row -- whose empty key
    /// then bypassed the "wait for both halves non-empty" guard in
    /// `commitEdit`, so committing it wrote an empty-named key straight to
    /// the user's real git config.
    public func beginAddingEntry() {
        if let existing = placeholderRow {
            tableView.selectRowIndexes(IndexSet(integer: existing), byExtendingSelection: false)
            tableView.editColumn(0, row: existing, with: nil, select: true)
            return
        }
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

    /// A key `git config` will accept: shaped `section.name`, optionally
    /// `section.subsection.name`. A bare word like `email` is rejected by
    /// both `--unset` and a plain set, so it is refused here, before either
    /// ever reaches git -- in particular before the destructive unset half
    /// of a rename fires. This is a cheap, local first line of defense, not
    /// the only one: `onRename`'s contract additionally has the panel
    /// restore the old key/value if the *new* key is well-formed but the
    /// set still fails for some other reason (a locked config file, a
    /// permissions error, and so on) -- see that property's doc comment.
    private static func isWellFormedKey(_ key: String) -> Bool {
        key.contains(".")
    }

    /// Applies one edited cell.
    ///
    /// The row `beginAddingEntry` appended (`placeholderRow`) is held back
    /// until both halves are non-empty and the key is well-formed (see
    /// `commitEdit`); committing it early would write a junk key into the
    /// user's real git config the moment they tab off the key cell. Once it
    /// fully commits it stops being the placeholder.
    ///
    /// Every other row is a live entry. Renaming its key fires `onRename`
    /// (not a separate `onUnset` followed by `onSet`) so the panel can
    /// restore the old key/value in one queued operation if the new key
    /// fails to set. Blanking its key, or typing one that is not
    /// well-formed, is not a delete -- the cell reverts to the stored key
    /// rather than committing an invalid one. Clearing its *value* to empty,
    /// in contrast, is a legitimate clear and still fires `onSet`.
    func commitEdit(row: Int, key: String, value: String) {
        guard row >= 0, row < entries.count else { return }

        if row == placeholderRow {
            entries[row] = GitConfigEntry(key: key, value: value)
            guard !key.isEmpty, Self.isWellFormedKey(key), !value.isEmpty else { return }
            placeholderRow = nil
            onSet?(key, value)
            return
        }

        let oldKey = entries[row].key
        let oldValue = entries[row].value
        guard !key.isEmpty, Self.isWellFormedKey(key) else {
            let keyColumn = tableView.column(withIdentifier: Self.keyColumn)
            tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: keyColumn))
            return
        }

        entries[row] = GitConfigEntry(key: key, value: value)
        if key != oldKey {
            onRename?(oldKey, oldValue, key, value)
        } else {
            onSet?(key, value)
        }
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
    public func controlTextDidBeginEditing(_ notification: Notification) {
        isEditingField = true
    }

    public func controlTextDidEndEditing(_ notification: Notification) {
        isEditingField = false
        defer {
            if let pending = pendingEntries {
                pendingEntries = nil
                applyEntries(pending)
            }
        }
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
