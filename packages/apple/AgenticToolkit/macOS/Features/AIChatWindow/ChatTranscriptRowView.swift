import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreUI
import AgenticToolkitCoreMacOS

/// One row of a *merged* transcript — several conversations interleaved on a
/// single timeline, the way a group chat reads.
///
/// ```
/// [app] project » branch » session name
///       ╭──────────────────────────────╮
///       │ what the agent said          │
///       ╰──────────────────────────────╯
///       09:41
///
///       project » branch » session name [app]
///       ╭──────────────────────────────╮
///       │ what the human said          │
///       ╰──────────────────────────────╯
///                                 09:41
/// ```
///
/// Both sides run between the same two margins. Who is talking is said by the
/// fill, by which side the header and the timestamp are on, and by which margin
/// the icon is against — none of which needs the column to move.
///
/// That icon is the **application** the conversation is running in — iTerm,
/// Terminal, Ghostty — and not a badge for the speaker. Who is speaking is
/// already said three other ways in the same row, so a fourth saying of it
/// would be the one piece of the row carrying no new fact; what a reader
/// scanning a merged feed actually wants is *their window*, and the picture
/// they would find it by on the Dock is the fastest way to say which row is
/// it. It is also the control that goes there, so the row has one icon that
/// says what it is and does what it says, rather than a badge beside a button.
///
/// It exists because a bubble alone cannot carry a merged transcript: with more
/// than one conversation on the timeline, "which side is it on" no longer says
/// who is talking, so every row has to name its own speaker. The header,
/// the icon and the timestamp are that naming — and the whole row is a target,
/// because the useful thing to do with a row in a feed is to go to where it
/// came from.
///
/// Rendered only for messages that carry a ``ChatMessage/attribution``; an
/// ordinary one-to-one chat keeps the bare bubbles it has always had.
public final class ChatTranscriptRowView: NSView {

    /// What a row can do when it is pressed. Grouped rather than passed one
    /// closure at a time because they are three faces of one gesture — the row
    /// opened, the row left for its source, the row's own message opened out —
    /// and a caller that wires one usually wires several.
    public struct Actions {
        /// The row was **double**-clicked.
        ///
        /// A double click and not a single one because a single click is worth
        /// more where it is: selecting the text to copy it. Opening a
        /// conversation is deliberate enough to be worth two.
        public var onOpen: ((ChatMessage) -> Void)?
        /// The row's app icon was clicked: leave for wherever this came from.
        public var onJump: ((ChatMessage) -> Void)?
        /// The bubble's expand/collapse toggle was used — the reader wants all
        /// of this message, or wants it back the way it was.
        public var onToggleExpanded: ((ChatMessage) -> Void)?
        /// The row was clicked once: make it *the* row.
        ///
        /// A single click is the cheapest gesture there is and it was doing
        /// nothing, while the keyboard had nothing to move: naming a row is what
        /// gives the arrow keys, Return and Shift-Return something to act on.
        /// It does not take the press — the text under it still starts its
        /// selection drag.
        public var onSelect: ((ChatMessage) -> Void)?

        public init(
            onOpen: ((ChatMessage) -> Void)? = nil,
            onJump: ((ChatMessage) -> Void)? = nil,
            onToggleExpanded: ((ChatMessage) -> Void)? = nil,
            onSelect: ((ChatMessage) -> Void)? = nil
        ) {
            self.onOpen = onOpen
            self.onJump = onJump
            self.onToggleExpanded = onToggleExpanded
            self.onSelect = onSelect
        }
    }

    private let message: ChatMessage
    private let attribution: ChatMessage.Attribution
    private let actions: Actions

    /// The line over the bubble — the application's icon and the session's
    /// trail — which is the *same* control the Sessions window and the
    /// Conversations shelf head their rows with, so a reader learns it once.
    ///
    /// The icon in it is also the control that leaves for the conversation, and
    /// it is a ``PointingHandButton`` only where going there is actually wired:
    /// that button promises a link under the pointer wherever it is hovered,
    /// key window or not, and a promise kept by nothing is worse than no
    /// promise. Where it is not wired it is a plain button with no target —
    /// still the picture that says which application, which is worth having on
    /// its own.
    private let headerView: SessionHeaderView
    private let timeLabel = NSTextField(labelWithString: "")
    private let bubble: AIChatBubbleView

