import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreUI
import AgenticToolkitCoreMacOS

/// One row of a *merged* transcript — several conversations interleaved on a
/// single timeline, the way a group chat reads.
///
/// ```
/// [icon] project » branch » session name
///        ╭──────────────────────────────╮
///        │ what the agent said          │
///        ╰──────────────────────────────╯
///        09:41                    [app]
///
///        project » branch » session name
///        ╭──────────────────────────────╮
///        │ what the human said          │
///        ╰──────────────────────────────╯
///           [app]                   09:41
/// ```
///
/// Both sides run between the same two margins. Who is talking is said by the
/// fill, by which side the header and the timestamp are on, and by the avatar
/// the agent's side carries — none of which needs the column to move.
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

    /// The clock reading on the row's own margin, where every other row's is.
    private var timeAtMargin: NSLayoutConstraint!

    /// The clock reading moved to the far side of the jump control, for a
    /// bubble too narrow to hold the two of them side by side.
    private var timePastControl: NSLayoutConstraint!
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

    /// Whether the row is showing less than the message holds — the question a
    /// keyboard asks before offering to open it out, since the **More…** control
    /// that would answer it with a click is drawn only when it is true.
    public var isTruncated: Bool { bubble.isTruncated }

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

    /// The jump control's size.
    ///
    /// Two thirds of the 44pt the Sessions window gives the identical control.
    /// There it is the row's subject; here it is a badge pinned to the corner of
    /// a bubble, and at full size it was the loudest thing on a timeline whose
    /// subject is what was said.
    private static let jumpSize: CGFloat = 30

    /// How far the jump control leans on the bubble it belongs to.
    ///
    /// A few points, not half the control: the overlap is there to say *whose*
    /// bubble this is, and any more of it puts a 30pt disc over the last line
    /// of the message — which is the one line a truncated bubble cannot spare,
    /// since that is where its own **More…** control lives.
    private static let jumpOverlap: CGFloat = 4

    /// The least air between the timestamp and the jump control.
    ///
    /// The two share the band under the bubble from opposite ends, and on a
    /// bubble narrow enough — "ok", "cy" — the control, which tracks the
    /// bubble's inside edge, arrives where the timestamp already was. The
    /// timestamp is the one that gives way: the control's position is what says
    /// *which* bubble it belongs to, while a clock reading says the same thing
    /// wherever in the band it sits.
    private static let timeClearance: CGFloat = 6

    /// How far in from the row's leading edge every bubble starts — the agent's
    /// avatar column — and how far in from the trailing edge every bubble ends.
    private static let agentOuterInset = hInset + iconSize + iconGap
    private static let userOuterInset = hInset

    /// How wide a bubble may grow in a row this wide.
    ///
    /// One column, both sides. A merged feed is read straight down, and two
    /// columns offset by a few points give it four vertical edges where it only
    /// ever meant to have two — noise that says nothing, since who is talking is
    /// already said by the fill, the header's side and the avatar. So a bubble
    /// runs from the avatar column to the far margin whichever side it is on,
    /// and the sides of the feed line up.
    ///
    /// A bubble with little to say still stops at its own text — see
    /// ``AIChatBubbleView/fillsWidthWhenWrapped``. This is the cap, not the
    /// width.
    public static func maxBubbleWidth(forRowWidth width: CGFloat) -> CGFloat {
        max(width - agentOuterInset - userOuterInset, 80)
    }

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
        // The timestamp gets its own line here, so the bubble renders none.
        //
        // Nothing is held back for the jump control: it hangs below the bubble
        // in the band the timestamp occupies, inside the bubble's own column —
        // see ``installConstraints()``.
        self.bubble = AIChatBubbleView(
            message: message,
            maxWidth: max(maxBubbleWidth, 80),
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
            fillsWidthWhenWrapped: true
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
        // row is it. Same control and same mapping as the Sessions list, drawn
        // smaller here because there it is the row and here it is a badge.
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

        // The jump control hangs off the bottom of the bubble on its *inside*
        // edge — the side facing the middle of the window, which is the side
        // with room on it and the side a reader's eye is already on. It leans
        // on the bubble by ``jumpOverlap`` and no more: enough to read as
        // belonging to that bubble rather than floating under it, little enough
        // that it never sits over the last line of the message.
        //
        // Below the bubble and not beside it because a bubble is as tall as its
        // text — anything measured off its middle moves from row to row — and
        // because the bottom is where the reading finishes, which is also when
        // going to the session is the thing a reader might want.
        //
        // Its inside edge lines up with the *text's* inside edge, not the
        // bubble's: the text column is the line a reader's eye actually holds,
        // and a control flush with the bubble's rounded corner reads as hanging
        // past it.
        let jumpInnerEdge = isFromUser ? jumpButton.leadingAnchor : jumpButton.trailingAnchor
        let bubbleInnerEdge = isFromUser ? bubble.leadingAnchor : bubble.trailingAnchor
        let textEdge = isFromUser
            ? AIChatBubbleView.textInset
            : -AIChatBubbleView.textInset
        constraints += [
            jumpInnerEdge.constraint(equalTo: bubbleInnerEdge, constant: textEdge),
            jumpButton.topAnchor.constraint(equalTo: bubble.bottomAnchor,
                                            constant: -Self.jumpOverlap),
            jumpButton.widthAnchor.constraint(equalToConstant: Self.jumpSize),
            jumpButton.heightAnchor.constraint(equalToConstant: Self.jumpSize),
            // Nearly all of the control is below the bubble, in the band the
            // delivery mark and the timestamp occupy; the row grows if it has to
            // rather than letting the control hang out past its own bounds,
            // where ``hitTest(_:)`` would stop answering for it.
            bottomAnchor.constraint(greaterThanOrEqualTo: jumpButton.bottomAnchor,
                                    constant: Self.vInset)
        ]

        // The bubble and the time align with the header on the speaker's side;
        // on the far side the bubble stops at the other side's margin — the same
        // limit ``maxBubbleWidth(forRowWidth:)`` measured, said again as a
        // constraint so a row narrower than the width it was built for still
        // honours it, and so both columns end on the same two lines.
        // The two places the clock reading can sit; ``placeTimestamp()`` picks
        // between them once the bubble's width is known.
        timeAtMargin = isFromUser
            ? timeLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor)
            : timeLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor)
        timePastControl = isFromUser
            ? timeLabel.trailingAnchor.constraint(equalTo: jumpButton.leadingAnchor,
                                                  constant: -Self.timeClearance)
            : timeLabel.leadingAnchor.constraint(equalTo: jumpButton.trailingAnchor,
                                                 constant: Self.timeClearance)

        if isFromUser {
            constraints += [
                bubble.trailingAnchor.constraint(equalTo: header.trailingAnchor),
                timeAtMargin,
                header.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor,
                                                constant: Self.hInset),
                bubble.leadingAnchor.constraint(
                    greaterThanOrEqualTo: leadingAnchor,
                    constant: Self.agentOuterInset)
            ]
        } else {
            constraints += [
                bubble.leadingAnchor.constraint(equalTo: header.leadingAnchor),
                timeAtMargin,
                header.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor,
                                                 constant: -Self.hInset),
                bubble.trailingAnchor.constraint(
                    lessThanOrEqualTo: trailingAnchor,
                    constant: -Self.userOuterInset)
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

        // A new face is a new width, for the bubble and for the reading both —
        // so whether the band under the bubble still holds the two of them is
        // a question this has just re-opened.
        needsUpdateConstraints = true
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

    /// Constraints first, because where the clock reading goes is one of them.
    public override func updateConstraints() {
        placeTimestamp()
        super.updateConstraints()
    }

    /// Puts the clock reading where there is room for it.
    ///
    /// The timestamp and the jump control come at the band under the bubble
    /// from opposite ends — the timestamp from the row's margin, the control
    /// from the bubble's inside edge — and on a bubble as narrow as "ok" they
    /// arrive in the same place. The timestamp is what moves: the control's
    /// position is what says *which* bubble it belongs to, while a clock
    /// reading says the same thing wherever along the band it sits.
    ///
    /// Both widths are known here, before anything is laid out: the bubble
    /// measures its own text, and the reading is a label with an intrinsic
    /// size. Which is why the choice is made in the constraint pass — a view
    /// may not rearrange itself from inside a layout pass, and one that tries
    /// is simply ignored.
    private func placeTimestamp() {
        guard !jumpButton.isHidden, timeAtMargin != nil else { return }
        // What the band needs to hold both: the control, inset from the
        // bubble's edge by the width of the text's own inset, then air, then
        // the reading itself.
        let needed = AIChatBubbleView.textInset + Self.jumpSize
            + Self.timeClearance + timeLabel.intrinsicContentSize.width
        let crowded = bubble.measuredWidth < needed
        guard crowded == timeAtMargin.isActive else { return }

        // Deactivated first: both are required, and a moment with the two of
        // them on is a conflict the engine would report.
        if crowded {
            timeAtMargin.isActive = false
            timePastControl.isActive = true
        } else {
            timePastControl.isActive = false
            timeAtMargin.isActive = true
        }
    }

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
