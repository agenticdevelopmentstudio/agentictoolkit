import AppKit
import OSLog
import AgenticToolkitCore

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
        self.quickNoteWindowController = QuickNoteWindowController(onSave: { [weak manager] title, content in
            Task { @MainActor in
                guard let manager else { return }
                if !manager.isLoaded { await manager.loadNotes() }
                _ = await manager.createNote(title: title, content: content)
            }
        })

        super.init()

        self.menuContributions = [
            MenuContribution(slot: .window, title: "Notes", order: 40, key: "4") { [weak self] in
                self?.showNotesWindow()
            },
            MenuContribution(slot: .statusItem(section: 0), title: "Notes", order: 10, key: "n") { [weak self] in
                self?.showNotesWindow()
            },
            MenuContribution(slot: .statusItem(section: 0), title: "Quick Note", order: 20) { [weak self] in
                self?.showQuickNoteWindow()
            }
        ]

        self.scriptingKeys.insert("scriptingNotesVisible")
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