    /// What is drawn between the bubble and its timestamp while a message this
    /// client wrote has not been read back: thinking dots, or the reason it
    /// never will be. Nil for everything a source said, which is every message
    /// but the reader's own.
    private let deliveryView: NSView?
    private let failureLabel: NSTextField?

    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    /// Whether this is the row the keyboard is pointing at.
    ///
    /// Drawn as a frame rather than a fill: the hover fill already means "the
    /// mouse is here", and a second fill would leave a reader unable to tell a
    /// row they are pointing at from the one they picked. A border also leaves
    /// the bubble's own colour — which says who is talking — untouched.
    public var isSelected = false {
        didSet {
            guard oldValue != isSelected else { return }
            applySelectionFrame(resolvedThemeScope.palette)
        }
    }

    /// The message this row is showing. What a caller gets back when the
    /// selection moves by keyboard rather than by a press on a particular row.
    public var shownMessage: ChatMessage { message }

    /// Whether the row is showing less than the message holds.
    public var isTruncated: Bool { bubble.isTruncated }

    /// Whether the message runs past the row's line limit — the question a
    /// keyboard asks before offering to open it out, since it stays true while
    /// the row is open and so answers "can this be closed again" too.
    public var isExpandable: Bool { bubble.isExpandable }

    /// Whether the row is showing the whole message, line limit or no.
    ///
    /// Settable, so the transcript can open a row the reader is looking at
    /// without rebuilding itself around it — a rebuild empties the stack, and
    /// the row that comes back is at the top of a transcript scrolled somewhere
    /// else entirely.
    public var isExpanded: Bool {
        get { bubble.isExpanded }
        set { bubble.isExpanded = newValue }
    }

    /// Thick enough to read as a frame at a glance across a busy feed, thin
    /// enough not to shift the row's content when it appears — it is drawn
    /// inside the row's own bounds.
    private static let selectionBorderWidth: CGFloat = 2

    /// Inset of the row's content from the highlight's edge, so hovering paints
    /// a band around the row rather than a rectangle flush against its text.
    private static let hInset: CGFloat = 8
    private static let vInset: CGFloat = 6

    /// The application icon's side.
    ///
    /// Well short of the 44pt the Sessions window gives the identical control,
    /// because there it *is* the row and here it heads one line of a timeline
    /// whose subject is what was said — but larger than the 24pt symbol it
    /// replaces, since an application icon is a picture to be recognised rather
    /// than a glyph to be read.
    private static let iconSize: CGFloat = 28
    private static let iconGap: CGFloat = 8

    /// How far in from either margin a bubble stops — the icon's column.
    ///
    /// The same on both sides although only one side's column is filled: the
    /// icon belongs to the speaker, so it changes margins from row to row, and
    /// a bubble that claimed the empty column whenever it happened to be free
    /// would give the feed a ragged edge that means nothing.
    private static let outerInset = hInset + iconSize + iconGap

    /// How wide a bubble may grow in a row this wide.
    ///
    /// One column, both sides. A merged feed is read straight down, and two
    /// columns offset by a few points give it four vertical edges where it only
    /// ever meant to have two — noise that says nothing, since who is talking is
    /// already said by the fill, the header's side and the icon's margin. So a
    /// bubble runs between the two icon columns whichever side it is on, and the
    /// sides of the feed line up.
    ///
    /// A bubble with little to say still stops at its own text — see
    /// ``AIChatBubbleView/fillsWidthWhenWrapped``. This is the cap, not the
    /// width.
    public static func maxBubbleWidth(forRowWidth width: CGFloat) -> CGFloat {
        max(width - outerInset * 2, 80)
    }

