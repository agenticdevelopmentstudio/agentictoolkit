import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS

public final class NotesSplitViewController: ThemedSplitViewController {

    // MARK: - Dependencies

    private let notesManager: NotesManager

    /// Divider-position key, distinct per pane when a host can open more than
    /// one notes pane at a time.
    private let splitAutosaveName: String

    // MARK: - Child VCs

    private let listVC: NotesListViewController
    private let editorVC = NoteEditorViewController()

    // MARK: - Initialization

    public init(notesManager: NotesManager, autosaveName: String = "notes-split") {
        self.notesManager = notesManager
        self.splitAutosaveName = autosaveName
        // The list watches the manager itself, so a note created anywhere else
        // — Quick Note, a scripting command, a second window — reaches this
        // pane without the mutating code having to know the pane exists. The
        // explicit `reload()` calls below stay: they also refresh the editor
        // and move the selection, which the notification deliberately does not.
        self.listVC = NotesListViewController(notesManager: notesManager)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override public func viewDidLoad() {
        super.viewDidLoad()

        let listItem = NSSplitViewItem(viewController: listVC)
        listItem.minimumThickness = 180
        listItem.maximumThickness = 320
        // The list keeps the width it was given; the editor absorbs the rest.
        // Without this both panes share the pane's resizing, and a restored
        // width is scaled away as the split view grows into place.
        listItem.holdingPriority = .defaultLow + 1

        let editorItem = NSSplitViewItem(viewController: editorVC)
        editorItem.minimumThickness = Self.minimumEditorWidth

        addSplitViewItem(listItem)
        addSplitViewItem(editorItem)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        seedDividerPositionIfUnset()
        // Set last, and only once the items exist: NSSplitView reads the
        // autosaved frames when the name is assigned, so a name given to an
        // empty split view restores nothing and never tries again.
        splitView.autosaveName = NSSplitView.AutosaveName(splitAutosaveName)

        listVC.delegate = self
        editorVC.delegate = self

        NotificationCenter.default.addObserver(
            self, selector: #selector(storageDidFail),
            name: NotesManager.storageDidFailNotification, object: notesManager)
    }

    @objc private func storageDidFail() {
        presentStorageFailureIfPossible()
    }

    /// Shows whatever failure the manager is still holding, as a sheet on this
    /// pane's window, and does nothing if there is none or if there is no
    /// window yet.
    ///
    /// Claimed before it is shown: every host of this manager observes the same
    /// notification, and `clearStorageFailure()` is what stops three windows
    /// from stacking three sheets saying the same thing. A pane with no window
    /// — off screen, in a tab that is not selected, or not yet built — leaves
    /// the failure unclaimed, which is why `storageFailure` is read and only
    /// then cleared.
    ///
    /// Called from two places, and it has to be both. A notification alone
    /// misses every failure that happens before this pane has a window:
    /// `NotesCoordinator.start()` loads notes at launch, and Quick Note creates
    /// one from a window that has already closed by the time the write lands —
    /// in each case the notification is posted to a pane that cannot show it,
    /// and nothing ever asked again. So the pane also asks on the way in, when
    /// a window exists by definition. A failure therefore survives in the
    /// manager until some host can actually put it on screen.
    ///
    /// `beginSheetModal` and not `runModal`: this is the idiom the delete
    /// confirmation two files over already uses, and a modal run loop here
    /// would block the main thread inside a notification delivery.
    private func presentStorageFailureIfPossible() {
        guard let failure = notesManager.storageFailure, let window = view.window else { return }
        notesManager.clearStorageFailure()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = failure.operation.title
        alert.informativeText = failure.operation.consequence + "\n\n" + failure.message
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window, completionHandler: nil)
    }

    override public func viewDidAppear() {
        super.viewDidAppear()
        // `viewWillAppear` is too early for this: `view.window` is already set
        // there, but the window is not yet on screen and `beginSheetModal`
        // against it is a sheet nobody sees.
        presentStorageFailureIfPossible()
    }

