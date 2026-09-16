//
//  FloatingChooserPanelController.swift
//  AgenticToolkit
//

import AppKit

/// The floating, titleless `NSPanel` every transient chooser in this app comes
/// up in: the command palette, and the quick pick and input box an extension
/// asks for.
///
/// **This is the one copy.** `CommandPaletteWindowController` was written
/// first; `ExtensionPickerWindowController` was then written "modelled line for
/// line" on it, its own doc comment naming the palette's file and line numbers
/// for the reasoning behind each piece it had reproduced. That is a copy that
/// documents itself as one, and the line references went stale the first time
/// the palette's file changed length. Everything both of them stated the same
/// way is stated here once, and each of them now says only what makes it
/// different.
///
/// A base class rather than a helper object, because the shared behaviour *is*
/// `NSWindowController` and `NSWindowDelegate`: the re-entrancy guard is an
/// override of `close()`, and the dismissal is `windowDidResignKey` /
/// `windowWillClose`. A helper would have to be handed the delegate role and
/// then call back into its owner for each of the three decisions below, which
/// is more wiring than the three overrides it would replace.
///
/// Subclasses decide exactly three things:
///
/// 1. **How big**, by the `contentRect` they pass to `init` — the palette
///    spells two numbers, the extension panel reads its content's
///    `preferredContentSize`.
/// 2. **Whether a focus loss dismisses**, via `dismissesOnFocusLoss`. True by
///    default, because a chooser left floating behind another app is a stale
///    list about a window that is no longer in front; VS Code's
///    `ignoreFocusOut` option is what makes it false.
/// 3. **What happens on the way in and out**, via `takeInitialFocus()` and
///    `panelWillClose()`.
@MainActor
open class FloatingChooserPanelController: NSWindowController {

    // MARK: - Views

    /// The panel's content view controller, so the chooser below is a genuine
    /// child in the view-controller hierarchy rather than an orphan whose view
    /// happens to be a subview — the same reason `QuickNoteWindowController`
    /// hosts one.
    private let containerController = NSViewController()

    /// The chooser this panel hosts. Subclasses that need it back in its own
    /// type cast it here rather than storing a second reference.
    public let contentController: NSViewController

    /// How far below the top of the screen the panel's own top edge sits, as a
    /// fraction of the visible height. A chooser belongs in the upper third of
    /// the screen, where one is looked for, rather than dead centre where it
    /// covers the work it is about to act on.
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

    // MARK: - Subclass hooks

    /// Whether losing the keyboard dismisses this panel.
    ///
    /// `windowDidResignKey` and not `hidesOnDeactivate`: hiding is not
    /// dismissing. AppKit *restores* a hidden-on-deactivate window on the app's
    /// next activation, which would bring the chooser back on its own — same
    /// query, same selection, no first responder, because nothing on that path
    /// calls `show()`. Closing is permanent, and `isReleasedWhenClosed = false`
    /// keeps the panel alive to be re-shown.
    open var dismissesOnFocusLoss: Bool { true }

    /// Hand the keyboard to whatever the hosted content wants focused. Called
    /// at the end of `show()`, once the window is key.
    open func takeInitialFocus() {}

    /// Every dismissal, however it was asked for, lands here exactly once.
    open func panelWillClose() {}

    // MARK: - Lifecycle

    /// - Parameters:
    ///   - content: the chooser's own view controller.
    ///   - contentRect: the panel's size. A zero-sized rect collapses the
    ///     window (see the container framing below), so subclasses pass a real
    ///     one. A subclass deriving it from `content.preferredContentSize` must
    ///     force the view to load itself first — this argument is evaluated
    ///     before any of this initialiser's body runs, so the `content.view`
    ///     access below is too late to help it
    ///     (`ExtensionPickerWindowController.init` is the one that does).
    public init(content: NSViewController, contentRect: NSRect) {
        self.contentController = content
        let hostedView = content.view

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
        // A chooser has no title-bar furniture. `.titled` is here for the frame
        // and `.fullSizeContentView` draws the search field up into the title
        // band, so the traffic lights would otherwise sit on top of the field's
        // magnifying glass. Nothing is lost: Escape, a click away and accepting
        // all dismiss, so the close button was never the way out, and a panel
        // this size has nothing to say about minimising or zooming.
        for button: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }

        super.init(window: window)
        window.delegate = self

        // Framed with the window's own rect: a zero-frame container view
        // collapses the window to Auto Layout's intrinsic minimum the moment it
        // becomes `contentViewController`, discarding `contentRect` (see
        // `QuickNoteWindowController`, which learned this the same way).
        containerController.view = NSView(frame: contentRect)
        window.contentViewController = containerController
        containerController.addChild(content)

        hostedView.translatesAutoresizingMaskIntoConstraints = false
        containerController.view.addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.topAnchor.constraint(equalTo: containerController.view.topAnchor),
            hostedView.leadingAnchor.constraint(equalTo: containerController.view.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: containerController.view.trailingAnchor),
            hostedView.bottomAnchor.constraint(equalTo: containerController.view.bottomAnchor)
        ])
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    // MARK: - Show

    /// Position the panel, activate, take key, and hand first responder to the
    /// content.
    ///
    /// Idempotent: showing an already-open panel re-positions and re-focuses
    /// the one window rather than stacking a second (`idempotency`).
    open func show() {
        guard let window else { return }
        position(window)
        // Activate *before* taking key: a chooser can open from a system-global
        // request with another app frontmost, and activating afterwards lets
        // AppKit hand key back to whichever window of this app held it last —
        // which, now that resigning key closes the panel, would shut it again
        // the instant it opened.
        //
        // `activateUnlessQuiet()` rather than the bare
        // `activate(ignoringOtherApps:)`: every activation site in this app
        // goes through it, and it is what keeps an automated run — which drives
        // these panels — from taking the screen away from whoever is typing.
        NSApp.activateUnlessQuiet()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        takeInitialFocus()
    }

    // MARK: - Dismiss

    /// The single dismissal, entered once however it was asked for.
    ///
    /// Every way out of the panel comes through here, and the close this starts
    /// can re-enter it (see `isDismissing`). Re-entering returns without closing
    /// again, so `windowWillClose` — and with it `panelWillClose()` — runs once
    /// per dismissal instead of twice.
    ///
    /// The flag is cleared on the way out rather than left set, so the *next*
    /// dismissal of a re-shown panel is a first entry again.
    open override func close() {
        guard !isDismissing else { return }
        isDismissing = true
        defer { isDismissing = false }
        super.close()
    }

    /// Horizontally centred, near the top, on the screen the pointer is on.
    ///
    /// The pointer rather than the key window because a chooser is opened by a
    /// system-global shortcut or by an extension: there may be no window of this
    /// app on screen at all, and the screen the user is looking at is the one
    /// their pointer is on. Not anchored to the status item the way Quick Note
    /// is — a 640-point list hung off a menu-bar icon in the top-right corner
    /// has nowhere to go but clamped against the screen edge.
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

extension FloatingChooserPanelController: NSWindowDelegate {

    /// Losing the keyboard means the user is doing something else: dismiss,
    /// unless `dismissesOnFocusLoss` says to stay up regardless.
    ///
    /// Clicking another window and switching apps both land here, so together
    /// with Escape and accepting an answer every way out of the panel goes
    /// through `close()` and ends in `windowWillClose` below — one dismissal
    /// path, not four (`dry`).
    ///
    /// Two guards, for two different things. `isDismissing` is the one that
    /// keeps the single path from running twice: closing a key window resigns
    /// key on the way out, so this is re-entered mid-close, and without it
    /// `windowWillClose` — hence `panelWillClose()` — fires twice per dismissal.
    /// It is an owned bit rather than a reading of window state precisely
    /// because the window's state is what AppKit has not finished changing yet.
    ///
    /// Visibility is the second, and answers a different question: a panel that
    /// is already closed has no dismissal to perform, so a resignation arriving
    /// for one is ignored rather than reopening the close path on a window that
    /// is gone.
    public func windowDidResignKey(_ notification: Notification) {
        guard dismissesOnFocusLoss, !isDismissing, window?.isVisible == true else { return }
        close()
    }

    public func windowWillClose(_ notification: Notification) {
        panelWillClose()
    }
}