    /// - Parameters:
    ///   - lineLimit: how many lines of the message the bubble shows before it
    ///     truncates and offers the rest — see ``AIChatBubbleView``.
    ///   - bubbleStyle: which shape the bubble is drawn in — see
    ///     ``AIChatBubbleView/Style``.
    ///   - isExpanded: whether the row starts out showing the whole message —
    ///     see ``isExpanded``.
    public init(
        message: ChatMessage,
        maxBubbleWidth: CGFloat,
        actions: Actions,
        lineLimit: Int? = nil,
        bubbleStyle: AIChatBubbleView.Style = .speaker,
        isExpanded: Bool = false
    ) {
        self.message = message
        let attribution = message.attribution
            ?? .init(sourceID: "", context: [], name: "", iconSymbol: "")
        self.attribution = attribution
        self.actions = actions
        // Only a row that came from somewhere has an application to name: a
        // message still in flight in an ordinary one-to-one chat carries no
        // attribution, and an icon there would be a picture of a guess.
        let icon: SessionHeaderView.IconSpec? = message.attribution.map {
            .init(
                appIdentity: $0.appIdentity,
                side: Self.iconSize,
                // The icon belongs to whoever is talking, so it changes margins
                // from row to row — one of the three things that say who spoke.
                edge: message.role == .user ? .trailing : .leading,
                gap: Self.iconGap,
                isActionable: actions.onJump != nil)
        }
        self.headerView = SessionHeaderView(
            crumbs: .init(context: attribution.context, name: attribution.name),
            textRole: .caption,
            icon: icon)
        // The timestamp gets its own line here, so the bubble renders none.
        self.bubble = AIChatBubbleView(
            message: message,
            maxWidth: max(maxBubbleWidth, 80),
            style: bubbleStyle,
            showsInlineTimestamp: false,
            // Selectable, always: the text of a transcript is the thing a reader
            // most wants out of it, and a row that swallowed the drag to keep a
            // click for itself would be trading the message for the gesture.
            // That is what moved opening to a double click.
            isTextSelectable: true,
            lineLimit: lineLimit,
            // Anything that wraps takes the whole column. A merged feed is read
            // straight down, and paragraphs cut to their own longest line give
            // that column a ragged inside edge that means nothing — "this reply
            // was long" is already in the height. A one-liner still stops at its
            // own words: there the short shape *is* the message, and stretching
            // "ok" across the window would be reading weight into it.
            fillsWidthWhenWrapped: true,
            isExpanded: isExpanded
        )
        switch message.delivery {
        case .settled:
            self.deliveryView = nil
            self.failureLabel = nil
        case .sending:
            // The same dots the chat window shows while a reply is coming, for
            // the same reason: something was said and the answer is not here
            // yet. That it is *this* message waiting rather than the next one
            // is said by where they are — under the bubble, not after it.
            let indicator = TypingIndicatorView()
            self.deliveryView = indicator
            self.failureLabel = nil
        case .failed(let reason):
            let label = NSTextField(labelWithString: reason)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byWordWrapping
            label.maximumNumberOfLines = 0
            // Wrapping is only half of it: a label measures itself on one line
            // unless it is told the width it will be laid out at, so a reason
            // as long as "Typing into a session needs iTerm2 or Terminal.app;
            // this one runs in Ghostty" comes out one line tall and truncated
            // — the half that says what to do about it cut off. The cap the
            // bubble beside it uses is the starting width; `layout()` narrows
            // it to whatever the row actually gave the label.
            label.preferredMaxLayoutWidth = max(maxBubbleWidth, 80)
            self.deliveryView = label
            self.failureLabel = label
        }
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8

        setupSubviews()
        installConstraints()

        observeTheme { row, palette in row.apply(palette) }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    /// Re-measures the failure reason against the width the row actually gave
    /// it.
    ///
    /// The bubble's cap is an upper bound; the row is narrower than that
    /// whenever the window is, and a label measured for a width it did not get
    /// is measured for the wrong number of lines. Setting the width it has and
    /// asking for a fresh intrinsic size is the AppKit recipe for a wrapping
    /// label that has to be as tall as its text — and it settles, because the
    /// width is then the one the constraints already produced.
    public override func layout() {
        super.layout()
        guard let failureLabel, failureLabel.frame.width > 0,
              failureLabel.preferredMaxLayoutWidth != failureLabel.frame.width
        else { return }
        failureLabel.preferredMaxLayoutWidth = failureLabel.frame.width
        failureLabel.invalidateIntrinsicContentSize()
    }

    /// Which column the row lives in. A merged transcript still keeps the two
    /// sides apart — that is what makes it scannable — even though the header
    /// is what actually identifies the speaker.
    private var isFromUser: Bool { message.role == .user }

    /// Whether pressing the row itself means anything. The hover fill and the
    /// pointing-hand cursor are promises that it does, so both are held back
    /// when the row is only something to read.
    private var isPressable: Bool { actions.onOpen != nil }

    /// The application's icon, when this row has one — see the header's own
    /// ``SessionHeaderView/iconButton``.
    private var appIcon: NSButton? { headerView.iconButton }

    // MARK: - Build

    private func setupSubviews() {
        // The application the conversation is running in, not a badge for the
        // speaker: a reader scanning a merged feed is looking for *their*
        // window, and the icon they would find it by on the Dock is the fastest
        // way to say which row is it. Same control and same mapping as the
        // Sessions list, drawn smaller here because there it is the row.
        if let appIcon {
            appIcon.accessibilityID("chat-row.jump")
            if actions.onJump != nil {
                appIcon.target = self
                appIcon.action = #selector(jumpTapped)
                appIcon.toolTip = attribution.appIdentity.isEmpty
                    ? "Go to this conversation"
                    : "Go to this conversation in \(attribution.appIdentity)"
                appIcon.setAccessibilityLabel("Go to \(attribution.headerLine)")
            }
        }

        headerView.setAccessibilityLabel(attribution.headerLine)
        headerView.accessibilityID("chat-row.header")

        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.stringValue = AIChatBubbleView.timeFormatter.string(from: message.timestamp)
        timeLabel.alignment = isFromUser ? .right : .left

        bubble.setContentHuggingPriority(.required, for: .horizontal)
        bubble.onToggleExpanded = { [weak self] in
            guard let self else { return }
            self.actions.onToggleExpanded?(self.message)
        }
        // A click anywhere in the row picks it, the bubble's own text included:
        // hit-testing hands presses on the text to the bubble, so a row that
        // only listened for its own margins would be selectable everywhere
        // except where a reader actually clicks.
        if actions.onSelect != nil {
            bubble.onSingleClick = { [weak self] in
                guard let self else { return }
                self.actions.onSelect?(self.message)
            }
        }
        // Only where opening is wired. Where it is not — inside a conversation
        // that is already open — the bubble keeps the gesture and a double click
        // selects a word, which is what a reader copying a line expects of it.
        if actions.onOpen != nil {
            bubble.onDoubleClick = { [weak self] in
                guard let self else { return }
                self.actions.onOpen?(self.message)
            }
        }

        if let deliveryView {
            deliveryView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(deliveryView)
            (deliveryView as? TypingIndicatorView)?.startAnimating()
        }

        addSubview(headerView)
        addSubview(bubble)
        addSubview(timeLabel)
    }

    /// Laid out by hand rather than with nested stack views: the row is mirrored
    /// about its own centre line, and "the same layout, flipped" is one set of
    /// anchors chosen per side — where stacked views would be two hierarchies.
    ///
    /// The header line is the one exception, and it is a stack because it is the
    /// shared control: the icon and the trail keep their own arrangement
    /// wherever the header is used, and only which margin the whole line is
    /// against is this row's business.
    private func installConstraints() {
        let outerEdge = isFromUser ? trailingAnchor : leadingAnchor
        let inset = isFromUser ? -Self.hInset : Self.hInset
        let headerEdge = isFromUser ? headerView.trailingAnchor : headerView.leadingAnchor
        // The bubble and the timestamp line up with the *trail*, not with the
        // header as a whole: the icon sits outside the column, in the margin.
        // With no icon the two are the same edge, which is what puts an
        // unattributed message against the row's own inset.
        let crumbs = headerView.breadcrumb
        let contentEdge = isFromUser ? crumbs.trailingAnchor : crumbs.leadingAnchor

        var constraints: [NSLayoutConstraint] = [
            headerView.topAnchor.constraint(equalTo: topAnchor, constant: Self.vInset + 3),
            headerEdge.constraint(equalTo: outerEdge, constant: inset),

            bubble.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 4),
            timeLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.vInset)
        ]

