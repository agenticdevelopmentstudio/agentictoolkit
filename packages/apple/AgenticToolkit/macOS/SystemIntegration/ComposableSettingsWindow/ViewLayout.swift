import AppKit
import Combine

extension ComposableSettings {

    public enum LayoutKey: String, Sendable, Codable, Equatable {
        case panelInset
        case groupSpacing
        case rowSpacing
        case dividerThickness
        /// Corner radius of a group's card.
        case cardCornerRadius
        /// Horizontal inset from a card's edge to its rows' content.
        case cardHorizontalInset
        /// Vertical inset above and below a row's content inside a card.
        case cardVerticalInset
        /// Gap between a group's caption and the card beneath it.
        case captionSpacing
    }

    @MainActor
    public final class SettingsLayout: Observable {

        /// System Settings' metrics: a roomy outer margin, generously spaced
        /// group cards, and rows padded enough that a switch or popup has air
        /// around it. The card values are what make a group read as one grouped
        /// box rather than a run of loose controls.
        public static let `default` = SettingsLayout([
            .panelInset: 20.0,
            .groupSpacing: 20.0,
            .rowSpacing: 8.0,
            .dividerThickness: 1.0,
            .cardCornerRadius: 10.0,
            .cardHorizontalInset: 14.0,
            .cardVerticalInset: 9.0,
            .captionSpacing: 6.0
        ])

        @Published public private(set) var values: [LayoutKey: CGFloat]

        public init(_ values: [LayoutKey: CGFloat]) {
            self.values = values
        }

        public subscript(_ index: LayoutKey) -> Double {
            guard let value = values[index] else {
                return 0.0
            }

            return value
        }
    }
}

extension NSView {

    /// A settings row: the naming label leads, every control trails.
    ///
    /// The spacer is what produces the System Settings layout — label pinned
    /// left, switch/popup/stepper pinned right — out of the `[label, control…]`
    /// order every row view already passes. A control that should *fill* the gap
    /// rather than hug the right edge (a slider) says so by taking a horizontal
    /// hugging priority below `rowSpacerHugging`.
    @MainActor
    static func makeRow(
        _ views: [NSView]
    ) -> NSStackView {
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        var arranged = views
        var spacer: NSView?
        if views.count > 1 {
            let gap = makeRowSpacer()
            spacer = gap
            arranged.insert(gap, at: 1)
        }
        let row = NSStackView(views: arranged)
        row.orientation = .horizontal
        row.spacing = ComposableSettings.SettingsLayout.default[.rowSpacing]
        if let spacer {
            // The spacer is a gap, not a control, so it must not also contribute
            // a gap of its own: without this a collapsed spacer would still put
            // two `rowSpacing`s between the label and the control beside it.
            row.setCustomSpacing(0, after: spacer)
        }
        // Center, not first-baseline: a row now pairs text with a switch or a
        // popup whose bezel is taller than the label, and baselines line those
        // up by their glyphs, leaving the control sitting low in the row.
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    /// The priority at which the row spacer wants to stay closed: one step below
    /// the `defaultLow` an untouched AppKit control hugs at, so the *spacer*
    /// opens up and the controls keep their natural size. A control that should
    /// fill the row instead says so by hugging below this — `.init(1)`, as the
    /// sliders and `TextEditView` do.
    static let rowSpacerHugging = NSLayoutConstraint.Priority(
        NSLayoutConstraint.Priority.defaultLow.rawValue - 1)

    /// The flexible gap between a row's label and its controls.
    ///
    /// The zero-width constraint is not a formality: content hugging is
    /// expressed *against* an intrinsic size, and a bare `NSView` has none
    /// horizontally (`noIntrinsicMetric`), which makes a hugging priority on it
    /// inert. A spacer set up that way is infinitely willing to grow, so it
    /// absorbs every point of slack in the row and collapses the slider or text
    /// field beside it to zero width. The constraint is the intrinsic width the
    /// spacer would otherwise lack, at the priority it should defend it with.
    @MainActor
    static func makeRowSpacer() -> NSView {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        let closed = spacer.widthAnchor.constraint(equalToConstant: 0)
        closed.priority = rowSpacerHugging
        closed.isActive = true
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return spacer
    }

    @MainActor
    static func pinToEdges(_ view: NSView, of container: NSView) {
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }
}
