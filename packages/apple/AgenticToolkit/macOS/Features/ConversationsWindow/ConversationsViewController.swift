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
/// feed's poll that reads it. A lock box rather than an actor because the read
/// sits inside a loader that should not have to await anything.
///
/// Two halves, because there are two things that turn it on: what the reader
/// asked for, and single mode insisting on it regardless. Kept apart rather
/// than folded together so that leaving single mode gives the reader their own
/// setting back instead of whatever the mode left behind.
private final class WorkOutputFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var preferred = false
    private var forced = false

    /// What the next read should actually ask for.
    var value: Bool {
        lock.lock(); defer { lock.unlock() }
        return preferred || forced
    }

    /// The reader's own setting, with nothing overriding it.
    var preference: Bool {
        lock.lock(); defer { lock.unlock() }
        return preferred
    }

    /// Whether something other than the reader is insisting on work output.
    var isForced: Bool {
        lock.lock(); defer { lock.unlock() }
        return forced
    }

    /// Each setter reports whether ``value`` moved, so the caller re-reads the
    /// feed only when the answer would differ — a refresh that asks the same
    /// question costs a round trip and replaces the reader's rows with copies.
    func setPreference(_ newValue: Bool) -> Bool { mutate { preferred = newValue } }

    func setForced(_ newValue: Bool) -> Bool { mutate { forced = newValue } }

    private func mutate(_ change: () -> Void) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let before = preferred || forced
        change()
        return (preferred || forced) != before
    }
}

/// The newest thing the agent was doing, as the feed's last read found it —
/// written by the poll, off the main actor, and read by the status line on it.
///
/// Taken from a read that carries work output whether or not the bubbles do,
/// which is the point: single mode shows the agent's work here, on one line that
/// is replaced as it moves, rather than as a stack of bubbles burying what it
/// said.
private final class FeedWorkStatus: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: (sourceID: String, text: String)?
    private var onChange: (@Sendable () -> Void)?

    func set(onChange: (@Sendable () -> Void)?) {
        lock.lock(); self.onChange = onChange; lock.unlock()
    }

    /// What `sourceID` was last seen doing, or nil when its newest line was not
    /// work — a reply, or a prompt it has not started on.
    func text(for sourceID: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return latest?.sourceID == sourceID ? latest?.text : nil
    }

    /// Records the newest line of `messages` if it is work output. Tells the
    /// main actor only when the answer moved, since this runs on every poll.
    func note(_ messages: [ChatMessage]) {
        let next = messages.last.flatMap { last -> (String, String)? in
            guard last.isWorkOutput, let id = last.attribution?.sourceID,
                  let line = Self.firstLine(of: last.text) else { return nil }
            return (id, line)
        }
        lock.lock()
        let moved = next?.0 != latest?.sourceID || next?.1 != latest?.text
        latest = next.map { (sourceID: $0.0, text: $0.1) }
        let onChange = self.onChange
        lock.unlock()
        if moved { onChange?() }
    }

    /// The first line with anything on it: a status line has room for one, and
    /// the first is the one that says what the rest is about.
    private static func firstLine(of text: String) -> String? {
        text.split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }
}

/// The host's write, shared between the main actor that supplies it and the
/// session's sender, which runs off it.
///
/// A box rather than a captured closure because the host supplies the write
/// *after* the session exists. Where the line goes is not in here: the session
/// hands over the destination the line was typed at, so a reader who moves on
/// before the write runs does not take the line with them.
private final class FeedSendTarget: @unchecked Sendable {
    private let lock = NSLock()
    private var send: (@Sendable (String, String) async -> String?)?

    func set(send: (@Sendable (String, String) async -> String?)?) {
        lock.lock(); self.send = send; lock.unlock()
    }

    /// Whether there is something to write with.
    var isReady: Bool {
        lock.lock(); defer { lock.unlock() }
        return send != nil
    }

