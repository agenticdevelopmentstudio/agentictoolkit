import AppKit

extension ComposableSettings {

    @MainActor
    public class ButtonView: NSView, SettingsViewProtocol {
        public let button: NSButton

        private let viewModel: ButtonViewModel

        /// Where the button sits in the row it is given.
        public enum Placement: Sendable {
            /// Stretched across the whole card.
            case fill
            /// Sized to its own title, at the leading edge — which is what a
            /// button that performs one act, rather than choosing between two,
            /// looks like on this platform.
            case leading
            /// Sized to its own title, centred in the card. For an act the card
            /// offers as a whole rather than one belonging to the row above it:
            /// centring is what keeps it from reading as that row's control.
            case centered
        }

        /// - Parameter placement: where the button sits in its row. The default
        ///   is `.fill` because that is what every caller before this parameter
        ///   got, and a settings row that silently changed shape would be a
        ///   worse surprise than a verbose call site.
        public init(viewModel: ButtonViewModel, placement: Placement = .fill) {
            self.viewModel = viewModel
            self.button = NSButton(title: viewModel.title, target: nil, action: nil)

            super.init(frame: .zero)
            self.translatesAutoresizingMaskIntoConstraints = false

            self.button.translatesAutoresizingMaskIntoConstraints = false
            self.addSubview(self.button)
            if placement == .fill {
                Self.pinToEdges(self.button, of: self)
            } else {
                var constraints = [
                    self.button.topAnchor.constraint(equalTo: self.topAnchor),
                    self.button.bottomAnchor.constraint(equalTo: self.bottomAnchor),
                    // Less-than, not equal: the row is as wide as the card, and
                    // an equal trailing edge is the stretch `.fill` is for.
                    self.button.trailingAnchor.constraint(
                        lessThanOrEqualTo: self.trailingAnchor)
                ]
                if placement == .centered {
                    // Greater-than on the leading edge for the same reason as
                    // the trailing one; the centre anchor does the placing.
                    constraints.append(self.button.leadingAnchor.constraint(
                        greaterThanOrEqualTo: self.leadingAnchor))
                    constraints.append(
                        self.button.centerXAnchor.constraint(equalTo: self.centerXAnchor))
                } else {
                    constraints.append(
                        self.button.leadingAnchor.constraint(equalTo: self.leadingAnchor))
                }
                NSLayoutConstraint.activate(constraints)
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
