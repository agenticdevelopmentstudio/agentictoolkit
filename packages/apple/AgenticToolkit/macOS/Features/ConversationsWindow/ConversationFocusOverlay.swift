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
    ///   - lineLimit: how many lines of a message a row shows before offering
    ///     the rest — see ``ChatView/bubbleLineLimit``. The same cap as the feed,
    ///     so a message does not change length on the way into the overlay.
    ///   - onJump: the row's app icon was used — leave for the real thing.
    public init(
        refreshInterval: Duration,
        load: @escaping FeedChatSession.Loader,
        lineLimit: Int?,
        onJump: ((ChatMessage) -> Void)?
    ) {
        let session = FeedChatSession(refreshInterval: refreshInterval, load: load)
        self.session = session
        self.viewModel = AIChatViewModel(session: session)
        self.chatView = ChatView(viewModel: self.viewModel)
        super.init(material: .hudWindow)

        accessibilityID("conversation-focus.overlay")

        // No surface of its own: an opaque chat painted over the blur would hide
        // exactly what the blur is there to show.
        chatView.drawsBackground = false
        // Same reason the feed's composer is greyed rather than removed — this
        // is a conversation being read, and a transcript with the entry field
        // cut out reads as a different kind of view rather than a read-only one.
        chatView.isComposerEnabled = false
        chatView.bubbleLineLimit = lineLimit
        // No `onOpen`: this *is* the conversation, so there is nothing for a
        // double click to open — and with the handler unset the bubbles keep the
        // gesture, where it means "select this word". A press that no bubble and
        // no control took reaches this view, which reads it as "done".
        chatView.rowActions = .init(onJump: onJump)
        chatView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(chatView)
        NSLayoutConstraint.activate([
            chatView.topAnchor.constraint(equalTo: topAnchor),
            chatView.leadingAnchor.constraint(equalTo: leadingAnchor),
            chatView.trailingAnchor.constraint(equalTo: trailingAnchor),
            chatView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    deinit { session.close() }

    /// Stopped before the fade rather than in `deinit`: the fade is a fifth of a
    /// second in which a poll would otherwise land and rebuild a transcript
    /// nobody is going to see.
    public override func willDismiss() {
        session.close()
    }
}
