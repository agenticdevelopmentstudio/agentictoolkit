import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS

extension ComposableSettings {

    /// A heading over a *run* of groups, one level above a group's own caption.
    ///
    /// A panel whose groups all belong to one list needs nothing above them —
    /// which is why this is not what `GroupView`'s header is. It exists for the
    /// panel whose cards divide into two kinds, where the kind is the first
    /// thing a reader has to know: the Key Commands panel lists a card per
    /// window, and whether a window's commands fire only in this app or
    /// everywhere is what separates them.
    @MainActor
    public final class PanelHeadingView: NSView, SettingsViewProtocol {

        public let titleLabel: ThemedLabel

        /// `nil` when the heading was given no caption.
        public let captionLabel: NSTextField?

        public init(title: String, caption: String? = nil) {
            self.titleLabel = ThemedLabel(string: title, role: .primaryText, textRole: .heading)
            self.captionLabel = caption.map { ComposableSettings.makeValueLabel($0) }

            super.init(frame: .zero)
            self.translatesAutoresizingMaskIntoConstraints = false

            let stack = NSStackView()
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = SettingsLayout.default[.captionSpacing]
            stack.translatesAutoresizingMaskIntoConstraints = false
            self.addSubview(stack)

            self.titleLabel.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(self.titleLabel)

            if let captionLabel {
                // The same wrap policy `ExplanationView` needs, and for the same
                // reason: a `ThemedLabel` is single-line until the cell is told
                // otherwise, so a caption left at its defaults runs off the
                // panel's right edge rather than wrapping inside it.
                captionLabel.translatesAutoresizingMaskIntoConstraints = false
                captionLabel.cell?.wraps = true
                captionLabel.cell?.usesSingleLineMode = false
                captionLabel.lineBreakMode = .byWordWrapping
                captionLabel.maximumNumberOfLines = 0
                captionLabel.setContentCompressionResistancePriority(.required, for: .vertical)
                captionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                captionLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
                stack.addArrangedSubview(captionLabel)
                captionLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }

            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: self.topAnchor),
                stack.leadingAnchor.constraint(equalTo: self.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: self.trailingAnchor),
                stack.bottomAnchor.constraint(equalTo: self.bottomAnchor)
            ])
        }

        public override init(frame frameRect: NSRect) {
            fatalError("init(frame frameRect: NSRect)")
        }

        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}
