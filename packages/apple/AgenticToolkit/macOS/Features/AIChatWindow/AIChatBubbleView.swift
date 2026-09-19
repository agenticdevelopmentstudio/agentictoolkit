import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreUI
import AgenticToolkitCoreMacOS

/// A chat message bubble with text and inline timestamp.
///
/// The name is not the obvious one, and that is the point. This framework
/// `@_exported import`s `AgenticDeveloperToolkitUI`, which declares its own
/// `MessageBubbleView` — so a consumer importing both saw two Swift types of
/// that name and had no way to say which it meant. An `@objc(...)` alias fixed
/// only the Objective-C half of that (one runtime class name, colliding
/// compatibility headers) and left every Swift reference ambiguous. The toolkit
/// that ships to customers keeps the plain name; this one, an app feature of
/// ours, takes a qualified one — at Swift level, where the ambiguity actually
/// was. Same reasoning renamed `ChatViewModel` to ``AIChatViewModel``.
public final class AIChatBubbleView: NSView {

    /// `HH:mm`, shared with ``ChatTranscriptRowView`` so a timestamp reads the
    /// same whether it trails the text or sits on its own line under it.
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// What a truncated bubble says where its text stops, and what the control
    /// under it is called.
    private static let ellipsis = "…"
    private static let moreTitle = "More…"

    private let message: ChatMessage
    private let maxWidth: CGFloat
    private let showsInlineTimestamp: Bool
    private let isTextSelectable: Bool

    /// How many lines the bubble shows before it stops and offers the rest, or
    /// nil for a bubble that shows whatever it holds.
    ///
    /// A feed is the case for a limit: a reply that runs forty lines is not more
    /// important than the four around it, but it takes the whole window, and a
    /// reader scrolling past it has lost the thread by the time they are out.
    /// A limit turns that into a fixed-cost row with a way in.
    private let lineLimit: Int?

    private let textView: BubbleTextView
    private let moreButton = NSButton()

    /// Fired by the **More…** control: the message wants showing whole, and this
    /// view is not where that happens — a bubble that grew in place would move
    /// everything under it and lose the reader's place.
    public var onExpand: (() -> Void)? {
        didSet { moreButton.isEnabled = onExpand != nil }
    }

    /// Fired by a double-click anywhere on the bubble's text.
    ///
    /// Set only where a double-click means something; where it is nil the text
    /// view keeps the gesture and a double-click selects a word, which is what a
    /// reader copying a line out of a transcript expects.
    public var onDoubleClick: (() -> Void)? {
        didSet { textView.onDoubleClick = onDoubleClick }
    }

    /// Fired by a single click anywhere on the bubble, text included.
    ///
    /// Unlike ``onDoubleClick`` this does not *take* the gesture: the text view
    /// still starts its selection drag on the same press. A click on a bubble in
    /// a feed means two things at once — select this row, and begin selecting
    /// this text — and neither one is worth taking from the other.
    public var onSingleClick: (() -> Void)? {
        didSet { textView.onSingleClick = onSingleClick }
    }

    /// Whether the text ran past ``lineLimit`` and is showing an ellipsis.
    public private(set) var isTruncated = false

    // The bubble sizes itself to its text, and the theme owns the font, so the
    // measurement has to be redone on every theme change rather than baked in
    // at init. These constraints are what that re-measurement writes.
    private let textWidthConstraint: NSLayoutConstraint
    private let textHeightConstraint: NSLayoutConstraint
    private var bubbleWidthConstraint: NSLayoutConstraint!
    private var moreHeightConstraint: NSLayoutConstraint!
    private var moreGapConstraint: NSLayoutConstraint!

    /// The **More…** control, for a container that has taken over hit-testing
    /// for its whole subtree and has to name the parts that still take a click.
    public var expandControl: NSView { moreButton }

    private static let hPad: CGFloat = 12
    private static let vPad: CGFloat = 8

