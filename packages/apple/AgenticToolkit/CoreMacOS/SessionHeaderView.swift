import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreUI
import AgenticDeveloperToolkitUI

/// The one line that says which session a thing belongs to:
///
/// ```
/// [icon]  project » branch » session name              [accessory]
///   │              │                                        │
///  the app    SessionBreadcrumbView                  whatever the
///  it runs in                                        window adds
/// ```
///
/// Three places show the same sessions — the Sessions list, the Conversations
/// shelf, and the header over a message in the Conversations feed — and a
/// reader moving between them is looking at one set of conversations, not
/// three. So they head their rows with this *one* view rather than with three
/// arrangements of the same three facts, which drift a separator, an inset or a
/// colour at a time until the windows no longer read as being about the same
/// thing.
///
/// What varies between them is only what this takes as arguments: the type
/// size, how big the icon is, which margin it is against, and what (if
/// anything) goes at the far end. The ordering, the spacing and the colours are
/// not negotiable, because they are what makes the three recognisable as one.
///
/// The trailing slot is a plain view rather than a known control on purpose:
/// the Sessions list fills it with an activity indicator that lives a tier
/// above this file, and a lower tier naming a higher one is the dependency this
/// layout is not worth inverting.
public final class SessionHeaderView: NSStackView, Themeable {

    /// Which margin the icon is against.
    ///
    /// The Conversations feed mirrors it per speaker — the icon belongs to
    /// whoever is talking, and a merged timeline is read by which side a row
    /// hangs off — while a list, having one column, always puts it first.
    public enum IconEdge: Sendable { case leading, trailing }

    /// How the icon is drawn, and whether it does anything.
    public struct IconSpec: Sendable {
        /// The `TERM_PROGRAM` the session runs under, which
        /// ``TerminalAppIcon`` maps to a Dock icon.
        public let appIdentity: String
        public let side: CGFloat
        public let edge: IconEdge
        /// Air between the icon and the first crumb.
        public let gap: CGFloat
        /// Whether the caller is going to wire a target and an action to it.
        ///
        /// Decided here rather than discovered later because it picks the
        /// *class*: ``PointingHandButton`` promises a link under the pointer
        /// unconditionally — cursor rect and tracking area both — and a promise
        /// kept by nothing is worse than no promise. An icon nobody wired is a
        /// plain button, still the picture that says which application.
        public let isActionable: Bool

        public init(
            appIdentity: String,
            side: CGFloat = 28,
            edge: IconEdge = .leading,
            gap: CGFloat = 8,
            isActionable: Bool = false
        ) {
            self.appIdentity = appIdentity
            self.side = side
            self.edge = edge
            self.gap = gap
            self.isActionable = isActionable
        }
    }

    /// The trail itself, exposed because a host aligns things to *it* rather
    /// than to this view: a row's prose lines up under the first crumb, not
    /// under the icon that heads the line.
    public let breadcrumb: SessionBreadcrumbView

    /// The application icon, when this header has one. A button whether or not
    /// it was wired — see ``IconSpec/isActionable``.
    public private(set) var iconButton: NSButton?

    /// What the caller put at the far end, if anything.
    public private(set) var accessory: NSView?

    private let accessoryGap: CGFloat
    private let iconSpec: IconSpec?

    /// The trail on show.
    public var crumbs: SessionBreadcrumbView.Crumbs {
        get { breadcrumb.crumbs }
        set { breadcrumb.crumbs = newValue }
    }

    /// The type size the trail is set at — ``TextRole/body`` in a list of
    /// sessions, ``TextRole/caption`` over a chat bubble, where the line is a
    /// caption on the message rather than the row's subject.
    public var textRole: TextRole {
        get { breadcrumb.textRole }
        set { breadcrumb.textRole = newValue }
    }

    public init(
        crumbs: SessionBreadcrumbView.Crumbs = .init(context: []),
        textRole: TextRole = .body,
        icon: IconSpec? = nil,
        accessory: NSView? = nil,
        accessoryGap: CGFloat = 12
    ) {
        self.breadcrumb = SessionBreadcrumbView(crumbs: crumbs, textRole: textRole)
        self.accessory = accessory
        self.accessoryGap = accessoryGap
        self.iconSpec = icon
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        orientation = .horizontal
        alignment = .centerY
        // Every gap here is named by the caller, so the stack contributes none
        // of its own and `minimumWidth` can add up what is actually drawn.
        spacing = 0

        if let icon { iconButton = makeIcon(icon) }
        build()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    // MARK: - Build

    private func makeIcon(_ spec: IconSpec) -> NSButton {
        let button = spec.isActionable ? PointingHandButton() : InertIconButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.image = TerminalAppIcon.image(forTermProgram: spec.appIdentity)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyUpOrDown
        button.isBordered = false
        button.bezelStyle = .shadowlessSquare
        button.setAccessibilityLabel(spec.appIdentity)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: spec.side),
            button.heightAnchor.constraint(equalToConstant: spec.side)
        ])
        return button
    }

    private func build() {
        let icon = iconButton
        let edge = iconSpec?.edge ?? .leading
        let gap = iconSpec?.gap ?? 0

        // Eats the slack between the trail and the accessory, so the accessory
        // is against the far margin however short the trail is. Made only when
        // there is an accessory: without one the header hugs its own text,
        // which is what lets a chat row's bubble start where the trail does.
        var slack: NSView?
        if accessory != nil {
            let view = NSView()
            view.setContentHuggingPriority(.init(1), for: .horizontal)
            view.setContentCompressionResistancePriority(.init(1), for: .horizontal)
            slack = view
        }

        // Reading order is the same both ways round — only which end the icon
        // and the accessory are at changes.
        let ordered: [NSView?] = edge == .leading
            ? [icon, breadcrumb, slack, accessory]
            : [accessory, slack, breadcrumb, icon]
        for view in ordered.compactMap({ $0 }) { addArrangedSubview(view) }

        if let icon {
            setCustomSpacing(gap, after: edge == .leading ? icon : breadcrumb)
        }
        if let accessory, let slack {
            setCustomSpacing(
                accessoryGap, after: edge == .leading ? slack : accessory)
        }
    }

    /// An icon nobody wired: a picture, not a target. It hands every click to
    /// what is under it — a list row's own selection, say — rather than
    /// swallowing it in a button whose action does nothing.
    private final class InertIconButton: NSButton {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    // MARK: - Measurement

    /// The narrowest this header can be drawn whole — every crumb untruncated,
    /// with the icon and the accessory beside them. A window that lists these
    /// keeps itself at least this wide.
    ///
    /// Measured from ``SessionBreadcrumbView/minimumWidth`` rather than from
    /// `fittingSize`, because the crumb labels deliberately abstain from the
    /// fitting width (a single long session name once dragged the Sessions
    /// window out to forty thousand points) and a fitting size squeezes them to
    /// nothing.
    public var minimumWidth: CGFloat {
        var width = breadcrumb.minimumWidth
        if let spec = iconSpec { width += spec.side + spec.gap }
        if let accessory {
            width += accessoryGap + ceil(max(
                accessory.intrinsicContentSize.width, accessory.fittingSize.width))
        }
        return width
    }

    // MARK: - Theme

    public func applyTheme(_ palette: SemanticPalette) {
        breadcrumb.applyTheme(palette)
        // Nothing to theme on the icon: an application's icon is its own
        // artwork, and a tint over it would be this window's opinion painted
        // on the one thing in the line a reader recognises without reading.
        (accessory as? Themeable)?.applyTheme(palette)
    }
}
