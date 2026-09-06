import AppKit
import os
import AgenticToolkitCore
import AgenticToolkitCoreUI
import AgenticToolkitCoreMacOS

/// Manages the Notes window lifecycle. Hosts a `NotesSplitViewController`
/// with folders, list, editor and help panes.
@MainActor
public final class NotesWindowController: WindowController<NotesSplitViewController> {

    private let notesManager: NotesManager

    /// Built in `init`, not in `configureWindow` (task-7-grounding G4):
    /// `NSToolbar.delegate` is weak, so a delegate with no other owner would
    /// be deallocated the instant `configureWindow` returns, leaving the
    /// titlebar with no items and no error.
    private let toolbarDelegate: NotesWindowToolbar

    public static let windowID = "notes"

    public init(notesManager: NotesManager) {
        self.notesManager = notesManager
        let splitViewController = NotesSplitViewController(
            notesManager: notesManager, markdownStore: notesManager.markdownStore)
        self.toolbarDelegate = NotesWindowToolbar(splitViewController: splitViewController)
        super.init(
            windowID: Self.windowID,
            contentViewController: splitViewController
        )
        self.windowSpec = WindowSpec(
            defaultSize: NSSize(width: 900, height: 600),
            minSize: NSSize(width: 640, height: 400),
            defaultPosition: .center,
            persistsFrame: true
        )
        self.windowTitle = "Notes"
        self.windowStyleMask = [.titled, .closable, .miniaturizable, .resizable]
        self.minSize = NSSize(width: 640, height: 400)
    }

    /// Installs the titlebar toolbar (task-7 spec §3): unified style, hidden
    /// window-title text (the toolbar's own controls carry the window's
    /// meaning, as in `ComposableSettings.SettingsWindow`), no user
    /// customization.
    public override func configureWindow(_ window: NSWindow) {
        super.configureWindow(window)
        let toolbar = NSToolbar(identifier: "notes.toolbar")
        toolbar.delegate = toolbarDelegate
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.titleVisibility = .hidden
    }

    /// Shows (or brings forward) the notes window, loading notes if needed.
    public func showNotes() {
        if !notesManager.isLoaded {
            Task { @MainActor in
                await notesManager.loadNotes()
                viewController?.reload()
            }
        }
        showWindow()
        logger.debug("Notes window shown")
    }
}

extension NotesWindowController: Loggable {
    public static nonisolated let logger = makeLogger()
}
