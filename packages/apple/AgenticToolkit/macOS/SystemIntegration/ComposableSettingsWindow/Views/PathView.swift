import AppKit
import AgenticToolkitCore

extension ComposableSettings {

    /// One filesystem path in a settings card, shown as a path rather than as prose.
    ///
    /// `ExplanationView` word-wraps, which is right for a sentence and wrong for
    /// a path. A settings panel's detail column is 200pt at the window's minimum
    /// width, of which the card's content is about 134pt, and a real path wrapped
    /// into that broke across nine hyphenated lines — long enough to push the
    /// group heading below it off the bottom of the pane, and unreadable as a
    /// single value even when it fits.
    ///
    /// So a path gets one line and truncates in the middle: the head says where
    /// it lives, the tail says which one it is, and what is dropped is the middle
    /// every sibling path shares anyway. The whole thing stays reachable — it is
    /// the view's tooltip and its accessibility value, and the field is
    /// selectable, which copies the string rather than what is drawn.
    @MainActor
    public final class PathView: NSView, SettingsViewProtocol {

        /// The path this row shows, whole and untruncated, whatever the width.
        public let path: String

        public let label: NSTextField

        /// - Parameters:
        ///   - path: the path itself, kept whole for the tooltip and VoiceOver.
        ///   - caption: an optional name for what the path *is* ("Folder"),
        ///     drawn ahead of it. It sits at the head, which middle truncation
        ///     never eats, so the row still says what it is at any width.
        public init(withPath path: String, caption: String? = nil) {
            self.path = path
            let shown = caption.map { "\($0): \(path)" } ?? path
            self.label = ComposableSettings.makeValueLabel(shown)
            super.init(frame: .zero)
            translatesAutoresizingMaskIntoConstraints = false

            label.translatesAutoresizingMaskIntoConstraints = false
            // `wraps = false` rather than `usesSingleLineMode = true`: single-line
            // mode is what makes the cell ignore `lineBreakMode`, and the line
            // break is the whole point here.
            label.cell?.wraps = false
            label.cell?.usesSingleLineMode = false
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byTruncatingMiddle
            // A path yields its width to the panel instead of widening the window
            // to stay whole — the same bargain every truncating label here makes.
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
            // The drawn text is lossy by design, so the three ways of asking for
            // it all answer with the path itself.
            label.isSelectable = true
            label.toolTip = path
            label.setAccessibilityValue(path)
            addSubview(label)

            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: topAnchor),
                label.leadingAnchor.constraint(equalTo: leadingAnchor),
                label.trailingAnchor.constraint(equalTo: trailingAnchor),
                label.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        public override init(frame frameRect: NSRect) {
            fatalError("init(frame:) has not been implemented")
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}
