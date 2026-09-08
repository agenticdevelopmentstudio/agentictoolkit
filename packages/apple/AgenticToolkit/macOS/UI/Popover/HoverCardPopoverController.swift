//
//  HoverCardPopoverController.swift
//  AgenticToolkit
//

import AgenticToolkitCore
import AgenticToolkitCoreMacOS
import AppKit

/// What a hover card has to say, and how to read it.
///
/// Two cases rather than an `NSAttributedString` parameter, so that callers do
/// not each have to know which renderer and which theme roles produce a card
/// that matches every other card. The rendering is this file's business.
public enum HoverCardContent: Equatable, Sendable {

    /// Shown verbatim, in the system font.
    case plainText(String)

    /// Rendered through `MarkdownRenderer` — headings, emphasis, lists and
    /// fenced code blocks, all coloured from the active palette.
    case markdown(String)
}

/// A small, themed, transient popover for explanatory text next to something
/// the pointer is on.
///
/// Generic on purpose: it knows nothing about language servers, diagnostics or
/// documents, and takes a string and a rect to point at. `LSPHoverController`
/// is its first caller; anything else that wants a hover card should use this
/// rather than grow a second one.
///
/// `ComposableSettings.HelpPopoverController` is the prior art for the popover
/// mechanics — `.transient`, an `NSViewController` wrapping a plain themed
/// view, a `window != nil` guard before showing — and this deliberately copies
/// that shape without depending on it: help is settings prose keyed to a panel,
/// this is one string keyed to a point, and folding them together would put a
/// `PanelHelp` in the editor's path.
@MainActor
public final class HoverCardPopoverController: NSObject, NSPopoverDelegate {

    /// The card never grows past this. Wide enough for a signature line at a
    /// readable measure, tall enough for a paragraph of documentation; past
    /// that the content scrolls, because a hover card that covers the code it
    /// describes has defeated itself.
    public static let maximumContentSize = NSSize(width: 460, height: 320)

    private let popover = NSPopover()
    private let cardView = HoverCardView()

    /// Whether the card is on screen right now.
    public var isShown: Bool { popover.isShown }

    /// Called when the popover closes for any reason, including the user
    /// clicking away from it.
    public var onDismiss: (() -> Void)?

    override public init() {
        super.init()

        let contentController = NSViewController()
        contentController.view = cardView
        popover.contentViewController = contentController
        popover.contentSize = Self.maximumContentSize
        // Transient, like the help popover: a hover card is a glance, and the
        // next click anywhere should put it away without a second gesture.
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
    }

    /// Shows `content` pointing at `rect`, which is in `view`'s coordinate
    /// space.
    ///
    /// A no-op when `view` has no window: `NSPopover.show` raises an exception
    /// in that case rather than returning, and a view that is off screen is
    /// routine — the editor may have been detached between the request and its
    /// answer. Same guard as `HelpPopoverController.toggleHelp`.
    public func show(
        _ content: HoverCardContent,
        relativeTo rect: NSRect,
        of view: NSView,
        preferredEdge: NSRectEdge
    ) {
        guard view.window != nil else { return }
        cardView.setContent(content)
        popover.contentSize = cardView.contentSize(within: Self.maximumContentSize)
        popover.show(relativeTo: rect, of: view, preferredEdge: preferredEdge)
    }

    /// Closes the card if it is open. Idempotent.
    ///
    /// `close()` rather than `performClose(nil)`: this is the program deciding,
    /// not the user, and `performClose` runs the delegate's veto path that
    /// exists for a user-initiated close.
    public func dismiss() {
        guard popover.isShown else { return }
        popover.close()
    }

    // MARK: - NSPopoverDelegate

    public func popoverDidClose(_ notification: Notification) {
        onDismiss?()
    }
}

/// The inside of the card: one scrollable, non-editable run of text on a themed
/// background.
///
/// A text view rather than a label because hover documentation is unbounded —
/// a server may return three lines or thirty — and a label would either clip
/// the long ones or make the popover taller than the screen.
@MainActor
final class HoverCardView: NSView {

    private static let inset = NSSize(width: 10, height: 8)

    private let scrollView = NSScrollView()
    private let textView = NSTextView()
    private let renderer = MarkdownRenderer()

    /// Kept so the card can re-render itself when the theme changes: the
    /// attributed string carries colours baked in at render time, so a palette
    /// change has to run the content through the renderer again.
    private var content: HoverCardContent = .plainText("")

    private var palette: SemanticPalette = ThemePaletteObserver.currentPalette
    private var themeObserver: ThemePaletteObserver?

    init() {
        super.init(frame: NSRect(origin: .zero, size: HoverCardPopoverController.maximumContentSize))

        textView.isEditable = false
        // Selectable so the user can copy a type signature out of the card,
        // which is most of what anyone wants a hover card for.
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = Self.inset
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.autoresizingMask = [.width, .height]
        scrollView.frame = bounds
        addSubview(scrollView)

        wantsLayer = true
        themeObserver = ThemePaletteObserver(host: self) { [weak self] palette in self?.apply(palette) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setContent(_ content: HoverCardContent) {
        self.content = content
        render()
    }

    /// The size this card wants, clamped to `maximum`.
    ///
    /// Measured from the rendered text rather than from the source string:
    /// markdown's rendered height and its source's height are not the same
    /// number, and the difference is a scroller that should not be there.
    func contentSize(within maximum: NSSize) -> NSSize {
        let available = maximum.width - Self.inset.width * 2
        let measured = (textView.textStorage ?? NSTextStorage()).boundingRect(
            with: NSSize(width: available, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return NSSize(
            width: min(ceil(measured.width) + Self.inset.width * 2, maximum.width),
            height: min(ceil(measured.height) + Self.inset.height * 2, maximum.height)
        )
    }

    private func apply(_ palette: SemanticPalette) {
        self.palette = palette
        layer?.backgroundColor = palette.nsColor(.elevatedSurface).cgColor
        render()
    }

    private func render() {
        let rendered: NSAttributedString
        switch content {
        case .plainText(let text):
            rendered = NSAttributedString(
                string: text,
                attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                    .foregroundColor: palette.nsColor(.primaryText)
                ]
            )
        case .markdown(let markdown):
            // The toolkit already has a themed markdown renderer, shipped in
            // AgenticDeveloperToolkitUI and used by the chat surfaces. Writing a
            // second one here would be a second set of heading sizes and code
            // block colours to keep in step with the first.
            rendered = renderer.render(markdown, palette: palette, textColor: palette.nsColor(.primaryText))
        }
        textView.textStorage?.setAttributedString(rendered)
    }
}
