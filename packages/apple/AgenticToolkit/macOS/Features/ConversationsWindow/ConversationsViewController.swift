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
    /// human. `sourceID` narrows the read to one conversation — nil is the
    /// merged feed, and a value is what the focus overlay asks for. Returning
    /// nil means "couldn't read it" and keeps what is on screen — a momentary
    /// failure is not an empty feed.
    ///
    /// The narrowing is a parameter rather than a filter applied to the merged
    /// result because the merged result is a *page*: the newest few hundred
    /// lines across every session, of which one session's share may be two. A
    /// conversation read out of that has holes in it.
    public typealias Load = @Sendable (
        _ includeWorkOutput: Bool,
        _ sourceID: String?
    ) async -> [ChatMessage]?

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

    /// Called when a row's jump control is used, with the message that row
    /// rendered. The host reads ``ChatMessage/Attribution/sourceID`` to decide
    /// where to go.
    ///
    /// Named for what it does rather than for the gesture that fires it, because
    /// the gesture moved: clicking a row now opens the focus overlay, and
    /// leaving for the real session is what the control on the row's inside edge
    /// is for. A click that navigates away is the wrong default in a feed you
    /// are reading — it costs you your place to answer a question the overlay
    /// answers without moving.
    public var onGoToSource: ((ChatMessage) -> Void)?

    /// Types a line into one observed session, as if it had been typed at that
    /// session's own terminal. Given the session's
    /// ``ChatMessage/Attribution/sourceID`` and the text; returns nil when the
    /// line was handed over, or the reason it could not be, which the reader
    /// sees under the message they typed.
    ///
    /// Only the focus overlay offers it: the merged feed has no single session
    /// a line would belong to, so its composer stays disabled however this is
    /// set. Left nil — a host with no way to reach a terminal — the overlay's
    /// composer is disabled too.
    public var onSendToSource: (@Sendable (String, String) async -> String?)?

    /// Called when the set of sessions appearing in the feed changes, on the
    /// main actor. The shelf beside the feed draws exactly this.
    public var onRosterChanged: (([ConversationsSessionFilter.Session]) -> Void)?

    private let session: FeedChatSession
    private let viewModel: AIChatViewModel
    private let workOutputFlag: WorkOutputFlag
    private let sessionFilter: ConversationsSessionFilter
    private let load: Load
    private let refreshInterval: Duration
    private var chatView: ChatView?
    private var overlay: ConversationFocusOverlay?

    /// How many lines of a message a feed row shows before it truncates and
    /// offers the rest.
    ///
    /// Eight is a paragraph — enough to tell what a reply is about and decide
    /// whether to open it, short enough that three long messages in a row still
    /// leave the timeline visible. Deciding to open it is the point: the
    /// overlay is uncapped, so the rest of the message is one click away rather
    /// than nowhere.
    public static let bubbleLineLimit = 8

    /// - Parameters:
    ///   - refreshInterval: how often the feed is re-read. A transcript on disk
    ///     has no push channel, so this is the whole of the window's liveness.
    ///   - load: reads the feed.
    public init(refreshInterval: Duration = .seconds(5), load: @escaping Load) {
        // The filter is read at load time rather than captured by value, so
        // toggling it changes the *next* read without rebuilding the session.
        let flag = WorkOutputFlag()
        self.workOutputFlag = flag
        self.load = load
        self.refreshInterval = refreshInterval
        // The merged page is read whole and narrowed here, never narrowed at the
        // source: the roster is read off that page, so a read that already left
        // a session out would also leave out the only row that could bring it
        // back.
        let sessionFilter = ConversationsSessionFilter()
        self.sessionFilter = sessionFilter
        let session = FeedChatSession(refreshInterval: refreshInterval) {
            guard let messages = await load(flag.value, nil) else { return nil }
            return sessionFilter.apply(to: messages)
        }
        self.session = session
        self.viewModel = AIChatViewModel(session: session)
        super.init(nibName: nil, bundle: nil)

        // The poll runs off the main actor; the shelf lives on it.
        sessionFilter.onRosterChanged = { [weak self] roster in
            Task { @MainActor in self?.onRosterChanged?(roster) }
        }
    }

    /// The sessions the feed is currently not drawing, by
    /// ``ChatMessage/Attribution/sourceID``. Setting it re-reads immediately, so
    /// a tick in the shelf lands on the timeline rather than at the next poll.
    public var hiddenSessions: Set<String> {
        get { sessionFilter.hidden }
        set { setHiddenSessions(newValue) }
    }

    /// Hides everything in `ids` and shows everything else.
    public func setHiddenSessions(_ ids: Set<String>) {
        guard ids != sessionFilter.hidden else { return }
        sessionFilter.hidden = ids
        refresh()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    deinit { session.close() }

    /// A plain container holding the feed, so the overlay is the feed's
    /// *sibling* rather than its subview — a chat view rebuilds its transcript
    /// on every layout pass, and nothing else belongs inside that.
    public override func loadView() {
        let chatView = ChatView(viewModel: viewModel)
        // The composer stays, greyed: this is a conversation being watched, not
        // one being joined, and a chat with the entry field cut out reads as a
        // different kind of window rather than a read-only one.
        chatView.isComposerEnabled = false
        chatView.bubbleLineLimit = Self.bubbleLineLimit
        // A merged feed is a list before it is a conversation, so it behaves
        // like one: a row can be picked, the arrows walk them, Return opens the
        // conversation a row came from and Shift-Return leaves for it.
        chatView.isRowSelectionEnabled = true
        chatView.rowActions = .init(
            onOpen: { [weak self] message in self?.presentFocus(on: message) },
            onJump: { [weak self] message in self?.onGoToSource?(message) }
        )
        chatView.translatesAutoresizingMaskIntoConstraints = false
        self.chatView = chatView

        let container = NSView()
        container.addSubview(chatView)
        NSLayoutConstraint.activate([
            // The safe area's top, not the container's: the window's titlebar is
            // transparent so the shelf beside this can run full height, and a
            // transcript pinned to the container scrolls its text up behind the
            // traffic lights with nothing to blur it.
            chatView.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
            chatView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            chatView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            chatView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        self.view = container
    }

    /// Re-reads the feed now rather than at the next interval — for a filter
    /// change, or a host that knows something just happened.
    public func refresh() {
        session.refresh()
        // The overlay is a second reader of the same conversation, so a push
        // that reaches the feed has to reach it too — otherwise the closer look
        // is the *less* current of the two views, which is backwards.
        overlay?.refresh()
    }

    // MARK: - Focus overlay

    /// Lifts one conversation out of the feed and lays it over the top.
    private func presentFocus(on message: ChatMessage) {
        guard let sourceID = message.attribution?.sourceID, !sourceID.isEmpty else { return }
        dismissFocus()

        let flag = workOutputFlag
        let load = self.load
        let overlay = ConversationFocusOverlay(
            refreshInterval: refreshInterval,
            load: { await load(flag.value, sourceID) },
            // What this session's rows already say, taken straight off the feed
            // behind. A page of the merged feed may hold only part of the
            // conversation, and the first read replaces it — but it is the part
            // the reader just double-clicked, so the overlay opens on it.
            seed: viewModel.messages.filter { $0.attribution?.sourceID == sourceID },
            // No cap here. The feed truncates because it is several
            // conversations on one timeline, where a forty-line message would
            // be the whole window; this is the one conversation the reader
            // asked to see, and reading the rest of that message is most of
            // what asking meant.
            lineLimit: nil,
            send: onSendToSource.map { send in
                { @Sendable text in await send(sourceID, text) }
            }
        )
        overlay.onDismissed = { [weak self, weak overlay] in
            if self?.overlay === overlay { self?.overlay = nil }
        }
        self.overlay = overlay
        overlay.present(in: view)
    }

    private func dismissFocus() {
        overlay?.dismiss()
        overlay = nil
    }
}
