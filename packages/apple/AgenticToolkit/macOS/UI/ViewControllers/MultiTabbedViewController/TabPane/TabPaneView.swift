import AgenticToolkitCore
import AgenticToolkitCoreMacOS
import AppKit

/// The card drawn in the edge bar: a stacked block, the same on all four edges.
///
/// Every card paints what the workspace paints, in the workspace's own outline
/// colour, and its background overhangs the bar by `workspaceOverlap` — far
/// enough to cover the line the workspace draws down that side. So there is no
/// seam where the two meet: a single unbroken 1pt line runs up one side of a
/// card, around its two outer corners, down the other side, across the bare
/// workspace edge to the next card, and on around the workspace itself.
///
/// Which card is in front is therefore carried by its text, not by its fill:
/// the active card's labels sit a role brighter than the rest.
///
/// `TabBarView` supplies the other half of the attachment: it pads the outer
/// side of the bar and leaves the workspace side at zero.
@MainActor
final class TabPaneView: NSView {
    /// A card is never narrower than this and never wider than `maxWidth`,
    /// whichever edge it is on — a vertical bar gets the same card a
    /// horizontal one does.
    static let minWidth: CGFloat = 240
    static let maxWidth: CGFloat = 340
    /// Deep enough for the header and the four lines under it with room left
    /// over: the card is a block you read, not a strip you squint at.
    static let minHeight: CGFloat = 136

    /// How far the card's background reaches past the bar and over the
    /// workspace's own outline. One point is that outline's whole width, which
    /// is the point: the line ceases to exist across the card's mouth.
    static let workspaceOverlap: CGFloat = 1

