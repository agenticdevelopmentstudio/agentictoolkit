import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS

extension ComposableSettings {

    /// How a view sits in a group's card.
    public enum CardRowStyle: Sendable {
        /// A setting of its own: padded above and below, and divided from the
        /// row above it by a hairline.
        case row
        /// Prose or a value that belongs to the row above — tucked up against
        /// it, with no divider between them. A run of these reads as one block.
        /// As the *first* thing in a card it becomes a `row`: there is nothing
        /// above it to continue.
        case continuation
    }

    /// A row that decides for itself whether it belongs on screen.
    ///
    /// `GroupView` listens so the card can close up around a row that has
    /// hidden itself — its padding and the hairline above it go with it. An
    /// `NSStackView` collapses a hidden arranged subview, but the row's padding
    /// cell is not hidden just because its content is, so without this a
    /// dismissed hint leaves an empty band and a stray divider behind.
    @MainActor
    public protocol SelfHidingSettingsView: NSView {
        /// Called after the view has changed its own `isHidden`.
        var onVisibilityChange: (() -> Void)? { get set }
    }

    /// A setting row built from a view model, carrying that model's
    /// ``AbstractViewModel/explanation``.
    ///
    /// `GroupView` draws the explanation as a secondary-label line tucked under
    /// the row — the same ``ExplanationView`` a caller would add by hand, as a
    /// `.continuation`. Before this, every view model took an `explanation:`
    /// and no view drew it, so a panel's prose was silently thrown away.
    @MainActor
    public protocol ExplainedSettingsView: NSView {
        /// The sentence to show under the row; nil or empty shows nothing.
        var settingExplanation: String? { get }
    }

    /// A group of settings, drawn the way System Settings draws one: a caption
    /// *outside* and above a rounded card, and inside the card one padded row
    /// per setting with a hairline between them.
    ///
    /// The caption sits outside the card because that is what separates a
    /// group's name from its contents at a glance — a title as the card's first
    /// row reads as just another setting.
    @MainActor
    public class GroupView: NSView, SettingsViewProtocol {

        /// The card holding the rows. Exposed so a panel can address the box
        /// itself (measuring it, insetting something over it) without reaching
        /// through `subviews`.
        public let cardView: NSView

        private let outerStack = NSStackView()
        private let rowStack = NSStackView()
        private var rows: [CardRow] = []

        public convenience init(withTitle title: String) {
            self.init(withHeaderView: HeaderView(title: title))
        }

        /// A group headed by an arbitrary view instead of the standard caption
        /// header — e.g. a picker's detail pane leading with a heading-role label.
        public init(withHeaderView header: NSView) {
            self.cardView = ThemedBox(
                fill: .elevatedSurface,
                stroke: nil,
                cornerRadius: SettingsLayout.default[.cardCornerRadius])

            super.init(frame: .zero)
            self.translatesAutoresizingMaskIntoConstraints = false

            self.outerStack.orientation = .vertical
            self.outerStack.alignment = .leading
            self.outerStack.spacing = SettingsLayout.default[.captionSpacing]
            self.outerStack.translatesAutoresizingMaskIntoConstraints = false
            self.addSubview(self.outerStack)
            Self.pinToEdges(self.outerStack, of: self)

            self.rowStack.orientation = .vertical
            self.rowStack.alignment = .leading
            self.rowStack.spacing = 0
            self.rowStack.translatesAutoresizingMaskIntoConstraints = false

            header.translatesAutoresizingMaskIntoConstraints = false
            self.outerStack.addArrangedSubview(header)
            self.cardView.translatesAutoresizingMaskIntoConstraints = false
            self.outerStack.addArrangedSubview(self.cardView)
            self.cardView.addSubview(self.rowStack)
            Self.pinToEdges(self.rowStack, of: self.cardView)

            // Both bands span the group, so a caption never widens the card and a
            // full-width row (a slider, a grid) actually gets the whole card.
            NSLayoutConstraint.activate([
                header.widthAnchor.constraint(equalTo: self.outerStack.widthAnchor),
                self.cardView.widthAnchor.constraint(equalTo: self.outerStack.widthAnchor)
            ])
        }

        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // Each group fills its parent stack's width so that any child that
        // wants to span the full panel (sliders with trailing captions, dividers,
        // etc.) actually can. Items inside the group still control their own
        // horizontal layout via content-hugging priorities.
        public override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            guard let parent = self.superview else { return }
            self.widthAnchor.constraint(equalTo: parent.widthAnchor).isActive = true
        }

