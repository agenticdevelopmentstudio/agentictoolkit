import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreUI
import AgenticToolkitCoreMacOS

/// One conversation, lifted out of the merged feed and laid over it.
///
/// A feed of several sessions is readable and still hard to *follow*: the reply
/// to the line you are reading is four rows down, under two other projects'
/// traffic. Pulling one session to the front — same rows, same bubbles, nothing
/// else on the timeline — is what makes it a conversation again, and blurring
/// the feed behind it is what says this is a closer look at that feed rather
/// than a different window.
///
/// It is a ``ChatView`` over an ``NSVisualEffectView``, which means it is the
/// same transcript UI as the thing it covers: a fix to bubbles, theming or
/// scroll anchoring lands in both at once. What it adds is only the layering —
/// the blur, the fade, and the several ways a reader says "done".
@MainActor
public final class ConversationFocusOverlay: NSView {

    /// Length of the blend in and out.
    ///
    /// Short enough to read as the same surface changing rather than a window
    /// opening — a peek is held down for a moment, and an animation that outlasts
    /// the gesture is just a delay.
    public static let fadeDuration: TimeInterval = 0.2

    private let backdrop = NSVisualEffectView()
    private let chatView: ChatView
    private let session: FeedChatSession
    private let viewModel: AIChatViewModel

    private var isDismissing = false

    /// Fired once the overlay has begun to go away, so the owner can drop its
    /// reference without waiting out the fade.
    public var onDismissed: (() -> Void)?

    /// - Parameters:
    ///   - refreshInterval: how often this one conversation is re-read. The same
    ///     cadence as the feed underneath, so a reply lands in both together.
    ///   - load: reads *this* conversation, already narrowed to its session.
    ///   - onJump: the row's jump control was used — leave for the real thing.
    public init(
        refreshInterval: Duration,
        load: @escaping FeedChatSession.Loader,
        onJump: ((ChatMessage) -> Void)?
    ) {
        let session = FeedChatSession(refreshInterval: refreshInterval, load: load)
        self.session = session
        self.viewModel = AIChatViewModel(session: session)
        self.chatView = ChatView(viewModel: self.viewModel)
        super.init(frame: .zero)

        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        accessibilityID("conversation-focus.overlay")

        backdrop.material = .hudWindow
        // `.withinWindow`: what is being blurred is the feed directly behind
        // this view, not the desktop — this is a layer over a window, not a
        // window over a screen.
        backdrop.blendingMode = .withinWindow
        backdrop.state = .active
        backdrop.translatesAutoresizingMaskIntoConstraints = false

        // No surface of its own: an opaque chat painted over the blur would hide
        // exactly what the blur is there to show.
        chatView.drawsBackground = false
        // Same reason the feed's composer is greyed rather than removed — this
        // is a conversation being read, and a transcript with the entry field
        // cut out reads as a different kind of view rather than a read-only one.
        chatView.isComposerEnabled = false
        // Only the jump control. A press anywhere else on a row has to reach
        // this view, which reads it as "done" — see ``mouseDown(with:)``.
        chatView.rowActions = .init(onJump: onJump)
        chatView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(backdrop)
        addSubview(chatView)

        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
            chatView.topAnchor.constraint(equalTo: topAnchor),
            chatView.leadingAnchor.constraint(equalTo: leadingAnchor),
            chatView.trailingAnchor.constraint(equalTo: trailingAnchor),
            chatView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    deinit { session.close() }

    // MARK: - Present / dismiss

    /// Covers `host` entirely and blends in.
    public func present(in host: NSView) {
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

    /// Blends out and removes itself. Safe to call twice — a reader can press
    /// Escape and click in the same breath, and the second one is not a second
    /// dismissal.
    public func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true

        // Stopped now rather than in `deinit`: the fade is a fifth of a second
        // in which a poll would otherwise land and rebuild a transcript nobody
        // is going to see.
        session.close()
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

    // MARK: - Dismissal gestures

    /// Anything that isn't a live control means "done".
    ///
    /// This works by *not* being reached: an enabled control — the scroller, the
    /// jump button — handles its own press and the event stops there. Everything
    /// else (the blur, the transcript's empty space, a row, the greyed composer)
    /// passes the press up the responder chain, and this view is what it reaches.
    public override func mouseDown(with event: NSEvent) {
        dismiss()
    }

    /// Escape and Return take the overlay down.
    ///
    /// A key *equivalent* rather than `keyDown`: the window offers every key-down
    /// to this subtree before the responder chain sees it, so the two keys are
    /// caught without making the overlay first responder — which would cost the
    /// transcript the arrow keys and the page keys that make it readable.
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard !isDismissing, Self.dismissKeyCodes.contains(event.keyCode) else {
            return super.performKeyEquivalent(with: event)
        }
        dismiss()
        return true
    }

    /// Escape, Return, and the keypad's Enter. Escape is the cancel every macOS
    /// sheet answers to; Return is what a reader who came here by pressing
    /// something presses again.
    private static let dismissKeyCodes: Set<UInt16> = [53, 36, 76]
}
