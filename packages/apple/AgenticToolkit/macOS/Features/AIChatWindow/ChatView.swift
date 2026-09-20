import AppKit
import Combine
import AgenticToolkitCore
import AgenticToolkitCoreMacOS

/// A chat view with transcript, message bubbles, typing indicator, and input field.
public final class ChatView: NSView, NSTextFieldDelegate {
    private let viewModel: AIChatViewModel
    private var cancellables = Set<AnyCancellable>()

    private let transcriptScroll = NSScrollView()
    private let transcriptStack = NSStackView()
    private let inputField = NSTextField()
    private let sendButton = NSButton()
    private var isAtBottom = true

    /// The message currently laid out in full over the transcript, if any.
    private var expansion: BubbleExpansionOverlay?

    /// True from the start of a transcript rebuild until the scroll that follows
    /// it has landed, so ``transcriptDidScroll`` can tell the reader's scrolling
    /// apart from the view's own.
    ///
    /// A rebuild empties the stack and refills it, which collapses the content
    /// height and pins the clip view at the top. Read as a scroll, that says the
    /// reader is now far from the bottom — and `isAtBottom` latches false for
    /// good. A watched feed that replaces its whole transcript every few seconds
    /// then never follows the newest message again: it sits on the oldest one.
    private var isRebuilding = false

    /// The transcript width the bubbles were last laid out for. Bubbles bake in a
    /// fixed width at build time (their text is pre-measured), so we rebuild them
    /// when the width changes — see `layout()` — to keep them proportional on resize.
    private var lastTranscriptWidth: CGFloat = 0

    /// How wide the transcript is drawn — a **number**, written down each pass,
    /// and deliberately not `transcriptStack.width == transcriptScroll.width`.
    ///
    /// That equality reads both ways. A bubble bakes the width it was measured
    /// at into a constraint of its own, and through the equality those baked
    /// widths become a width the scroll view *must* be, which becomes a width
    /// the window must be: the window could be dragged wider and never narrower
    /// again, and every widening raised the floor. `NSWindow` takes its minimum
    /// from the content's fitting size, and a fitting size is worked out from
    /// constraints of *any* priority, so lowering one would not have helped —
    /// the relation itself is what had to go.
    ///
    /// Written in ``layout()``, where the clip view's width is already known.
    private lazy var transcriptWidthConstraint =
        transcriptStack.widthAnchor.constraint(equalToConstant: 0)

    /// Bubbles cap at this fraction of the transcript width, so they read as chat
    /// bubbles and grow/shrink with the window rather than spanning it.
    ///
    /// Plain bubbles only. A ``ChatTranscriptRowView`` — a merged feed's row —
    /// spans the transcript instead and works its own width out from the columns
    /// it has to leave room for.
    private static let maxBubbleWidthFraction: CGFloat = 0.75

    /// What a row gives up to the transcript stack's own side insets. Every row
    /// is this much narrower than the transcript, which is what makes the stack's
    /// width the row's width minus a constant.
    private static let rowWidthInset: CGFloat = 32

    /// Where a day starts and ends, for the banners that head each one.
    ///
    /// The reader's own calendar and time zone: a message is on the day they
    /// were having when it arrived, not the day it was in wherever the clock
    /// that stamped it was running.
    private static let dayCalendar = Calendar.current

    /// Whether the composer accepts input at all.
    ///
    /// A transcript that is being *watched* rather than talked to (a feed, a
    /// log, a replay) sets this false: the composer stays in the window, greyed,
    /// because removing it would make the view a different shape depending on
    /// what it is showing — and because a chat with nowhere to type reads as
    /// broken, while a chat with a disabled composer reads as read-only.
    public var isComposerEnabled = true {
        didSet { applyComposerEnablement() }
    }