        // The delivery mark takes the gap between the bubble and its timestamp,
        // so a message that is waiting or that failed is taller than a settled
        // one by exactly that mark — nothing else about the row moves.
        if let deliveryView {
            constraints += [
                deliveryView.topAnchor.constraint(equalTo: bubble.bottomAnchor, constant: 4),
                timeLabel.topAnchor.constraint(equalTo: deliveryView.bottomAnchor, constant: 2),
                deliveryView.widthAnchor.constraint(lessThanOrEqualTo: bubble.widthAnchor),
                (isFromUser ? deliveryView.trailingAnchor : deliveryView.leadingAnchor)
                    .constraint(equalTo: contentEdge)
            ]
        } else {
            constraints.append(
                timeLabel.topAnchor.constraint(equalTo: bubble.bottomAnchor, constant: 2))
        }

        // The bubble and the time align with the header on the speaker's side;
        // on the far side the bubble stops at the other side's icon column —
        // the same limit ``maxBubbleWidth(forRowWidth:)`` measured, said again
        // as a constraint so a row narrower than the width it was built for
        // still honours it, and so both columns end on the same two lines.
        let timeAtMargin = isFromUser
            ? timeLabel.trailingAnchor.constraint(equalTo: crumbs.trailingAnchor)
            : timeLabel.leadingAnchor.constraint(equalTo: crumbs.leadingAnchor)

