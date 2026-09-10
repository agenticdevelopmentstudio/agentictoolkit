import AgenticToolkitCore
import AgenticToolkitCoreMacOS
import AppKit

/// A titled card that folds: a rounded surface, a titlebar naming it, and
/// whatever content is added under that.
///
///     ┌══════════════════════════════════════════🛑═┐
///     ║ ⃝  mike@example.com                       ▾ ║
///     ├──────────────────────────────────────────────┤
///     │ …content…                                    │
///     └──────────────────────────────────────────────┘
///
///     ┌══════════════════════════════════════════🛑═┐
///     ║ ⃝  me@example.com                         ▸ ║
///     ├──────────────────────────────────────────────┤
///     │                        5H: 23% | 7D: 12%     │
///     └──────────────────────────────────────────────┘
///
/// A card that folds is what makes a list of five sections readable on a laptop
/// screen: the cards a reader is not watching cost one line each instead of
/// four, and a content-hugging window shrinks to the smaller content. The
/// collapsed line still has to answer the question the card exists to answer, so
/// it keeps a summary of what it is hiding — a fold that hides the numbers is
/// just a card you have to open again.
///
/// The folded summary is on its own row under the title, pinned to the right.
/// Beside the title it made every folded card at least as wide as an address
/// plus its readings plus the toggle, which is a width nothing else in the
/// window needed — and the two competed, so a long address went short on a card
/// that had a whole second line free. Under it they each get the full width, and
/// stacked cards still read as a column of readings under one right edge rather
/// than starting wherever each title happened to stop.
///
/// ## The masthead is a bar, not the first row of the content
///
/// The title and its toggle sit on a strip of their own — a slightly raised
/// fill (`elevatedSurface`) across the top of the card, ruled off from what is
/// under it. A card is a thing with a name and a body, and drawing the name as
/// simply the first line inside the body made a stack of them read as one long
/// column of text in which some lines happened to be bolder: the fold's handle
/// had to be *found* rather than looked at. A bar is found without reading.
///
/// It is **tighter than the body it introduces** (`titlebarInset`, half the
/// card's own `verticalInset`). That is what makes it read as a titlebar rather
/// than as a first row: a strip is defined by being shallower than what it caps.
/// Its lower inset is where the bar ends, so a folded card with nothing to
/// summarise is exactly the bar and nothing else — the card's bottom inset
/// switches to the bar's, rather than leaving a sliver of empty surface under a
/// one-line card.
///
/// The bar is a subview of the surface rather than of the card, purely so it is
/// clipped: it runs edge to edge, and the corners it would otherwise square off
/// are the card's rounded ones. Being inside the surface also puts it *under*
/// the surface's border — a `CALayer` draws its border above its sublayers —
/// which is what keeps the card's outline unbroken across the top.
///
/// `titleIcon` puts one SF Symbol in front of the name (a person for an
/// account, say). It is decoration on a name that is already spoken, so it is
/// left out of the accessibility tree: a card whose address is read out does not
/// also need to announce that it is a card about a person.
///
/// `titleIconIsVisible` is how a *stack* of such cards marks one of them — the
/// account that is logged in, say — without the others' names stepping left to
/// fill the gap. The unmarked card still builds the symbol and still holds its
/// width; it simply does not paint it. Passing `titleIcon: nil` instead would
/// take the column away with the symbol, and a list of addresses that start in
/// two different places is harder to read than one with a blank in front of
/// most of them.
///
/// ## The standing is a corner badge, not a masthead item
///
/// A card's status is stamped on its top-right corner — centred on the corner's
/// own curve, half of it hanging off the card — rather than set in the masthead
/// beside the toggle.
/// On the line it cost every card a reserved slot — a card with nothing to
/// report still had to hold the width of the widest symbol the host could draw,
/// or the summaries either side of it stopped lining up — and it spent that
/// width on the cards that had the least to say. On the corner it costs no card
/// anything, it is found without reading the line it is on, and it can be drawn
/// big enough to read across a list. It reaches no further into the card than
/// its own radius, which is less than the gutter the masthead is already held
/// off the edge by: that is what keeps it clear of the disclosure triangle
/// without either knowing about the other.
///
/// It is centred on the *visible* corner, not on the frame's: a rounded card has
/// no ink at the square corner, so a badge centred there sits up and out on air
/// and reads as having slipped off. `cornerPeakInset` walks it back down and in
/// to the point where the corner arc actually turns — the 45° point on it, which
/// is `r - r/√2` inside the frame on each axis.
///
/// The card's surface and border are drawn by a subview rather than by the card
/// itself, purely so the badge can be drawn over them. A `CALayer` paints its own
/// border ABOVE its sublayers, so a card that draws its own border draws a
/// hairline straight across a badge sitting on its corner, whatever the badge's
/// `zPosition` says — the only fix is for the border to belong to a layer the
/// badge is not inside.
///
/// ## The title gets whatever the masthead is not using
///
/// The title is the one thing on that line that yields, so it is the one thing
/// that goes short when the line is full. An open card draws no summary at all,
/// so what the summary WILL need when the card folds is reserved on the card's
/// width floor (`mastheadWidthFloor`) instead of on a row that is not there.
/// That is what keeps folding from moving anything sideways.
///
/// The floor is the WIDER of the two rows, not their sum — the title's line and
/// the summary's line are each entitled to the whole card, which is the point of
/// stacking them. It counts the title's line so that yielding is what the title
/// does when the window is too narrow for it, not something a card asks of it
/// while there is a window still willing to grow.
///
/// ## Folding never changes the card's width
///
/// A card is exactly as wide folded as it is open, and that is the whole reason
/// its content is built even while it is shut. A window that hugs its content
/// derives its width from the widest thing in it; if a fold dropped the content
/// out of the layout, every fold would re-derive a narrower window and the
/// window would jump sideways under the reader on a click that was about
/// height. So the content is added to the card in both states and merely
/// *hidden* when folded, and the card carries a width floor measured from it
/// (`contentWidthFloor`), which the collapsed summary's reserved slot matches on
/// the header side. Height is the only thing a fold is allowed to move.
///
/// The host still gets to skip the *work* a hidden card would otherwise cause —
/// registering a live countdown, subscribing to a feed — because it knows which
/// cards are folded (`CardFoldMemory.isCollapsed`); what it must not skip is
/// building the views, which is what makes the width knowable.
@MainActor
public final class DisclosureCardView: NSView, Themeable {

