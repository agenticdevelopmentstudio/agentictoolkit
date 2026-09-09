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
        // Clicking away dismisses. This is the one place the palette departs
        // from Quick Note, deliberately: a note being typed must survive a
        // distraction, whereas a palette left floating behind another app is a
        // stale list of commands about a window that is no longer in front.
        window.hidesOnDeactivate = true

        super.init(window: window)

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
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        paletteController.focusSearchField()
        logger.debug("Command palette shown")
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

extension CommandPaletteWindowController: Loggable {
    public static nonisolated let logger = makeLogger()
}
