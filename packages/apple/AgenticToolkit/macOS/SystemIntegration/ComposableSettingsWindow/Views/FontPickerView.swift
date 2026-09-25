import AppKit
import AgenticToolkitCore

extension ComposableSettings {

    /// A settings row binding a `FontViewModel` to a `FontChooserButton`: the
    /// chosen font, named and drawn in itself, opening the system font panel
    /// when clicked.
    ///
    /// The row is the binding and nothing else — the panel plumbing lives once,
    /// in the button, so a theme editor's font rows and this one cannot drift
    /// apart (`dry`).
    @MainActor
    public final class FontPickerView: NSView, SettingsViewProtocol {

        public let label: NSTextField
        public let button: FontChooserButton

        private let viewModel: FontViewModel

        /// The view model's ``AbstractViewModel/explanation``, which the
        /// ``GroupView`` this is placed in draws under the row.
        public var settingExplanation: String? { viewModel.explanation }

        public init(viewModel: FontViewModel) {
            self.viewModel = viewModel
            self.label = ComposableSettings.makeRowLabel(viewModel.title)
            self.button = FontChooserButton()

            super.init(frame: .zero)
            self.translatesAutoresizingMaskIntoConstraints = false

            self.button.accessibilityID("settings.font-picker.choose")
            self.button.onChange = { [weak self] font in
                guard let self else { return }
                self.viewModel.setFont(font)
                self.sync()
            }

            let row = Self.makeRow([self.label, self.button])
            self.addSubview(row)
            Self.pinToEdges(row, of: self)

            viewModel.onChange = { [weak self] _ in self?.sync() }
            self.sync()
        }

        public override init(frame frameRect: NSRect) {
            fatalError("init(frame frameRect: NSRect)")
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        /// Grays out the whole row. Used by panels where the font is only
        /// editable while some other switch is on.
        public var isEnabled: Bool = true {
            didSet {
                button.isEnabled = isEnabled
                label.alphaValue = isEnabled ? 1 : 0.4
            }
        }

        private func sync() {
            let font = viewModel.font
            label.stringValue = viewModel.title
            button.show(font, title: Self.describe(font, installed: viewModel.isInstalled))
        }

        private static func describe(_ font: NSFont, installed: Bool) -> String {
            let name = font.displayName ?? font.fontName
            let size = Int(font.pointSize.rounded())
            return installed ? "\(name) — \(size) pt" : "\(name) — \(size) pt (not installed)"
        }
    }
}

extension ComposableSettings.FontPickerView: ComposableSettings.ExplainedSettingsView {}
