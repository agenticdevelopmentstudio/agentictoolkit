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
    private let promptLabel = NSTextField(labelWithString: "")
    private let statusRow = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "")
    private var statusIcon: NSView?
    private var isAtBottom = true

    /// The messages the reader has opened out, by id.
    ///
    /// Kept here rather than on the rows because the rows do not last: a
    /// watched feed rebuilds its whole transcript every few seconds, and a
    /// message opened on one pass would close itself on the next. This view
    /// survives that, so it is what remembers, and each rebuild hands the
    /// answer back to the row it builds.
    private var expandedMessageIDs: Set<String> = []

    /// Watches the text the reader is selecting while a rebuild waits for them
    /// to finish — see ``holdsForTextSelection()``.
    private var heldSelectionObserver: NSObjectProtocol?

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

    /// What is drawn in front of the composer, the way a shell draws its prompt —
    /// nil for none, which is how an ordinary chat reads.
    ///
    /// A host whose composer types into a terminal sets it, so the field reads
    /// as the command line it stands in for rather than as a message box.
    public var composerPrompt: String? {
        didSet {
            promptLabel.stringValue = composerPrompt ?? ""
            promptLabel.isHidden = composerPrompt == nil
        }
    }

    /// The line above the composer saying what the other side is doing, or nil
    /// when there is nothing to say — see ``setStatus(_:icon:)``.
    public private(set) var statusText: String?

    /// Shows `text` above the composer with `icon` in front of it, or hides the
    /// line when `text` is nil.
    ///
    /// The icon is the host's, not this view's: what "busy" looks like is a
    /// fact about whatever is busy, and a host that already draws it somewhere
    /// else wants the two to be the same glyph. Passing the view already on
    /// screen leaves it where it is, so an animation in it keeps running
    /// across updates instead of restarting from its first frame.
    public func setStatus(_ text: String?, icon: NSView?) {
        statusText = text
        statusLabel.stringValue = text ?? ""
        statusLabel.toolTip = text
        if icon !== statusIcon {
            statusIcon?.removeFromSuperview()
            statusIcon = icon
            if let icon { statusRow.insertArrangedSubview(icon, at: 0) }
        }
        statusRow.isHidden = text == nil
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
    /// the time they are out. Opening the rest is this view's job, and it wires
    /// it — a row that can truncate can always un-truncate, so there is nothing
    /// for a caller to remember.
    public var bubbleLineLimit: Int? {
        didSet { scheduleRender() }
    }

    /// The shape every bubble in this transcript is drawn in.
    ///
    /// A property of the *view* rather than of each message, because the answer
    /// is a fact about which window this is: one chat with one other party
    /// colours its bubbles by role, a merged feed of many sessions names the
    /// speaker in a header instead and draws the Sessions window's box. Either
    /// answer applies to every row, and a transcript that mixed the two — a
    /// message still in flight taking one shape and the same message taking the
    /// other once it settled — would flicker between them.
    public var bubbleStyle: AIChatBubbleView.Style = .speaker {
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
        promptLabel.observeTheme { [weak self] label, palette in
            label.font = palette.font(.body)
            self?.applyPromptTint(palette)
        }
        promptLabel.isHidden = true
        promptLabel.setContentHuggingPriority(.required, for: .horizontal)
        promptLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        promptLabel.accessibilityID("ai-chat.prompt")

        statusLabel.observeTheme { label, palette in
            label.font = palette.font(.caption)
            label.textColor = palette.nsColor(.secondaryText)
        }
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 1
        statusLabel.cell?.usesSingleLineMode = true
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.accessibilityID("ai-chat.status")
        statusRow.addArrangedSubview(statusLabel)
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 6
        statusRow.edgeInsets = NSEdgeInsets(top: 6, left: 16, bottom: 6, right: 16)
        statusRow.isHidden = true

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

        let inputRow = NSStackView(views: [promptLabel, inputField, sendButton])
        inputRow.orientation = .horizontal
        inputRow.spacing = 10
        inputRow.setCustomSpacing(6, after: promptLabel)
        inputRow.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        inputRow.translatesAutoresizingMaskIntoConstraints = false

        // The status line sits over the divider, at the foot of the transcript:
        // it is about what is happening in the conversation, which is the thing
        // above the line, not about what is being typed below it. A stack so a
        // hidden status closes up rather than leaving a blank band.
        let footer = NSStackView(views: [statusRow, divider, inputRow])
        footer.orientation = .vertical
        footer.alignment = .leading
        footer.spacing = 0
        footer.translatesAutoresizingMaskIntoConstraints = false
        for view in [statusRow, divider, inputRow] {
            view.widthAnchor.constraint(equalTo: footer.widthAnchor).isActive = true
        }

        let topAnchorView: NSView = self

        addSubview(transcriptScroll)
        addSubview(footer)

        NSLayoutConstraint.activate([
            transcriptScroll.topAnchor.constraint(equalTo: topAnchorView.topAnchor),
            transcriptScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            transcriptScroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            transcriptScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
            transcriptWidthConstraint,
            footer.topAnchor.constraint(equalTo: transcriptScroll.bottomAnchor),
            footer.leadingAnchor.constraint(equalTo: leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor)
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

    /// The composer, for a host wiring a window-wide Tab order — see
    /// ``KeyViewLoop``. A view rather than the field's own type: what a host has
    /// any business doing with it is putting it in a key-view loop.
    public var composerField: NSView { inputField }

    /// Called whenever ``isComposerEnabled`` takes effect, so a host that wired
    /// the composer into a Tab order can drop it out of the cycle while it is
    /// off. Tab landing on a greyed-out composer is focus with nothing to do.
    public var onComposerEnablementChanged: (() -> Void)?

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
        var bubbleStyle: AIChatBubbleView.Style
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
            messages: viewModel.messages,
            bubbleStyle: bubbleStyle
        )
        guard inputs != rendered else { return }
        guard !holdsForTextSelection() else { return }
        carryExpansion(from: rendered?.messages ?? [], to: inputs.messages)
        rendered = inputs

        // Where the reader is, by message, so a transcript rebuilt under them
        // puts the same message back at the same place — the stack is emptied
        // and refilled, and an offset alone would land on whatever row now
        // happens to sit there.
        let anchor = isAtBottom ? nil : scrollAnchor()

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
            //
            // So does a message that is not settled yet, whatever it knows
            // about its speaker: the sending spinner and the failure reason are
            // drawn by that row and by nothing else, and a line written before
            // the first read has nothing to borrow an attribution from — which
            // is exactly the moment the reader most needs to see it in flight.
            if message.attribution != nil || message.delivery != .settled {
                var actions = rowActions
                actions.onToggleExpanded = { [weak self] message in
                    self?.toggleExpanded(message.id)
                }
                if isRowSelectionEnabled {
                    // A click picks the row under the pointer, which is already
                    // in view; scrolling it "into view" would drag the text out
                    // from under a reader starting to select it.
                    actions.onSelect = { [weak self] message in
                        self?.select(message.id, reveal: false)
                    }
                }
                let row = ChatTranscriptRowView(
                    message: message, maxBubbleWidth: rowBubbleWidth,
                    actions: actions, lineLimit: bubbleLineLimit,
                    bubbleStyle: bubbleStyle,
                    isExpanded: expandedMessageIDs.contains(message.id))
                // A rebuild is not a deselection: the reader picked a message,
                // and the row showing it having been thrown away and built again
                // in the meantime is this view's business, not theirs.
                if isRowSelectionEnabled {
                    row.isSelected = message.id == selectedMessageID
                    selectableRows.append(row)
                }
                row.identifier = NSUserInterfaceItemIdentifier(message.id)
                transcriptStack.addArrangedSubview(row)
                row.widthAnchor.constraint(
                    equalTo: transcriptStack.widthAnchor, constant: -Self.rowWidthInset).isActive = true
                continue
            }

            let bubble = AIChatBubbleView(
                message: message, maxWidth: maxBubbleWidth, style: bubbleStyle)
            bubble.setContentHuggingPriority(.required, for: .horizontal)
            let messageID = NSUserInterfaceItemIdentifier(message.id)

            if message.role == .user {
                let spacer = NSView()
                spacer.translatesAutoresizingMaskIntoConstraints = false
                spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
                let hStack = NSStackView(views: [spacer, bubble])
                hStack.orientation = .horizontal
                hStack.alignment = .top
                hStack.spacing = 0
                hStack.identifier = messageID
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
                hStack.identifier = messageID
                transcriptStack.addArrangedSubview(hStack)
                hStack.widthAnchor.constraint(
                    equalTo: transcriptStack.widthAnchor,
                    constant: -Self.rowWidthInset).isActive = true
            } else {
                bubble.identifier = messageID
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
            if followNewest {
                self.scrollToBottom()
            } else if let anchor {
                self.restore(anchor)
            }
            self.isRebuilding = false
        }
    }

    // MARK: - Surviving a rebuild

    /// Whether the reader is selecting text in the transcript right now — in
    /// which case the rebuild waits, and runs once they let go.
    ///
    /// A rebuild throws every row away, and with it the text view the
    /// selection lives in: a poll landing between the drag and ⌘C would copy
    /// nothing. The selection ending — collapsing to a caret, which is what a
    /// click elsewhere in the text does — is what releases it; a reader who
    /// moves to another view entirely stops being "selecting", so the next
    /// change goes through.
    private func holdsForTextSelection() -> Bool {
        guard let textView = window?.firstResponder as? NSTextView,
              textView.isDescendant(of: transcriptStack),
              textView.selectedRange().length > 0
        else { return false }
        guard heldSelectionObserver == nil else { return true }
        heldSelectionObserver = NotificationCenter.default.addObserver(
            forName: NSTextView.didChangeSelectionNotification, object: textView, queue: .main
        ) { [weak self, weak textView] _ in
            MainActor.assumeIsolated {
                guard let self, textView?.selectedRange().length ?? 0 == 0 else { return }
                self.releaseSelectionHold()
                self.rebuildTranscript()
            }
        }
        return true
    }

    private func releaseSelectionHold() {
        if let heldSelectionObserver {
            NotificationCenter.default.removeObserver(heldSelectionObserver)
        }
        heldSelectionObserver = nil
    }

    /// Hands an opened-out message's state on to the message that replaced it.
    ///
    /// A line typed here is drawn under an id of its own until the source says
    /// it back, and then it is the source's row, under the source's id. Keyed
    /// by id alone, a long line the reader had opened snapped shut the moment
    /// it arrived. Ids that simply left the page are forgotten rather than kept
    /// for ever.
    private func carryExpansion(from old: [ChatMessage], to new: [ChatMessage]) {
        guard !expandedMessageIDs.isEmpty else { return }
        let present = Set(new.map(\.id))
        for id in expandedMessageIDs.subtracting(present) {
            expandedMessageIDs.remove(id)
            guard let gone = old.first(where: { $0.id == id }), gone.delivery != .settled else {
                continue
            }
            let said = FeedChatSession.normalized(gone.text)
            if let arrived = new.last(where: {
                $0.role == gone.role && FeedChatSession.normalized($0.text) == said
            }) {
                expandedMessageIDs.insert(arrived.id)
            }
        }
    }

    /// A message on screen and how far the visible region's top edge sits from
    /// that message's own top.
    private struct ScrollAnchor {
        var id: NSUserInterfaceItemIdentifier
        var offset: CGFloat
    }

    /// The topmost message showing, and where the reader is relative to it.
    private func scrollAnchor() -> ScrollAnchor? {
        guard let docView = transcriptScroll.documentView else { return nil }
        let visible = transcriptScroll.contentView.bounds
        let top = Self.topEdge(of: visible, flipped: docView.isFlipped)
        let showing = transcriptStack.arrangedSubviews.filter {
            $0.identifier != nil && $0.frame.intersects(visible)
        }
        let topmost = docView.isFlipped
            ? showing.min { $0.frame.minY < $1.frame.minY }
            : showing.max { $0.frame.maxY < $1.frame.maxY }
        guard let view = topmost, let id = view.identifier else { return nil }
        return ScrollAnchor(id: id, offset: top - Self.topEdge(of: view.frame, flipped: docView.isFlipped))
    }

    /// Scrolls so the anchored message sits where it sat before the rebuild.
    private func restore(_ anchor: ScrollAnchor) {
        guard let docView = transcriptScroll.documentView,
              let view = transcriptStack.arrangedSubviews.first(where: { $0.identifier == anchor.id })
        else { return }
        docView.layoutSubtreeIfNeeded()
        let clip = transcriptScroll.contentView
        let top = Self.topEdge(of: view.frame, flipped: docView.isFlipped) + anchor.offset
        let origin = docView.isFlipped ? top : top - clip.bounds.height
        let limit = max(docView.bounds.height - clip.bounds.height, 0)
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: min(max(origin, 0), limit)))
        transcriptScroll.reflectScrolledClipView(clip)
    }

    /// The edge of `rect` that is at the top of the screen.
    private static func topEdge(of rect: NSRect, flipped: Bool) -> CGFloat {
        flipped ? rect.minY : rect.maxY
    }

    // MARK: - Selection

    /// Picks the row showing `id`, or clears the selection when it is nil.
    ///
    /// Applied straight to the rows rather than through a rebuild: a rebuild
    /// throws away every bubble and measures them again, which is a visible
    /// stutter to pay for a two-pixel frame moving one row.
    ///
    /// `reveal` scrolls the picked row into view — what a pick made from the
    /// keyboard needs, and what a click, landing on a row already in view,
    /// must not do.
    public func select(_ id: String?, reveal: Bool = true) {
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
        if reveal, let id, let row = selectableRows.first(where: { $0.shownMessage.id == id }) {
            // An opened-out message can be taller than the view; showing all
            // of it is impossible, and showing its end skips what it says
            // first — so a tall row is revealed from its top.
            let height = min(row.bounds.height, transcriptScroll.contentView.bounds.height)
            let top = Self.topEdge(of: row.bounds, flipped: row.isFlipped)
            let slice = NSRect(x: row.bounds.minX, y: row.isFlipped ? top : top - height,
                               width: row.bounds.width, height: height)
            row.scrollToVisible(slice)
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
    /// **m** opens the message out — or closes it — and **g** goes to the
    /// session it came from.
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
            // Only where there is more to the message than the row's limit
            // shows. On one already short enough the key means nothing, and a
            // row that flashed to say "here it is again" would be an answer to
            // a question nobody asked.
            guard row.isExpandable else { return false }
            toggleExpanded(row.shownMessage.id)
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

    /// Opens one message out in place, or closes it again.
    ///
    /// The row on screen is changed directly and the transcript is *not* rebuilt
    /// around it: a rebuild empties the stack and refills it, which puts the
    /// reader back at the top of a transcript they had scrolled — for the sake
    /// of one row that is already in front of them. What the rebuild is for is
    /// the *next* one, where the row itself is gone and only the id survives.
    private func toggleExpanded(_ messageID: String) {
        let isOpening = !expandedMessageIDs.contains(messageID)
        if isOpening {
            expandedMessageIDs.insert(messageID)
        } else {
            expandedMessageIDs.remove(messageID)
        }
        transcriptRows.first { $0.shownMessage.id == messageID }?.isExpanded = isOpening
    }

    /// Every row currently in the transcript, in order.
    ///
    /// Not ``selectableRows``: that list is empty wherever row selection is off,
    /// and a message opens out the same either way.
    private var transcriptRows: [ChatTranscriptRowView] {
        transcriptStack.arrangedSubviews.compactMap { $0 as? ChatTranscriptRowView }
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
        applyPromptTint(resolvedThemeScope.palette)
        applySendButtonTint(resolvedThemeScope.palette)
        onComposerEnablementChanged?()
    }

    /// What is typed, with the whitespace that is not worth sending taken off.
    private var composerText: String {
        inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The prompt greys with the field it stands in front of, so a composer that
    /// is off does not still read as a command line waiting for input.
    private func applyPromptTint(_ palette: SemanticPalette) {
        promptLabel.textColor = inputField.isEnabled
            ? palette.nsColor(.secondaryText)
            : palette.nsColor(.placeholderText)
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

    /// Lands the next rebuild on the newest message, wherever the reader had
    /// scrolled to — for a host that has just swapped in a different
    /// conversation, where keeping the old one's place would put the reader
    /// somewhere arbitrary in the new one.
    public func followNewest() {
        isAtBottom = true
    }

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