    /// The **More…** control is a symbol rather than the words, and a big one.
    ///
    /// It is the one thing in a bubble that is not the message, so the words
    /// competed with the text they sat under — three glyphs of caption type
    /// reading as one more line of the reply. A symbol is not read at all, it is
    /// recognised, and at this size it is a target a reader hits without aiming.
    private static let moreSymbol = "ellipsis.circle.fill"
    private static let moreSymbolPointSize: CGFloat = 17
    private static let moreHeight: CGFloat = 22
    private static let moreGap: CGFloat = 2

    /// - Parameters:
    ///   - showsInlineTimestamp: whether the time trails the text inside the
    ///     bubble. A bubble that sits in a ``ChatTranscriptRowView`` has the
    ///     time on its own line underneath instead, so it turns this off rather
    ///     than printing it twice.
    ///   - isTextSelectable: whether the text takes the mouse. A selectable text
    ///     view swallows clicks, which is right for a conversation you are
    ///     reading and copying out of, and wrong for a view whose whole job is
    ///     to be clicked through.
    ///   - lineLimit: the most lines to show before truncating — see
    ///     ``lineLimit``.
    public init(
        message: ChatMessage,
        maxWidth: CGFloat,
        showsInlineTimestamp: Bool = true,
        isTextSelectable: Bool = true,
        lineLimit: Int? = nil
    ) {
        self.message = message
        self.maxWidth = maxWidth
        self.showsInlineTimestamp = showsInlineTimestamp
        self.isTextSelectable = isTextSelectable
        self.lineLimit = lineLimit
        self.textView = BubbleTextView(frame: .zero)
        self.textWidthConstraint = textView.widthAnchor.constraint(equalToConstant: 0)
        self.textHeightConstraint = textView.heightAnchor.constraint(equalToConstant: 0)

        super.init(frame: .zero)
        self.bubbleWidthConstraint = widthAnchor.constraint(equalToConstant: maxWidth)

        wantsLayer = true
        layer?.cornerRadius = 12
        translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = false
        textView.isSelectable = isTextSelectable
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.translatesAutoresizingMaskIntoConstraints = false

        moreButton.image = NSImage(
            systemSymbolName: Self.moreSymbol, accessibilityDescription: Self.moreTitle)
        moreButton.symbolConfiguration = .init(
            pointSize: Self.moreSymbolPointSize, weight: .regular)
        moreButton.imagePosition = .imageOnly
        moreButton.imageScaling = .scaleProportionallyDown
        moreButton.setAccessibilityLabel(Self.moreTitle)
        moreButton.isBordered = false
        moreButton.setButtonType(.momentaryChange)
        moreButton.target = self
        moreButton.action = #selector(moreTapped)
        moreButton.isEnabled = false
        moreButton.isHidden = true
        moreButton.toolTip = "Show the whole message"
        moreButton.accessibilityID("chat-bubble.more")
        moreButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(textView)
        addSubview(moreButton)
        self.moreHeightConstraint = moreButton.heightAnchor.constraint(equalToConstant: 0)
        self.moreGapConstraint = moreButton.topAnchor.constraint(
            equalTo: textView.bottomAnchor, constant: 0)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor, constant: Self.vPad),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.hPad),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.hPad),
            textWidthConstraint,
            textHeightConstraint,
            bubbleWidthConstraint,

            // The control goes under the text rather than over it: a "More…"
            // floated on the last line covers the words it is offering to show.
            moreGapConstraint,
            moreHeightConstraint,
            moreButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.hPad),
            moreButton.leadingAnchor.constraint(
                greaterThanOrEqualTo: leadingAnchor, constant: Self.hPad),
            moreButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.vPad)
        ])

        observeTheme { bubble, palette in bubble.apply(palette) }
    }

    /// The bubble's fill, text color, and optional hairline for this role.
    ///
    /// The two conversational roles use the theme's **chat** vocabulary —
    /// `personaBubble` / `userBubble` and their text and border roles — rather
    /// than a low-alpha tint of `accent`. Those roles exist precisely so a theme
    /// can say what a chat looks like in it, every theme derives them when it
    /// says nothing, and the same tokens drive the web and iOS chats: one
    /// answer to "what colour is a bubble", in the layer that owns colour.
    ///
    /// `error` and `notice` are not conversation, and stay on the general
    /// semantic roles — there is no chat token for "this went wrong".
    private func colors(from palette: SemanticPalette)
    -> (fill: NSColor, text: NSColor, border: NSColor?) {
        // A hairline only where the theme asked for one: derived borders sit
        // close enough to the fill that drawing them everywhere reads as fuzz.
        func border(_ role: ThemeRole) -> NSColor? {
            palette.declares(role) ? palette.nsColor(role) : nil
        }
        switch message.role {
        case .user:
            return (palette.nsColor(.userBubble), palette.nsColor(.userText),
                    border(.userBubbleBorder))
        case .assistant:
            return (palette.nsColor(.personaBubble), palette.nsColor(.personaText),
                    border(.personaBubbleBorder))
        case .error:
            return (palette.nsColor(.danger).withAlphaComponent(0.08),
                    palette.nsColor(.danger), palette.nsColor(.danger))
        case .notice:
            return (palette.nsColor(.secondaryText).withAlphaComponent(0.10),
                    palette.nsColor(.secondaryText), nil)
        }
    }

    private func attributedText(for palette: SemanticPalette) -> NSAttributedString {
        let textColor = colors(from: palette).text
        let bodyFont = palette.font(.body)
        // The timestamp is deliberately smaller than the body it trails; the
        // theme's caption style is that relationship expressed once.
        let timeFont = palette.font(.caption)

        let string = NSMutableAttributedString(
            string: message.text,
            attributes: [.font: bodyFont, .foregroundColor: textColor]
        )
        guard showsInlineTimestamp else { return string }
        string.append(NSAttributedString(
            string: "  " + Self.timeFormatter.string(from: message.timestamp),
            attributes: [.font: timeFont, .foregroundColor: palette.nsColor(.timestampText)]
        ))
        return string
    }

    private func apply(_ palette: SemanticPalette) {
        let (fill, text, border) = colors(from: palette)
        layer?.backgroundColor = fill.cgColor
        layer?.borderColor = border?.cgColor
        layer?.borderWidth = border == nil ? 0 : 1

        let full = attributedText(for: palette)
        let textMaxWidth = maxWidth - Self.hPad * 2

        var shown = full
        var measured = measure(full, width: textMaxWidth)
        if let lineLimit, measured.lineCount > lineLimit,
           let cut = truncating(full, to: lineLimit, using: measured) {
            shown = cut
            measured = measure(cut, width: textMaxWidth)
            isTruncated = true
        } else {
            isTruncated = false
        }

        textView.textContainer?.size = NSSize(
            width: measured.width, height: .greatestFiniteMagnitude)
        textView.textStorage?.setAttributedString(shown)

        textWidthConstraint.constant = measured.width
        textHeightConstraint.constant = measured.height

        moreButton.isHidden = !isTruncated
        // Tinted with the bubble's own text colour: it belongs to this message,
        // and an accent here would read as a different kind of thing entirely.
        moreButton.contentTintColor = text
        moreHeightConstraint.constant = isTruncated ? Self.moreHeight : 0
        moreGapConstraint.constant = isTruncated ? Self.moreGap : 0

        // The control has to fit as well as the text: a one-word message under a
        // "More…" it is narrower than would clip the offer rather than the text.
        let contentWidth = isTruncated
            ? max(measured.width, ceil(moreButton.intrinsicContentSize.width))
            : measured.width
        bubbleWidthConstraint.constant = min(contentWidth + Self.hPad * 2, maxWidth)

        textView.insertionPointColor = palette.nsColor(.cursor)
        textView.selectedTextAttributes = [
            .backgroundColor: palette.nsColor(.selection),
            .foregroundColor: palette.nsColor(.selectionText)
        ]
    }

    // MARK: - Measuring

    /// What one attributed string comes to at a given width.
    ///
    /// The storage is held alongside the layout manager because it *owns* it —
    /// a manager whose storage has gone answers nothing, and the truncation pass
    /// below asks the same manager a second question.
    private struct Measurement {
        let storage: NSTextStorage
        let layoutManager: NSLayoutManager
        let width: CGFloat
        let height: CGFloat
        let lineCount: Int
    }

    /// Measured off-screen in a throwaway layout stack rather than by asking the
    /// live text view, whose container is about to be resized to the answer.
    private func measure(_ attributed: NSAttributedString, width: CGFloat) -> Measurement {
        let storage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(
            size: NSSize(width: width, height: .greatestFiniteMagnitude)
        )
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)

        let used = layoutManager.usedRect(for: container)
        var lineCount = 0
        var glyph = 0
        while glyph < layoutManager.numberOfGlyphs {
            var range = NSRange()
            _ = layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: &range)
            lineCount += 1
            // A zero-length effective range would leave the walk standing still;
            // stopping is the honest answer, an infinite loop is not.
            guard range.length > 0 else { break }
            glyph = NSMaxRange(range)
        }

        return Measurement(
            storage: storage, layoutManager: layoutManager,
            width: ceil(used.width), height: ceil(used.height), lineCount: lineCount
        )
    }

    /// The first `limit` lines of `attributed`, ending in an ellipsis, or nil if
    /// there was nothing to cut.
    ///
    /// Cut on the *laid-out* lines rather than on a character count, because the
    /// two have nothing to do with each other: eight lines of a wrapped paragraph
    /// and eight lines of a bulleted list differ by an order of magnitude in
    /// characters, and a character budget would give one of them two lines and
    /// the other twenty.
    private func truncating(
        _ attributed: NSAttributedString, to limit: Int, using measurement: Measurement
    ) -> NSAttributedString? {
        let layoutManager = measurement.layoutManager
        var glyph = 0
        var line = 0
        while glyph < layoutManager.numberOfGlyphs, line < limit {
            var range = NSRange()
            _ = layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: &range)
            guard range.length > 0 else { break }
            line += 1
            glyph = NSMaxRange(range)
        }
        guard glyph > 0, glyph < layoutManager.numberOfGlyphs else { return nil }

        let characters = layoutManager.characterRange(
            forGlyphRange: NSRange(location: 0, length: glyph), actualGlyphRange: nil)
        let head = NSMutableAttributedString(
            attributedString: attributed.attributedSubstring(from: characters))

        // The cut lands on a line break or the space that wrapped it; leaving
        // that in puts the ellipsis on a line of its own.
        let lastVisible = (head.string as NSString).rangeOfCharacter(
            from: CharacterSet.whitespacesAndNewlines.inverted, options: .backwards)
        guard lastVisible.location != NSNotFound else { return nil }
        let end = NSMaxRange(lastVisible)
        if end < head.length {
            head.deleteCharacters(in: NSRange(location: end, length: head.length - end))
        }

        head.append(NSAttributedString(
            string: Self.ellipsis,
            attributes: head.attributes(at: head.length - 1, effectiveRange: nil)))
        return head
    }

    // MARK: - Mouse

    @objc private func moreTapped() {
        onExpand?()
    }

    /// A selectable bubble keeps the presses that land on its padding.
    ///
    /// The text view already keeps the ones on the text. Letting the gap around
    /// it fall through would mean a click two points from a word you were about
    /// to select dismissed the overlay you were reading in — the same press,
    /// two different answers, decided by a couple of points.
    public override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2, let onDoubleClick {
            onDoubleClick()
            return
        }
        onSingleClick?()
        guard isTextSelectable else {
            super.mouseDown(with: event)
            return
        }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }
}

/// The bubble's text view, which hands double-clicks back when someone is
/// waiting for one.
///
/// A double-click on selectable text means "select this word" and, in a feed,
/// also means "open this conversation". Only one of them can have it: the
/// gesture is given away where a handler is wired and kept where it is not, so
/// a reader copying text out of an already-open conversation still gets their
/// word.
private final class BubbleTextView: NSTextView {
    var onDoubleClick: (() -> Void)?

    /// Reported and then forgotten: the press goes on to start a selection drag
    /// as it always did.
    var onSingleClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2, let onDoubleClick {
            onDoubleClick()
            return
        }
        onSingleClick?()
        super.mouseDown(with: event)
    }
}
