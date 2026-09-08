import AppKit
import OSLog
import AgenticToolkitCore
import AgenticDeveloperToolkitUI

/// Owns the Notes feature stack — the storage-backed `NotesManager` plus the
/// two AppKit window controllers (full editor and quick-note popover) — and
/// hides the wiring AppDelegate used to do directly. Hosts construct one with
/// a `NoteStorage`, kick off `loadNotes()` on launch, and call
/// `flushPendingSaves()` from `applicationWillTerminate`.
@MainActor
public final class NotesCoordinator: AppFeature {

    public let notesManager: NotesManager
    public let notesWindowController: NotesWindowController
    public let quickNoteWindowController: QuickNoteWindowController

    /// Status-item-button-frame provider — the host's `MenuManager` knows where
    /// the menu bar icon is; the Quick Note popover anchors below it. Hosts
    /// inject a closure that returns the current button frame.
    private let statusItemButtonFrameProvider: () -> NSRect

    public init(
        storage: NoteStorage,
        statusItemButtonFrameProvider: @escaping () -> NSRect = { .zero }
    ) {
        let manager = NotesManager(storage: storage)
        self.notesManager = manager
        self.statusItemButtonFrameProvider = statusItemButtonFrameProvider
        self.notesWindowController = NotesWindowController(notesManager: manager)
        self.quickNoteWindowController = QuickNoteWindowController(onSave: { [weak manager] content in
            Task { @MainActor in
                guard let manager else { return }
                if !manager.isLoaded { await manager.loadNotes() }
                _ = await manager.createNote(content: content)
            }
        })

        super.init()

        // One predicate for all four File-menu items: they mean the same
        // thing by "this action applies right now" — there is a notes view in
        // front of the user — and they would have to change together if that
        // ever stopped being the whole story. The `NewItemProvider` below
        // means it too but cannot share this constant; the comment there says
        // why.
        //
        // The predicate used to read `notesWindowController.window?.isKeyWindow`,
        // which is a narrower question than the items mean. Hosts mount the
        // very same `NotesSplitViewController` inside a project window's pane
        // (Whippet's `DocumentPanes`), and with that window key the
        // standalone window is not — so New Folder, Import Markdown File…,
        // Delete Note, Delete Folder and ⌘N all greyed out over a notes view
        // the user was working in, and the keyboard shortcuts did nothing.
        // `activeNotesViewController` answers the real question, and every
        // action below is routed through it so the command lands on the view
        // that enabled it rather than on a window that may not even be open.
        let hasNotesTarget: () -> Bool = { [weak self] in
            self?.activeNotesViewController != nil
        }

        self.menuContributions = [
            MenuContribution(slot: .window, title: "Notes", order: 40, key: "4") { [weak self] in
                self?.showNotesWindow()
            },
            MenuContribution(slot: .statusItem(section: 0), title: "Notes", order: 10) { [weak self] in
                self?.showNotesWindow()
            },
            MenuContribution(slot: .statusItem(section: 0), title: "Quick Note", order: 20) { [weak self] in
                self?.showQuickNoteWindow()
            },
            MenuContribution(
                slot: .file, title: "New Folder", order: 10, key: "n", modifiers: [.command, .shift],
                isEnabled: hasNotesTarget,
                action: { [weak self] in
                    self?.activeNotesViewController?.createFolderUnderSelection()
                }
            ),
            MenuContribution(
                slot: .file, title: "Import Markdown File…", order: 20,
                isEnabled: hasNotesTarget,
                action: { [weak self] in
                    // The presenter is the notes view itself, so the open
                    // panel is a sheet on whichever window is showing notes —
                    // and, because the same view receives the text, an import
                    // started from a project window's notes pane lands there
                    // instead of in a standalone window the user cannot see.
                    guard let presenter = self?.activeNotesViewController else { return }
                    MarkdownFileImporter.present(from: presenter) { [weak presenter] text in
                        guard let text else { return } // cancel or undecodable — no dialog
                        presenter?.createNote(content: text)
                    }
                }
            ),
            MenuContribution(
                slot: .file, title: "Delete Note", order: 30,
                isEnabled: hasNotesTarget,
                action: { [weak self] in
                    self?.activeNotesViewController?.deleteSelectedNote()
                }
            ),
            MenuContribution(
                slot: .file, title: "Delete Folder", order: 40,
                isEnabled: hasNotesTarget,
                action: { [weak self] in
                    self?.activeNotesViewController?.deleteSelectedFolder()
                }
            )
        ]

        self.newItemProviders = [
            NewItemProvider(
                // Spelled out rather than reusing `notesWindowIsKey` above:
                // this parameter is `@MainActor @Sendable () -> Bool` while
                // `MenuContribution.isEnabled` is a plain `() -> Bool`, and
                // Swift 6 converts between them in neither direction. A closure
                // literal takes its type from context, so the two contexts each
                // get one; a shared constant can only satisfy one of them.
                claimsKeyWindow: { [weak self] in
                    self?.activeNotesViewController != nil
                },
                title: { "New Note" },
                action: { [weak self] in
                    self?.activeNotesViewController?.createNote()
                }
            )
        ]

        self.scriptingKeys.insert("scriptingNotesVisible")
    }

