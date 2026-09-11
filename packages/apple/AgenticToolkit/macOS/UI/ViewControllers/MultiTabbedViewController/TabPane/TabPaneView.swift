import AgenticToolkitCore
import AgenticToolkitCoreMacOS
import AppKit

/// The card drawn in the edge bar: one row, the same on all four edges.
///
/// The card is flush against the side of the bar that faces the workspace and
/// open on that side — the fill runs into it, and the border stops there — so
/// the card reads as attached to the workspace rather than as a chip floating
/// beside it. The selected card paints what the workspace paints, and is
/// outlined in the workspace's own outline colour, so the two are one object
/// with a tab sticking out of it. The unselected ones sit a plane lower, on
/// `surface`, with dimmer text: present, but not the one in front.
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
    static let rowHeight: CGFloat = 34
    static let cornerRadius: CGFloat = 8

    /// The card's own padding, inside the border.
    private static let padding = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)

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
        self.background = TabCardBackgroundView(edge: edge, cornerRadius: Self.cornerRadius)
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
    /// width held between `minWidth` and `maxWidth`, and a height that grows
    /// past `rowHeight` when the content needs it to (a larger text scale).
    ///
    /// It measures the row, not the card. `TabPaneViewController` makes this
    /// view its own `view`, so AppKit installs the priority-501
    /// `preferredContentSize` constraints onto the card itself — and the
    /// labels resist compression at only `.defaultLow`. Asking the card for
    /// its `fittingSize` after a first measurement therefore returns that
    /// first answer back, and a card whose text grows on a later `reload()`
    /// would never widen. The row carries none of those constraints.
    var contentSize: NSSize {
        let fitting = content.fittingSize
        return NSSize(
            width: min(Self.maxWidth, max(Self.minWidth, fitting.width)),
            height: max(Self.rowHeight, fitting.height)
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
        // The lowest priorities in the row, so a narrow bar squeezes the
        // summary before it touches the agent name, branch, or path.
        summaryLabel.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        summaryLabel.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)

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

        for view in rowContents() { content.addArrangedSubview(view) }
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 8
        content.edgeInsets = Self.padding
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: topAnchor),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        // No self-pin on either axis: the cross axis is the hosting bar's
        // job at required priority (`TabBarView.rebuildButtons()`), and the
        // length axis is AppKit's own priority-501
        // `NSViewController.preferredContentSize` constraint, driven by
        // `contentSize` below. A required pin here would restate one of
        // those two numbers at required priority and risk an unsatisfiable
        // conflict with whichever one wins.
        applyHighlight()
    }

    /// The row, outermost item first. The close button goes on the end of the
    /// card nearest the outside of the window — the leading end on a left bar,
    /// the trailing end everywhere else — so it is never the thing standing
    /// between the card's text and the workspace it belongs to.
    private func rowContents() -> [NSView] {
        let body = [agentLabel, statusStack, sessionLabel, directoryLabel, branchLabel, summaryLabel] as [NSView]
        return edge == .left ? [closeButton] + body : body + [closeButton]
    }

    /// Selection is the card changing plane, not a highlight over it: the
    /// selected card paints the workspace's own backdrop and outline, so it
    /// reads as the near end of the workspace. The rest sit on `surface` with
    /// dimmer text.
    private func applyHighlight() {
        let palette = resolvedThemeScope.palette
        background.fillColor = isHighlighted
            ? NSColor(palette.projectPaneBackdrop)
            : palette.nsColor(.surface)
        background.borderColor = isHighlighted
            ? NSColor(palette.projectPaneOutline)
            : palette.nsColor(.border)
        agentLabel.role = isHighlighted ? .primaryText : .secondaryText
        sessionLabel.role = isHighlighted ? .primaryText : .secondaryText
        directoryLabel.role = isHighlighted ? .tertiaryText : .placeholderText
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
/// facing the workspace: three sides, rounded at the two corners between them,
/// open where the card meets what it belongs to.
///
/// A layer's `cornerRadius`/`maskedCorners` cannot do this — a layer border
/// follows all four sides — and the open side is the whole point: a line there
/// would box the card off from the workspace it is supposed to be part of.
@MainActor
private final class TabCardBackgroundView: NSView {
    var fillColor: NSColor = .clear { didSet { needsDisplay = true } }
    var borderColor: NSColor = .clear { didSet { needsDisplay = true } }

    private let edge: Edge
    private let cornerRadius: CGFloat

    init(edge: Edge, cornerRadius: CGFloat) {
        self.edge = edge
        self.cornerRadius = cornerRadius
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

    /// Traced from one end of the open side, round the two outer corners, to
    /// the other end — never across the open side itself.
    private func cardPath() -> NSBezierPath? {
        let rect = strokeBounds()
        guard rect.width > 0, rect.height > 0 else { return nil }
        let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
        let corners = corners(of: rect)
        let path = NSBezierPath()
        path.move(to: corners[0])
        path.appendArc(from: corners[1], to: corners[2], radius: radius)
        path.appendArc(from: corners[2], to: corners[3], radius: radius)
        path.line(to: corners[3])
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
    /// side keeps its half point: nothing is drawn there, and the fill has to
    /// reach all the way to the workspace.
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
