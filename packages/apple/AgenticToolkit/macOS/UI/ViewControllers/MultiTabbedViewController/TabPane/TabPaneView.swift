import AgenticToolkitCore
import AgenticToolkitCoreMacOS
import AppKit

/// The card drawn in the edge bar: a stacked block, the same on all four edges.
///
/// The card in front paints what the workspace paints, in the workspace's own
/// outline colour, and its background overhangs the bar by `workspaceOverlap` —
/// far enough to cover the line the workspace draws down that side. So there is
/// no seam where those two meet: one unbroken line runs up the active card's
/// side, around its two outer corners, down the other side, and on around the
/// workspace itself.
///
/// A card behind stops short of its own edge instead, leaving the workspace's
/// line whole where it passes: the outline belongs to the workspace and to
/// whatever is joined to it, and a waiting card is not that. How far short —
/// and how much smaller — is `stackDepth`'s doing: on a vertical bar, where the
/// cards overlap down a column, each one further from the card in front pulls
/// in another step on every side — the whole card, text included — so the
/// column reads as a deck turned to the tab you are in. A change of depth is
/// animated, so the deck is seen to turn.
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

    /// How far the active card's background reaches past the bar and over the
    /// workspace's own outline. One point is that outline's whole width, which
    /// is the point: the line ceases to exist across the card's mouth — and
    /// only across that one card's mouth.
    static let workspaceOverlap: CGFloat = 1

    /// One step back: how far a card behind is drawn in from where the card in
    /// front is drawn, on every side.
    ///
    /// The whole card moves — its paint and its text together, because a card
    /// that shrank around stationary words would read as a box closing in on
    /// them rather than as a card standing further off.
    ///
    /// On a vertical bar the steps accumulate — see `recession`.
    static let inactiveInset: CGFloat = 4

    /// How many steps back a card is drawn at before they stop adding up.
    ///
    /// Three, because four would put the paint's edge past where the card's own
    /// text begins (`padding`), and a stack that has receded further than its
    /// words is no longer a stack of anything readable.
    static let maxStackDepth = 3

    /// How long a card takes to move between depths.
    ///
    /// Quick, because the motion is the deck turning under the click that
    /// turned it: long enough to be read as one movement, short enough that it
    /// is over before the eye goes looking for what it landed on.
    static let depthAnimationDuration: TimeInterval = 0.16

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

    /// Which card in the deck this is: 0 for the one in front — the selected
    /// tab — 1 for a card immediately behind it, and on back. A card is behind
    /// until something says otherwise.
    var stackDepth = 1 {
        didSet {
            guard stackDepth != oldValue else { return }
            applyDepth(animated: animatesDepthChanges)
        }
    }

    /// Whether a change of depth slides the paint into place or puts it there
    /// at once.
    ///
    /// A card with no window is not on screen: there is nothing to watch move,
    /// and an animated constraint reads its old value until the animation ends,
    /// so anything measuring the card straight afterwards would measure where
    /// it used to be.
    var animatesDepthChanges: Bool { window != nil }

    private let edge: Edge
    private let background: TabCardBackgroundView
    private let content = NSStackView()
    private var statusViews: [NSImageView] = []
    /// Where the card's paint and text sit inside the slot the bar gave it,
    /// and which side of that slot faces the workspace. `place` moves them.
    private var cardSides: CardSides?

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
        // Room for the card to stand all the way back and still hold its own
        // text: the slot the bar hands a card never changes size, so it has to
        // be the size the deepest card needs. Sized to the front card instead,
        // the words would be squeezed as the deck turned — or, worse, the bar
        // would resize itself every time one was clicked.
        let slack = 2 * deepestRecession
        return NSSize(
            width: min(Self.maxWidth, max(Self.minWidth, fitting.width + slack)),
            height: max(Self.minHeight, fitting.height + slack)
        )
    }

    /// What the card is painted with, as the theme resolved it — the fill
    /// inside its three sides, and the line along them.
    var cardFillColor: NSColor { background.fillColor }
    var cardBorderColor: NSColor { background.borderColor }

    /// How far the painted block stands past the card's own edge on the side
    /// facing the workspace: a point out over the workspace's outline while
    /// this is the card in front, and back inside the card by `recession`
    /// while it is not.
    var workspaceOverhang: CGFloat { cardSides?.workspaceOverhang ?? 0 }

    /// Where the painted block has landed inside the card, once laid out.
    var cardPaintFrame: NSRect { background.frame }

    /// Where the card's text column has landed inside the card, once laid out.
    /// It travels with the paint; the two part company only over the
    /// workspace's own line — see `CardSides`.
    var cardTextFrame: NSRect { content.frame }

    /// What the card's two boxes are in the middle of animating, if anything —
    /// the evidence that a change of depth is being moved to rather than
    /// jumped to.
    var runningMoveAnimationKeys: [String] {
        [background, content].flatMap { $0.layer?.animationKeys() ?? [] }
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

        // The two boxes move under an implicit animation, and AppKit only
        // animates a view that has a layer of its own to move. Layer-backing
        // spreads down a subtree on its own, but not until the subtree is first
        // drawn — a card told its depth before then would jump to it — so each
        // box that moves is given its layer outright.
        for view in [self, background, content] { view.wantsLayer = true }

        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)
        observeTheme { view, _ in view.applyDepth() }

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

        let sides = CardSides(edge: edge, card: self, background: background, content: content)
        cardSides = sides
        NSLayoutConstraint.activate(sides.constraints + [
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
        applyDepth()
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

    /// Whether this is the card the workspace is showing.
    private var isFrontCard: Bool { stackDepth == 0 }

    /// How far this card is drawn in from its full size — on every side, the
    /// one facing the workspace included, and its text along with it.
    ///
    /// On a vertical bar the steps accumulate: each card further from the one
    /// in front pulls in another `inactiveInset`, up to `maxStackDepth`, so a
    /// column of cards fans away from the workspace and shrinks as it goes,
    /// like a deck being turned rather than one flat row of blocks waiting
    /// behind the front card. A horizontal bar has no such column — its cards
    /// are laid out along their long side — so every card behind takes the same
    /// single step.
    private var recession: CGFloat { recession(atDepth: stackDepth) }

    /// As far in as a card on this bar is ever drawn. What the slot has to be
    /// big enough for — see `contentSize`.
    private var deepestRecession: CGFloat { recession(atDepth: Self.maxStackDepth) }

    private func recession(atDepth depth: Int) -> CGFloat {
        guard depth > 0 else { return 0 }
        let steps = edge.isVertical ? min(depth, Self.maxStackDepth) : 1
        return CGFloat(steps) * Self.inactiveInset
    }

    /// The card in front and a card behind are two different objects, not one
    /// object at two brightnesses.
    ///
    /// The card in front paints the workspace's own backdrop and outline and
    /// reaches over the workspace's line, so it and the workspace are one
    /// surface under one line, and its agent name is the theme's accent — the
    /// one thing on the bar in a colour, so the eye finds it without reading
    /// anything. A card behind paints the plane the bar itself is on, is drawn
    /// in the border tone, and pulls in `recession` on every side — so it
    /// stands back from the workspace's line rather than over it, leaving that
    /// line whole, and is plainly the smaller of the two shapes, the more so
    /// the further back it stands. It reads as a waiting outline
    /// rather than a dimmed copy of the card in front: its own text stays at
    /// the roles a body of text is meant to be read at, so only the card around
    /// it recedes, never the words.
    private func applyDepth(animated: Bool = false) {
        let palette = resolvedThemeScope.palette
        place(animated: animated)
        background.reachesOverWorkspace = isFrontCard
        background.fillColor = isFrontCard
            ? NSColor(palette.projectPaneBackdrop)
            : palette.nsColor(.windowBackground)
        background.borderColor = isFrontCard
            ? NSColor(palette.projectPaneOutline)
            : palette.nsColor(.border)
        agentLabel.role = isFrontCard ? .accent : .primaryText
        sessionLabel.role = isFrontCard ? .primaryText : .secondaryText
        directoryLabel.role = isFrontCard ? .secondaryText : .tertiaryText
        branchLabel.role = isFrontCard ? .secondaryText : .tertiaryText
        summaryLabel.role = isFrontCard ? .secondaryText : .tertiaryText
        closeButton.contentTintColor = palette.nsColor(isFrontCard ? .secondaryText : .tertiaryText)
    }

    /// Puts the card where this depth wants it: pulled in by `recession` on
    /// every side, except that the card in front is let out over the
    /// workspace's own line instead.
    ///
    /// Animated, the whole deck moves at once — every card was told its new
    /// depth in the same turn — so the cards read as one stack rotating rather
    /// than as several blocks each deciding something separately.
    ///
    /// The constants are set the same way either way; what the animation adds
    /// is `allowsImplicitAnimation` and a layout pass taken inside the group,
    /// which is what turns the resulting change of frame into a move.
    ///
    /// Two near misses, both of which leave the card jumping: animating each
    /// constraint's `constant` through its own animator proxy — a constraint's
    /// constant is animatable, but nothing then re-lays-out the card as it
    /// changes — and running the layout pass through the *view's* animator
    /// proxy, which has no animatable property by that name and simply forwards
    /// the call.
    private func place(animated: Bool) {
        guard let cardSides else { return }
        let overhang = isFrontCard ? Self.workspaceOverlap : -recession
        guard animated else {
            cardSides.place(inset: recession, overhang: overhang)
            return
        }
        // Settle whatever layout is still outstanding first: the animation has
        // to start from where the card is, not from wherever it was last drawn.
        layoutSubtreeIfNeeded()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.depthAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            cardSides.place(inset: recession, overhang: overhang)
            layoutSubtreeIfNeeded()
        }
    }

    @objc private func closePressed() {
        onClose?()
    }
}

