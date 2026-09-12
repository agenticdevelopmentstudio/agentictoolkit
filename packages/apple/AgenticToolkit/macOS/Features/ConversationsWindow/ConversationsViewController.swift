import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreUI
import AgenticToolkitCoreMacOS

/// A read-only chat over *other people's* conversations: every observed session
/// on one timeline, newest at the bottom, each row naming where it came from.
///
/// It is a `ChatView` and not a list because that is what it is — a group chat
/// nobody in this process is a member of. Hosting it on the chat stack means
/// the bubbles, the theming, the scroll anchoring and the composer are the ones
/// the chat window already uses, and a fix to any of them arrives here too.
///
/// What this type owns is only the parts a *feed* adds: the poll (through
/// ``FeedChatSession``), the work-output filter, and handing a row tap back to
/// whoever knows what the row points at. It knows nothing about where the
/// conversations come from — that is the ``Load`` closure, supplied by the host.
/// The work-output filter, shared between the main actor that sets it and the
/// feed's poll that reads it. A one-field lock box rather than an actor because
/// the read sits inside a loader that should not have to await anything.
private final class WorkOutputFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

@MainActor
public final class ConversationsViewController: NSViewController {

    /// Reads the feed as it stands, oldest first. `includeWorkOutput` asks for
    /// the agent's narration of its own work as well as what it said to the
    /// human. Returning nil means "couldn't read it" and keeps what is on
    /// screen — a momentary failure is not an empty feed.
    public typealias Load = @Sendable (_ includeWorkOutput: Bool) async -> [ChatMessage]?

    /// Whether the agent's work output (its narration and, where captured, its
    /// thinking) is shown alongside what it actually said to the human.
    ///
    /// Off by default, and that is the whole reason the feed is readable:
    /// measured against live transcripts, narration outnumbers replies two to
    /// one and runs an order of magnitude shorter — showing it by default
    /// buries the conversation in "let me check X".
    public var includeWorkOutput: Bool {
        get { workOutputFlag.value }
        set {
            guard newValue != workOutputFlag.value else { return }
            workOutputFlag.value = newValue
            refresh()
        }
    }

    /// Called when a row is clicked, with the message that row rendered. The
    /// host reads ``ChatMessage/Attribution/sourceID`` to decide where to go.
    public var onRowTap: ((ChatMessage) -> Void)? {
        didSet { chatView?.onRowTap = onRowTap }
    }

    private let session: FeedChatSession
    private let viewModel: AIChatViewModel
    private let workOutputFlag: WorkOutputFlag
    private var chatView: ChatView?

    /// - Parameters:
    ///   - refreshInterval: how often the feed is re-read. A transcript on disk
    ///     has no push channel, so this is the whole of the window's liveness.
    ///   - load: reads the feed.
    public init(refreshInterval: Duration = .seconds(5), load: @escaping Load) {
        // The filter is read at load time rather than captured by value, so
        // toggling it changes the *next* read without rebuilding the session.
        let flag = WorkOutputFlag()
        self.workOutputFlag = flag
        let session = FeedChatSession(refreshInterval: refreshInterval) {
            await load(flag.value)
        }
        self.session = session
        self.viewModel = AIChatViewModel(session: session)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    deinit { session.close() }

    public override func loadView() {
        let chatView = ChatView(viewModel: viewModel)
        // The composer stays, greyed: this is a conversation being watched, not
        // one being joined, and a chat with the entry field cut out reads as a
        // different kind of window rather than a read-only one.
        chatView.isComposerEnabled = false
        chatView.onRowTap = onRowTap
        chatView.translatesAutoresizingMaskIntoConstraints = false
        self.chatView = chatView
        self.view = chatView
    }

    /// Re-reads the feed now rather than at the next interval — for a filter
    /// change, or a host that knows something just happened.
    public func refresh() { session.refresh() }
}
