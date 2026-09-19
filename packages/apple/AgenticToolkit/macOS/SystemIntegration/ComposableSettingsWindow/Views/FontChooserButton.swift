import AppKit
import AgenticToolkitCore

extension ComposableSettings {

    /// A button that names a font, drawn in that font, and opens the system
    /// font panel when it is clicked.
    ///
    /// The sample *is* the button: the thing you want to change is the thing
    /// you press (`principle-of-least-astonishment`). A text field holding a
    /// font name asks you to know how the name is spelled, and a popup of
    /// families cannot express the choice at all once Nerd Font patches are
    /// installed — a dozen faces share one family name — so this defers to the
    /// panel macOS already ships rather than growing a second font browser
    /// (`native-controls`).
    ///
    /// It stores nothing. The owner records the picked font wherever that font
    /// belongs and calls `show(_:title:)` back with what it actually recorded —
    /// so a size that was clamped, or an edit a locked theme refused outright,
    /// is what the button ends up drawing (`explicit-over-implicit`).
    @MainActor
    public final class FontChooserButton: NSButton, NSFontChanging {

        /// The sample is drawn at one readable size whatever size the font is
        /// set to. A 48 pt title role would otherwise tear apart the row it
        /// sits in, and every caller already shows the size as a number beside
        /// it.
        public static let sampleSize: CGFloat = 12

        /// Called with the font the user picked in the panel.
        public var onChange: ((NSFont) -> Void)?

        /// The font last handed to `show(_:title:)`, at its own size — which is
        /// not the size it is *drawn* at, so `font` cannot stand in for it.
        /// `nil` is "nothing chosen here".
        public private(set) var selectedFont: NSFont?

        /// - Parameter width: a fixed width, for a button that has to line up
        ///   with others in a grid column. Omitted, the button takes the width
        ///   its title wants and gives it up first when the row is squeezed,
        ///   which is what a settings row wants.
        public convenience init(width: CGFloat?) {
            self.init(frame: .zero)
            if let width {
                self.widthAnchor.constraint(equalToConstant: width).isActive = true
            }
        }

        /// The designated initialiser, and a working one rather than the
        /// `fatalError` these views usually carry: `FontChooserButton()` is a
        /// spelling Swift resolves to `NSObject.init()`, which AppKit funnels
        /// through `initWithFrame:` — so a trap here is a crash at a call site
        /// that looks like it is using the initialiser above.
        public override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            self.translatesAutoresizingMaskIntoConstraints = false
            self.bezelStyle = .rounded
            self.setButtonType(.momentaryPushIn)
            self.alignment = .left
            self.target = self
            self.action = #selector(openFontPanel(_:))
            (self.cell as? NSButtonCell)?.lineBreakMode = .byTruncatingTail
            self.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            self.setContentHuggingPriority(.defaultLow, for: .horizontal)
            self.show(nil, title: "System")
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        /// - Parameters:
        ///   - font: the face to draw the title in, and what the panel opens
        ///     on. `nil` draws the title in the system font.
        ///   - title: what the button reads. The caller owns the wording
        ///     because only it knows what the font means where it is stored —
        ///     "System" for a role that has no family of its own, "Menlo — 14 pt
        ///     (not installed)" for a face this machine does not have.
        public func show(_ font: NSFont?, title: String) {
            self.selectedFont = font
            self.font = font.map { NSFontManager.shared.convert($0, toSize: Self.sampleSize) }
                ?? .systemFont(ofSize: Self.sampleSize)
            self.title = title
        }

        // MARK: - The panel

        @objc private func openFontPanel(_ sender: Any?) {
            let manager = NSFontManager.shared
            manager.target = self
            manager.setSelectedFont(self.panelFont, isMultiple: false)
            manager.orderFrontFontPanel(self)
        }

        /// The panel opens on the real font at its real size — never the
        /// clamped sample size, which would quietly rewrite a 48 pt role to
        /// 12 pt the moment you opened the panel and picked a face.
        private var panelFont: NSFont {
            self.selectedFont ?? .systemFont(ofSize: NSFont.systemFontSize)
        }

        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // The font panel outlives the row that opened it, and
            // `NSFontManager` holds its target without owning it. Hand the
            // target back when the row goes away rather than leaving the panel
            // writing into freed memory.
            if self.window == nil, NSFontManager.shared.target === self {
                NSFontManager.shared.target = nil
            }
        }

        // MARK: - NSFontChanging

        public func changeFont(_ sender: NSFontManager?) {
            guard let sender else { return }
            self.onChange?(sender.convert(self.panelFont))
        }

        /// Only the parts of the panel that pick a font — the color and
        /// underline effects would write nothing anyone reads back.
        public func validModesForFontPanel(_ fontPanel: NSFontPanel) -> NSFontPanel.ModeMask {
            [.collection, .face, .size]
        }
    }
}
