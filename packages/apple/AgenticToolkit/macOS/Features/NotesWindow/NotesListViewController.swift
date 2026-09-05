import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS

@MainActor public protocol NotesListViewControllerDelegate: AnyObject {
    func notesListDidSelectNote(_ note: Note?)
    func notesListDidRequestNewNote()
}

public final class NotesListViewController: NSViewController {

    // MARK: - Public API

    public weak var delegate: NotesListViewControllerDelegate?

    /// The manager this list mirrors, when it has one.
    ///
    /// Optional because the list is perfectly usable as a dumb view driven by
    /// `reload(notes:keepingSelectedID:)` — that is how it worked before, and
    /// how a preview or a test can still drive it. Supplying a manager adds
    /// one thing: the list also refreshes itself when *anything else* changes
    /// that manager's notes, which is what a host cannot arrange by
    /// remembering to call `reload` after its own actions.
    private weak var notesManager: NotesManager?

    public init(notesManager: NotesManager? = nil) {
        self.notesManager = notesManager
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    /// Reload the displayed notes. Call on main thread after notes array changes.
    public func reload(notes: [Note], keepingSelectedID: UUID?) {
        allNotes = notes
        applySearch()
        if let id = keepingSelectedID,
           let idx = filteredNotes.firstIndex(where: { $0.id == id }) {
            tableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false)
            tableView.scrollRowToVisible(idx)
        } else {
            tableView.deselectAll(nil)
        }
    }

    public var selectedNoteID: UUID? {
        let row = tableView.selectedRow
        guard row >= 0 && row < filteredNotes.count else { return nil }
        return filteredNotes[row].id
    }

    // MARK: - Properties

    private var allNotes: [Note] = []
    private var filteredNotes: [Note] = []

    private lazy var searchField: NSSearchField = {
        let field = NSSearchField()
        field.placeholderString = "Search notes"
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        field.accessibilityID("notes.search")
        // The magnifier and the clear "x" are cells of their own in the
        // accessibility tree, and they do not inherit the field's identifier.
        let cell = field.cell as? NSSearchFieldCell
        cell?.searchButtonCell?.setAccessibilityIdentifier("notes.search.magnifier")
        cell?.cancelButtonCell?.setAccessibilityIdentifier("notes.search.clear")
        return field
    }()

    private lazy var newNoteButton: NSButton = {
        let btn = NSButton()
        btn.isBordered = false
        btn.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "New Note")
        btn.image?.isTemplate = true
        btn.toolTip = "New note"
        btn.target = self
        btn.action = #selector(newNoteTapped)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.accessibilityID("notes.new-note-button")
        return btn
    }()

    private lazy var headerLabel: NSTextField = {
        let label = ThemedLabel(string: "Notes", role: .primaryText, textRole: .heading)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var scrollView: NSScrollView = {
        let scroll = ThemedScrollView(frame: .zero)
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        return scroll
    }()

    private lazy var tableView: NSTableView = {
        let table = ThemedTableView(role: .surface)
        table.headerView = nil
        table.rowHeight = 60
        table.selectionHighlightStyle = .regular
        table.delegate = self
        table.dataSource = self
        table.rowSizeStyle = .custom
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("note"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        return table
    }()

    // MARK: - View Lifecycle

    override public func loadView() {
        // The notes list is the sidebar of the split view, so it sits on
        // `surface` rather than the window backdrop the editor pane fills.
        view = ThemedBackgroundView(role: .surface)
        view.translatesAutoresizingMaskIntoConstraints = false
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        scrollView.documentView = tableView
        view.addSubview(headerLabel)
        view.addSubview(newNoteButton)
        view.addSubview(searchField)
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            headerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),

            newNoteButton.centerYAnchor.constraint(equalTo: headerLabel.centerYAnchor),
            newNoteButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            newNoteButton.widthAnchor.constraint(equalToConstant: 24),
            newNoteButton.heightAnchor.constraint(equalToConstant: 24),

            searchField.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        if let notesManager {
            NotificationCenter.default.addObserver(
                self, selector: #selector(notesDidChange),
                name: NotesManager.notesDidChangeNotification, object: notesManager)
            reload(notes: notesManager.notes, keepingSelectedID: selectedNoteID)
        }
    }

    /// Mirrors the manager's notes into the table, and touches nothing else.
    ///
    /// Deliberately narrower than `NotesSplitViewController.reload()`, which
    /// also pushes the selected note back into the editor: this fires on
    /// *every* mutation, including the ones the editor itself is making as
    /// the user types, and re-showing a note mid-edit would reset the text
    /// view under the cursor. The list is safe to refresh at any moment; the
    /// editor is not, and it already has the text.
    ///
    /// The early return is the second half of that guarantee. The split view
    /// controller still reloads the list explicitly after each of its own
    /// actions, so this notification usually arrives to find the table
    /// already showing exactly these notes — and re-selecting a row that is
    /// already selected is not free: `selectRowIndexes` scrolls, and a table
    /// reload drops the search field's first responder ordering on the floor.
    /// Doing nothing when nothing changed leaves the redundant case
    /// genuinely inert, so the only reloads a user can perceive are the ones
    /// carrying news.
    @objc private func notesDidChange(_ notification: Notification) {
        guard let notesManager, notesManager.notes != allNotes else { return }
        reload(notes: notesManager.notes, keepingSelectedID: selectedNoteID)
    }

    // MARK: - Actions

    @objc private func newNoteTapped() {
        delegate?.notesListDidRequestNewNote()
    }

    // MARK: - Filtering

    private func applySearch() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        if query.isEmpty {
            filteredNotes = allNotes
        } else {
            filteredNotes = allNotes.filter {
                $0.title.lowercased().contains(query) || $0.content.lowercased().contains(query)
            }
        }
        tableView.reloadData()
    }
}

