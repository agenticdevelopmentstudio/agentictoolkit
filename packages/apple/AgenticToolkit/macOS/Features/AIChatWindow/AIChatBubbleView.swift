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

    private let message: ChatMessage
    private let maxWidth: CGFloat
    private let showsInlineTimestamp: Bool

    private let textView = NSTextView(frame: .zero)

    // The bubble sizes itself to its text, and the theme owns the font, so the
    // measurement has to be redone on every theme change rather than baked in
    // at init. These three constraints are what that re-measurement writes.
    private let textWidthConstraint: NSLayoutConstraint
    private let textHeightConstraint: NSLayoutConstraint
    private var bubbleWidthConstraint: NSLayoutConstraint!

    private static let hPad: CGFloat = 12
    private static let vPad: CGFloat = 8

    /// - Parameters:
    ///   - showsInlineTimestamp: whether the time trails the text inside the
    ///     bubble. A bubble that sits in a ``ChatTranscriptRowView`` has the
    ///     time on its own line underneath instead, so it turns this off rather
    ///     than printing it twice.
    ///   - isTextSelectable: whether the text takes the mouse. A selectable text
    ///     view swallows clicks, which is right for a conversation you are
    ///     reading and wrong for a row whose whole job is to be clicked.
    public init(
        message: ChatMessage,
        maxWidth: CGFloat,
        showsInlineTimestamp: Bool = true,
        isTextSelectable: Bool = true
    ) {
        self.message = message
        self.maxWidth = maxWidth
        self.showsInlineTimestamp = showsInlineTimestamp
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

        addSubview(textView)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor, constant: Self.vPad),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.hPad),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.hPad),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.vPad),
            textWidthConstraint,
            textHeightConstraint,
            bubbleWidthConstraint
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
        let (fill, _, border) = colors(from: palette)
        layer?.backgroundColor = fill.cgColor
        layer?.borderColor = border?.cgColor
        layer?.borderWidth = border == nil ? 0 : 1

        let attributed = attributedText(for: palette)
        let textMaxWidth = maxWidth - Self.hPad * 2

        // Measure off-screen in a throwaway layout stack rather than asking the
        // live text view, whose container is about to be resized to the answer.
        let textStorage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            size: NSSize(width: textMaxWidth, height: .greatestFiniteMagnitude)
        )
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let textWidth = ceil(usedRect.width)
        let textHeight = ceil(usedRect.height)

        textView.textContainer?.size = NSSize(width: textWidth, height: .greatestFiniteMagnitude)
        textView.textStorage?.setAttributedString(attributed)

        textWidthConstraint.constant = textWidth
        textHeightConstraint.constant = textHeight
        bubbleWidthConstraint.constant = min(textWidth + Self.hPad * 2, maxWidth)

        textView.insertionPointColor = palette.nsColor(.cursor)
        textView.selectedTextAttributes = [
            .backgroundColor: palette.nsColor(.selection),
            .foregroundColor: palette.nsColor(.selectionText)
        ]
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }
}