// MARK: - Where the card sits inside its slot

/// The four constraints holding one box inside the card's slot, kept together
/// because they are only ever moved together: the box is inset from the slot by
/// one number, on every side.
///
/// Each side is stored with the sign that moves it *inward*, which is what lets
/// `inset(_:)` take one number rather than four — `top` and `leading` move
/// inward on a positive constant, `trailing` and `bottom` on a negative one.
@MainActor
private struct InsetBox {
    /// The side facing the workspace, and which way is out from it as that
    /// side's constraint has to spell it: a trailing or bottom edge moves out
    /// on a positive constant, a leading or top edge on a negative one. The two
    /// are one piece of knowledge, so they are stored as one.
    let workspace: (constraint: NSLayoutConstraint, outwardSign: CGFloat)
    private let sides: [(constraint: NSLayoutConstraint, inward: CGFloat)]

    init(edge: Edge, slot: NSView, box: NSView) {
        let top = box.topAnchor.constraint(equalTo: slot.topAnchor)
        let leading = box.leadingAnchor.constraint(equalTo: slot.leadingAnchor)
        let trailing = box.trailingAnchor.constraint(equalTo: slot.trailingAnchor)
        let bottom = box.bottomAnchor.constraint(equalTo: slot.bottomAnchor)
        sides = [(top, 1), (leading, 1), (trailing, -1), (bottom, -1)]
        switch edge {
        case .top: workspace = (bottom, 1)
        case .bottom: workspace = (top, -1)
        case .left: workspace = (trailing, 1)
        case .right: workspace = (leading, -1)
        }
    }

