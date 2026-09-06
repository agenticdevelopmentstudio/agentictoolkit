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

    public static let windowID = "notes"

    public init(notesManager: NotesManager) {
        self.notesManager = notesManager
        super.init(
            windowID: Self.windowID,
            contentViewController: NotesSplitViewController(
                notesManager: notesManager, markdownStore: notesManager.markdownStore)
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