    /// One reading on a collapsed card's summary line: `5H: 23%`. Kept as parts
    /// rather than a formatted string so each value can carry its own colour — a
    /// fold that greys out a red 97% hides exactly the fact it most needed to
    /// keep.
    public struct SummaryPart {
        public let name: String
        public let value: String
        /// How the value is coloured, asked of the live palette rather than
        /// resolved once when the part is built — so a card already on screen
        /// recolours with everything else when the theme changes. A closure
        /// rather than a colour name because a host may colour by something the
        /// palette's name table cannot say (a position in a series, say), and
        /// the card has no business knowing which.
        public let color: (SemanticPalette) -> NSColor?

        public init(
            name: String, value: String, color: @escaping (SemanticPalette) -> NSColor?
        ) {
            self.name = name
            self.value = value
            self.color = color
        }

        /// The common case: a colour the palette already knows by name.
        public init(name: String, value: String, colorName: String?) {
            self.init(name: name, value: value, color: { $0.color(named: colorName) })
        }
    }

    /// What a card says about its own standing, drawn on the card's top-right
    /// corner. `accessibilityLabel` is also the tooltip: a symbol is compact,
    /// not self-explaining, and the word it replaced has to stay reachable
    /// somewhere.
    public struct StatusSymbol {
        public let symbolName: String
        public let colorName: String?
        public let accessibilityLabel: String

        public init(symbolName: String, colorName: String?, accessibilityLabel: String) {
            self.symbolName = symbolName
            self.colorName = colorName
            self.accessibilityLabel = accessibilityLabel
        }
    }