    private func current() -> (@Sendable (String, String) async -> String?)? {
        lock.lock(); defer { lock.unlock() }
        return send
    }

    func write(_ text: String, to destination: String?) async -> String? {
        // Read out of the lock before the await: `NSLock.lock()` is unavailable
        // from an async context, and a lock held across a suspension would be a
        // bug even where the compiler allowed it.
        guard let destination, let send = current() else {
            return "There is no single session to write to."
        }
        return await send(destination, text)
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
    ///
    /// `limit` is how many entries to read. It is asked for rather than fixed
    /// because hiding sessions in the shelf has to deepen the read — see
    /// ``ConversationsSessionFilter/pageDeepening`` — and only the host knows
    /// how to ask its source for more.
    public typealias Load = @Sendable (
        _ includeWorkOutput: Bool,
        _ sourceID: String?,
        _ limit: Int
    ) async -> [ChatMessage]?

    /// Whether the agent's work output (its narration and, where captured, its
    /// thinking) is shown alongside what it actually said to the human.
    ///
    /// Off by default, and that is the whole reason the feed is readable:
    /// measured against live transcripts, narration outnumbers replies two to
    /// one and runs an order of magnitude shorter — showing it by default
    /// buries the conversation in "let me check X".
    ///
    /// Single mode reads work output regardless (``isWorkOutputForced``): the
    /// narration is most of what following one session means, so it is shown —
    /// but as the status line over the composer, one line replaced as the agent
    /// moves, from a short read of its own. This setting still decides whether
    /// it is *also* drawn as bubbles, in either mode, and it stays the reader's
    /// own: leaving single mode gives it back unchanged.
    public var includeWorkOutput: Bool {
        get { workOutputFlag.preference }
        set {
            guard newValue != workOutputFlag.preference else { return }
            let moved = workOutputFlag.setPreference(newValue)
            if moved || workOutputFlag.isForced { refresh() }
        }
    }

    /// Whether work output is being shown whatever ``includeWorkOutput`` says —
    /// true for as long as the window is in single mode. For a host that greys
    /// out its own checkbox while the choice is not the reader's to make.
    public var isWorkOutputForced: Bool { workOutputFlag.isForced }

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
    /// In multi mode only the focus overlay offers it: a merged feed has no
    /// single session a line would belong to, so its own composer stays disabled
    /// however this is set. In single mode the window *is* one conversation, so
    /// the feed's composer is the one that takes the line. Left nil — a host with
    /// no way to reach a terminal — both are disabled.
    public var onSendToSource: (@Sendable (String, String) async -> String?)? {
        didSet {
            sendTarget.set(send: onSendToSource)
            updateComposer()
        }
    }

    /// Whether the window is reading one conversation or several.
    ///
    /// Single mode changes three things here, and all of them follow from there
    /// being exactly one session on the timeline: there is nothing left for the
    /// focus overlay to isolate, there is an unambiguous destination for a typed
    /// line, and there is nothing for the agent's narration to bury. So the
    /// overlay goes away, the composer comes alive, and the agent's work is
    /// shown on the status line whatever the reader's own setting says.
    public var selectionMode: ConversationsSelectionMode = .multi {
        didSet {
            guard selectionMode != oldValue else { return }
            if selectionMode == .single { dismissFocus() }
            let soloMoved = syncSolo()
            updateComposer()
            // Only when the answer actually moved — with the reader's own
            // setting already on and no conversation picked there is nothing to
            // re-read, and a refresh that asks the same question costs the
            // reader their rows.
            let forcedMoved = workOutputFlag.setForced(selectionMode == .single)
            if forcedMoved || soloMoved { refresh() }
        }
    }

    /// The conversation single mode reads, by
    /// ``ChatMessage/Attribution/sourceID`` — the shelf's pick, handed over by
    /// the split view. Kept while in multi mode, so going back to single mode
    /// goes back to the same conversation; it is only *read* in single mode.
    ///
    /// Nil falls back to whichever one session the hidden set leaves showing,
    /// which is what a feed used without a shelf has.
    ///
    /// A change re-reads after a short pause rather than at once: a reader
    /// holding an arrow key walks through a dozen conversations a second, and
    /// a read per step queues a dozen reads that cannot be called back, each
    /// landing after the one the reader stopped on.
    public var soloSessionID: String? {
        didSet {
            guard soloSessionID != oldValue else { return }
            guard syncSolo() else { return }
            updateComposer()
            scheduleRefresh()
        }
    }

    /// Called when the set of sessions appearing in the feed changes, on the
    /// main actor. The shelf beside the feed draws exactly this.
    public var onRosterChanged: (([ConversationsSessionFilter.Session]) -> Void)?

    /// Called when the reader hides or shows a session, with the whole hidden
    /// set. A host that wants the ticks to survive the window being closed
    /// writes this to a setting and hands it back through ``hiddenSessions``.
    public var onHiddenSessionsChanged: ((Set<String>) -> Void)?

    /// What each session is doing, by ``ChatMessage/Attribution/sourceID`` —
    /// the shelf's activity, handed over by the split view. In single mode the
    /// shown session's entry decides whether the status line is up at all: a
    /// transcript cannot say the agent has *finished*, only what it did last.
    public var activity: [String: SessionWatcher.SessionWatcherActivity] = [:] {
        didSet {
            guard activity != oldValue else { return }
            updateStatus()
        }
    }

    private let session: FeedChatSession
    private let viewModel: AIChatViewModel
    private let workOutputFlag: WorkOutputFlag
    private let sessionFilter: ConversationsSessionFilter
    private let sendTarget = FeedSendTarget()
    private let workStatus = FeedWorkStatus()
    /// Kept across updates so its animation runs on rather than restarting from
    /// its first frame on every poll.
    private var statusIcon: SessionWatcher.SessionWatcherActivityIconView?
    private let load: Load
    private let refreshInterval: Duration
    private let pageLimit: Int
    private var chatView: ChatView?
    private var overlay: ConversationFocusOverlay?
    private var pendingRefresh: Task<Void, Never>?

    /// How long a moved pick waits before the feed re-reads — long enough to
    /// swallow key repeat, short enough not to read as lag.
    static let soloSettle: Duration = .milliseconds(150)

    /// How many of one session's newest entries the status line reads. It
    /// shows the newest line only; the rest is slack for a read that races a
    /// turn ending.
    static let statusDepth = 20

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
    ///   - pageLimit: how many entries a read asks for while nothing is hidden.
    ///     A hidden session multiplies it, so that ticking a box changes *which*
    ///     conversations are on the timeline and not how much timeline there is.
    ///   - load: reads the feed.
    public init(
        refreshInterval: Duration = .seconds(5),
        pageLimit: Int = 200,
        load: @escaping Load
    ) {
        self.pageLimit = pageLimit
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
        let sendTarget = self.sendTarget
        let workStatus = self.workStatus
        let statusDepth = Self.statusDepth
        let session = FeedChatSession(
            refreshInterval: refreshInterval,
            // A sender from the start, resolved when a line is actually typed —
            // the host has not supplied the write yet. The session hands over
            // the destination the line was typed at. What decides whether the
            // composer is live is `canSend`, set below.
            send: { text, destination in await sendTarget.write(text, to: destination) },
            load: {
                // The bubbles ask for what the reader asked for, in either mode.
                // Single mode's work output comes from a read of its own below:
                // asked for here it would take the page's room from what the
                // agent said, and a page that is two thirds narration shows a
                // third of the conversation.
                let bubbles: [ChatMessage]
                if let solo = sessionFilter.solo {
                    // The merged page for the roster, the conversation's own
                    // read for the timeline — see `apply(page:conversation:solo:)`.
                    async let page = load(flag.preference, nil, pageLimit)
                    async let conversation = load(flag.preference, solo, pageLimit)
                    guard let page = await page, let conversation = await conversation else { return nil }
                    // A read the reader has already moved on from says nothing
                    // about the roster or the status line any more.
                    guard !Task.isCancelled else { return nil }
                    bubbles = sessionFilter.apply(page: page, conversation: conversation, solo: solo)
                } else {
                    // Deepened by whatever the last page lost to the hidden
                    // sessions, so the filter takes rows out of a bigger answer
                    // rather than out of the reader's scrollback.
                    let depth = pageLimit * sessionFilter.pageDeepening
                    guard let messages = await load(flag.preference, nil, depth) else { return nil }
                    guard !Task.isCancelled else { return nil }
                    bubbles = sessionFilter.apply(to: messages)
                }
                guard flag.isForced, !flag.preference else {
                    workStatus.note(bubbles)
                    return bubbles
                }
                // The status line's own read: the newest few entries of the
                // one conversation, work output included. A failed read leaves
                // the line saying what it said.
                if let target = sessionFilter.solo ?? sessionFilter.soleShownID,
                   let recent = await load(true, target, statusDepth) {
                    guard !Task.isCancelled else { return nil }
                    workStatus.note(recent.filter { $0.attribution?.sourceID == target })
                }
                // The loader was not asked for work output, but a source that
                // sends it anyway would put it back as bubbles.
                return bubbles.filter { !$0.isWorkOutput }
            })
        // Watched until told otherwise: the window opens on the merged feed,
        // which has no one session a typed line would belong to.
        session.canSend = false
        self.session = session
        self.viewModel = AIChatViewModel(session: session)
        super.init(nibName: nil, bundle: nil)

        // The poll runs off the main actor; the shelf lives on it.
        sessionFilter.onRosterChanged = { [weak self] roster in
            Task { @MainActor in
                guard let self else { return }
                self.onRosterChanged?(roster)
                // A roster that changed may have changed which single session is
                // on the timeline, and in single mode that is the composer's
                // destination.
                self.updateComposer()
            }
        }
        workStatus.set(onChange: { [weak self] in
            Task { @MainActor in self?.updateStatus() }
        })
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
        onHiddenSessionsChanged?(ids)
        updateComposer()
        refresh()
    }

    /// The one conversation single mode is reading — the destination a line
    /// typed into the feed's own composer would have. Nil in multi mode.
    ///
    /// The shelf's pick when there is one; otherwise whichever one session the
    /// hidden set leaves showing.
    private var singleDestination: String? {
        guard selectionMode == .single else { return nil }
        return soloSessionID ?? sessionFilter.soleShownID
    }

    /// Hands the pick to the filter while in single mode, and takes it away
    /// outside it. Reports whether what the filter reads moved.
    private func syncSolo() -> Bool {
        let solo = selectionMode == .single ? soloSessionID : nil
        guard sessionFilter.solo != solo else { return false }
        sessionFilter.solo = solo
        return true
    }

    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: Self.soloSettle)
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    /// Points the composer at the conversation single mode is reading, and turns
    /// it on only when there is one and something to write to it with.
    private func updateComposer() {
        let destination = singleDestination
        session.destinationID = destination
        let live = destination != nil && sendTarget.isReady
        session.canSend = live
        chatView?.isComposerEnabled = live
        updateStatus()
    }

