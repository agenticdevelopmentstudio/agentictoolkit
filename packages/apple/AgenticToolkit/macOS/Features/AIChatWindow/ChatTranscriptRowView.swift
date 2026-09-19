import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreUI
import AgenticToolkitCoreMacOS

/// One row of a *merged* transcript — several conversations interleaved on a
/// single timeline, the way a group chat reads.
///
/// ```
/// [icon] project/branch (session name)
///        ╭──────────────────────────╮
///        │ what the agent said      │
///        ╰──────────────────────────╯
///        09:41
///
///                project/branch (session name)  [icon]
///                       ╭──────────────────────────╮
///                       │ what the human said      │
///                       ╰──────────────────────────╯
///                                            09:41
/// ```
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
    /// closure at a time because they are four faces of one gesture — a click,
    /// a press held, that press released, and a click on the row's own control —
    /// and a caller that wires one usually wires several.
    public struct Actions {
        /// A plain click on the row.
        public var onTap: ((ChatMessage) -> Void)?
        /// The row's jump control was clicked: leave for wherever this came from.
        public var onJump: ((ChatMessage) -> Void)?
        /// The mouse has been held down on the row long enough to mean "hold
        /// this open while I look".
        public var onPeekBegan: ((ChatMessage) -> Void)?
        /// That hold ended. Always paired with an ``onPeekBegan``, and a row
        /// that peeked does **not** also fire ``onTap`` on release.
        public var onPeekEnded: ((ChatMessage) -> Void)?

        public init(
            onTap: ((ChatMessage) -> Void)? = nil,
            onJump: ((ChatMessage) -> Void)? = nil,
            onPeekBegan: ((ChatMessage) -> Void)? = nil,
            onPeekEnded: ((ChatMessage) -> Void)? = nil
        ) {
            self.onTap = onTap
            self.onJump = onJump
            self.onPeekBegan = onPeekBegan
            self.onPeekEnded = onPeekEnded
        }
    }

    private let message: ChatMessage
    private let attribution: ChatMessage.Attribution
    private let actions: Actions

    private let iconContainer = NSView()
    private let iconView = NSImageView()
    private let headerLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private let bubble: AIChatBubbleView
    private let jumpButton = NSButton()

    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    /// Armed on mouse-down, fired if the button is still down when it lands.
    private var peekWorkItem: DispatchWorkItem?
    private var isPeeking = false

    /// Inset of the row's content from the highlight's edge, so hovering paints
    /// a band around the row rather than a rectangle flush against its text.
    private static let hInset: CGFloat = 8
    private static let vInset: CGFloat = 6
    private static let iconSize: CGFloat = 24
    private static let iconGap: CGFloat = 8

    /// The jump control's size, and its gap from the bubble's inside edge.
    private static let jumpSize: CGFloat = 16
    private static let jumpGap: CGFloat = 10

    /// How long the mouse has to stay down before the press stops being a click
    /// and becomes a peek. Long enough not to fire on an ordinary click
    /// (`NSEvent.doubleClickInterval` is typically 0.5s and a click is far
    /// shorter than that), short enough that holding feels like a gesture rather
    /// than a wait.
    private static let peekDelay: TimeInterval = 0.3

    public init(message: ChatMessage, maxBubbleWidth: CGFloat, actions: Actions) {
        self.message = message
        self.attribution = message.attribution ?? .init(sourceID: "", context: "", name: "", iconSymbol: "")
        self.actions = actions
        // The jump control sits *outside* the bubble, so the room it needs comes
        // out of the width the bubble may grow to. Charging it to the bubble
        // here — rather than asking every caller to subtract it — is what keeps
        // the control on screen in a narrow window, where a full-width bubble
        // would otherwise push it past the row's own edge.
        let reserved = actions.onJump == nil ? 0 : Self.jumpGap + Self.jumpSize
        // The timestamp gets its own line here, and the row — not the text —
        // takes the click, so the bubble renders neither.
        self.bubble = AIChatBubbleView(
            message: message,
            maxWidth: max(maxBubbleWidth - reserved, 80),
            showsInlineTimestamp: false,
            isTextSelectable: false
        )
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

    /// Which column the row lives in. A merged transcript still keeps the two
    /// sides apart — that is what makes it scannable — even though the header
    /// is what actually identifies the speaker.
    private var isFromUser: Bool { message.role == .user }

    /// Whether pressing the row itself means anything. The hover fill and the
    /// pointing-hand cursor are promises that it does, so both are held back
    /// when the row is only something to read.
    private var isPressable: Bool { actions.onTap != nil || actions.onPeekBegan != nil }

    // MARK: - Build

    private func setupSubviews() {
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.wantsLayer = true
        iconContainer.layer?.cornerRadius = Self.iconSize / 2

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(
            systemSymbolName: attribution.iconSymbol,
            accessibilityDescription: attribution.headerLine
        )
        iconView.symbolConfiguration = .init(pointSize: 12, weight: .medium)
        iconView.imageScaling = .scaleProportionallyDown
        iconContainer.addSubview(iconView)

        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.stringValue = attribution.headerLine
        headerLabel.lineBreakMode = .byTruncatingMiddle
        headerLabel.alignment = isFromUser ? .right : .left
        headerLabel.accessibilityID("chat-row.header")

        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.stringValue = AIChatBubbleView.timeFormatter.string(from: message.timestamp)
        timeLabel.alignment = isFromUser ? .right : .left

        bubble.setContentHuggingPriority(.required, for: .horizontal)

        jumpButton.translatesAutoresizingMaskIntoConstraints = false
        jumpButton.image = NSImage(
            systemSymbolName: "arrow.up.forward.app",
            accessibilityDescription: "Go to \(attribution.headerLine)"
        )
        jumpButton.symbolConfiguration = .init(pointSize: 12, weight: .medium)
        jumpButton.isBordered = false
        jumpButton.imageScaling = .scaleProportionallyDown
        jumpButton.target = self
        jumpButton.action = #selector(jumpTapped)
        jumpButton.toolTip = "Go to this conversation"
        jumpButton.isHidden = actions.onJump == nil
        jumpButton.accessibilityID("chat-row.jump")

        addSubview(iconContainer)
        addSubview(headerLabel)
        addSubview(bubble)
        addSubview(timeLabel)
        addSubview(jumpButton)
    }

    /// Laid out by hand rather than with nested stack views: the row is mirrored
    /// about its own centre line, and "the same layout, flipped" is one set of
    /// anchors chosen per side — where stacked views would be two hierarchies.
    private func installConstraints() {
        let outerEdge = isFromUser ? trailingAnchor : leadingAnchor
        let iconOuter = isFromUser ? iconContainer.trailingAnchor : iconContainer.leadingAnchor
        let iconInner = isFromUser ? iconContainer.leadingAnchor : iconContainer.trailingAnchor
        let contentEdge = isFromUser ? headerLabel.trailingAnchor : headerLabel.leadingAnchor
        let inset = isFromUser ? -Self.hInset : Self.hInset
        let gap = isFromUser ? -Self.iconGap : Self.iconGap

        var constraints: [NSLayoutConstraint] = [
            iconOuter.constraint(equalTo: outerEdge, constant: inset),
            iconContainer.topAnchor.constraint(equalTo: topAnchor, constant: Self.vInset),
            iconContainer.widthAnchor.constraint(equalToConstant: Self.iconSize),
            iconContainer.heightAnchor.constraint(equalToConstant: Self.iconSize),
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),

            contentEdge.constraint(equalTo: iconInner, constant: gap),
            headerLabel.topAnchor.constraint(equalTo: topAnchor, constant: Self.vInset + 3),

            bubble.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 4),
            timeLabel.topAnchor.constraint(equalTo: bubble.bottomAnchor, constant: 2),
            timeLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.vInset),
            heightAnchor.constraint(greaterThanOrEqualTo: iconContainer.heightAnchor,
                                    constant: Self.vInset * 2)
        ]

        // The jump control hangs off the bubble's *inside* edge — the one facing
        // the middle of the window, which is the side with room on it, and the
        // side a reader's eye is already on. Level with the bubble's first line
        // of text rather than with the bubble, which on a long message would put
        // it halfway down a paragraph.
        let jumpEdge = isFromUser ? jumpButton.trailingAnchor : jumpButton.leadingAnchor
        let bubbleInnerEdge = isFromUser ? bubble.leadingAnchor : bubble.trailingAnchor
        constraints += [
            jumpEdge.constraint(equalTo: bubbleInnerEdge,
                                constant: isFromUser ? -Self.jumpGap : Self.jumpGap),
            jumpButton.centerYAnchor.constraint(equalTo: bubble.firstLineCenterYAnchor),
            jumpButton.widthAnchor.constraint(equalToConstant: Self.jumpSize),
            jumpButton.heightAnchor.constraint(equalToConstant: Self.jumpSize)
        ]

        // The bubble and the time align with the header on the speaker's side;
        // on the far side they only have to stay inside the row.
        if isFromUser {
            constraints += [
                bubble.trailingAnchor.constraint(equalTo: headerLabel.trailingAnchor),
                timeLabel.trailingAnchor.constraint(equalTo: headerLabel.trailingAnchor),
                headerLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor,
                                                     constant: Self.hInset),
                bubble.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor,
                                                constant: Self.hInset)
            ]
        } else {
            constraints += [
                bubble.leadingAnchor.constraint(equalTo: headerLabel.leadingAnchor),
                timeLabel.leadingAnchor.constraint(equalTo: headerLabel.leadingAnchor),
                headerLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor,
                                                      constant: -Self.hInset),
                bubble.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor,
                                                 constant: -Self.hInset)
            ]
        }
        NSLayoutConstraint.activate(constraints)
    }

    // MARK: - Theme

    private func apply(_ palette: SemanticPalette) {
        headerLabel.font = palette.font(.caption)
        headerLabel.textColor = palette.nsColor(isFromUser ? .userName : .personaName)

        timeLabel.font = palette.font(.caption)
        timeLabel.textColor = palette.nsColor(.timestampText)

        iconContainer.layer?.backgroundColor =
            palette.nsColor(isFromUser ? .userBubble : .personaBubble).cgColor
        iconView.contentTintColor = palette.nsColor(isFromUser ? .userName : .personaName)

        applyHoverFill(palette)
    }

    private func applyHoverFill(_ palette: SemanticPalette) {
        layer?.backgroundColor = isHovered
            ? palette.nsColor(.selection).withAlphaComponent(0.18).cgColor
            : NSColor.clear.cgColor
    }

    // MARK: - Mouse

    /// The row is the target, not its parts: a click anywhere on it — the icon,
    /// the header, the bubble's text — means the same thing.
    ///
    /// The one exception is the jump control, which means something *else*. It
    /// has to be named here rather than left to the normal search, because that
    /// search never happens: this override answers for the whole subtree.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if !jumpButton.isHidden, jumpButton.frame.contains(local) { return jumpButton }
        return self
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

    public override func mouseEntered(with event: NSEvent) {
        guard isPressable else { return }
        isHovered = true
        applyHoverFill(resolvedThemeScope.palette)
    }

    public override func mouseExited(with event: NSEvent) {
        isHovered = false
        applyHoverFill(resolvedThemeScope.palette)
    }

    /// Arms the peek. A row nobody is watching for a hold passes the press
    /// straight up the responder chain, which is what lets a container behind it
    /// — the focus overlay, say — treat a click on a row as a click on itself.
    public override func mouseDown(with event: NSEvent) {
        guard actions.onPeekBegan != nil else {
            super.mouseDown(with: event)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.peekWorkItem != nil else { return }
            self.isPeeking = true
            self.actions.onPeekBegan?(self.message)
        }
        peekWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.peekDelay, execute: work)
    }

    /// A press that became a peek ends the peek and nothing else: the reader
    /// already saw what a tap would have shown them, and opening it again on
    /// release is the opposite of what letting go means.
    public override func mouseUp(with event: NSEvent) {
        peekWorkItem?.cancel()
        peekWorkItem = nil

        if isPeeking {
            isPeeking = false
            actions.onPeekEnded?(message)
            return
        }
        guard let onTap = actions.onTap,
              bounds.contains(convert(event.locationInWindow, from: nil)) else {
            super.mouseUp(with: event)
            return
        }
        onTap(message)
    }

    @objc private func jumpTapped() {
        actions.onJump?(message)
    }

    public override func resetCursorRects() {
        guard isPressable else { return }
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