    /// What a transcript row does when it is pressed. Only rows that carry a
    /// ``ChatMessage/attribution`` get them — in a merged transcript a row came
    /// from somewhere, and going there is the obvious thing to want.
    ///
    /// Rows are built during a rebuild, so changing this re-renders rather than
    /// waiting for the next poll to notice.
    public var rowActions = ChatTranscriptRowView.Actions() {
        didSet {
            actionsGeneration += 1
            scheduleRender()
        }
    }

    /// Bumped whenever ``rowActions`` is set. It stands in for the actions
    /// themselves in ``TranscriptInputs``, which compares what a rebuild would
    /// read — and closures are never equal to each other, so the only honest
    /// thing to compare is whether they were replaced.
    private var actionsGeneration = 0

    /// Whether a row can be picked, by click or by arrow key.
    ///
    /// Off by default, and off inside a focused conversation: picking a row is
    /// only worth anything where a row *leads* somewhere — the merged feed,
    /// where Return opens the conversation a row came from and Shift-Return
    /// leaves for the real thing. In a view that is already one conversation
    /// both of those are where the reader is standing.
    public var isRowSelectionEnabled = false {
        didSet {
            guard oldValue != isRowSelectionEnabled else { return }
            if !isRowSelectionEnabled { selectedMessageID = nil }
            scheduleRender()
        }
    }

    /// The picked row's message, by id rather than by view: a feed rebuilds its
    /// whole transcript every few seconds, so the view a reader clicked is gone
    /// by the next poll and only the id survives it.
    public private(set) var selectedMessageID: String?

    /// The rows a selection can land on, newest last — the order the arrow keys
    /// walk. Rebuilt with the transcript, which is what keeps the two in step.
    private var selectableRows: [ChatTranscriptRowView] = []

    /// How many lines of a message a transcript row shows before it truncates
    /// and offers the rest. Nil shows whatever the message holds.
    ///
    /// A feed is the case for setting it: one long reply among short ones takes
    /// the whole window, and a reader scrolling past it has lost the thread by
    /// the time they are out. Opening the rest is ``BubbleExpansionOverlay``'s
    /// job, and this view wires it — a row that can truncate can always
    /// un-truncate, so there is nothing for a caller to remember.
    public var bubbleLineLimit: Int? {
        didSet { scheduleRender() }
    }

    /// Whether the view paints the theme's chat surface behind the transcript.
    ///
    /// Off when the chat is being stacked over something that supplies its own
    /// ground — a blurred backdrop, say. An opaque surface there would hide the
    /// very thing the blur exists to show.
    public var drawsBackground = true {
        didSet { applySurfaceFill(resolvedThemeScope.palette) }
    }

    public init(viewModel: AIChatViewModel) {
        self.viewModel = viewModel
        super.init(frame: .zero)
        setupViews()
        bindViewModel()
        // Not left to the binding: every path through it is asynchronous, so a
        // view model that already holds a conversation would still draw one
        // frame without it.
        rebuildTranscript()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    // MARK: - Layout

    private func setupViews() {
        transcriptStack.orientation = .vertical
        transcriptStack.spacing = 12
        transcriptStack.alignment = .leading
        transcriptStack.edgeInsets = NSEdgeInsets(top: 20, left: 16, bottom: 20, right: 16)
        transcriptStack.translatesAutoresizingMaskIntoConstraints = false

        transcriptScroll.documentView = transcriptStack
        transcriptScroll.hasVerticalScroller = true
        transcriptScroll.automaticallyAdjustsContentInsets = false
        transcriptScroll.drawsBackground = false
        transcriptScroll.translatesAutoresizingMaskIntoConstraints = false

        transcriptScroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(transcriptDidScroll),
            name: NSView.boundsDidChangeNotification,
            object: transcriptScroll.contentView
        )

        let divider = ThemedSeparatorView(role: .divider)
        divider.translatesAutoresizingMaskIntoConstraints = false

        inputField.observeTheme { field, palette in
            field.font = palette.font(.body)
            field.textColor = palette.nsColor(.primaryText)
            field.placeholderAttributedString = NSAttributedString(
                string: "Type a message...",
                attributes: [
                    .font: palette.font(.body),
                    .foregroundColor: palette.nsColor(.placeholderText)
                ]
            )
        }
        inputField.isBordered = false
        inputField.focusRingType = .none
        inputField.drawsBackground = false
        inputField.delegate = self
        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputField.accessibilityID("ai-chat.input")

        sendButton.image = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: "Send")
        sendButton.symbolConfiguration = .init(pointSize: 18, weight: .regular)
        sendButton.isBordered = false
        sendButton.target = self
        sendButton.action = #selector(sendTapped)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.accessibilityID("ai-chat.send-button")
        sendButton.observeTheme { [weak self] _, palette in
            self?.applySendButtonTint(palette)
        }