        if isFromUser {
            constraints += [
                bubble.trailingAnchor.constraint(equalTo: crumbs.trailingAnchor),
                timeAtMargin,
                crumbs.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor,
                                                constant: Self.outerInset),
                bubble.leadingAnchor.constraint(
                    greaterThanOrEqualTo: leadingAnchor,
                    constant: Self.outerInset)
            ]
        } else {
            constraints += [
                bubble.leadingAnchor.constraint(equalTo: crumbs.leadingAnchor),
                timeAtMargin,
                crumbs.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor,
                                                 constant: -Self.outerInset),
                bubble.trailingAnchor.constraint(
                    lessThanOrEqualTo: trailingAnchor,
                    constant: -Self.outerInset)
            ]
        }
        NSLayoutConstraint.activate(constraints)
    }

    // MARK: - Theme

    private func apply(_ palette: SemanticPalette) {
        headerView.applyTheme(palette)

        timeLabel.font = palette.font(.caption)
        timeLabel.textColor = palette.nsColor(.timestampText)

        failureLabel?.font = palette.font(.caption)
        failureLabel?.textColor = palette.nsColor(.danger)

        // Nothing to theme on the icon: an application's icon is its own
        // artwork, and a tint or a disc behind it would be this window's
        // opinion painted over the one thing in the row a reader recognises
        // without reading.

        applyHoverFill(palette)
        applySelectionFrame(palette)
    }

    private func applySelectionFrame(_ palette: SemanticPalette) {
        layer?.borderWidth = isSelected ? Self.selectionBorderWidth : 0
        layer?.borderColor = isSelected ? palette.nsColor(.selection).cgColor : nil
    }

    private func applyHoverFill(_ palette: SemanticPalette) {
        layer?.backgroundColor = isHovered
            ? palette.nsColor(.selection).withAlphaComponent(0.18).cgColor
            : NSColor.clear.cgColor
    }

    // MARK: - Mouse

    /// The row is the target, not its parts — except for the parts that mean
    /// something else.
    ///
    /// They have to be named here rather than left to the normal search, because
    /// that search never happens: this override answers for the whole subtree.
    /// There are two: the app icon (leave for the session), and the bubble
    /// itself — its expand toggle, and its text, which a reader drags across to
    /// copy and whose double click this row reads as "open".
    public override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if let hit = super.hitTest(point), hit !== self, isInteractive(hit) { return hit }
        return self
    }

    private func isInteractive(_ view: NSView) -> Bool {
        if let appIcon, actions.onJump != nil, view.isDescendant(of: appIcon) { return true }
        return view.isDescendant(of: bubble)
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    /// Hovering lights the row up — unless something is in front of it.
    ///
    /// A tracking area belongs to its view, not to what is drawn over it, so a
    /// row under an overlay still hears the mouse cross it and still lit up:
    /// the reader saw bubbles glowing *through* the conversation they had
    /// opened. Hit-testing from the window's own content view is what asks the
    /// question the tracking area cannot — is this row what the pointer is
    /// actually on?
    public override func mouseEntered(with event: NSEvent) {
        guard isPressable, isFrontmostUnderPointer(event) else { return }
        isHovered = true
        applyHoverFill(resolvedThemeScope.palette)
    }

    private func isFrontmostUnderPointer(_ event: NSEvent) -> Bool {
        guard let content = window?.contentView else { return true }
        let point = content.convert(event.locationInWindow, from: nil)
        guard let hit = content.hitTest(point) else { return false }
        return hit === self || hit.isDescendant(of: self)
    }

    public override func mouseExited(with event: NSEvent) {
        isHovered = false
        applyHoverFill(resolvedThemeScope.palette)
    }

    /// Opens on the second click and on nothing else. A single click stays worth
    /// what it is worth everywhere else — selecting, dismissing, nothing — which
    /// is what makes copying text out of a transcript possible.
    ///
    /// Everything this does not claim goes up the responder chain, which is what
    /// lets a container behind the row — the focus overlay — read a press on a
    /// row as a press on itself. `mouseDown` is not overridden at all for the
    /// same reason.
    public override func mouseUp(with event: NSEvent) {
        guard let onOpen = actions.onOpen,
              event.clickCount >= 2,
              bounds.contains(convert(event.locationInWindow, from: nil)) else {
            super.mouseUp(with: event)
            return
        }
        onOpen(message)
    }

    /// The press that picks the row. Reported and passed on: `super` is what
    /// lets a container behind the row — the focus overlay — still read a press
    /// nothing else took as a press on itself.
    public override func mouseDown(with event: NSEvent) {
        if let onSelect = actions.onSelect,
           bounds.contains(convert(event.locationInWindow, from: nil)) {
            onSelect(message)
        }
        super.mouseDown(with: event)
    }

    @objc private func jumpTapped() {
        actions.onJump?(message)
    }

    public override func resetCursorRects() {
        guard isPressable else { return }
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
