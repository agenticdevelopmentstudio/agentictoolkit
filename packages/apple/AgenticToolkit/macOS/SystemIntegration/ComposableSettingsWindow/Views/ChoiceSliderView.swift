import AppKit
import AgenticToolkitCore

extension ComposableSettings {

    /// Discrete-tick slider bound to a `ChoiceViewModel`. Each tick position
    /// corresponds to one entry in `viewModel.choices`; the slider snaps to
    /// ticks only. The current choice's `label` is shown as a secondary
    /// caption to the right of the slider.
    @MainActor
    public class ChoiceSliderView<Value: Codable & Sendable & Equatable>: NSView, SettingsViewProtocol {
        public let label: NSTextField
        public let slider: NSSlider
        public let valueLabel: NSTextField

        private let viewModel: ChoiceViewModel<Value>

        /// The view model's ``AbstractViewModel/explanation``, which the
        /// ``GroupView`` this is placed in draws under the row.
        public var settingExplanation: String? { viewModel.explanation }

        public init(viewModel: ChoiceViewModel<Value>) {
            self.viewModel = viewModel
            self.label = Self.createLabel(title: viewModel.title)
            self.slider = NSSlider()
            self.valueLabel = Self.createValueLabel()

            super.init(frame: .zero)
            self.translatesAutoresizingMaskIntoConstraints = false

            let count = viewModel.choices.count
            self.slider.minValue = 0
            self.slider.maxValue = Double(max(count - 1, 0))
            self.slider.numberOfTickMarks = count
            self.slider.allowsTickMarkValuesOnly = true
            self.slider.target = self
            self.slider.action = #selector(sliderChanged(_:))

            // The slider is the only flexible element in the row — let it
            // absorb extra width so the right-hand caption pins to the panel
            // edge instead of leaving a gap. Below the row spacer's own
            // `defaultLow` (see `NSView.makeRowSpacer`), or the two tie and the
            // free width is split between them.
            self.label.setContentHuggingPriority(.required, for: .horizontal)
            self.valueLabel.setContentHuggingPriority(.required, for: .horizontal)
            self.slider.setContentHuggingPriority(.init(1), for: .horizontal)

            // Pin the value label to the width of the longest possible caption
            // so the slider's width doesn't oscillate as the user drags through
            // shorter/longer choice labels (e.g. "Small" → "Extra Small").
            let longestLabelWidth = Self.maxLabelWidth(
                for: viewModel.choices.map(\.label),
                font: self.valueLabel.font
            )
            self.valueLabel.widthAnchor.constraint(
                equalToConstant: ceil(longestLabelWidth)
            ).isActive = true

            let row = Self.makeRow(
                [self.label, self.slider, self.valueLabel]
            )
            self.addSubview(row)
            Self.pinToEdges(row, of: self)

            viewModel.onChange = { [weak self] _ in
                self?.syncSelection()
            }

            self.syncSelection()
        }

        private func syncSelection() {
            self.label.stringValue = viewModel.title
            let current = viewModel.value
            if let index = viewModel.choices.firstIndex(where: { $0.value == current }) {
                self.slider.doubleValue = Double(index)
                self.valueLabel.stringValue = viewModel.choices[index].label
            }
        }

        @objc private func sliderChanged(_ sender: NSSlider) {
            let index = Int(sender.doubleValue.rounded())
            guard viewModel.choices.indices.contains(index) else { return }
            let value = viewModel.choices[index].value
            if viewModel.settingObserver.value != value {
                viewModel.settingObserver.value = value
            }
        }

        public override init(frame frameRect: NSRect) {
            fatalError("init(frame frameRect: NSRect")
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // Span the full width so the slider can stretch and the trailing value
        // label pins to the right edge. One below required: a group's card
        // insets its rows with required constraints, and two required width
        // rules on one view is an unsatisfiable pair AppKit resolves by dropping
        // whichever it likes.
        public override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            guard let parent = self.superview else { return }
            let fullWidth = self.widthAnchor.constraint(equalTo: parent.widthAnchor)
            fullWidth.priority = .required - 1
            fullWidth.isActive = true
        }

        static func createLabel(title: String) -> NSTextField {
            ComposableSettings.makeRowLabel(title)
        }

        static func createValueLabel() -> NSTextField {
            let label = ComposableSettings.makeValueLabel()
            label.alignment = .left
            return label
        }

        private static func maxLabelWidth(for labels: [String], font: NSFont?) -> CGFloat {
            // The widest choice label decides the column width, so it has to be
            // measured in the font the label will actually draw in — the theme's
            // caption style, not a fixed 11pt system font.
            let font = font ?? ThemePaletteObserver.currentPalette.font(.caption)
            return labels
                .map { $0.renderedWidth(usingFont: font) }
                .max() ?? 0
        }
    }
}

extension ComposableSettings.ChoiceSliderView: ComposableSettings.ExplainedSettingsView {}