    private let titleField = NSTextField(labelWithString: "")
    /// The one symbol in front of the name, when the host gave one.
    private let titleIconView = NSImageView()
    /// Icon and name as one piece, so the pair yields together when the line is
    /// too narrow for them.
    private let titleLine = NSStackView()
    /// The strip the title and its toggle are drawn on, and the hairline that
    /// rules it off from the body. Subviews of `surface`, so the card's rounded
    /// corners clip the bar and the card's border draws over it.
    private let titlebar = NSView()
    private let titlebarRule = NSView()
    /// One quiet line under the masthead saying what the card's content means.
    private let subtitleField = NSTextField(labelWithString: "")
    /// The collapsed card's one-line stand-in for its content, on its own row
    /// under the title. Not drawn at all while the card is open — what it will
    /// need on folding is held on the width floor instead.
    private let summaryField = NSTextField(labelWithString: "")
    /// The card's surface and border, drawn by a view of its own so the corner
    /// badge can sit above them — see the note in the type's documentation.
    private let surface = NSView()
    private let statusIcon = NSImageView()
    private let disclosure = NSButton()
    private let content = NSStackView()
    /// Everything under the titlebar: the folded card's summary, the subtitle,
    /// and the content itself. Detached entirely when there is nothing in it,
    /// which is what lets a folded card be exactly its own titlebar.
    private let body = NSStackView()

    /// Accent (an identifier, an address) vs. primary text (a plain heading).
    private let titleIsAccent: Bool
    /// The SF Symbol drawn in front of the name, if any.
    private let titleSymbol: String?
    /// Whether the symbol is painted. False still reserves its width — see the
    /// type's own documentation for why that is not the same as no symbol.
    private let titleSymbolIsVisible: Bool
    private let summary: [SummaryPart]
    private let status: StatusSymbol?
    private let scaledSize: CGFloat
    private let onToggle: ((Bool) -> Void)?

    private var observer: ThemePaletteObserver?

    /// The card's fold-independent width floor: as wide as its content wants to
    /// be, whether or not the content is currently drawn.
    private var contentWidthFloor: NSLayoutConstraint?
    /// What the masthead needs when this card is FOLDED — the wider of its two
    /// rows: the title beside the toggle, or the summary under them. Held on the
    /// width floor instead of in the open card's layout, so folding cannot
    /// change the card's width.
    private var mastheadWidthFloor: CGFloat = 0

    private static let cornerRadius: CGFloat = 10
    private static let borderWidth: CGFloat = 1
    private static let horizontalInset: CGFloat = 14
    private static let verticalInset: CGFloat = 12
    /// The titlebar's own vertical inset. Deliberately half the body's: a strip
    /// reads as a strip by being shallower than what it caps.
    private static let titlebarInset: CGFloat = 6
    /// Between the symbol and the name it introduces — closer than the
    /// masthead's own gap, because the two are one piece.
    private static let iconGap: CGFloat = 6
    /// How far a dimmed card recedes. Far enough to sort one card out of a list
    /// at a glance, not so far that the dimmed cards stop being readable.
    private static let dimmedAlpha: CGFloat = 0.55
    /// The masthead's own spacing, named once because the folded width floor
    /// has to add up the same line the layout builds.
    private static let mastheadGap: CGFloat = 8

    private let padX: CGFloat
    private let padY: CGFloat
    /// The titlebar's vertical inset at this text size.
    private let padTitleY: CGFloat