    var constraints: [NSLayoutConstraint] { sides.map(\.constraint) }

    func inset(_ inset: CGFloat) {
        for side in sides { side.constraint.constant = side.inward * inset }
    }
}

/// The card's two boxes — the block it is painted as, and the column of text
/// inside that block — moved as one, because they are one card. A card behind
/// pulls both in by the same number: paint and words travel together, and the
/// card recedes rather than closing in on its own text.
///
/// The one place they part company is the side facing the workspace, where the
/// card in front lets its paint out over the workspace's own line while its
/// text stays inside the card.
@MainActor
private struct CardSides {
    private let paint: InsetBox
    private let text: InsetBox

    init(edge: Edge, card: NSView, background: NSView, content: NSView) {
        paint = InsetBox(edge: edge, slot: card, box: background)
        text = InsetBox(edge: edge, slot: card, box: content)
    }

    var constraints: [NSLayoutConstraint] { paint.constraints + text.constraints }

    /// How far the paint stands past the card on the side facing the
    /// workspace — negative while it stands short of it.
    var workspaceOverhang: CGFloat {
        paint.workspace.constraint.constant * paint.workspace.outwardSign
    }

    /// Pulls the whole card in by `inset`, then lets the paint's workspace side
    /// back out by `overhang` — the one side the two numbers can disagree
    /// about, because the card in front reaches over the workspace's line
    /// rather than stopping short of it.
    func place(inset: CGFloat, overhang: CGFloat) {
        paint.inset(inset)
        text.inset(inset)
        paint.workspace.constraint.constant = overhang * paint.workspace.outwardSign
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
    /// Whether this card's own edge is standing over the workspace's outline
    /// rather than short of it; see `strokeBounds()`.
    var reachesOverWorkspace = false { didSet { needsDisplay = true } }

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
    /// 1pt line lands inside the card instead of straddling its edge.
    ///
    /// The open side gets its half point back only while the card reaches over
    /// the workspace: nothing is drawn along that side, and the fill and the
    /// two side strokes have to run all the way out through the overhang and
    /// over the workspace's own outline, which is what leaves no seam between
    /// them. A card standing short of the outline keeps the inset instead, so
    /// not even the ends of its two side strokes cross the line.
    private func strokeBounds() -> NSRect {
        let half: CGFloat = 0.5
        var rect = bounds.insetBy(dx: half, dy: half)
        guard reachesOverWorkspace else { return rect }
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
