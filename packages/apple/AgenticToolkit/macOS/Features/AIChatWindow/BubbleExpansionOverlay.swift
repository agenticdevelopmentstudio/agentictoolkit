import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreUI
import AgenticToolkitCoreMacOS

/// One message, opened to its full length over the transcript it came from.
///
/// A transcript caps how much of a long message it shows, because a forty-line
/// reply is not forty times as important as the four lines around it and a feed
/// that lets it take the window has stopped being a feed. The cap needs a way
/// out, and this is it: the same bubble, the same theme, nothing cropped, laid
/// over the transcript rather than pushed into it — so the rows underneath stay
/// exactly where the reader left them.
///
/// Everything about *going away* — the blur, the fade, Escape, Return, a press
/// nothing else took — is ``DismissibleOverlayView``'s. What this adds is the
/// one bubble and the scroll that holds it when even the whole window is not
/// enough.
@MainActor
public final class BubbleExpansionOverlay: DismissibleOverlayView {

    /// Room left around the bubble, so the transcript stays visible at the edges
    /// and the overlay reads as a layer over the feed rather than a new window.
    private static let margin: CGFloat = 40

    /// The widest the expanded bubble goes, however wide the window is. Past
    /// this a line of prose is measured in eye movements rather than words.
    private static let maxBubbleWidth: CGFloat = 720

    private let message: ChatMessage

    /// The shape the transcript drew this message in. Carried across rather than
    /// defaulted: an overlay is the *same* bubble opened out, so one that came
    /// back in the other style would read as a different message.
    private let style: AIChatBubbleView.Style

    public init(message: ChatMessage, style: AIChatBubbleView.Style = .speaker) {
        self.message = message
        self.style = style
        super.init(material: .hudWindow)
        accessibilityID("bubble-expansion.overlay")
    }

    /// Built here rather than in `init` because the bubble bakes its width in at
    /// build time — it pre-measures its own text — so it cannot be made until
    /// there is a host to measure against.
    public override func present(in host: NSView) {
        let available = max(host.bounds.width - Self.margin * 2, 200)

        let bubble = AIChatBubbleView(
            message: message,
            maxWidth: min(available, Self.maxBubbleWidth),
            style: style,
            showsInlineTimestamp: true,
            isTextSelectable: true
        )
        bubble.accessibilityID("bubble-expansion.bubble")

        // A message can be longer than the screen, and an overlay that ran off
        // the bottom would have replaced one crop with a worse one.
        let scroll = NSScrollView()
        scroll.documentView = bubble
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        // As tall as the bubble, up to what the host leaves it: the required
        // `<=` caps it and the merely-strong `==` pulls it up to the content, so
        // a two-line message gets a two-line overlay rather than a full-height
        // one with a bubble stranded at the top.
        let fitsContent = scroll.heightAnchor.constraint(equalTo: bubble.heightAnchor)
        fitsContent.priority = .defaultHigh

        NSLayoutConstraint.activate([
            scroll.centerXAnchor.constraint(equalTo: centerXAnchor),
            scroll.centerYAnchor.constraint(equalTo: centerYAnchor),
            scroll.widthAnchor.constraint(equalTo: bubble.widthAnchor),
            scroll.heightAnchor.constraint(
                lessThanOrEqualTo: heightAnchor, constant: -Self.margin * 2),
            fitsContent
        ])

        super.present(in: host)
    }
}