// MARK: - NSSearchFieldDelegate

extension NotesListViewController: NSSearchFieldDelegate {
    public func controlTextDidChange(_ obj: Notification) {
        applySearch()
    }
}

// MARK: - NSTableViewDataSource

extension NotesListViewController: NSTableViewDataSource {
    public func numberOfRows(in tableView: NSTableView) -> Int {
        filteredNotes.count
    }
}

// MARK: - NSTableViewDelegate

extension NotesListViewController: NSTableViewDelegate {

    public func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 60 }

    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        // AppKit pools row views, so the row has to own a palette observer of
        // its own — a selection fill baked in at creation draws stale after a
        // theme swap.
        ThemedTableRowView()
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        // NSTableView can request a row that's just been removed (e.g. between
        // a data mutation and the next reload). Guard rather than crash.
        guard row >= 0, row < filteredNotes.count else { return nil }
        let note = filteredNotes[row]
        let id = NSUserInterfaceItemIdentifier("NoteCell")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NoteListCellView
            ?? NoteListCellView(identifier: id)
        cell.configure(with: note)
        return cell
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        let note = (row >= 0 && row < filteredNotes.count) ? filteredNotes[row] : nil
        delegate?.notesListDidSelectNote(note)
    }
}

// MARK: - NoteListCellView

public final class NoteListCellView: NSTableCellView {

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private let pinIndicator = NSImageView()
    private let titleLabel = ThemedLabel(role: .primaryText, textRole: .body)
    private let dateLabel = ThemedLabel(role: .secondaryText, textRole: .caption)
    private let previewLabel = ThemedLabel(role: .tertiaryText, textRole: .caption)

    public init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setupViews()
    }

    public required init?(coder: NSCoder) { fatalError() }

    private func setupViews() {
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        dateLabel.translatesAutoresizingMaskIntoConstraints = false

        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.translatesAutoresizingMaskIntoConstraints = false

        pinIndicator.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned")
        pinIndicator.translatesAutoresizingMaskIntoConstraints = false
        pinIndicator.setContentHuggingPriority(.required, for: .horizontal)
        // The pin glyph borrows the theme's warning-accent tint rather than a
        // hardcoded orange, so it still reads against every palette.
        pinIndicator.observeTheme { view, palette in
            view.contentTintColor = palette.nsColor(.warning)
        }

        addSubview(titleLabel)
        addSubview(dateLabel)
        addSubview(previewLabel)
        addSubview(pinIndicator)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: pinIndicator.leadingAnchor, constant: -4),

            pinIndicator.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            pinIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            pinIndicator.widthAnchor.constraint(equalToConstant: 12),
            pinIndicator.heightAnchor.constraint(equalToConstant: 12),

            dateLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            dateLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),

            previewLabel.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 2),
            previewLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            previewLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        ])
    }

    public func configure(with note: Note) {
        titleLabel.stringValue = note.title
        dateLabel.stringValue = Self.relativeFormatter.localizedString(for: note.modifiedDate, relativeTo: Date())
        let preview = note.content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        previewLabel.stringValue = preview.isEmpty ? "(empty)" : String(preview.prefix(60))
        pinIndicator.isHidden = !note.isPinned
    }
}