    public init(
        title: String,
        titleIsAccent: Bool,
        titleIcon: String? = nil,
        titleIconIsVisible: Bool = true,
        subtitle: String? = nil,
        summary: [SummaryPart] = [],
        status: StatusSymbol? = nil,
        isCollapsed: Bool = false,
        isDimmed: Bool = false,
        scaledSize: CGFloat,
        onToggle: ((Bool) -> Void)? = nil
    ) {
        self.titleIsAccent = titleIsAccent
        self.titleSymbol = titleIcon
        self.titleSymbolIsVisible = titleIconIsVisible
        self.summary = summary
        self.status = status
        self.scaledSize = scaledSize
        self.onToggle = onToggle
        self.padX = Self.padXFor(scaledSize: scaledSize)
        self.padY = ceil(Self.verticalInset * scaledSize / CGFloat(NSFont.systemFontSize))
        self.padTitleY = ceil(Self.titlebarInset * scaledSize / CGFloat(NSFont.systemFontSize))
        super.init(frame: .zero)
        // Whole-card alpha rather than a second set of dimmed colours: the card
        // recedes complete — border, surface, content and all — and every colour
        // it draws keeps meaning exactly what it means on the live card.
        alphaValue = isDimmed ? Self.dimmedAlpha : 1.0
        translatesAutoresizingMaskIntoConstraints = false
        // The corner badge is drawn half outside the card on purpose.
        clipsToBounds = false
        surface.wantsLayer = true
        surface.translatesAutoresizingMaskIntoConstraints = false

        titleField.stringValue = title
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.lineBreakMode = .byTruncatingMiddle
        // The title yields before anything else on the line: a truncated address
        // is still recognisable, and a truncated percentage is a lie.
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        subtitleField.stringValue = subtitle ?? ""
        subtitleField.translatesAutoresizingMaskIntoConstraints = false
        subtitleField.lineBreakMode = .byTruncatingTail
        // The subtitle explains, it does not measure: it yields its width to the
        // card's content rather than widening the window to stay whole.
        subtitleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // A folded card is a headline; the explanation belongs to the content it
        // is currently hiding, and reprinting it under a one-line card doubles
        // the height the fold was asked to reclaim.
        subtitleField.isHidden = subtitle == nil || isCollapsed

        configureSummary(isCollapsed: isCollapsed)
        configureStatusBadge()
        configureDisclosure(isCollapsed: isCollapsed)
        configureTitleLine()
        configureTitlebar()

        content.orientation = .vertical
        content.alignment = .width
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        content.isHidden = isCollapsed

        // The name at the left edge, the toggle at the right — the one piece
        // every card has, so it lands in the same place on all of them.
        let header = PinnedEndsLine.make(
            leading: titleLine, trailing: disclosure,
            minimumGap: Self.mastheadGap, alignment: .centerY
        )

        body.orientation = .vertical
        body.alignment = .width
        body.spacing = 10
        body.translatesAutoresizingMaskIntoConstraints = false
        body.addFullWidthArrangedSubview(summaryField)
        body.addFullWidthArrangedSubview(subtitleField)
        // Hidden rather than left out: an `NSStackView` detaches a hidden
        // arranged view completely, so a folded card is one line tall with no
        // stray spacing under it — and, unlike leaving the content out, the card
        // can still be measured at the width it will want when it opens.
        body.addFullWidthArrangedSubview(content)
        // Nothing under the bar at all: a folded card with no summary IS its
        // titlebar, so the body leaves the layout rather than standing there as
        // an empty stack between two insets.
        let bodyIsEmpty = isCollapsed && summary.isEmpty
        body.isHidden = bodyIsEmpty

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        // The bar's own lower inset plus the body's upper one: the bar stops
        // `padTitleY` under the header, and the body starts `padY` under that.
        stack.spacing = padTitleY + padY
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addFullWidthArrangedSubview(header)
        stack.addFullWidthArrangedSubview(body)
        // Order is what puts the badge over the border: the surface first (with
        // the titlebar inside it, so the border draws over that too), the
        // content on it, the badge last and so above all three.
        addSubview(surface)
        addSubview(stack)
        addSubview(statusIcon)

        let floor = widthAnchor.constraint(greaterThanOrEqualToConstant: 0)
        // Just under required: on a screen too narrow for the content the window
        // scrolls rather than the layout becoming unsatisfiable.
        floor.priority = NSLayoutConstraint.Priority(999)
        contentWidthFloor = floor

        // Centred ON the corner rather than tucked inside it: half of the badge
        // hangs off the card, which is what makes it read as a stamp on the card
        // rather than as something the card is making room for. It reaches no
        // further in than its own radius, and that is less than the gutter the
        // masthead is already held off the edge by, so it cannot touch the
        // toggle however large a text size asks for.
        let badge = Self.cornerBadgeDiameter(scaledSize: scaledSize)
        let peak = Self.cornerPeakInset
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            // The bar runs edge to edge and stops a tight inset under the line
            // it carries — so its height is the header's, never the body's.
            titlebar.topAnchor.constraint(equalTo: surface.topAnchor),
            titlebar.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            titlebar.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            titlebar.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: padTitleY),
            titlebarRule.leadingAnchor.constraint(equalTo: titlebar.leadingAnchor),
            titlebarRule.trailingAnchor.constraint(equalTo: titlebar.trailingAnchor),
            titlebarRule.bottomAnchor.constraint(equalTo: titlebar.bottomAnchor),
            titlebarRule.heightAnchor.constraint(equalToConstant: Self.borderWidth),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: padTitleY),
            // The card's own bottom inset is the BAR's whenever the bar is all
            // there is, so a one-line card ends where the bar ends.
            stack.bottomAnchor.constraint(equalTo: bottomAnchor,
                                          constant: -(bodyIsEmpty ? padTitleY : padY)),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padX),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padX),
            statusIcon.centerXAnchor.constraint(equalTo: trailingAnchor, constant: -peak),
            statusIcon.centerYAnchor.constraint(equalTo: topAnchor, constant: peak),
            statusIcon.widthAnchor.constraint(equalToConstant: badge),
            statusIcon.heightAnchor.constraint(equalToConstant: badge),
            floor
        ])

        observer = ThemePaletteObserver(host: self) { [weak self] palette in self?.applyTheme(palette) }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    /// The summary's row, right-aligned across the whole masthead. Present only
    /// when there is a summary AND the card is folded — what keeps the fold from
    /// moving anything sideways is the width floor (`mastheadWidthFloor`), not a
    /// row standing empty under an open card's title.
    private func configureSummary(isCollapsed: Bool) {
        summaryField.translatesAutoresizingMaskIntoConstraints = false
        summaryField.alignment = .right
        summaryField.lineBreakMode = .byClipping
        summaryField.setContentCompressionResistancePriority(.required, for: .horizontal)
        // An `NSStackView` detaches a hidden arranged view completely, which is
        // the point: an open card is exactly as tall as it was before the
        // summary had a row of its own.
        summaryField.isHidden = summary.isEmpty || !isCollapsed
    }

    /// The symbol and the name as one piece.
    ///
    /// A stack rather than a third end on the masthead line: the icon and the
    /// address are one thing that yields together, and what a masthead pins to
    /// its ends is the name and the toggle — not the name's own punctuation.
    /// The stack takes the field's own priorities, so the pair goes short
    /// exactly where the address alone used to, and the symbol keeps its width
    /// while the letters give theirs up.
    private func configureTitleLine() {
        titleIconView.translatesAutoresizingMaskIntoConstraints = false
        titleIconView.imageScaling = .scaleProportionallyDown
        titleIconView.isHidden = titleSymbol == nil
        // Present and unpainted, not absent: the image is what gives the view
        // its width, so hiding it would close the column the unmarked names are
        // lining up against.
        titleIconView.alphaValue = titleSymbolIsVisible ? 1 : 0
        if let titleSymbol {
            titleIconView.image = NSImage(
                systemSymbolName: titleSymbol, accessibilityDescription: nil
            )
            titleIconView.symbolConfiguration = NSImage.SymbolConfiguration(
                pointSize: scaledSize, weight: .regular
            )
        }
        // Decoration on a name that is already spoken: a card whose address is
        // read out does not also need to announce that it is about a person.
        titleIconView.setAccessibilityElement(false)
        titleIconView.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleIconView.setContentHuggingPriority(.required, for: .horizontal)

        titleLine.orientation = .horizontal
        titleLine.alignment = .centerY
        titleLine.spacing = Self.iconGap
        titleLine.translatesAutoresizingMaskIntoConstraints = false
        titleLine.addArrangedSubview(titleIconView)
        titleLine.addArrangedSubview(titleField)
        titleLine.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLine.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    /// The bar itself: a fill inside the surface, and a rule along its foot.
    /// Both are pure background, so neither is in the accessibility tree and
    /// neither has anything to say when the card is read.
    private func configureTitlebar() {
        for strip in [titlebar, titlebarRule] {
            strip.wantsLayer = true
            strip.translatesAutoresizingMaskIntoConstraints = false
        }
        surface.addSubview(titlebar)
        titlebar.addSubview(titlebarRule)
    }

    /// The corner badge: this card's standing, on its top-right corner, or
    /// nothing at all. A card with nothing to report draws nothing and pays
    /// nothing — there is no slot to keep open, because the badge shares its
    /// line with nothing.
    private func configureStatusBadge() {
        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        statusIcon.imageScaling = .scaleProportionallyDown
        statusIcon.isHidden = status == nil
        guard let status else { return }
        statusIcon.image = NSImage(
            systemSymbolName: status.symbolName,
            accessibilityDescription: status.accessibilityLabel
        )
        statusIcon.symbolConfiguration = Self.statusSymbolConfiguration(scaledSize: scaledSize)
        statusIcon.toolTip = status.accessibilityLabel
        // Its own element, because it is no longer inside a line a reader is
        // handed anyway: unspoken, a corner mark is invisible rather than terse.
        statusIcon.setAccessibilityElement(true)
        statusIcon.setAccessibilityRole(.image)
        statusIcon.setAccessibilityLabel(status.accessibilityLabel)
    }

    /// How big the corner badge is drawn. Bigger than the text beside it: it is
    /// the one mark on a card that has to be legible from across a list of them,
    /// and it is not competing for room with anything — it sits in the corner's
    /// own air. Bounded by the gutter all the same, since half of it hangs
    /// inside the card and must stay clear of the toggle.
    static func cornerBadgeDiameter(scaledSize: CGFloat) -> CGFloat {
        min(ceil(scaledSize * 1.3), padXFor(scaledSize: scaledSize) * 1.5)
    }

    /// How far inside the frame's corner the rounded corner's curve actually
    /// peaks: the 45° point on an arc of radius `r` lies `r - r/√2` in on each
    /// axis. What the badge is centred on, since the square corner it would
    /// otherwise take is a place the card draws nothing.
    static let cornerPeakInset: CGFloat = cornerRadius - cornerRadius / 2.0.squareRoot()

    /// The card's horizontal gutter, as a function of the text size — the same
    /// arithmetic `padX` is built from, available before there is an instance
    /// to ask.
    private static func padXFor(scaledSize: CGFloat) -> CGFloat {
        ceil(Self.horizontalInset * scaledSize / CGFloat(NSFont.systemFontSize))
    }

    private static func statusSymbolConfiguration(
        scaledSize: CGFloat
    ) -> NSImage.SymbolConfiguration {
        NSImage.SymbolConfiguration(
            pointSize: Self.cornerBadgeDiameter(scaledSize: scaledSize), weight: .semibold
        )
    }

    /// The system disclosure triangle rather than a drawn chevron: it is the
    /// control macOS already uses for exactly this, it points the way every
    /// other folding thing on the platform points, and it comes with the
    /// keyboard and accessibility behaviour for free.
    private func configureDisclosure(isCollapsed: Bool) {
        disclosure.translatesAutoresizingMaskIntoConstraints = false
        disclosure.bezelStyle = .disclosure
        disclosure.setButtonType(.onOff)
        disclosure.title = ""
        disclosure.state = isCollapsed ? .off : .on
        disclosure.setContentCompressionResistancePriority(.required, for: .horizontal)
        disclosure.target = self
        disclosure.action = #selector(disclosureTapped)
        disclosure.toolTip = isCollapsed ? "Show details" : "Hide details"
        disclosure.setAccessibilityLabel(isCollapsed ? "Show details" : "Hide details")
    }

    @objc private func disclosureTapped() {
        onToggle?(disclosure.state == .off)
    }

    /// Appends a view below the masthead. Called whether or not the card is
    /// folded — see the width note in the type's documentation.
    public func addContent(_ view: NSView) {
        content.addFullWidthArrangedSubview(view)
        updateContentWidthFloor()
    }

    /// Spacing between the card's own content views. Some content wants air
    /// between its pieces; a table's rows want to read as a table.
    public var contentSpacing: CGFloat {
        get { content.spacing }
        set {
            content.spacing = newValue
            updateContentWidthFloor()
        }
    }

    /// Whether this card is currently folded. Set at build time; a fold is
    /// applied by rebuilding, not by mutating.
    public var isCollapsed: Bool { content.isHidden }

    /// The width the card wants for its content, drawn or not. Re-measured on
    /// every layout pass so a font change (a theme swap, the text-size slider)
    /// that resizes the hidden content is picked up too; the guard is what stops
    /// a measurement made during layout from asking for another one forever.
    public override func layout() {
        super.layout()
        updateContentWidthFloor()
    }

    private func updateContentWidthFloor() {
        guard let contentWidthFloor else { return }
        // The wider of the two things a fold swaps between: the content the open
        // card draws, and the masthead the folded one draws instead. Both are
        // measured in whichever state the card is in, which is what makes the
        // floor fold-independent.
        let wanted = max(ceil(content.fittingSize.width), mastheadWidthFloor) + padX * 2
        guard abs(wanted - contentWidthFloor.constant) > 0.5 else { return }
        contentWidthFloor.constant = wanted
    }

    public func applyTheme(_ palette: SemanticPalette) {
        surface.layer?.cornerRadius = Self.cornerRadius
        surface.layer?.borderWidth = Self.borderWidth
        surface.layer?.backgroundColor = palette.surfaceColor.cgColor
        surface.layer?.borderColor = palette.outlineColor.cgColor
        // What clips the bar's square top corners to the card's round ones —
        // and, since a layer draws its border above its sublayers, what keeps
        // the card's outline unbroken across the strip.
        surface.layer?.masksToBounds = true

        titlebar.layer?.backgroundColor = palette.elevatedSurfaceColor.cgColor
        titlebarRule.layer?.backgroundColor = palette.dividerColor.cgColor

        var titleStyle = palette.theme.typography.style(.body)
        titleStyle.weight = .semibold
        titleField.font = titleStyle.nsFont(scaledSize: scaledSize)
        titleField.textColor = titleIsAccent ? palette.accentColor : palette.primaryTextColor
        // The symbol is part of the name, so it takes the name's colour rather
        // than a tier of its own.
        titleIconView.contentTintColor = titleField.textColor

        subtitleField.font = palette.theme.typography.style(.caption)
            .nsFont(scaledSize: scaledSize * 0.85)
        subtitleField.textColor = palette.tertiaryTextColor

        statusIcon.contentTintColor = palette.color(named: status?.colorName)
            ?? palette.secondaryTextColor
        disclosure.contentTintColor = palette.secondaryTextColor

        let line = Self.summaryString(summary, palette: palette, scaledSize: scaledSize)
        summaryField.attributedStringValue = line
        // The title is measured at its full length — symbol and all, which is
        // why the LINE is measured rather than the field — not at whatever the
        // bar currently affords it, so the address is truncated only by a window
        // that cannot be any wider. Against the summary, not added to it: the
        // summary has a row to itself, and the wider of the two rows is what the
        // masthead needs.
        mastheadWidthFloor = summary.isEmpty ? 0 : max(
            ceil(titleLine.fittingSize.width)
                + Self.mastheadGap + ceil(disclosure.fittingSize.width),
            ceil(line.size().width)
        )
        updateContentWidthFloor()
    }

    /// `5H: 23% | 7D: 12%` — each name in the quietest text tier, each value in
    /// the colour its part carries (which is the same colour the open card gives
    /// that reading, so folding a card changes what is on screen and never what
    /// it says).
    private static func summaryString(
        _ parts: [SummaryPart], palette: SemanticPalette, scaledSize: CGFloat
    ) -> NSAttributedString {
        let typography = palette.theme.typography
        let nameFont = typography.style(.caption).nsFont(scaledSize: scaledSize * 0.85)
        let valueFont = typography.style(.code).nsFont(scaledSize: scaledSize * 0.85)
        let line = NSMutableAttributedString()
        for (index, part) in parts.enumerated() {
            if index > 0 {
                line.append(NSAttributedString(
                    string: "  |  ",
                    attributes: [.font: nameFont, .foregroundColor: palette.tertiaryTextColor]
                ))
            }
            line.append(NSAttributedString(
                string: "\(part.name): ",
                attributes: [.font: nameFont, .foregroundColor: palette.tertiaryTextColor]
            ))
            line.append(NSAttributedString(
                string: part.value,
                attributes: [
                    .font: valueFont,
                    .foregroundColor: part.color(palette) ?? palette.secondaryTextColor
                ]
            ))
        }
        return line
    }
}
