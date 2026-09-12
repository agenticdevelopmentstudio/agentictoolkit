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

    private let message: ChatMessage
    private let attribution: ChatMessage.Attribution
    private let onTap: ((ChatMessage) -> Void)?

    private let iconContainer = NSView()
    private let iconView = NSImageView()
    private let headerLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private let bubble: AIChatBubbleView

    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    /// Inset of the row's content from the highlight's edge, so hovering paints
    /// a band around the row rather than a rectangle flush against its text.
    private static let hInset: CGFloat = 8
    private static let vInset: CGFloat = 6
    private static let iconSize: CGFloat = 24
    private static let iconGap: CGFloat = 8

    public init(message: ChatMessage, maxBubbleWidth: CGFloat, onTap: ((ChatMessage) -> Void)?) {
        self.message = message
        self.attribution = message.attribution ?? .init(sourceID: "", context: "", name: "", iconSymbol: "")
        self.onTap = onTap
        // The timestamp gets its own line here, and the row — not the text —
        // takes the click, so the bubble renders neither.
        self.bubble = AIChatBubbleView(
            message: message,
            maxWidth: maxBubbleWidth,
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

        addSubview(iconContainer)
        addSubview(headerLabel)
        addSubview(bubble)
        addSubview(timeLabel)
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
    public override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
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
        guard onTap != nil else { return }
        isHovered = true
        applyHoverFill(resolvedThemeScope.palette)
    }

    public override func mouseExited(with event: NSEvent) {
        isHovered = false
        applyHoverFill(resolvedThemeScope.palette)
    }

    public override func mouseUp(with event: NSEvent) {
        guard let onTap, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onTap(message)
    }

    public override func resetCursorRects() {
        guard onTap != nil else { return }
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
