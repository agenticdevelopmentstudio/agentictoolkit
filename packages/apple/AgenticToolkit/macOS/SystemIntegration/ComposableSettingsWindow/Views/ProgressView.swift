import AppKit
import Combine

extension ComposableSettings {

    @MainActor
    public class ProgressView: NSView, SettingsViewProtocol {
        public let progressIndicator: NSProgressIndicator

        private let viewModel: ProgressViewModel

        /// The view model's ``AbstractViewModel/explanation``, which the
        /// ``GroupView`` this is placed in draws under the row.
        public var settingExplanation: String? { viewModel.explanation }

        private var cancellable: AnyCancellable?

        public init(viewModel: ProgressViewModel) {
            self.viewModel = viewModel
            self.progressIndicator = NSProgressIndicator()
            self.progressIndicator.controlSize = .regular

            super.init(frame: .zero)
            self.translatesAutoresizingMaskIntoConstraints = false

            self.progressIndicator.translatesAutoresizingMaskIntoConstraints = false
            self.addSubview(self.progressIndicator)
            Self.pinToEdges(self.progressIndicator, of: self)

            self.cancellable = viewModel.$progress.sink { [weak self] newValue in
                self?.apply(progress: newValue)
            }
            self.apply(progress: viewModel.progress)
        }

        private func apply(progress: Double?) {
            if let value = progress {
                self.progressIndicator.isIndeterminate = false
                self.progressIndicator.doubleValue = value
                self.progressIndicator.stopAnimation(nil)
            } else {
                self.progressIndicator.isIndeterminate = true
                self.progressIndicator.startAnimation(nil)
            }
        }

        public override init(frame frameRect: NSRect) {
            fatalError("init(frame frameRect: NSRect")
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}

extension ComposableSettings.ProgressView: ComposableSettings.ExplainedSettingsView {}
