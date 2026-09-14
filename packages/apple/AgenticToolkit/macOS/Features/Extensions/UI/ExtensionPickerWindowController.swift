//
//  ExtensionPickerWindowController.swift
//  AgenticToolkit
//

import AppKit

/// The floating panel `showQuickPick` and `showInputBox` share.
///
/// Modelled line for line on `CommandPaletteWindowController`
/// (`macOS/Features/CommandPalette/CommandPaletteWindowController.swift`): an
/// `NSPanel` with the same styling, the same container-controller framing,
/// and the same `isDismissing` re-entrancy guard for the reason stated there
/// — closing a key panel makes AppKit resign key *before* the window is
/// ordered out, which re-enters `windowDidResignKey` in the middle of a
/// dismissal already running.
///
/// Three differences from the palette, each deliberate:
///
/// 1. **Sized from `content.preferredContentSize`**, not from two numbers
///    spelled here — the quick pick wants a fixed list size, the input box
///    wants whatever height its Auto Layout stack comes to, and one `init`
///    serving both is why the size is asked for rather than stated.
/// 2. **`ignoreFocusOut`.** `windowDidResignKey` dismisses only when it is
///    false. When it is true the panel stays up on a focus loss — that is
///    what `QuickPickOptions.ignoreFocusOut` / `InputBoxOptions.ignoreFocusOut`
///    are for, and a panel that closed anyway would make the flag a lie.
/// 3. **`onDismiss` fires exactly once, from `windowWillClose`, whatever
///    closed the window.** It means "the user left without answering." The
///    content controllers report acceptance on their own callbacks and the
///    presenter closes the window afterwards, so acceptance is not also
///    reported here as a dismissal — the presenter's `OnceOnlyContinuation`
///    (part 1) is what makes that ordering safe, by ignoring the second
///    `finish` call, rather than a second flag on this type.
@MainActor
final class ExtensionPickerWindowController: NSWindowController {

    private let contentController: NSViewController
    private let containerController = NSViewController()
    private let ignoreFocusOut: Bool

    /// How far below the top of the screen the panel's own top edge sits, as
    /// a fraction of the visible height — matching
    /// `CommandPaletteWindowController.topInsetFraction`.
    private static let topInsetFraction: CGFloat = 0.2

    /// True for as long as one dismissal is unwinding. See
    /// `CommandPaletteWindowController.isDismissing` for why this bit exists
    /// rather than a reading of window state.
    private var isDismissing = false

    /// The user left without answering. Fired at most once per panel, from
    /// `windowWillClose`.
    var onDismiss: () -> Void = {}

    init(content: NSViewController, ignoreFocusOut: Bool) {
        self.contentController = content
        self.ignoreFocusOut = ignoreFocusOut

        // Force the content controller's view to load *before* reading
        // `preferredContentSize` below. `NSViewController.loadView` runs on
        // the first `.view` access, not on `.preferredContentSize` itself:
        // `ExtensionQuickPickViewController` sets the property in its own
        // `init` (so it is available either way), but
        // `ExtensionInputBoxViewController` computes and sets it from its
        // assembled Auto Layout height at the *end* of `loadView()` — reading
        // the property before that method has run reads a value that was
        // never set.
        let hostedView = content.view

        let contentRect = NSRect(origin: .zero, size: content.preferredContentSize)
        let window = NSPanel(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        for button: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }

        super.init(window: window)

        window.delegate = self

        // Framed with the window's own rect: a zero-frame container view
        // collapses the window to Auto Layout's intrinsic minimum the moment
        // it becomes `contentViewController`
        // (`CommandPaletteWindowController.swift:86-91`).
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
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Show

    /// Position, activate, take key, and hand first responder to whichever
    /// content this panel hosts.
    ///
    /// Order copied from `CommandPaletteWindowController.show()`
    /// (`:117-131`): activate before taking key — this can open from a
    /// system-global request with another app frontmost, and activating
    /// afterwards would let AppKit hand key back to whichever window of this
    /// app held it last, which (now that resigning key closes the panel)
    /// would shut it again the instant it opened (`:121-126`).
    func show() {
        guard let window else { return }
        position(window)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        takeInitialFocus()
    }

    private func takeInitialFocus() {
        if let quickPick = contentController as? ExtensionQuickPickViewController {
            quickPick.focusSearchField()
        } else if let inputBox = contentController as? ExtensionInputBoxViewController {
            inputBox.focusField()
        }
    }

    // MARK: - Dismiss

    /// The single dismissal path, entered once however it was asked for —
    /// see `isDismissing`.
    override func close() {
        guard !isDismissing else { return }
        isDismissing = true
        defer { isDismissing = false }
        super.close()
    }

    /// Horizontally centred, near the top, on the screen the pointer is on.
    /// Copied in behaviour from `CommandPaletteWindowController.position(_:)`
    /// (`:160-173`): the pointer rather than the key window, because a
    /// system-global chooser may open with no window of this app on screen
    /// at all (`:152-159`).
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

extension ExtensionPickerWindowController: NSWindowDelegate {

    /// Losing the keyboard means the user is doing something else — unless
    /// `ignoreFocusOut` says to stay up regardless.
    func windowDidResignKey(_ notification: Notification) {
        guard !ignoreFocusOut, !isDismissing, window?.isVisible == true else { return }
        close()
    }

    /// Every dismissal — Return, Escape, a focus loss, or the presenter
    /// closing the panel after an accepted answer — lands here exactly once.
    func windowWillClose(_ notification: Notification) {
        onDismiss()
    }
}
