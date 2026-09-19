import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreUI
import AgenticToolkitCoreMacOS

/// One row of a *merged* transcript — several conversations interleaved on a
/// single timeline, the way a group chat reads.
///
/// ```
/// [icon] project » branch » session name
///        ╭──────────────────────────╮ [app]
///        │ what the agent said      │
///        ╰──────────────────────────╯
///        09:41
///
///                 project » branch » session name
///          [app] ╭──────────────────────────╮
///                │ what the human said      │
///                ╰──────────────────────────╯
///                                            09:41
/// ```
///
/// The human's side has no avatar: there is only ever one of them, and a badge
/// repeated down every second row says nothing the side of the window did not
/// already say. The agent's icon stays because it is not decoration — it is
/// which *kind* of line this is, and with work output shown there are four.
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
        /// The bubble's **More…** control was used — this message is truncated
        /// and the reader wants all of it.
        public var onExpand: ((ChatMessage) -> Void)?
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
            onExpand: ((ChatMessage) -> Void)? = nil,
            onSelect: ((ChatMessage) -> Void)? = nil
        ) {
            self.onOpen = onOpen
            self.onJump = onJump
            self.onExpand = onExpand
            self.onSelect = onSelect
        }
    }

    private let message: ChatMessage
    private let attribution: ChatMessage.Attribution
    private let actions: Actions

    private let iconContainer = NSView()
    private let iconView = NSImageView()
    private let header = SessionBreadcrumbView(textRole: .caption)
    private let timeLabel = NSTextField(labelWithString: "")
    private let bubble: AIChatBubbleView
    private let jumpButton = PointingHandButton()

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

    /// Thick enough to read as a frame at a glance across a busy feed, thin
    /// enough not to shift the row's content when it appears — it is drawn
    /// inside the row's own bounds.
    private static let selectionBorderWidth: CGFloat = 2

    /// Inset of the row's content from the highlight's edge, so hovering paints
    /// a band around the row rather than a rectangle flush against its text.
    private static let hInset: CGFloat = 8
    private static let vInset: CGFloat = 6
    private static let iconSize: CGFloat = 24
    private static let iconGap: CGFloat = 8

    /// The jump control's size, and its gap from the bubble's inside edge.
    ///
    /// The same 44pt the Sessions window gives the identical control, because it
    /// *is* the identical control — the application the conversation is running
    /// in, clicked to go there. A reader who has learned that icon in one window
    /// should not have to learn a smaller one here.
    private static let jumpSize: CGFloat = 44
    private static let jumpGap: CGFloat = 10

    /// - Parameters:
    ///   - lineLimit: how many lines of the message the bubble shows before it
    ///     truncates and offers the rest — see ``AIChatBubbleView``.
    public init(
        message: ChatMessage,
        maxBubbleWidth: CGFloat,
        actions: Actions,
        lineLimit: Int? = nil
    ) {
        self.message = message
        self.attribution = message.attribution
            ?? .init(sourceID: "", context: [], name: "", iconSymbol: "")
        self.actions = actions
        // The jump control sits *outside* the bubble, so the room it needs comes
        // out of the width the bubble may grow to. Charging it to the bubble
        // here — rather than asking every caller to subtract it — is what keeps
        // the control on screen in a narrow window, where a full-width bubble
        // would otherwise push it past the row's own edge.
        let reserved = actions.onJump == nil ? 0 : Self.jumpGap + Self.jumpSize
        // The timestamp gets its own line here, so the bubble renders none.
        self.bubble = AIChatBubbleView(
            message: message,
            maxWidth: max(maxBubbleWidth - reserved, 80),
            showsInlineTimestamp: false,
            // Selectable, always: the text of a transcript is the thing a reader
            // most wants out of it, and a row that swallowed the drag to keep a
            // click for itself would be trading the message for the gesture.
            // That is what moved opening to a double click.
            isTextSelectable: true,
            lineLimit: lineLimit
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

    /// Which column the row lives in. A merged transcript still keeps the two
    /// sides apart — that is what makes it scannable — even though the header
    /// is what actually identifies the speaker.
    private var isFromUser: Bool { message.role == .user }

    /// Whether pressing the row itself means anything. The hover fill and the
    /// pointing-hand cursor are promises that it does, so both are held back
    /// when the row is only something to read.
    private var isPressable: Bool { actions.onOpen != nil }

    /// Whether the row carries an avatar. Only the agent's side does: there is
    /// only ever one human here, so a badge repeated down every second row is a
    /// column of the same fact. The agent's stays because it says which *kind*
    /// of line this is.
    private var showsIcon: Bool { !isFromUser }

    // MARK: - Build

    private func setupSubviews() {
        if showsIcon {
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
        }

        // The same trail the Sessions window heads its rows with, down to the
        // separator and the colour of each segment — the two windows are looking
        // at the same sessions, and a reader should not have to learn it twice.
        header.crumbs = .init(context: attribution.context, name: attribution.name)
        header.setAccessibilityLabel(attribution.headerLine)
        header.accessibilityID("chat-row.header")

        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.stringValue = AIChatBubbleView.timeFormatter.string(from: message.timestamp)
        timeLabel.alignment = isFromUser ? .right : .left

        bubble.setContentHuggingPriority(.required, for: .horizontal)
        bubble.onExpand = { [weak self] in
            guard let self else { return }
            self.actions.onExpand?(self.message)
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

        // The application the conversation is running in, not a generic arrow:
        // a reader scanning a merged feed is looking for *their* window, and the
        // icon they would find it by on the Dock is the fastest way to say which
        // row is it. Same control, same size, same mapping as the Sessions list.
        jumpButton.translatesAutoresizingMaskIntoConstraints = false
        jumpButton.image = TerminalAppIcon.image(forTermProgram: attribution.appIdentity)
        jumpButton.imagePosition = .imageOnly
        jumpButton.imageScaling = .scaleProportionallyUpOrDown
        jumpButton.isBordered = false
        jumpButton.bezelStyle = .shadowlessSquare
        jumpButton.target = self
        jumpButton.action = #selector(jumpTapped)
        jumpButton.toolTip = attribution.appIdentity.isEmpty
            ? "Go to this conversation"
            : "Go to this conversation in \(attribution.appIdentity)"
        jumpButton.setAccessibilityLabel("Go to \(attribution.headerLine)")
        jumpButton.isHidden = actions.onJump == nil
        jumpButton.accessibilityID("chat-row.jump")

        if let deliveryView {
            deliveryView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(deliveryView)
            (deliveryView as? TypingIndicatorView)?.startAnimating()
        }

        if showsIcon { addSubview(iconContainer) }
        addSubview(header)
        addSubview(bubble)
        addSubview(timeLabel)
        addSubview(jumpButton)
    }

    /// Laid out by hand rather than with nested stack views: the row is mirrored
    /// about its own centre line, and "the same layout, flipped" is one set of
    /// anchors chosen per side — where stacked views would be two hierarchies.
    private func installConstraints() {
        let outerEdge = isFromUser ? trailingAnchor : leadingAnchor
        let contentEdge = isFromUser ? header.trailingAnchor : header.leadingAnchor
        let inset = isFromUser ? -Self.hInset : Self.hInset
        let gap = isFromUser ? -Self.iconGap : Self.iconGap

        var constraints: [NSLayoutConstraint] = [
            header.topAnchor.constraint(equalTo: topAnchor, constant: Self.vInset + 3),

            bubble.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
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

        // With an icon the content hangs off its inside edge; without one — the
        // human's side, which has no avatar — it starts at the row's own edge.
        if showsIcon {
            let iconOuter = isFromUser ? iconContainer.trailingAnchor : iconContainer.leadingAnchor
            let iconInner = isFromUser ? iconContainer.leadingAnchor : iconContainer.trailingAnchor
            constraints += [
                iconOuter.constraint(equalTo: outerEdge, constant: inset),
                iconContainer.topAnchor.constraint(equalTo: topAnchor, constant: Self.vInset),
                iconContainer.widthAnchor.constraint(equalToConstant: Self.iconSize),
                iconContainer.heightAnchor.constraint(equalToConstant: Self.iconSize),
                iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
                iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),

                contentEdge.constraint(equalTo: iconInner, constant: gap),
                heightAnchor.constraint(greaterThanOrEqualTo: iconContainer.heightAnchor,
                                        constant: Self.vInset * 2)
            ]
        } else {
            constraints.append(contentEdge.constraint(equalTo: outerEdge, constant: inset))
        }

        // The jump control hangs off the bubble's *inside* edge — the one facing
        // the middle of the window, which is the side with room on it, and the
        // side a reader's eye is already on. Level with the bubble's **top**
        // rather than its centre: a bubble is as tall as its text, and centring
        // would put the control halfway down a paragraph and at a different
        // height on every row.
        let jumpEdge = isFromUser ? jumpButton.trailingAnchor : jumpButton.leadingAnchor
        let bubbleInnerEdge = isFromUser ? bubble.leadingAnchor : bubble.trailingAnchor
        constraints += [
            jumpEdge.constraint(equalTo: bubbleInnerEdge,
                                constant: isFromUser ? -Self.jumpGap : Self.jumpGap),
            jumpButton.topAnchor.constraint(equalTo: bubble.topAnchor),
            jumpButton.widthAnchor.constraint(equalToConstant: Self.jumpSize),
            jumpButton.heightAnchor.constraint(equalToConstant: Self.jumpSize),
            // A 44pt control beside a one-line bubble is taller than the rest of
            // the row; the row grows to hold it rather than letting it hang out
            // past its own bounds, where ``hitTest(_:)`` would stop answering
            // for it.
            bottomAnchor.constraint(greaterThanOrEqualTo: jumpButton.bottomAnchor,
                                    constant: Self.vInset)
        ]

        // The bubble and the time align with the header on the speaker's side;
        // on the far side they only have to stay inside the row.
        if isFromUser {
            constraints += [
                bubble.trailingAnchor.constraint(equalTo: header.trailingAnchor),
                timeLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor),
                header.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor,
                                                constant: Self.hInset),
                bubble.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor,
                                                constant: Self.hInset)
            ]
        } else {
            constraints += [
                bubble.leadingAnchor.constraint(equalTo: header.leadingAnchor),
                timeLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor),
                header.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor,
                                                 constant: -Self.hInset),
                bubble.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor,
                                                 constant: -Self.hInset)
            ]
        }
        NSLayoutConstraint.activate(constraints)
    }

    // MARK: - Theme

    private func apply(_ palette: SemanticPalette) {
        header.applyTheme(palette)

        timeLabel.font = palette.font(.caption)
        timeLabel.textColor = palette.nsColor(.timestampText)

        failureLabel?.font = palette.font(.caption)
        failureLabel?.textColor = palette.nsColor(.danger)

        if showsIcon {
            iconContainer.layer?.backgroundColor = palette.nsColor(.personaBubble).cgColor
            iconView.contentTintColor = palette.nsColor(.personaName)
        }

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
    /// There are three: the app icon (leave for the session), the **More…**
    /// control (open this message out), and the bubble itself, whose text a
    /// reader drags across to copy and whose double click this row reads as
    /// "open".
    public override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if let hit = super.hitTest(point), hit !== self, isInteractive(hit) { return hit }
        return self
    }

    private func isInteractive(_ view: NSView) -> Bool {
        if !jumpButton.isHidden, view.isDescendant(of: jumpButton) { return true }
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