    override public func viewWillAppear() {
        super.viewWillAppear()
        reload()
        // The manager loads from storage asynchronously at launch, and a notes
        // *pane* is on screen before that finishes — it comes up with the
        // project window rather than because someone asked for it. Reloading
        // once from an empty manager and never hearing about the load is how a
        // pane sits blank beside a notes window listing the same notes. The
        // window already does this when it is shown; the pane is the third host
        // and the only one that appears unbidden.
        guard !notesManager.isLoaded else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.notesManager.loadNotes()
            self.reload()
        }
    }

    /// Width a notes pane opens at, the first time it is ever shown, in a pane
    /// as wide as `defaultPaneWidth`; proportionally less in a narrower one.
    private static let defaultListWidth: CGFloat = 240
    private static let defaultPaneWidth: CGFloat = 969

    /// Below this the note itself is narrower than the list beside it.
    private static let minimumEditorWidth: CGFloat = 300

    /// Gives a pane nobody has ever dragged a saved position to be restored
    /// from, rather than a width set from a lifecycle callback.
    ///
    /// `setPosition` is not an option here: `NSSplitViewController` lays its
    /// items out with constraints and puts the divider straight back, wherever
    /// in the lifecycle the call is made. Restoring is the one path that
    /// survives, so the first run takes it too — one mechanism for the default
    /// and for every run after it.
    private func seedDividerPositionIfUnset() {
        guard !hasStoredDividerPosition else { return }
        let height = splitView.bounds.height
        let editorWidth = Self.defaultPaneWidth - Self.defaultListWidth - splitView.dividerThickness
        UserDefaults.standard.set(
            [
                "0.0, 0.0, \(Self.defaultListWidth), \(height), NO, NO",
                "\(Self.defaultListWidth + splitView.dividerThickness), 0.0, \(editorWidth), \(height), NO, NO"
            ],
            forKey: Self.dividerPositionKey(splitAutosaveName)
        )
    }

    /// Where AppKit keeps an autosaved divider position. Its absence is what
    /// "nobody has ever sized this pane" looks like.
    private var hasStoredDividerPosition: Bool {
        UserDefaults.standard.object(forKey: Self.dividerPositionKey(splitAutosaveName)) != nil
    }

    static func dividerPositionKey(_ autosaveName: String) -> String {
        "NSSplitView Subview Frames \(autosaveName)"
    }

    // MARK: - Reload

    public func reload() {
        listVC.reload(notes: notesManager.notes, keepingSelectedID: listVC.selectedNoteID)
        if let id = listVC.selectedNoteID,
           let note = notesManager.notes.first(where: { $0.id == id }) {
            editorVC.show(note: note)
        }
    }
}

// MARK: - NotesListViewControllerDelegate

extension NotesSplitViewController: NotesListViewControllerDelegate {

    public func notesListDidSelectNote(_ note: Note?) {
        editorVC.show(note: note)
    }

    public func notesListDidRequestNewNote() {
        Task { @MainActor in
            // No id means the insert failed and the note was discarded; the
            // sheet is already on its way, and selecting nothing is right.
            guard let newID = await notesManager.createNote(title: "", content: "") else { return }
            let newNote = notesManager.notes.first(where: { $0.id == newID })
            listVC.reload(notes: notesManager.notes, keepingSelectedID: newID)
            editorVC.show(note: newNote)
        }
    }
}

// MARK: - NoteEditorViewControllerDelegate

extension NotesSplitViewController: NoteEditorViewControllerDelegate {

    public func noteEditorDidChangeTitle(_ title: String, for noteID: UUID) {
        guard let note = notesManager.notes.first(where: { $0.id == noteID }) else { return }
        Task { @MainActor in
            await notesManager.updateNote(note, title: title, content: note.content)
            listVC.reload(notes: notesManager.notes, keepingSelectedID: noteID)
        }
    }

    public func noteEditorDidChangeContent(_ content: String, for noteID: UUID) {
        guard let note = notesManager.notes.first(where: { $0.id == noteID }) else { return }
        Task { @MainActor in
            await notesManager.updateNote(note, title: note.title, content: content)
            listVC.reload(notes: notesManager.notes, keepingSelectedID: noteID)
        }
    }

    public func noteEditorDidRequestPin(for noteID: UUID) {
        guard let note = notesManager.notes.first(where: { $0.id == noteID }) else { return }
        Task { @MainActor in
            await notesManager.togglePin(note: note)
            listVC.reload(notes: notesManager.notes, keepingSelectedID: noteID)
            if let updated = notesManager.notes.first(where: { $0.id == noteID }) {
                editorVC.show(note: updated)
            }
        }
    }

    public func noteEditorDidRequestDelete(for noteID: UUID) {
        Task { @MainActor in
            await notesManager.deleteNote(id: noteID)
            listVC.reload(notes: notesManager.notes, keepingSelectedID: nil)
            editorVC.show(note: nil)
        }
    }
}
