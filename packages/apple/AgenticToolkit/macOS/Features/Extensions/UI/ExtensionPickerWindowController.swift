//
//  ExtensionPickerWindowController.swift
//  AgenticToolkit
//

import AppKit

/// The floating panel `showQuickPick` and `showInputBox` share.
///
/// The panel itself is `FloatingChooserPanelController`'s — the same one the
/// command palette comes up in, and documented there. Three things are this
/// type's own:
///
/// 1. **Sized from `content.preferredContentSize`**, not from two numbers
///    spelled here — the quick pick wants a fixed list size, the input box
///    wants whatever height its Auto Layout stack comes to, and one `init`
///    serving both is why the size is asked for rather than stated — with the
///    forced `loadViewIfNeeded()` that read depends on.
/// 2. **`ignoreFocusOut`.** A focus loss dismisses only when it is false —
///    that is what `QuickPickOptions.ignoreFocusOut` /
///    `InputBoxOptions.ignoreFocusOut` are for, and a panel that closed anyway
///    would make the flag a lie.
/// 3. **`onDismiss` fires exactly once, from the base's close hook, whatever
///    closed the window.** It means "the user left without answering." The
///    content controllers report acceptance on their own callbacks and the
///    presenter closes the window afterwards, so acceptance is not also
///    reported here as a dismissal — the presenter's `OnceOnlyContinuation`
///    (part 1) is what makes that ordering safe, by ignoring the second
///    `finish` call, rather than a second flag on this type.
@MainActor
final class ExtensionPickerWindowController: FloatingChooserPanelController {

    private let ignoreFocusOut: Bool

    /// The user left without answering. Fired at most once per panel.
    var onDismiss: () -> Void = {}

    init(content: NSViewController, ignoreFocusOut: Bool) {
        self.ignoreFocusOut = ignoreFocusOut

        // Force the content controller's view to load *before* reading
        // `preferredContentSize` below. `NSViewController.loadView` runs on the
        // first `.view` access, not on `.preferredContentSize` itself:
        // `ExtensionQuickPickViewController` sets the property in its own
        // `init` (so it is available either way), but
        // `ExtensionInputBoxViewController` computes and sets it from its
        // assembled Auto Layout height at the *end* of `loadView()` — reading
        // the property before that method has run reads a value that was never
        // set, and the panel collapses to zero.
        //
        // Here and not in the base: the rect is an *argument* to `super.init`,
        // so it is evaluated before any of the base's own body runs.
        content.loadViewIfNeeded()

        super.init(
            content: content,
            contentRect: NSRect(origin: .zero, size: content.preferredContentSize)
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var dismissesOnFocusLoss: Bool { !ignoreFocusOut }

    /// The field keeps first responder for the panel's whole life; which field
    /// that is depends on which of the two contents is hosted.
    override func takeInitialFocus() {
        if let quickPick = contentController as? ExtensionQuickPickViewController {
            quickPick.focusSearchField()
        } else if let inputBox = contentController as? ExtensionInputBoxViewController {
            inputBox.focusField()
        }
    }

    /// Every dismissal — Return, Escape, a focus loss, or the presenter closing
    /// the panel after an accepted answer — lands here exactly once.
    override func panelWillClose() {
        onDismiss()
    }
}