        observeTheme { view, palette in
            view.wantsLayer = true
            view.applySurfaceFill(palette)
        }

        let inputRow = NSStackView(views: [inputField, sendButton])
        inputRow.orientation = .horizontal
        inputRow.spacing = 10
        inputRow.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        inputRow.translatesAutoresizingMaskIntoConstraints = false

        let topAnchorView: NSView = self

        addSubview(transcriptScroll)
        addSubview(divider)
        addSubview(inputRow)

        NSLayoutConstraint.activate([
            transcriptScroll.topAnchor.constraint(equalTo: topAnchorView.topAnchor),
            transcriptScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            transcriptScroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            transcriptScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
            transcriptWidthConstraint,
            divider.topAnchor.constraint(equalTo: transcriptScroll.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            inputRow.topAnchor.constraint(equalTo: divider.bottomAnchor),
            inputRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            inputRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            inputRow.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func applySurfaceFill(_ palette: SemanticPalette) {
        layer?.backgroundColor = drawsBackground
            ? palette.nsColor(.chatSurface).cgColor
            : NSColor.clear.cgColor
    }

    /// Rebuild the transcript when the transcript width changes (window resize),
    /// so the pre-measured bubbles reflow to the new proportional width. Guarded on
    /// a width delta so the rebuild's own relayout doesn't recurse.
    public override func layout() {
        super.layout()
        let width = transcriptScroll.contentView.bounds.width
        // The transcript is as wide as the window has made the clip view, and
        // is told so here rather than constrained to it — see
        // ``transcriptWidthConstraint``. Laid out again in the same pass so the
        // rows below are measured against the width they are about to be drawn
        // at, not the previous one.
        if width > 0, transcriptWidthConstraint.constant != width {
            transcriptWidthConstraint.constant = width
            transcriptStack.layoutSubtreeIfNeeded()
        }
        if width > 0, abs(width - lastTranscriptWidth) > 1 {
            lastTranscriptWidth = width
            rebuildTranscript()
        }
    }

    /// Makes the input field the window's first responder. Returns `false` when the
    /// view is not in a window yet, or the window declined the change.
    @discardableResult
    public func focusInput() -> Bool {
        window?.makeFirstResponder(inputField) ?? false
    }

    /// Whether what is typed right now goes into the composer.
    ///
    /// Asked by hosts that also give Return a meaning of their own — an overlay
    /// that closes on it, say. A focused `NSTextField` is not itself the first
    /// responder: the window's shared field editor is, installed inside the
    /// field, which is why this is two questions rather than an identity check.
    public var isComposerFocused: Bool {
        guard let responder = window?.firstResponder as? NSView else { return false }
        return responder === inputField || responder.isDescendant(of: inputField)
    }

    private func bindViewModel() {
        viewModel.$messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleRender() }
            .store(in: &cancellables)

        viewModel.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleRender() }
            .store(in: &cancellables)

        // A bubble is set in the terminal's face, and half of that answer lives
        // in Terminal settings rather than in the theme — so a theme change is
        // not the only thing that changes what a bubble measures to. Every
        // bubble already re-measures itself on a theme change; this is the other
        // door into the same fact.
        UserSettings.shared.changes
            .filter { TerminalAppearance.fontSettingKeys.contains($0) }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildForFontChange() }
            .store(in: &cancellables)
    }

