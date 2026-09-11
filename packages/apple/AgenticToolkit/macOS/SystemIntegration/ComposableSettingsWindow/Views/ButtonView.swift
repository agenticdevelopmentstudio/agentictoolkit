import AppKit

extension ComposableSettings {

    @MainActor
    public class ButtonView: NSView, SettingsViewProtocol {
        public let button: NSButton

        private let viewModel: ButtonViewModel

        /// - Parameter fillsWidth: whether the button stretches across the
        ///   whole card. The default is `true` because that is what every
        ///   caller before this parameter got, and a settings row that
        ///   silently changed shape would be a worse surprise than a verbose
        ///   call site. Pass `false` for an ordinary push button, sized to its
        ///   own title and sitting at the leading edge — which is what a
        ///   button that performs one act, rather than choosing between two,
        ///   looks like on this platform.
        public init(viewModel: ButtonViewModel, fillsWidth: Bool = true) {
            self.viewModel = viewModel
            self.button = NSButton(title: viewModel.title, target: nil, action: nil)

            super.init(frame: .zero)
            self.translatesAutoresizingMaskIntoConstraints = false

            self.button.translatesAutoresizingMaskIntoConstraints = false
            self.addSubview(self.button)
            if fillsWidth {
                Self.pinToEdges(self.button, of: self)
            } else {
                NSLayoutConstraint.activate([
                    self.button.topAnchor.constraint(equalTo: self.topAnchor),
                    self.button.leadingAnchor.constraint(equalTo: self.leadingAnchor),
                    self.button.bottomAnchor.constraint(equalTo: self.bottomAnchor),
                    // Less-than, not equal: the row is as wide as the card, and
                    // an equal trailing edge is the stretch this parameter
                    // exists to avoid.
                    self.button.trailingAnchor.constraint(
                        lessThanOrEqualTo: self.trailingAnchor)
                ])
            }

            self.button.target = self
            self.button.action = #selector(buttonWasPressed(_:))
        }

        public override init(frame frameRect: NSRect) {
            fatalError("init(frame frameRect: NSRect")
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        @objc private func buttonWasPressed(_ sender: NSButton) {
            viewModel.wasPressedCallback?()
        }
    }
}
