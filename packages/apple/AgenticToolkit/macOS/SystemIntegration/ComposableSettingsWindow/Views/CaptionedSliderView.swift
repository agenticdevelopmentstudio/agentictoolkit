import AppKit
import AgenticToolkitCore

extension ComposableSettings {

    /// Slider with a live trailing caption derived from the current value via a
    /// caller-supplied formatter (e.g. `{ "\(Int($0 * 100))%" }` or
    /// `{ "\(Int($0))s" }`). Use when the slider's raw position isn't enough
    /// to identify the current value.
    @MainActor
    public class CaptionedSliderView: NSView, SettingsViewProtocol {
        public let label: NSTextField
        public let slider: NSSlider
        public let captionLabel: NSTextField

        private let viewModel: RangeViewModel<Double>

        /// The view model's ``AbstractViewModel/explanation``, which the
        /// ``GroupView`` this is placed in draws under the row.
        public var settingExplanation: String? { viewModel.explanation }

        private let formatter: @MainActor (Double) -> String

        public init(
            viewModel: RangeViewModel<Double>,
            formatter: @escaping @MainActor (Double) -> String
        ) {
            self.viewModel = viewModel
            self.formatter = formatter
            self.label = Self.createLabel(title: viewModel.title)
            self.slider = NSSlider()
            self.captionLabel = Self.createCaption()

            super.init(frame: .zero)
            self.translatesAutoresizingMaskIntoConstraints = false

            self.slider.maxValue = viewModel.maxValue
            self.slider.minValue = viewModel.minValue
            self.slider.doubleValue = viewModel.value
            self.slider.target = self
            self.slider.action = #selector(sliderChanged(_:))
            // Below the row spacer's `defaultLow` so the slider, not the gap,
            // takes the width left over after the label and caption.
            self.slider.setContentHuggingPriority(.init(1), for: .horizontal)

            let row = Self.makeRow([self.label, self.slider, self.captionLabel])
            self.addSubview(row)
            Self.pinToEdges(row, of: self)

            viewModel.onChange = { [weak self] _ in
                self?.sync()
            }

            self.sync()
        }

        private func sync() {
            self.label.stringValue = viewModel.title
            self.slider.doubleValue = viewModel.value
            self.captionLabel.stringValue = formatter(viewModel.value)
        }

        @objc private func sliderChanged(_ sender: NSSlider) {
            let newValue = sender.doubleValue
            self.captionLabel.stringValue = formatter(newValue)
            if viewModel.settingObserver.value != newValue {
                viewModel.settingObserver.value = newValue
            }
        }

        public override init(frame frameRect: NSRect) {
            fatalError("init(frame frameRect: NSRect")
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        static func createLabel(title: String) -> NSTextField {
            ComposableSettings.makeRowLabel(title)
        }

        static func createCaption() -> NSTextField {
            let label = ComposableSettings.makeValueLabel(monospacedDigits: true)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
            return label
        }
    }
}

extension ComposableSettings.CaptionedSliderView: ComposableSettings.ExplainedSettingsView {}
