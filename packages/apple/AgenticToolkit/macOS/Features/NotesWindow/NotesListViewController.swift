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

    /// Drives `applySearch()` from the window toolbar's search field (Task 7)
    /// now that this pane no longer hosts one of its own. Normalises the same
    /// way `applySearch()` itself used to read a live `NSSearchField`: trimmed
    /// and lowercased, so callers can pass the field's raw text unmodified.
    public func setSearchQuery(_ query: String) {
        searchQuery = query.trimmingCharacters(in: .whitespaces).lowercased()
        applySearch()
    }

    // MARK: - Properties

    private var allNotes: [Note] = []
    private var filteredNotes: [Note] = []

    /// The normalized search text `applySearch()` filters against. Replaces
    /// the `NSSearchField` this pane used to own — the field itself moved to
    /// the window toolbar in Task 7, but something still has to hold the
    /// query between keystrokes and a reload.
    private var searchQuery = ""

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
        table.style = .inset
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
        view.addSubview(scrollView)

        // The header, new-note button and search field that used to live here
        // moved to the window toolbar (Task 7) — this pane is now just the
        // scroll view, filling the whole item.
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
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

    // MARK: - Filtering

    private func applySearch() {
        if searchQuery.isEmpty {
            filteredNotes = allNotes
        } else {
            filteredNotes = allNotes.filter {
                $0.title.lowercased().contains(searchQuery) || $0.content.lowercased().contains(searchQuery)
            }
        }
        tableView.reloadData()
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
        previewLabel.stringValue = note.excerpt.isEmpty ? "(empty)" : note.excerpt
        pinIndicator.isHidden = !note.isPinned
    }
}