    /// The card's own padding, inside the border.
    private static let padding = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)

    let agentLabel = ThemedLabel(role: .primaryText, textRole: .body)
    let sessionLabel = ThemedLabel(role: .primaryText, textRole: .body)
    let directoryLabel = ThemedLabel(role: .tertiaryText, textRole: .caption)
    let branchLabel = ThemedLabel(role: .secondaryText, textRole: .caption)
    let summaryLabel = ThemedLabel(role: .secondaryText, textRole: .caption)
    let closeButton = NSButton()
    let statusStack = NSStackView()

    var onClose: (() -> Void)?
    var contextMenuProvider: ((NSEvent) -> NSMenu?)?
    var isHighlighted = false { didSet { applyHighlight() } }

    private let edge: Edge
    private let background: TabCardBackgroundView
    private let content = NSStackView()
    private var statusViews: [NSImageView] = []

    init(edge: Edge, tabID: UUID) {
        self.edge = edge
        self.background = TabCardBackgroundView(edge: edge)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        accessibilityID("tab-pane.\(tabID.uuidString)")
        agentLabel.accessibilityID("tab-pane.agent.\(tabID.uuidString)")
        sessionLabel.accessibilityID("tab-pane.session.\(tabID.uuidString)")
        directoryLabel.accessibilityID("tab-pane.directory.\(tabID.uuidString)")
        branchLabel.accessibilityID("tab-pane.branch.\(tabID.uuidString)")
        summaryLabel.accessibilityID("tab-pane.summary.\(tabID.uuidString)")
        closeButton.accessibilityID("tab-pane.close.\(tabID.uuidString)")
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: Content

    func setStatusSymbols(_ symbols: [TabPaneStatusSymbol]) {
        for view in statusViews { statusStack.removeView(view) }
        statusViews = symbols.map { symbol in
            let symbolImage = NSImage(
                systemSymbolName: symbol.symbolName,
                accessibilityDescription: symbol.accessibilityLabel
            ) ?? NSImage()
            let image = NSImageView(image: symbolImage)
            image.symbolConfiguration = .init(pointSize: 11, weight: .regular)
            image.setAccessibilityLabel(symbol.accessibilityLabel)
            image.widthAnchor.constraint(equalToConstant: 14).isActive = true
            image.heightAnchor.constraint(equalToConstant: 14).isActive = true
            statusStack.addArrangedSubview(image)
            return image
        }
    }

    /// The size the card wants for its current content. The same measurement
    /// on every edge, because the arrangement is the same on every edge: a
    /// width held between `minWidth` and `maxWidth`, and a height that starts
    /// at `minHeight` and grows past it when the content needs it to.
    ///
    /// It measures the stack, not the card. `TabPaneViewController` makes this
    /// view its own `view`, so AppKit installs the priority-501
    /// `preferredContentSize` constraints onto the card itself — and the
    /// labels resist compression at only `.defaultLow`. Asking the card for
    /// its `fittingSize` after a first measurement therefore returns that
    /// first answer back, and a card whose text grows on a later `reload()`
    /// would never widen. The stack carries none of those constraints.
    var contentSize: NSSize {
        let fitting = content.fittingSize
        return NSSize(
            width: min(Self.maxWidth, max(Self.minWidth, fitting.width)),
            height: max(Self.minHeight, fitting.height)
        )
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenuProvider?(event) ?? super.menu(for: event)
    }

    // MARK: Layout

    private func setUp() {
        for label in [agentLabel, sessionLabel, directoryLabel, branchLabel, summaryLabel] {
            label.lineBreakMode = .byTruncatingMiddle
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            // A selectable field takes its own `mouseDown` to begin a text
            // selection, which never reaches `TabItemHostView.mouseDown(with:)` —
            // these labels cover nearly the whole card, so that would eat
            // almost every click meant to select the tab.
            label.isSelectable = false
        }
        directoryLabel.lineBreakMode = .byTruncatingHead
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.isHidden = true

        statusStack.orientation = .horizontal
        statusStack.spacing = 2

        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
        closeButton.isBordered = false
        closeButton.bezelStyle = .inline
        closeButton.imagePosition = .imageOnly
        closeButton.target = self
        closeButton.action = #selector(closePressed)
        closeButton.widthAnchor.constraint(equalToConstant: 14).isActive = true
        closeButton.heightAnchor.constraint(equalToConstant: 14).isActive = true

        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)
        observeTheme { view, _ in view.applyHighlight() }

        let header = makeHeader()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 6
        content.edgeInsets = Self.padding
        content.translatesAutoresizingMaskIntoConstraints = false
        for view in [header, sessionLabel, directoryLabel, branchLabel, summaryLabel, makeSpacer()] {
            content.addArrangedSubview(view)
        }
        addSubview(content)

        let overhang = overhangInsets()
        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: topAnchor, constant: -overhang.top),
            background.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -overhang.left),
            background.trailingAnchor.constraint(equalTo: trailingAnchor, constant: overhang.right),
            background.bottomAnchor.constraint(equalTo: bottomAnchor, constant: overhang.bottom),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            // `.leading` alignment pins one edge only, so without this the
            // header is as wide as its own text and the close button lands
            // beside the agent name instead of in the card's far corner. The
            // inset arithmetic has to restate `edgeInsets` exactly — the
            // stack's own alignment constraints are required priority, and a
            // different number here is unsatisfiable rather than merely wrong.
            header.widthAnchor.constraint(
                equalTo: content.widthAnchor,
                constant: -(Self.padding.left + Self.padding.right)
            )
        ])
        // No self-pin on either axis: the cross axis is the hosting bar's
        // job at required priority (`TabBarView.rebuildButtons()`), and the
        // length axis is AppKit's own priority-501
        // `NSViewController.preferredContentSize` constraint, driven by
        // `contentSize` above. A required pin here would restate one of
        // those two numbers at required priority and risk an unsatisfiable
        // conflict with whichever one wins.
        applyHighlight()
    }

    /// The card's top line: the agent, its status symbols, and the close
    /// button.
    ///
    /// The close button goes on the end nearest the outside of the window —
    /// the leading end on a left bar, the trailing end everywhere else — so it
    /// sits in the card's outside top corner and is never the thing standing
    /// between the card's text and the workspace it belongs to.
    private func makeHeader() -> NSStackView {
        let gap = NSView()
        gap.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        gap.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let body = [agentLabel, statusStack, gap] as [NSView]
        let header = NSStackView(views: edge == .left ? [closeButton] + body : body + [closeButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 6
        return header
    }

    /// Takes whatever height is left over in a card taller than its text, so
    /// the lines sit at the top of the card rather than spreading down it.
    private func makeSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)
        spacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .vertical)
        return spacer
    }

    /// How far the background reaches past each side of the card. Only the
    /// side facing the workspace overhangs; the other three end where the card
    /// ends.
    private func overhangInsets() -> NSEdgeInsets {
        let over = Self.workspaceOverlap
        switch edge {
        case .top: return NSEdgeInsets(top: 0, left: 0, bottom: over, right: 0)
        case .bottom: return NSEdgeInsets(top: over, left: 0, bottom: 0, right: 0)
        case .left: return NSEdgeInsets(top: 0, left: 0, bottom: 0, right: over)
        case .right: return NSEdgeInsets(top: 0, left: over, bottom: 0, right: 0)
        }
    }

    /// Every card paints the workspace's own backdrop and outline, so the two
    /// are one surface under one line. Which card is in front is the text: the
    /// active card's labels sit a role brighter than the rest.
    private func applyHighlight() {
        let palette = resolvedThemeScope.palette
        background.fillColor = NSColor(palette.projectPaneBackdrop)
        background.borderColor = NSColor(palette.projectPaneOutline)
        agentLabel.role = isHighlighted ? .primaryText : .secondaryText
        sessionLabel.role = isHighlighted ? .primaryText : .secondaryText
        directoryLabel.role = isHighlighted ? .secondaryText : .placeholderText
        branchLabel.role = isHighlighted ? .secondaryText : .tertiaryText
        summaryLabel.role = isHighlighted ? .secondaryText : .tertiaryText
        closeButton.contentTintColor = palette.nsColor(isHighlighted ? .secondaryText : .placeholderText)
    }

    @objc private func closePressed() {
        onClose?()
    }
}

