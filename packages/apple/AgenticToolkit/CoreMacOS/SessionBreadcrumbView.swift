import AppKit
import AgenticToolkitCore
import AgenticDeveloperToolkitUI

/// The trail that says *which* conversation this is: `project » branch » name`,
/// each segment in the colour that says what kind of fact it is.
///
/// ```
/// stenographer » conversations » truncate long messages
/// ─────┬──────   ──────┬──────   ─────────┬───────────
///   the text      the accent        Claude's orange
/// ```
///
/// Two windows head their rows with it — the Sessions list and the
/// Conversations feed — and they are looking at the same sessions, so the two
/// have to agree down to the separator glyph: a reader who learns the trail in
/// one window reads it in the other without being told. That is why it is one
/// view here rather than a stack of labels built twice.
///
/// Every segment past the first is optional, and each separator belongs to the
/// segment after it, so a session with no branch or no name reads as a shorter
/// trail rather than as one with a dangling `»`.
public final class SessionBreadcrumbView: NSStackView, Themeable {

    /// The segments of one trail.
    ///
    /// ``context`` is where the conversation is happening, broadest first — a
    /// project, then a branch — and ``name`` is what the conversation is
    /// called. They are separated because they are coloured differently: the
    /// name is the only part a human chose.
    public struct Crumbs: Equatable, Sendable {
        public let context: [String]
        public let name: String

        /// Empty segments are dropped on the way in rather than rendered as
        /// gaps: a session outside a repo has no branch, and a live one often
        /// has no name yet — its title is written when it ends.
        public init(context: [String], name: String = "") {
            self.context = context.filter { !$0.isEmpty }
            self.name = name
        }

        public init(project: String, branch: String = "", name: String = "") {
            self.init(context: [project, branch], name: name)
        }

        /// Whether `other` can be written into a view already showing this —
        /// same number of segments, so every label it needs is already there.
        /// A rename is new text; a branch that appeared is a new label.
        public func hasSameShape(as other: Crumbs) -> Bool {
            context.count == other.context.count && name.isEmpty == other.name.isEmpty
        }

        /// The whole trail as one string, for a tooltip or a screen reader.
        public var line: String {
            (context + (name.isEmpty ? [] : [name])).joined(separator: " \(separator) ")
        }
    }

    /// Claude's brand orange, which marks the Claude session's own name.
    public static let nameColor = NSColor(srgbRed: 222 / 255, green: 115 / 255, blue: 86 / 255, alpha: 1)

    /// What goes between two segments.
    ///
    /// Nonisolated because ``Crumbs`` is not: the trail is a value a caller
    /// builds wherever it happens to be, and joining it into one line is the
    /// one thing it does without a view.
    public nonisolated static let separator = "»"

    /// The trail on show. Assigning writes the new text into the labels that
    /// are already there, and rebuilds them only when the *shape* changed —
    /// which is what keeps a branch checkout or a rename from flickering.
    public var crumbs: Crumbs {
        didSet {
            guard oldValue != crumbs else { return }
            if oldValue.hasSameShape(as: crumbs) {
                write(crumbs)
            } else {
                build(crumbs)
            }
            applyTheme(palette ?? ThemePaletteObserver.currentPalette)
        }
    }

    /// The type size the trail is set at — ``TextRole/body`` in a list of
    /// sessions, ``TextRole/caption`` over a chat bubble, where it is a caption
    /// on the message rather than the row's subject.
    public var textRole: TextRole = .body {
        didSet { applyTheme(palette ?? ThemePaletteObserver.currentPalette) }
    }

    /// The context segments, broadest first.
    public private(set) var contextLabels: [NSTextField] = []

    /// The session's own name, when it has one.
    public private(set) var nameLabel: NSTextField?

    /// The `»` glyphs, one before each segment after the first.
    private var separatorLabels: [NSTextField] = []

