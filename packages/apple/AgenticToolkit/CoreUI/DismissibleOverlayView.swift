import AppKit

/// A layer laid over another view: a blurred ground, a short blend in and out,
/// and the several ways a reader says "done".
///
/// Two overlays in this toolkit are the same shape — one conversation lifted out
/// of a merged feed, and one message opened to its full length — and what they
/// share is not their content but their *manners*: cover the host entirely, fade
/// rather than appear, and go away on Escape, on Return, or on a press no
/// control took. Those manners live here so a fix to any of them lands in both,
/// and so the next overlay starts with them rather than re-deriving them.
///
/// A subclass adds its content as ordinary subviews — the backdrop is already at
/// the bottom of the stack — and overrides ``willDismiss()`` for whatever it has
/// to stop.
@MainActor
open class DismissibleOverlayView: NSView {

    /// Length of the blend in and out.
    ///
    /// Short enough to read as the same surface changing rather than a window
    /// opening: an overlay a reader is clicking through should not make them
    /// wait for it twice.
    public static let fadeDuration: TimeInterval = 0.2

    /// Escape, Return, and the keypad's Enter. Escape is the cancel every macOS
    /// sheet answers to; Return is what a reader who came here by pressing
    /// something presses again.
    public static let dismissKeyCodes: Set<UInt16> = [53, 36, 76]

    /// Fired once the overlay has begun to go away, so the owner can drop its
    /// reference without waiting out the fade.
    public var onDismissed: (() -> Void)?

    /// True from the first ``dismiss()`` onwards. A reader can press Escape and
    /// click in the same breath, and the second one is not a second dismissal.
    public private(set) var isDismissing = false

    private let backdrop = NSVisualEffectView()

    /// - Parameter material: what the blurred ground is made of. `.hudWindow` is
    ///   the heavy one, for an overlay that wants the thing behind it legible as
    ///   context and not as content.
    public init(material: NSVisualEffectView.Material = .hudWindow) {
        super.init(frame: .zero)

        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        backdrop.material = material
        // `.withinWindow`: what is being blurred is the view directly behind
        // this one, not the desktop — this is a layer over a window, not a
        // window over a screen.
        backdrop.blendingMode = .withinWindow
        backdrop.state = .active
        backdrop.translatesAutoresizingMaskIntoConstraints = false

        addSubview(backdrop)
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    // MARK: - Present / dismiss

    /// Covers `host` entirely and blends in.
    open func present(in host: NSView) {
        host.addSubview(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: host.topAnchor),
            leadingAnchor.constraint(equalTo: host.leadingAnchor),
            trailingAnchor.constraint(equalTo: host.trailingAnchor),
            bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])

        alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            animator().alphaValue = 1
        }
    }

    /// Blends out and removes itself. Safe to call twice.
    public func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true

        willDismiss()
        onDismissed?()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            // The handler is declared non-isolated but AppKit runs it on the
            // main thread — asserting that is what keeps the removal here,
            // rather than hopping to a later turn where the reader would watch
            // a fully transparent overlay still swallowing their clicks.
            MainActor.assumeIsolated { self?.removeFromSuperview() }
        }
    }

    /// Called once, before the fade out starts. Override to stop whatever the
    /// overlay had running — the fade is a fifth of a second in which a poll
    /// would otherwise land and rebuild something nobody is going to see.
    open func willDismiss() {}

    // MARK: - Dismissal gestures

    /// Anything that isn't a live control means "done".
    ///
    /// This works by *not* being reached: a control that wants the press — a
    /// scroller, a button, a selectable message you are copying out of — handles
    /// it and the event stops there. Everything else passes the press up the
    /// responder chain, and this view is what it reaches.
    open override func mouseDown(with event: NSEvent) {
        dismiss()
    }

    /// Escape and Return take the overlay down.
    ///
    /// A key *equivalent* rather than `keyDown`: the window offers every key-down
    /// to this subtree before the responder chain sees it, so the keys are caught
    /// without making the overlay first responder — which would cost the content
    /// the arrow keys and the page keys that make it readable.
    ///
    /// Subviews are offered the event first, so an overlay stacked on top of this
    /// one — a message expanded over a conversation — is the one Escape closes.
    open override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        guard !isDismissing, Self.dismissKeyCodes.contains(event.keyCode) else { return false }
        dismiss()
        return true
    }
}