// MARK: - The card's shape

/// The card's fill and border, drawn as one path that leaves out the side
/// facing the workspace: three square-cornered sides, open where the card
/// meets what it belongs to.
///
/// A layer border cannot do this — it follows all four sides — and the open
/// side is the whole point: a line there would box the card off from the
/// workspace it is supposed to be part of.
@MainActor
private final class TabCardBackgroundView: NSView {
    var fillColor: NSColor = .clear { didSet { needsDisplay = true } }
    var borderColor: NSColor = .clear { didSet { needsDisplay = true } }

    private let edge: Edge

    init(edge: Edge) {
        self.edge = edge
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let path = cardPath() else { return }
        fillColor.setFill()
        // An open path fills as if it were closed, so the fill reaches the
        // workspace side that the stroke below deliberately misses.
        path.fill()
        borderColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    /// Traced from one end of the open side, through the two outer corners, to
    /// the other end — never across the open side itself.
    private func cardPath() -> NSBezierPath? {
        let rect = strokeBounds()
        guard rect.width > 0, rect.height > 0 else { return nil }
        let path = NSBezierPath()
        let corners = corners(of: rect)
        path.move(to: corners[0])
        for corner in corners.dropFirst() { path.line(to: corner) }
        return path
    }

    /// The four points the path runs through, starting and ending on the open
    /// side: `[open, outer, outer, open]`.
    private func corners(of rect: NSRect) -> [NSPoint] {
        switch edge {
        case .top:
            return [NSPoint(x: rect.minX, y: rect.minY), NSPoint(x: rect.minX, y: rect.maxY),
                    NSPoint(x: rect.maxX, y: rect.maxY), NSPoint(x: rect.maxX, y: rect.minY)]
        case .bottom:
            return [NSPoint(x: rect.minX, y: rect.maxY), NSPoint(x: rect.minX, y: rect.minY),
                    NSPoint(x: rect.maxX, y: rect.minY), NSPoint(x: rect.maxX, y: rect.maxY)]
        case .left:
            return [NSPoint(x: rect.maxX, y: rect.minY), NSPoint(x: rect.minX, y: rect.minY),
                    NSPoint(x: rect.minX, y: rect.maxY), NSPoint(x: rect.maxX, y: rect.maxY)]
        case .right:
            return [NSPoint(x: rect.minX, y: rect.minY), NSPoint(x: rect.maxX, y: rect.minY),
                    NSPoint(x: rect.maxX, y: rect.maxY), NSPoint(x: rect.minX, y: rect.maxY)]
        }
    }

    /// `bounds` pulled in by half a point on the three stroked sides, so a
    /// 1pt line lands inside the card instead of straddling its edge. The open
    /// side keeps its half point: nothing is drawn there, and both the fill
    /// and the two side strokes have to run all the way out through the
    /// overhang and over the workspace's own outline, which is what leaves no
    /// seam between them.
    private func strokeBounds() -> NSRect {
        let half: CGFloat = 0.5
        var rect = bounds.insetBy(dx: half, dy: half)
        switch edge {
        case .top:
            rect.origin.y -= half
            rect.size.height += half
        case .bottom:
            rect.size.height += half
        case .left:
            rect.size.width += half
        case .right:
            rect.origin.x -= half
            rect.size.width += half
        }
        return rect
    }
}
