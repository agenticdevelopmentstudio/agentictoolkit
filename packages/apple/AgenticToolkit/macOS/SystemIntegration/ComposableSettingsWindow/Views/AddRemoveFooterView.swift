import AppKit

import AgenticToolkitCoreMacOS

extension ComposableSettings {

    /// The `+`/`−` bar that sits under a list: under a sidebar of records,
    /// under a table of repos. Two clicks, two closures, and a remove button
    /// that is only live when removing would mean something.
    ///
    /// It exists apart from its hosts because a generic view controller cannot
    /// be a button's target — `@objc` members are not allowed in a generic
    /// `NSObject` subclass — and because two hosts wanting the same bar is
    /// exactly the case for one view (`dry`).
    @MainActor
    public final class AddRemoveFooterView: NSView {

        public var onAdd: (() -> Void)?
        public var onRemove: (() -> Void)?

        public let addButton = NSButton(
            title: "", image: NSImage(systemSymbolName: "plus", accessibilityDescription: "Add")!,
            target: nil, action: nil)
        public let removeButton = NSButton(
            title: "", image: NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove")!,
            target: nil, action: nil)

        /// Anything the host wants beside the buttons — a count, an error, a
        /// hint. It sits to their right and takes the slack.
        public var trailingView: NSView? {
            didSet {
                oldValue.map { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
                trailingView.map { stack.addArrangedSubview($0) }
            }
        }

        public var isRemoveEnabled: Bool {
            get { removeButton.isEnabled }
            set { removeButton.isEnabled = newValue }
        }

        private let stack = NSStackView()

        /// - Parameter accessibilityPrefix: `"<prefix>.add"` and
        ///   `"<prefix>.remove"` become the buttons' identifiers, so a UI test
        ///   can name them.
        public init(accessibilityPrefix: String) {
            super.init(frame: .zero)
            translatesAutoresizingMaskIntoConstraints = false

            addButton.bezelStyle = .smallSquare
            addButton.target = self
            addButton.action = #selector(addPressed)
            addButton.accessibilityID("\(accessibilityPrefix).add")

            removeButton.bezelStyle = .smallSquare
            removeButton.target = self
            removeButton.action = #selector(removePressed)
            removeButton.isEnabled = false
            removeButton.accessibilityID("\(accessibilityPrefix).remove")

            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 4
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(addButton)
            stack.addArrangedSubview(removeButton)
            addSubview(stack)

            let inset = SettingsLayout.default[.rowSpacing]
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: topAnchor, constant: inset),
                stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -inset),
                stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset)
            ])
        }

        @available(*, unavailable)
        public required init?(coder: NSCoder) { nil }

        @objc private func addPressed() { onAdd?() }

        @objc private func removePressed() { onRemove?() }
    }
}
