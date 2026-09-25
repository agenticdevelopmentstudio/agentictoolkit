import AppKit
import AgenticToolkitCore

extension ComposableSettings {

    /// Small descriptive blurb rendered beneath a setting.
    ///
    /// Also a status line whose text changes and which may be hidden: set
    /// ``text`` and `isHidden` after it is placed. It is a
    /// ``SelfHidingSettingsView``, so a card's row closes up and reopens with
    /// it — a plain label hidden before it was added would take its row down
    /// with it for good.
    @MainActor
    public class ExplanationView: NSView, SettingsViewProtocol, SelfHidingSettingsView {
        public let label: NSTextField

        /// Told to whoever placed this view when `isHidden` changes.
        public var onVisibilityChange: (() -> Void)?

        /// The blurb. Setting it re-wraps the label to the new text.
        public var text: String {
            get { label.stringValue }
            set { label.stringValue = newValue }
        }

        public override var isHidden: Bool {
            didSet {
                if isHidden != oldValue { onVisibilityChange?() }
            }
        }

        public init(withText text: String) {
            self.label = Self.createLabel(title: text)
            super.init(frame: .zero)
            self.translatesAutoresizingMaskIntoConstraints = false

            self.label.translatesAutoresizingMaskIntoConstraints = false
            // `ThemedLabel` is single-line by default — deliberately, so a
            // caption in a toolbar doesn't ask for two lines' height. A blurb is
            // the other case, and has to say so: `lineBreakMode` and
            // `maximumNumberOfLines` are both ignored while the cell is in
            // single-line mode, so without these two the text below set its wrap
            // policy and then ran off the right edge anyway.
            self.label.cell?.wraps = true
            self.label.cell?.usesSingleLineMode = false
            self.label.lineBreakMode = .byWordWrapping
            self.label.maximumNumberOfLines = 0
            self.label.setContentCompressionResistancePriority(.required, for: .vertical)
            // A wrapping label still reports its one-line intrinsic width unless it
            // is allowed to yield horizontally — otherwise a long blurb forces the
            // whole panel (and the settings window) as wide as the text. Let it be
            // compressed so it wraps to the available width instead.
            self.label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            self.label.setContentHuggingPriority(.defaultLow, for: .horizontal)
            self.addSubview(self.label)

            NSLayoutConstraint.activate([
                self.label.topAnchor.constraint(equalTo: self.topAnchor),
                self.label.leadingAnchor.constraint(equalTo: self.leadingAnchor),
                self.label.trailingAnchor.constraint(equalTo: self.trailingAnchor),
                self.label.bottomAnchor.constraint(equalTo: self.bottomAnchor)
            ])
        }

        public override init(frame frameRect: NSRect) {
            fatalError("init(frame frameRect: NSRect")
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        static func createLabel(title: String) -> NSTextField {
            let label = ComposableSettings.makeValueLabel(title)
            return label
        }
    }
}
