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
/// It is a ``ChatView`` over the blurred ground ``DismissibleOverlayView``
/// supplies, which means it is the same transcript UI as the thing it covers: a
/// fix to bubbles, theming or scroll anchoring lands in both at once. What it
/// adds to the overlay is only the conversation — the poll that keeps it current
/// and the one session it is narrowed to.
@MainActor
public final class ConversationFocusOverlay: DismissibleOverlayView {

    private let chatView: ChatView
    private let session: FeedChatSession
    private let viewModel: AIChatViewModel

    /// - Parameters:
    ///   - refreshInterval: how often this one conversation is re-read. The same
    ///     cadence as the feed underneath, so a reply lands in both together.
    ///   - load: reads *this* conversation, already narrowed to its session.
    ///   - seed: the rows the feed underneath already had for this session, so
    ///     the overlay fades in holding the conversation rather than filling in
    ///     after it has arrived.
    ///   - lineLimit: how many lines of a message a row shows before offering
    ///     the rest — see ``ChatView/bubbleLineLimit``. Nil for the reader who
    ///     came here to read one of them whole, which is what a feed that caps
    ///     its rows sends them here for.
    ///   - send: types a line into the session this conversation belongs to, as
    ///     if it had been typed at its own terminal. Nil leaves the composer
    ///     disabled, which is what a session nothing can be written to looks
    ///     like.
    public init(
        refreshInterval: Duration,
        load: @escaping FeedChatSession.Loader,
        seed: [ChatMessage] = [],
        lineLimit: Int?,
        send: FeedChatSession.Sender? = nil
    ) {
        // The seed goes to the session as well as to the view model. The view
        // model's copy is what is drawn; the session's is what it will publish
        // *around* — and a line typed in the second before the first read lands
        // publishes the transcript as the session knows it, which without this
        // is nothing at all. The overlay would blank the conversation the
        // moment somebody answered it.
        let session = FeedChatSession(
            refreshInterval: refreshInterval, send: send, initial: seed, load: load)
        self.session = session
        self.viewModel = AIChatViewModel(session: session, initial: seed)
        self.chatView = ChatView(viewModel: self.viewModel)
        super.init(material: .hudWindow)

        accessibilityID("conversation-focus.overlay")

        // No surface of its own: an opaque chat painted over the blur would hide
        // exactly what the blur is there to show.
        chatView.drawsBackground = false
        // One conversation is the one place typing has an unambiguous
        // destination — the merged feed behind it has no single session to write
        // to, which is why its composer stays grey. Without a sender there is
        // still nowhere to write, and the composer is greyed rather than removed
        // for the same reason it is in the feed: a transcript with the entry
        // field cut out reads as a different kind of view, not a read-only one.
        chatView.isComposerEnabled = session.canSend
        chatView.bubbleLineLimit = lineLimit
        // No row actions at all. `onOpen` would open the conversation the reader
        // is already inside, and the app icon it would draw says which
        // application each row is running in — a question a *merged* feed asks
        // and this view has already answered: every row here is the same session.
        // With both unset the bubbles keep the double click, where it means
        // "select this word", and a press that no bubble took reaches this view,
        // which reads it as "done".
        chatView.rowActions = .init()
        chatView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(chatView)
        NSLayoutConstraint.activate([
            chatView.topAnchor.constraint(equalTo: topAnchor),
            chatView.leadingAnchor.constraint(equalTo: leadingAnchor),
            chatView.trailingAnchor.constraint(equalTo: trailingAnchor),
            chatView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    /// Presented, and handed the keys when there is anywhere for them to go.
    ///
    /// A reader who opened one conversation to answer it should not have to
    /// click the composer first, and the overlay covers the whole window, so
    /// nothing else here is competing for them. An overlay over a session that
    /// cannot be written to leaves the keys where they were, because its
    /// composer is disabled and would only swallow them.
    public override func present(in host: NSView) {
        super.present(in: host)
        if session.canSend { chatView.focusInput() }
    }

    /// Return is the composer's while the composer has the keys.
    ///
    /// ``DismissibleOverlayView`` takes Return as "done", which is right for a
    /// transcript being read and wrong the moment there is something to type
    /// into: the reader pressing Return at the end of a line means *send it*,
    /// and an overlay that vanished instead would throw the line away. Escape
    /// still closes from anywhere, so there is always a way out.
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if Self.sendKeyCodes.contains(event.keyCode), chatView.isComposerFocused {
            return false
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Return and the keypad's Enter.
    private static let sendKeyCodes: Set<UInt16> = [36, 76]

    /// Re-read this conversation now.
    ///
    /// The overlay polls on its own, but the feed underneath is pushed to when
    /// the daemon says something changed; forwarding that push is what keeps
    /// the closer look as current as the thing it was lifted out of, rather
    /// than up to one interval behind it.
    public func refresh() { session.refresh() }

    deinit { session.close() }

    /// Stopped before the fade rather than in `deinit`: the fade is a fifth of a
    /// second in which a poll would otherwise land and rebuild a transcript
    /// nobody is going to see.
    public override func willDismiss() {
        session.close()
    }
}