    // MARK: - Where the notes commands act

    /// The notes view the File-menu commands and ⌘N apply to right now, or
    /// `nil` when nothing in front of the user is showing notes.
    ///
    /// `NotesSplitViewController` is not owned solely by
    /// `notesWindowController`: a host can mount it as a pane inside any
    /// window, so "is the Notes window key" and "is the user looking at notes"
    /// are different questions and only the second one is what a menu item
    /// means.
    ///
    /// Resolution goes through the key window, because a menu command acts on
    /// what has focus. Inside it the first responder's chain is walked before
    /// the view hierarchy, so a window holding two notes panes routes the
    /// command to the one being typed in rather than to whichever the tree
    /// happens to reach first. The hierarchy walk is the fallback for a window
    /// whose focus sits somewhere else entirely (a sidebar, the toolbar's
    /// search field), where "the notes view in this window" is still an
    /// unambiguous answer.
    private var activeNotesViewController: NotesSplitViewController? {
        guard let window = NSApp.keyWindow else { return nil }
        if window === notesWindowController.window { return notesWindowController.viewController }
        var responder: NSResponder? = window.firstResponder
        while let current = responder {
            if let notes = current as? NotesSplitViewController { return notes }
            responder = current.nextResponder
        }
        return window.contentViewController.flatMap(Self.firstNotesView(under:))
    }

    /// Depth-first search for a `NotesSplitViewController` in a view
    /// controller subtree.
    private static func firstNotesView(under root: NSViewController) -> NotesSplitViewController? {
        if let notes = root as? NotesSplitViewController { return notes }
        for child in root.children {
            if let found = firstNotesView(under: child) { return found }
        }
        return nil
    }

    // MARK: - AppFeature

    /// Load persisted notes on launch.
    ///
    /// This runs before any notes window or pane exists, so a failure here has
    /// no window to be a sheet on. That is deliberately *not* handled by
    /// building one: `NotesManager` keeps `storageFailure` set until a host
    /// claims it, and `NotesSplitViewController` asks on `viewDidAppear` as
    /// well as on the notification, so a launch failure is shown by whichever
    /// notes pane or window the user opens first rather than being dropped on
    /// the floor. The Quick Note save path has the same shape from the other
    /// end — its window closes before the async create completes — and is
    /// covered by the same mechanism.
    public override func start() throws {
        Task { [weak self] in await self?.loadNotes() }
    }

    /// Wait for any debounced saves before the app exits.
    public override func terminate() async {
        await notesManager.flushPendingSaves()
    }

    public func loadNotes() async {
        await notesManager.loadNotes()
        Self.logger.info("Notes loaded")
    }

    public func flushPendingSaves() async {
        await notesManager.flushPendingSaves()
    }

    public func showNotesWindow() {
        notesWindowController.showNotes()
    }

    public func showQuickNoteWindow() {
        quickNoteWindowController.showNearStatusItem(buttonFrame: statusItemButtonFrameProvider())
    }

    public override func value(forScriptingKey key: String) -> Any? {
        switch key {
        case "scriptingNotesVisible": return notesWindowController.isVisible
        default: return nil
        }
    }

    public override func setValue(_ value: Any?, forScriptingKey key: String) {
        switch key {
        case "scriptingNotesVisible":
            if (value as? Bool) == true {
                notesWindowController.showNotes()
            } else {
                notesWindowController.dismiss()
            }
        default:
            break
        }
    }
}

extension NotesCoordinator: Loggable {
    public static nonisolated let logger = makeLogger()
}