    /// Rebuilds the transcript for something the rebuild reads but
    /// ``TranscriptInputs`` cannot hold.
    ///
    /// The font is not an input the way the messages are: it is read out of a
    /// setting the same rows would be rebuilt from unchanged. So the record of
    /// what is on screen is dropped rather than compared — the next rebuild has
    /// nothing to match against and goes ahead.
    private func rebuildForFontChange() {
        rendered = nil
        scheduleRender()
    }

    /// Coalesce high-frequency delta updates into one rebuild per runloop tick.
    private var renderScheduled = false
    private func scheduleRender() {
        guard !renderScheduled else { return }
        renderScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.renderScheduled = false
            self.rebuildTranscript()
        }
    }

    // MARK: - Transcript

    /// Everything a rebuild reads.
    ///
    /// Two rebuilds from the same inputs produce the same rows, and building
    /// them twice is not free: the stack is emptied and refilled, every bubble
    /// re-measured, and the reader sees the transcript blink. A watched feed
    /// polls every few seconds and usually has nothing new, and a view that has
    /// just been presented renders once for its own construction and again when
    /// its bindings deliver the messages it was built holding — so the blink was
    /// most of what the overlay did on the way in.
    private struct TranscriptInputs: Equatable {
        var width: CGFloat
        var lineLimit: Int?
        var isSelectable: Bool
        var selection: String?
        var actionsGeneration: Int
        var state: ChatSessionState
        var messages: [ChatMessage]
    }

    /// What the transcript on screen was last built from, or nil before the
    /// first build.
    private var rendered: TranscriptInputs?

    private func rebuildTranscript() {
        let scrollWidth = transcriptScroll.contentView.bounds.width
        let inputs = TranscriptInputs(
            width: scrollWidth,
            lineLimit: bubbleLineLimit,
            isSelectable: isRowSelectionEnabled,
            selection: selectedMessageID,
            actionsGeneration: actionsGeneration,
            state: viewModel.state,
            messages: viewModel.messages
        )
        guard inputs != rendered else { return }
        rendered = inputs

        isRebuilding = true
        transcriptStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        selectableRows.removeAll()

        let maxBubbleWidth = max(scrollWidth * Self.maxBubbleWidthFraction, 200)
        // An attributed row spans the transcript rather than a fraction of it,
        // and its own geometry decides how much of that a bubble may take — the
        // avatar column and the gutter in front of the facing side are the row's
        // facts, not this view's.
        let rowBubbleWidth = ChatTranscriptRowView.maxBubbleWidth(
            forRowWidth: max(scrollWidth - Self.rowWidthInset, 0))

        let topSpacer = NSView()
        topSpacer.translatesAutoresizingMaskIntoConstraints = false
        topSpacer.setContentHuggingPriority(.init(1), for: .vertical)
        topSpacer.setContentCompressionResistancePriority(.init(1), for: .vertical)
        transcriptStack.addArrangedSubview(topSpacer)

        // Which day the rows so far belong to, so the next message can tell
        // whether it is opening a new one. Nil until the first message, which
        // always opens one.
        var shownDay: Date?

        for message in viewModel.messages {
            // Every message carries a clock reading; only the first of a day
            // carries the date. A banner goes in ahead of it, spanning the
            // transcript, because the day belongs to neither column.
            let day = Self.dayCalendar.startOfDay(for: message.timestamp)
            if day != shownDay {
                shownDay = day
                let banner = ChatDayBannerView(day: message.timestamp,
                                               calendar: Self.dayCalendar)
                transcriptStack.addArrangedSubview(banner)
                banner.widthAnchor.constraint(
                    equalTo: transcriptStack.widthAnchor,
                    constant: -Self.rowWidthInset).isActive = true
            }

            // A message that names its own speaker gets the fuller row: icon,
            // header line, timestamp underneath. Only a merged transcript
            // produces those, so an ordinary chat is untouched by this.
            if message.attribution != nil {
                var actions = rowActions
                actions.onExpand = { [weak self] message in self?.expand(message) }
                if isRowSelectionEnabled {
                    actions.onSelect = { [weak self] message in self?.select(message.id) }
                }
                let row = ChatTranscriptRowView(
                    message: message, maxBubbleWidth: rowBubbleWidth,
                    actions: actions, lineLimit: bubbleLineLimit)
                // A rebuild is not a deselection: the reader picked a message,
                // and the row showing it having been thrown away and built again
                // in the meantime is this view's business, not theirs.
                if isRowSelectionEnabled {
                    row.isSelected = message.id == selectedMessageID
                    selectableRows.append(row)
                }
                transcriptStack.addArrangedSubview(row)
                row.widthAnchor.constraint(
                    equalTo: transcriptStack.widthAnchor, constant: -Self.rowWidthInset).isActive = true
                continue
            }

            let bubble = AIChatBubbleView(message: message, maxWidth: maxBubbleWidth)
            bubble.setContentHuggingPriority(.required, for: .horizontal)

            if message.role == .user {
                let spacer = NSView()
                spacer.translatesAutoresizingMaskIntoConstraints = false
                spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
                let hStack = NSStackView(views: [spacer, bubble])
                hStack.orientation = .horizontal
                hStack.alignment = .top
                hStack.spacing = 0
                transcriptStack.addArrangedSubview(hStack)
                hStack.widthAnchor.constraint(
                    equalTo: transcriptStack.widthAnchor,
                    constant: -Self.rowWidthInset).isActive = true
            } else if message.role == .notice {
                // Center status lines (e.g. "Model changed to …") between the two
                // conversational columns.
                let leading = NSView()
                let trailing = NSView()
                for spacer in [leading, trailing] {
                    spacer.translatesAutoresizingMaskIntoConstraints = false
                    spacer.setContentHuggingPriority(.init(1), for: .horizontal)
                }
                let hStack = NSStackView(views: [leading, bubble, trailing])
                hStack.orientation = .horizontal
                hStack.alignment = .top
                hStack.spacing = 0
                leading.widthAnchor.constraint(equalTo: trailing.widthAnchor).isActive = true
                transcriptStack.addArrangedSubview(hStack)
                hStack.widthAnchor.constraint(
                    equalTo: transcriptStack.widthAnchor,
                    constant: -Self.rowWidthInset).isActive = true
            } else {
                transcriptStack.addArrangedSubview(bubble)
            }
        }

        let responding = viewModel.state == .responding
        if responding {
            let indicator = TypingIndicatorView()
            transcriptStack.addArrangedSubview(indicator)
            indicator.startAnimating()
        }

        applyComposerEnablement()

        // The scroll waits a turn because the rows were only just added: their
        // heights come out of the next layout pass, not this one.
        let followNewest = isAtBottom
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if followNewest { self.scrollToBottom() }
            self.isRebuilding = false
        }
    }

    // MARK: - Selection

    /// Picks the row showing `id`, or clears the selection when it is nil.
    ///
    /// Applied straight to the rows rather than through a rebuild: a rebuild
    /// throws away every bubble and measures them again, which is a visible
    /// stutter to pay for a two-pixel frame moving one row.
    public func select(_ id: String?) {
        guard isRowSelectionEnabled else { return }
        selectedMessageID = id
        for row in selectableRows {
            row.isSelected = row.shownMessage.id == id
        }
        // The rows on screen now match a selection the last rebuild did not,
        // so the record of what they were built from has to say so — or the
        // next poll would find its inputs "changed" and rebuild to draw a
        // frame that is already drawn.
        rendered?.selection = id
        // The keyboard follows the pick. Without this a reader who clicked a row
        // would find the arrow keys still scrolling the transcript, which is the
        // one thing selection is supposed to have taken over.
        window?.makeFirstResponder(self)
        if let id, let row = selectableRows.first(where: { $0.shownMessage.id == id }) {
            row.scrollToVisible(row.bounds)
        }
    }

    /// Only where there is something to pick — a read-only transcript with no
    /// selection has no use for the focus ring it would otherwise take from the
    /// composer.
    public override var acceptsFirstResponder: Bool { isRowSelectionEnabled }

    public override func keyDown(with event: NSEvent) {
        guard isRowSelectionEnabled, handleSelectionKey(event) else {
            super.keyDown(with: event)
            return
        }
    }

    private func handleSelectionKey(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case 125: moveSelection(by: 1); return true   // down
        case 126: moveSelection(by: -1); return true  // up
        case 36, 76:                                  // return, enter
            guard let message = selectedMessage else { return false }
            // Shift is "take me there", plain Return is "show me here" — the
            // same pair the mouse has, where a double click opens the
            // conversation in place and the row's app icon leaves for it.
            if event.modifierFlags.contains(.shift) {
                rowActions.onJump?(message)
            } else {
                rowActions.onOpen?(message)
            }
            return true
        default: return handleSelectionLetter(event)
        }
    }

    /// The letters a picked row answers to: **c** opens the conversation here,
    /// **m** opens the message out, **g** goes to the session it came from.
    ///
    /// Bare letters, because a feed with a picked row is a list and this is what
    /// lists do — the reader's hand is already on the keys that moved the pick.
    /// Any modifier hands the keystroke back: ⌘C is a copy, ⌥G is a character,
    /// and neither is this view's to take.
    private func handleSelectionLetter(_ event: NSEvent) -> Bool {
        let claimed: NSEvent.ModifierFlags = [.command, .control, .option]
        guard event.modifierFlags.isDisjoint(with: claimed),
              let letter = event.charactersIgnoringModifiers?.lowercased(),
              let row = selectedRow else { return false }
        switch letter {
        case "c": rowActions.onOpen?(row.shownMessage)
        case "g": rowActions.onJump?(row.shownMessage)
        case "m":
            // Only where there is more to show. On a message already whole the
            // key means nothing, and an overlay that opened to say "here it is
            // again" would be an answer to a question nobody asked.
            guard row.isTruncated else { return false }
            expand(row.shownMessage)
        default: return false
        }
        return true
    }

    private var selectedRow: ChatTranscriptRowView? {
        selectableRows.first { $0.shownMessage.id == selectedMessageID }
    }

    private var selectedMessage: ChatMessage? { selectedRow?.shownMessage }

    /// Moves the pick one row down (`1`) or up (`-1`).
    ///
    /// With nothing picked, each arrow enters from its own end: down lands on
    /// the first row, up on the last. Walking off either end stays put rather
    /// than wrapping — a feed is a timeline, and jumping from the newest message
    /// to the oldest is not what "one more down" means.
    private func moveSelection(by step: Int) {
        guard !selectableRows.isEmpty else { return }
        guard let current = selectableRows.firstIndex(where: {
            $0.shownMessage.id == selectedMessageID
        }) else {
            select(step > 0 ? selectableRows.first?.shownMessage.id
                            : selectableRows.last?.shownMessage.id)
            return
        }
        let next = current + step
        guard selectableRows.indices.contains(next) else { return }
        select(selectableRows[next].shownMessage.id)
    }

    // MARK: - Expansion

    /// Lays one message out in full over the transcript.
    ///
    /// Hosted on this view rather than on the transcript's document: a rebuild
    /// empties that stack, and a feed rebuilds every few seconds — the overlay
    /// would vanish mid-read. Covering the composer as well as the rows is the
    /// right shape anyway, since the composer is not what is being read.
    private func expand(_ message: ChatMessage) {
        expansion?.dismiss()
        let overlay = BubbleExpansionOverlay(message: message)
        overlay.onDismissed = { [weak self, weak overlay] in
            if self?.expansion === overlay { self?.expansion = nil }
        }
        expansion = overlay
        overlay.present(in: self)
    }

    /// Disabled while a turn is in flight, so rapid sends can't overlap turns —
    /// and disabled outright when the transcript is read-only.
    ///
    /// The button carries one condition the field does not: there has to be
    /// something to send. A lit arrow over an empty composer offers an action
    /// that does nothing when taken, and the greyed one says what the composer
    /// is waiting for without a word of explanation.
    private func applyComposerEnablement() {
        let enabled = isComposerEnabled && viewModel.state != .responding
        inputField.isEnabled = enabled
        sendButton.isEnabled = enabled && !composerText.isEmpty
        applySendButtonTint(resolvedThemeScope.palette)
    }

    /// What is typed, with the whitespace that is not worth sending taken off.
    private var composerText: String {
        inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The composer's text changed, so what can be done with it changed too.
    public func controlTextDidChange(_ obj: Notification) {
        applyComposerEnablement()
    }

    /// No tint at all when the composer is off, rather than a dimmer one: AppKit
    /// draws a template image at the full strength of whatever
    /// `contentTintColor` names, disabled or not, so an accent-tinted arrow over
    /// a dead text field reads as a chat you can still send into. Handing the
    /// tint back to AppKit is what restores the greyed-out look.
    private func applySendButtonTint(_ palette: SemanticPalette) {
        sendButton.contentTintColor = sendButton.isEnabled ? palette.nsColor(.accent) : nil
    }

    // MARK: - Scroll

    @objc private func transcriptDidScroll() {
        guard !isRebuilding else { return }
        isAtBottom = distanceFromNewest() < 30
    }

    private func scrollToBottom() {
        guard let docView = transcriptScroll.documentView else { return }
        // Solve the constraints the rebuild just added before measuring: until
        // that happens `bounds.height` is the height of the transcript that was
        // there *before* — nothing at all on a first load — and every offset
        // computed from it is wrong.
        docView.layoutSubtreeIfNeeded()
        transcriptScroll.contentView.scroll(to: NSPoint(x: 0, y: newestScrollOffset()))
        transcriptScroll.reflectScrolledClipView(transcriptScroll.contentView)
    }

    /// The clip-view offset that shows the newest message.
    ///
    /// The transcript stack is a plain `NSStackView`, which is **not** flipped:
    /// its y axis grows upward, so the newest message — visually the bottom one
    /// — sits at `y == 0`, and the largest offset shows the *oldest*. A flipped
    /// document view is the other way round, and both are asked here rather
    /// than assumed, because getting it backwards is not a visible glitch: the
    /// window simply opens on the oldest message it has and stays there.
    private func newestScrollOffset() -> CGFloat {
        guard let docView = transcriptScroll.documentView, docView.isFlipped else { return 0 }
        return max(docView.bounds.height - transcriptScroll.contentView.bounds.height, 0)
    }

    /// How far the visible region is from the newest message, in points.
    private func distanceFromNewest() -> CGFloat {
        guard let docView = transcriptScroll.documentView else { return 0 }
        let clip = transcriptScroll.contentView
        guard docView.isFlipped else { return clip.bounds.origin.y }
        return docView.bounds.height - (clip.bounds.origin.y + clip.bounds.height)
    }

    // MARK: - Input

    @objc private func sendTapped() {
        let text = composerText
        guard !text.isEmpty else { return }
        viewModel.sendMessage(text)
        inputField.stringValue = ""
        // Emptying the field is not a change anyone typed, so nothing tells the
        // delegate about it — the button has to be told itself, or it stays lit
        // over a composer with nothing left in it.
        applyComposerEnablement()
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            sendTapped()
            return true
        }
        return false
    }
}
