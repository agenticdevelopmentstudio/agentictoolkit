import AppKit
import OSLog
import AgenticToolkitCore

/// The floating panel the command palette lives in.
///
/// An `NSPanel` rather than a plain `NSWindow`, and titleless: a palette is a
/// transient chooser over whatever the user was already doing, not a document
/// window with a name of its own.
@MainActor
public final class CommandPaletteWindowController: NSWindowController {

    // MARK: - Views

    /// The panel's content view controller, so the palette below is a genuine
    /// child in the view-controller hierarchy rather than an orphan whose view
    /// happens to be a subview — the same reason `QuickNoteWindowController`
    /// hosts one.
    private let containerController = NSViewController()

    private let paletteController: CommandPaletteViewController

    /// How far below the top of the screen the panel's own top edge sits, as a
    /// fraction of the visible height. A palette belongs in the upper third of
    /// the screen, where a chooser is looked for, rather than dead centre where
    /// it covers the work it is about to act on.
    private static let topInsetFraction: CGFloat = 0.2

    /// True for as long as one dismissal is unwinding.
    ///
    /// Closing the key panel makes AppKit resign key *before* the window is
    /// ordered out, which lands in `windowDidResignKey` — the dismissal path —
    /// in the middle of the dismissal already running. This bit is what tells
    /// the two apart, because it is this controller's own answer to "am I
    /// already closing?" rather than an inference from window state AppKit has
    /// not finished updating.
    private var isDismissing = false

    // MARK: - Lifecycle

    public init(model: CommandPaletteModel) {
        self.paletteController = CommandPaletteViewController(model: model)

        let contentRect = NSRect(x: 0, y: 0, width: 640, height: 400)
        let window = NSPanel(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // Titled, but with nothing to say: `.titled` is what gives the panel a
        // standard frame and a close button, while a visible title bar would
        // take a band from the list and name a window the user is about to
        // dismiss.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // A palette has no title-bar furniture. `.titled` is here for the frame
        // and `.fullSizeContentView` draws the search field up into the title
        // band, so the traffic lights would otherwise sit on top of the field's
        // magnifying glass. Nothing is lost: Escape, a click away and running a
        // command all dismiss, so the close button was never the way out, and a
        // 640x400 chooser has nothing to say about minimising or zooming.
        for button: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }

        super.init(window: window)

        // Clicking away dismisses. This is the one place the palette departs
        // from Quick Note, deliberately: a note being typed must survive a
        // distraction, whereas a palette left floating behind another app is a
        // stale list of commands about a window that is no longer in front.
        //
        // `windowDidResignKey` and not `hidesOnDeactivate`: hiding is not
        // dismissing. AppKit *restores* a hidden-on-deactivate window on the
        // app's next activation, which would bring the palette back on its own
        // — same query, same selection, no first responder, because nothing on
        // that path calls `show()`. Closing is permanent, and
        // `isReleasedWhenClosed = false` above keeps the panel alive to be
        // re-shown.
        window.delegate = self

        // Framed with the window's own rect: a zero-frame container view
        // collapses the window to Auto Layout's intrinsic minimum the moment it
        // becomes `contentViewController`, discarding the 640x400 above (see
        // `QuickNoteWindowController`, which learned this the same way).
        containerController.view = NSView(frame: contentRect)
        window.contentViewController = containerController
        containerController.addChild(paletteController)

        let paletteView = paletteController.view
        paletteView.translatesAutoresizingMaskIntoConstraints = false
        containerController.view.addSubview(paletteView)
        NSLayoutConstraint.activate([
            paletteView.topAnchor.constraint(equalTo: containerController.view.topAnchor),
            paletteView.leadingAnchor.constraint(equalTo: containerController.view.leadingAnchor),
            paletteView.trailingAnchor.constraint(equalTo: containerController.view.trailingAnchor),
            paletteView.bottomAnchor.constraint(equalTo: containerController.view.bottomAnchor)
        ])

        paletteController.onRun = { [weak self] in self?.close() }
        paletteController.onCancel = { [weak self] in self?.close() }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    // MARK: - Show

    /// Bring the palette up empty, re-read from the registry, and focus it.
    ///
    /// Idempotent: showing an already-open palette re-positions and re-focuses
    /// the one panel rather than stacking a second (`idempotency`).
    public func show() {
        guard let window else { return }
        paletteController.reset()
        position(window)
        // Activate *before* taking key, the one place this departs from Quick
        // Note's ordering: the palette opens from a system-global shortcut with
        // another app frontmost, and activating afterwards lets AppKit hand key
        // back to whichever window of this app held it last — which, now that
        // resigning key closes the palette, would shut it again the instant it
        // opened.
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        paletteController.focusSearchField()
        logger.debug("Command palette shown")
    }

    // MARK: - Dismiss

    /// The single dismissal, entered once however it was asked for.
    ///
    /// All four ways out of the palette come through here, and the close this
    /// starts can re-enter it (see `isDismissing`). Re-entering returns without
    /// closing again, so `windowWillClose` — and with it `reset()` — runs once
    /// per dismissal instead of twice.
    ///
    /// The flag is cleared on the way out rather than left set, so the *next*
    /// dismissal of a re-shown palette is a first entry again.
    public override func close() {
        guard !isDismissing else { return }
        isDismissing = true
        defer { isDismissing = false }
        super.close()
    }

    /// Horizontally centred, near the top, on the screen the pointer is on.
    ///
    /// The pointer rather than the key window because the palette is opened by a
    /// system-global shortcut: there may be no window of this app on screen at
    /// all, and the screen the user is looking at is the one their pointer is
    /// on. Not anchored to the status item the way Quick Note is — a 640-point
    /// list hung off a menu-bar icon in the top-right corner has nowhere to go
    /// but clamped against the screen edge.
    private func position(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            window.center()
            return
        }
        let size = window.frame.size
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.maxY - visibleFrame.height * Self.topInsetFraction - size.height
        )
        window.setFrameOrigin(origin)
    }
}

// MARK: - Dismissal

extension CommandPaletteWindowController: NSWindowDelegate {

    /// Losing the keyboard means the user is doing something else: dismiss.
    ///
    /// Clicking another window and switching apps both land here, so together
    /// with Escape and running a command all four ways out of the palette go
    /// through `close()` and end in `windowWillClose` below — one dismissal
    /// path, not four (`dry`).
    ///
    /// Two guards, for two different things. `isDismissing` is the one that
    /// keeps the single path from running twice: closing a key window resigns
    /// key on the way out, so this is re-entered mid-close, and without it
    /// `windowWillClose` — hence `reset()` — fires twice per dismissal. It is
    /// an owned bit rather than a reading of window state precisely because
    /// the window's state is what AppKit has not finished changing yet.
    ///
    /// Visibility is the second, and answers a different question: a palette
    /// that is already closed has no dismissal to perform, so a resignation
    /// arriving for one is ignored rather than reopening the close path on a
    /// window that is gone.
    public func windowDidResignKey(_ notification: Notification) {
        guard !isDismissing, window?.isVisible == true else { return }
        close()
    }

    /// Every dismissal clears the palette.
    ///
    /// Here rather than only in `show()` because a closed palette should not be
    /// sitting on the last visit's query and selection at all: `runSelection`
    /// takes what it needs from the model *before* asking for the dismissal
    /// that clears it.
    public func windowWillClose(_ notification: Notification) {
        paletteController.reset()
    }
}

extension CommandPaletteWindowController: Loggable {
    public static nonisolated let logger = makeLogger()
}