        /// Adds `view` as the card's next row.
        ///
        /// The style is the caller's to state rather than the card's to guess.
        /// It was inferred from the view's *type* once — prose was assumed to
        /// annotate the row above it — which turned a list of plugin load
        /// failures into an unseparated run of jammed-together lines, and sliced
        /// one model description into six divided rows. What a view means in a
        /// card is not knowable from what class it is.
        ///
        /// A view built from a view model with an `explanation`
        /// (``ExplainedSettingsView``) brings it along: the explanation is added
        /// as a `.continuation` right under it, and comes and goes with it.
        public func addSettingSubview(_ view: NSView, style: CardRowStyle = .row) {
            let explanation = Self.explanationView(for: view)
            let row = CardRow(content: view, style: style)
            if let selfHiding = view as? any SelfHidingSettingsView {
                selfHiding.onVisibilityChange = { [weak self, weak row, weak view, weak explanation] in
                    row?.syncVisibility()
                    // Its own `onVisibilityChange` closes its row up with it.
                    if let view { explanation?.isHidden = view.isHidden }
                    self?.updateSeparators()
                }
            }
            append(row)
            if let explanation {
                explanation.isHidden = view.isHidden
                addSettingSubview(explanation, style: .continuation)
            }
        }

        private func append(_ row: CardRow) {
            rows.append(row)
            rowStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rowStack.widthAnchor).isActive = true
            updateSeparators()
        }

        /// The line drawn under `view` for its view model's explanation, or nil
        /// when it has none.
        private static func explanationView(for view: NSView) -> ExplanationView? {
            guard let text = (view as? any ExplainedSettingsView)?.settingExplanation,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return ExplanationView(withText: text)
        }

        /// A divider belongs above a row only when there is a visible row for it
        /// to divide this one from — so a hidden first row never leaves a
        /// hairline stranded at the top of the card.
        private func updateSeparators() {
            var hasVisiblePredecessor = false
            for row in rows {
                row.showsSeparator = hasVisiblePredecessor && row.style == .row
                if !row.isHidden { hasVisiblePredecessor = true }
            }
        }
    }

    /// One row of a group's card: the hairline that divides it from the row
    /// above, the card's padding, and the setting itself.
    ///
    /// The row *is* its content's visibility — hiding the content hides the row,
    /// so the card closes up rather than keeping a padded blank band where a
    /// `ConditionalView` used to be.
    @MainActor
    private final class CardRow: NSView {

        let content: NSView
        let style: ComposableSettings.CardRowStyle

        private let line = ThemedSeparatorView(role: .divider)
        /// The band the hairline occupies. `ThemedSeparatorView` pins its own
        /// height to one point, so the space it takes is this container's to
        /// state — which is also how the divider can be closed to nothing on a
        /// row that has no predecessor to be divided from.
        private let separatorBand = NSView()
        private let separatorHeight: NSLayoutConstraint

        var showsSeparator: Bool = false {
            didSet {
                guard showsSeparator != oldValue else { return }
                line.isHidden = !showsSeparator
                separatorHeight.constant = showsSeparator
                    ? ComposableSettings.SettingsLayout.default[.dividerThickness]
                    : 0
            }
        }

        init(content: NSView, style: ComposableSettings.CardRowStyle) {
            self.content = content
            self.style = style
            self.separatorHeight = separatorBand.heightAnchor.constraint(equalToConstant: 0)

            super.init(frame: .zero)
            self.translatesAutoresizingMaskIntoConstraints = false
            content.translatesAutoresizingMaskIntoConstraints = false
            separatorBand.translatesAutoresizingMaskIntoConstraints = false
            line.isHidden = true
            separatorBand.addSubview(line)
            addSubview(separatorBand)
            addSubview(content)

            let horizontal = ComposableSettings.SettingsLayout.default[.cardHorizontalInset]
            let vertical = ComposableSettings.SettingsLayout.default[.cardVerticalInset]
            // A continuation is tucked against what it continues, so it takes no
            // top padding of its own; a row is padded on both sides.
            let topInset = style == .row ? vertical : 0

            NSLayoutConstraint.activate([
                // Inset from the leading edge so the hairline starts under the
                // labels — System Settings' own separator inset.
                line.leadingAnchor.constraint(
                    equalTo: separatorBand.leadingAnchor, constant: horizontal),
                line.trailingAnchor.constraint(equalTo: separatorBand.trailingAnchor),
                line.topAnchor.constraint(equalTo: separatorBand.topAnchor),

                separatorBand.leadingAnchor.constraint(equalTo: leadingAnchor),
                separatorBand.trailingAnchor.constraint(equalTo: trailingAnchor),
                separatorBand.topAnchor.constraint(equalTo: topAnchor),
                separatorHeight,

                content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontal),
                content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontal),
                content.topAnchor.constraint(equalTo: separatorBand.bottomAnchor, constant: topInset),
                content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -vertical)
            ])

            syncVisibility()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        /// Takes the row's visibility from its content's, so a stack that
        /// collapses hidden arranged subviews collapses this one too.
        func syncVisibility() {
            isHidden = content.isHidden
        }
    }
}