    /// The palette last applied, so a rebuild can repaint itself without
    /// waiting for the host's next theme pass.
    private var palette: SemanticPalette?

    /// Every segment, in reading order — what a caller measures or asserts on.
    public var segmentLabels: [NSTextField] {
        contextLabels + (nameLabel.map { [$0] } ?? [])
    }

    public init(crumbs: Crumbs = .init(context: []), textRole: TextRole = .body) {
        self.crumbs = crumbs
        self.textRole = textRole
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        orientation = .horizontal
        alignment = .centerY
        spacing = 6
        build(crumbs)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    /// The narrowest this trail can be drawn whole. Measured from the labels'
    /// own text widths rather than from `fittingSize`, because the labels
    /// deliberately abstain from the fitting width (see ``segmentPriority``) and
    /// a fitting size would squeeze them to nothing.
    public var minimumWidth: CGFloat {
        let segments = arrangedSubviews.reduce(CGFloat(0)) { total, view in
            total + ceil(max(view.intrinsicContentSize.width, view.fittingSize.width))
        }
        return segments + spacing * CGFloat(max(arrangedSubviews.count - 1, 0))
    }

    public func applyTheme(_ palette: SemanticPalette) {
        self.palette = palette
        // One size for the whole trail; the segments are told apart by colour.
        let font = palette.font(textRole)
        for (index, label) in contextLabels.enumerated() {
            label.font = font
            // The first segment is the subject — the project — and reads as
            // ordinary text; everything narrowing it is the theme's highlight.
            label.textColor = index == 0 ? palette.primaryTextColor : palette.accentColor
        }
        nameLabel?.font = font
        nameLabel?.textColor = Self.nameColor
        for label in separatorLabels {
            label.font = font
            label.textColor = palette.tertiaryTextColor
        }
    }

    // MARK: - Build

    private func write(_ crumbs: Crumbs) {
        for (label, text) in zip(contextLabels, crumbs.context) { label.stringValue = text }
        nameLabel?.stringValue = crumbs.name
    }

    private func build(_ crumbs: Crumbs) {
        for view in arrangedSubviews { view.removeFromSuperview() }
        contextLabels = []
        separatorLabels = []
        nameLabel = nil

        let segments = crumbs.context + (crumbs.name.isEmpty ? [] : [crumbs.name])
        for (index, text) in segments.enumerated() {
            if index > 0 {
                let separator = NSTextField(labelWithString: Self.separator)
                separator.setContentCompressionResistancePriority(.required, for: .horizontal)
                addArrangedSubview(separator)
                separatorLabels.append(separator)
            }
            let label = NSTextField(labelWithString: text)
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.setContentCompressionResistancePriority(
                Self.segmentPriority(at: index), for: .horizontal
            )
            addArrangedSubview(label)
            if index < crumbs.context.count {
                contextLabels.append(label)
            } else {
                nameLabel = label
            }
        }
    }

    /// The order the segments give way in while the trail is too wide for its
    /// row: the narrowest fact first, the project last — it is what identifies
    /// the row, so it survives longest.
    ///
    /// Every one of them sits **below** `.fittingSizeCompression` (50), and that
    /// is the whole point. A label's compression resistance is not only about
    /// what gives way inside a fixed width; it is also a vote in `fittingSize`,
    /// which is what AppKit uses to derive a window's minimum content width.
    /// `lineBreakMode = .byTruncatingTail` says *how* to draw a squeezed label,
    /// never that it is willing to be squeezed — so a label at any priority
    /// above 50 demands its full intrinsic width there, and one long session
    /// name dragged the Sessions window out to forty thousand points wide.
    /// Below 50 these labels abstain from the fitting width, the window's
    /// minimum comes from ``minimumWidth``, and the order still holds at every
    /// real width.
    private static func segmentPriority(at index: Int) -> NSLayoutConstraint.Priority {
        NSLayoutConstraint.Priority(rawValue: Float(max(49 - index, 1)))
    }
}
