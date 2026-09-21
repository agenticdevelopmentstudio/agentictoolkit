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

    /// `9:41 AM`, shared with ``ChatTranscriptRowView`` so a timestamp reads the
    /// same whether it trails the text or sits on its own line under it.
    ///
    /// Twelve-hour, and spelled out rather than derived from the locale's time
    /// style: this is a clock a person glances at beside something they said,
    /// and "9:41 AM" is the shape that needs no arithmetic. The locale still
    /// supplies the AM/PM words and the separator — only the dial is fixed.
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    /// `Saturday, June 3 2026` — the banner a transcript puts in front of the
    /// first message of each day.
    ///
    /// The whole date written out, because it is said once per day rather than
    /// once per message: a reader who has scrolled back far enough to need it is
    /// asking *which* day, and `06/03` answers a different, smaller question.
    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d yyyy"
        return formatter
    }()

    /// What a truncated bubble says where its text stops, and what the control
    /// under it is called.
    private static let ellipsis = "…"
    private static let moreTitle = "More…"

    /// Which of the two shapes a bubble is drawn in.
    ///
    /// They answer different questions. A one-to-one chat has two speakers and
    /// no other way to tell them apart, so its bubbles are coloured by role —
    /// that *is* the attribution. A merged feed already says who is talking, in
    /// a header line over every row, so colouring by role there spends the
    /// window's whole palette repeating a fact already in words — and does it
    /// beside a session list where the same sessions are drawn as inset boxes on
    /// the window's surface. `terminal` is that box: the Sessions window's own,
    /// to the point.
    public enum Style: Sendable {
        /// Role-keyed fill, generous radius — the chat window's bubble.
        case speaker
        /// The Sessions window's inset output box: surface fill, hairline
        /// border, small radius, whoever is speaking.
        case terminal

        /// How round the corners are. The terminal box's 6 is the tighter of
        /// the two because it reads as a panel rather than as speech.
        var cornerRadius: CGFloat {
            switch self {
            case .speaker: return 12
            case .terminal: return 6
            }
        }
    }

    private let message: ChatMessage
    private let maxWidth: CGFloat
    private let style: Style
    private let showsInlineTimestamp: Bool
    private let isTextSelectable: Bool

    /// Whether a bubble whose text *wraps* is as wide as it is allowed to be,
    /// rather than as wide as its longest line.
    ///
    /// A one-to-one chat shrinks every bubble to its content: two shapes reading
    /// down one column are what tells "ok" from a paragraph at a glance. A
    /// merged feed cannot afford that for paragraphs — there the ragged inside
    /// edges of a hundred wrapped bubbles are a second, meaningless column of
    /// noise running down the middle of the window, and where a wrapped line
    /// happened to break says nothing about the message.
    ///
    /// It stops at wrapping because a bubble holding one short line is a
    /// different case: there the small shape *is* the content, read at a glance
    /// without being read at all, and filling the column would put the weight of
    /// a paragraph behind "ok".
    private let fillsWidthWhenWrapped: Bool

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
    private var moreWidthConstraint: NSLayoutConstraint!
    private var moreLeadingConstraint: NSLayoutConstraint!
    private var moreTopConstraint: NSLayoutConstraint!

    /// The width this bubble came to.
    ///
    /// The bubble measures its own text rather than leaving its width to the
    /// engine, which is what makes this answerable before any layout pass has
    /// run — and a caller arranging the band *under* the bubble has to know it
    /// while it is still deciding what to constrain.
    public var measuredWidth: CGFloat { bubbleWidthConstraint.constant }

    /// The **More…** control, for a container that has taken over hit-testing
    /// for its whole subtree and has to name the parts that still take a click.
    public var expandControl: NSView { moreButton }

    /// How far a bubble's text sits in from the bubble's own edge.
    ///
    /// Public because it is not only the bubble's business: a row that hangs
    /// furniture off a bubble — ``ChatTranscriptRowView``'s jump control — lines
    /// that furniture up with the *text*, not with the bubble's edge, and this
    /// is how far in the text's edge is.
    public static let textInset: CGFloat = 12
    private static let vPad: CGFloat = 8

    /// The **More…** control is a symbol rather than the words, and a big one.
    ///
    /// It is the one thing in a bubble that is not the message, so the words
    /// competed with the text they sat under — three glyphs of caption type
    /// reading as one more line of the reply. A symbol is not read at all, it is
    /// recognised, and at this size it is a target a reader hits without aiming.
    private static let moreSymbol = "ellipsis.circle.fill"
    private static let moreSymbolPointSize: CGFloat = 17
    private static let moreSize: CGFloat = 22

    /// How far the control sits behind the ellipsis it follows.
    ///
    /// It goes *on the last line*, right after the "…", because that is where
    /// the sentence stopped and so where the question "what else did it say"
    /// gets asked. Under the text it was a second thing to notice, and it cost
    /// every truncated row a line of height that carried no words.
    private static let moreInlineGap: CGFloat = 4

    /// - Parameters:
    ///   - style: which of the two bubble shapes to draw — see ``Style``.
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
    ///   - fillsWidthWhenWrapped: whether a bubble whose text wraps is
    ///     `maxWidth` wide however its lines break — see
    ///     ``fillsWidthWhenWrapped``.
    public init(
        message: ChatMessage,
        maxWidth: CGFloat,
        style: Style = .speaker,
        showsInlineTimestamp: Bool = true,
        isTextSelectable: Bool = true,
        lineLimit: Int? = nil,
        fillsWidthWhenWrapped: Bool = false
    ) {
        self.message = message
        self.maxWidth = maxWidth
        self.style = style
        self.showsInlineTimestamp = showsInlineTimestamp
        self.isTextSelectable = isTextSelectable
        self.lineLimit = lineLimit
        self.fillsWidthWhenWrapped = fillsWidthWhenWrapped
        self.textView = BubbleTextView(frame: .zero)
        self.textWidthConstraint = textView.widthAnchor.constraint(equalToConstant: 0)
        self.textHeightConstraint = textView.heightAnchor.constraint(equalToConstant: 0)

        super.init(frame: .zero)
        self.bubbleWidthConstraint = widthAnchor.constraint(equalToConstant: maxWidth)

        if fillsWidthWhenWrapped {
            // A row can be laid out narrower than the width its bubbles were
            // built for, for the moment between a live resize and the rebuild
            // that follows it. A width that outranked the row's own edges would
            // be an unsatisfiable-constraint report for that moment; one point
            // under required, the edges win and the bubble gives.
            bubbleWidthConstraint.priority = .required - 1
            textWidthConstraint.priority = .required - 1
        }

        wantsLayer = true
        layer?.cornerRadius = style.cornerRadius
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
        self.moreWidthConstraint = moreButton.widthAnchor.constraint(equalToConstant: 0)
        // Placed off the laid-out last line rather than off an edge, so both
        // constants are written by ``apply(_:)`` once the text has been measured.
        self.moreLeadingConstraint = moreButton.leadingAnchor.constraint(
            equalTo: textView.leadingAnchor, constant: 0)
        self.moreTopConstraint = moreButton.topAnchor.constraint(
            equalTo: textView.topAnchor, constant: 0)

        // The truncation pass keeps the last line short enough for the control
        // to follow it, so this normally has nothing to do. It is here for the
        // bubble too narrow to hold both: the control slides back over the
        // ellipsis instead of out through the bubble's own edge.
        moreLeadingConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor, constant: Self.vPad),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.textInset),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.textInset),
            bottomAnchor.constraint(equalTo: textView.bottomAnchor, constant: Self.vPad),
            textWidthConstraint,
            textHeightConstraint,
            bubbleWidthConstraint,

            moreLeadingConstraint,
            moreTopConstraint,
            moreHeightConstraint,
            moreWidthConstraint,
            moreButton.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor, constant: -Self.textInset)
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
        // The terminal shape takes the Sessions window's output box wholesale:
        // the window's surface, the window's border, one hairline, always. Its
        // two conversational roles come out identical on purpose — the row's
        // header line says who is talking, and saying it twice is what this
        // style exists to stop. `error` and `notice` fall through: they are not
        // conversation, so they keep the colour that says what they are.
        if case .terminal = style, message.role == .user || message.role == .assistant {
            return (palette.surfaceColor, palette.primaryTextColor, palette.borderColor)
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

    /// The face a bubble's text is set in: the terminal's.
    ///
    /// These bubbles are a terminal conversation written down — the feed's rows
    /// are literally transcripts of sessions running in one — and a transcript
    /// set in a different face than the session it came from reads as a
    /// different program's output. So the reader picks the face once, for the
    /// terminal, and the bubbles follow: theme override first, Terminal
    /// settings second, exactly as ``TerminalAppearance`` resolves it for the
    /// terminal itself.
    static func bodyFont(for palette: SemanticPalette) -> NSFont {
        TerminalAppearance.resolvedFont(theme: palette.theme)
    }

    /// The face the inline timestamp is set in: the body's, smaller.
    ///
    /// The timestamp is deliberately smaller than the text it trails, and the
    /// theme's caption-to-body ratio is that relationship expressed once. It is
    /// the *ratio* and not the caption font because the face is now the
    /// terminal's — a system-font caption beside monospaced text is two
    /// typefaces on one line.
    static func timestampFont(for palette: SemanticPalette) -> NSFont {
        let body = bodyFont(for: palette)
        let bodySize = palette.size(.body)
        guard bodySize > 0 else { return body }
        let scaled = body.pointSize * CGFloat(palette.size(.caption) / bodySize)
        return NSFont(descriptor: body.fontDescriptor, size: scaled) ?? body
    }

    private func attributedText(for palette: SemanticPalette) -> NSAttributedString {
        let textColor = colors(from: palette).text
        let bodyFont = Self.bodyFont(for: palette)
        let timeFont = Self.timestampFont(for: palette)

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
        let textMaxWidth = maxWidth - Self.textInset * 2

        var shown = full
        var measured = measure(full, width: textMaxWidth)
        if let lineLimit, measured.lineCount > lineLimit,
           let cut = truncating(full, to: lineLimit, using: measured) {
            // The control follows the ellipsis on the same line, so the last
            // line has to end early enough to leave room for it.
            (shown, measured) = trimming(
                cut, toLeave: Self.moreInlineGap + Self.moreSize,
                within: lineLimit, width: textMaxWidth)
            isTruncated = true
        } else {
            isTruncated = false
        }

        // The control has to fit as well as the text: a one-word message
        // followed by a control wider than it is would clip the offer.
        let contentWidth = isTruncated
            ? max(measured.width, measured.lastLine.maxX + Self.moreInlineGap + Self.moreSize)
            : measured.width

        // Whether *this* bubble takes the whole column. Measured, not declared:
        // a message is short when its text did not wrap at the width it was
        // given, which is a fact about the laid-out line count and nothing the
        // caller could have known.
        let fillsWidth = fillsWidthWhenWrapped && measured.lineCount > 1

        // The text view is exactly as wide as the bubble's content box, not as
        // wide as its longest line: it is pinned to both of the bubble's inside
        // edges, so a width constraint disagreeing with them is a conflict.
        let shownWidth = fillsWidth ? textMaxWidth : min(contentWidth, textMaxWidth)
        textView.textContainer?.size = NSSize(
            width: shownWidth, height: .greatestFiniteMagnitude)
        textView.textStorage?.setAttributedString(shown)

        textWidthConstraint.constant = shownWidth
        textHeightConstraint.constant = measured.height

        moreButton.isHidden = !isTruncated
        // Tinted with the bubble's own text colour: it belongs to this message,
        // and an accent here would read as a different kind of thing entirely.
        moreButton.contentTintColor = text
        moreHeightConstraint.constant = isTruncated ? Self.moreSize : 0
        moreWidthConstraint.constant = isTruncated ? Self.moreSize : 0
        moreLeadingConstraint.constant = isTruncated
            ? measured.lastLine.maxX + Self.moreInlineGap
            : 0
        // Centred on the line it follows, not on its baseline: a 22pt control
        // beside a 13pt line hangs a few points either side of it, which the
        // bubble's own padding already has room for.
        moreTopConstraint.constant = isTruncated
            ? measured.lastLine.midY - Self.moreSize / 2
            : 0

        bubbleWidthConstraint.constant = fillsWidth
            ? maxWidth
            : min(contentWidth + Self.textInset * 2, maxWidth)

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
        /// The used rect of the final line fragment, in the container's own
        /// coordinates — where the text actually stops, which is where anything
        /// that follows it has to start.
        let lastLine: NSRect
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
        var lastLine = NSRect.zero
        while glyph < layoutManager.numberOfGlyphs {
            var range = NSRange()
            lastLine = layoutManager.lineFragmentUsedRect(
                forGlyphAt: glyph, effectiveRange: &range)
            lineCount += 1
            // A zero-length effective range would leave the walk standing still;
            // stopping is the honest answer, an infinite loop is not.
            guard range.length > 0 else { break }
            glyph = NSMaxRange(range)
        }

        return Measurement(
            storage: storage, layoutManager: layoutManager,
            width: ceil(used.width), height: ceil(used.height), lineCount: lineCount,
            lastLine: lastLine
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

    /// `attributed` — a string ``truncating(_:to:using:)`` has already ended in
    /// an ellipsis — shortened until it is `limit` lines with `reserve` points
    /// free after the last of them, with what it measured to.
    ///
    /// Two things are being fixed, and they are the same fix. The cut is by
    /// laid-out lines, so the last one can stop anywhere from the far edge to a
    /// couple of glyphs in — and where it stopped flush, the appended ellipsis
    /// wrapped onto a line of its own, which is both a line over the limit and
    /// a "…" with nothing in front of it. Where it stopped just short, there is
    /// no room after it for the control that follows it. Characters come off one
    /// at a time from in front of the ellipsis, because a word at a time would
    /// take the reader's sentence apart to make room for a button.
    ///
    /// Only the last line can change, since removing from the end cannot re-wrap
    /// what came before it, and the string strictly shrinks, so this ends.
    private func trimming(
        _ attributed: NSAttributedString, toLeave reserve: CGFloat,
        within limit: Int, width: CGFloat
    ) -> (NSAttributedString, Measurement) {
        let ellipsisLength = (Self.ellipsis as NSString).length
        var candidate = attributed
        var measurement = measure(candidate, width: width)

        while measurement.lineCount > limit || measurement.lastLine.maxX + reserve > width {
            let string = candidate.string as NSString
            guard string.length > ellipsisLength else { break }
            // The character before the ellipsis, taken whole: a surrogate pair
            // or a combining sequence cut in half is a replacement glyph.
            let composed = string.rangeOfComposedCharacterSequence(
                at: string.length - ellipsisLength - 1)
            let mutable = NSMutableAttributedString(attributedString: candidate)
            mutable.deleteCharacters(in: composed)
            candidate = mutable
            measurement = measure(candidate, width: width)
        }
        return (candidate, measurement)
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