    /// Says what the shown session is doing over the composer, for as long as
    /// it is doing anything.
    ///
    /// Single mode only: over a merged feed the line would have to pick one
    /// conversation to talk about, and the shelf already shows every session's
    /// glyph. What it says is the agent's newest line of work when that is the
    /// newest thing in the transcript, and otherwise just the state — a reply
    /// written before the current turn started says nothing about the turn.
    private func updateStatus() {
        guard let chatView else { return }
        guard let id = singleDestination,
              let state = activity[id], state != .idle else {
            chatView.setStatus(nil, icon: nil)
            return
        }
        let icon = statusIcon ?? SessionWatcher.SessionWatcherActivityIconView(
            activity: state, isSummarizing: false)
        if statusIcon == nil {
            icon.observeTheme { view, palette in view.applyTheme(palette) }
            statusIcon = icon
        }
        icon.update(activity: state, isSummarizing: false)
        let fallback = state == .waiting ? "Waiting for you…" : "Working…"
        chatView.setStatus(workStatus.text(for: id) ?? fallback, icon: icon)
    }

    /// What the status line over the composer says right now, or nil when it is
    /// down — for a test, or a host's scripting surface.
    public var statusText: String? { chatView?.statusText }

    /// The feed's composer, for a host wiring a window-wide Tab order — see
    /// ``KeyViewLoop``.
    public var composerField: NSView? {
        loadViewIfNeeded()
        return chatView?.composerField
    }

    /// Called whenever the composer is turned on or off, so a host's Tab order
    /// can drop it out of the cycle while it is off.
    public var onComposerEnablementChanged: (() -> Void)?

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    deinit {
        pendingRefresh?.cancel()
        session.close()
    }

    /// A plain container holding the feed, so the overlay is the feed's
    /// *sibling* rather than its subview — a chat view rebuilds its transcript
    /// on every layout pass, and nothing else belongs inside that.
    public override func loadView() {
        let chatView = ChatView(viewModel: viewModel)
        // In multi mode the composer stays, greyed: a merged feed is a set of
        // conversations being watched, not one being joined, and a chat with the
        // entry field cut out reads as a different kind of window rather than a
        // read-only one. `updateComposer` below turns it on when single mode
        // gives it one session to write to.
        chatView.isComposerEnabled = false
        // A line typed here is typed at the session's own terminal, so the field
        // wears the prompt it lands at.
        chatView.composerPrompt = ">"
        chatView.bubbleLineLimit = Self.bubbleLineLimit
        // The Sessions window's box, not the chat window's speech bubble. Every
        // row here is headed by the session it came from, so a fill that says
        // "the user" or "the agent" is repeating in colour what the line above
        // already says in words — and the two windows are read one beside the
        // other, showing the same sessions.
        chatView.bubbleStyle = .terminal
        // A merged feed is a list before it is a conversation, so it behaves
        // like one: a row can be picked, the arrows walk them, Return opens the
        // conversation a row came from and Shift-Return leaves for it.
        chatView.isRowSelectionEnabled = true
        chatView.rowActions = .init(
            onOpen: { [weak self] message in self?.presentFocus(on: message) },
            onJump: { [weak self] message in self?.onGoToSource?(message) }
        )
        chatView.onComposerEnablementChanged = { [weak self] in
            self?.onComposerEnablementChanged?()
        }
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
        updateComposer()
    }

    /// Re-reads the feed now rather than at the next interval — for a filter
    /// change, or a host that knows something just happened.
    public func refresh() {
        pendingRefresh?.cancel()
        pendingRefresh = nil
        session.refresh()
        // The overlay is a second reader of the same conversation, so a push
        // that reaches the feed has to reach it too — otherwise the closer look
        // is the *less* current of the two views, which is backwards.
        overlay?.refresh()
    }

    // MARK: - Focus overlay

    /// Lifts one conversation out of the feed and lays it over the top.
    ///
    /// Nothing to do in single mode: the feed underneath is already the one
    /// conversation, so the overlay would cover it with itself.
    private func presentFocus(on message: ChatMessage) {
        guard selectionMode == .multi else { return }
        guard let sourceID = message.attribution?.sourceID, !sourceID.isEmpty else { return }
        dismissFocus()

        let flag = workOutputFlag
        let load = self.load
        let pageLimit = self.pageLimit
        let overlay = ConversationFocusOverlay(
            refreshInterval: refreshInterval,
            // The base page, undeepened: this read is already narrowed to one
            // session, so nothing is about to be filtered out of it.
            load: { await load(flag.value, sourceID, pageLimit) },
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
                { @Sendable text, _ in await send(sourceID, text) }
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
