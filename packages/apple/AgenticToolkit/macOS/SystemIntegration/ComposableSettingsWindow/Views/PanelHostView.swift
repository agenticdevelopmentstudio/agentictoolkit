import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS

extension ComposableSettings {

    /// The detail pane's chrome: the selected panel, plus a help button pinned to
    /// its top-right corner that opens the window's help drawer.
    ///
    /// One instance lives for the whole life of the split and only its *content*
    /// is swapped, because help is disclosed on the window — the drawer belongs
    /// to `HelpDrawerController` and slides out beside it — rather than on
    /// whichever panel happens to be showing.
    @MainActor
    public final class PanelHostView: NSView {

        /// Inset of the help button from the panel's top-right corner. Sits inside
        /// the panel's own content inset, so it lands in the empty gutter beside a
        /// group's leading-aligned header rather than on top of any control.
        private static let buttonInset: CGFloat = 12

        private let contentContainer = NSView()
        private let helpButton = NSButton()

        private var themeObserver: ThemePaletteObserver?
        private var help: PanelHelp?

        /// Where help is shown. Weak because the window owns the presenter — and
        /// `nil` for a nested split, which is what retires its button: help opens
        /// once, at the window's edge, not once per level of nesting.
        public weak var helpPresenter: (any SettingsHelpPresenting)? {
            didSet {
                self.helpPresenter?.onVisibilityChange = { [weak self] in
                    self?.helpVisibilityDidChange()
                }
                self.claimHelpAnchorIfShown()
                self.helpPresenter?.setHelp(self.help)
                self.updateHelpButton()
            }
        }

        /// Whether this view supplies the `?` itself.
        ///
        /// A window whose toolbar carries a help button of its own sets this
        /// `false`: help is a property of the window, so its control belongs in
        /// the titlebar with the window's other controls, and two buttons
        /// reporting one drawer is one too many. A settings split shown in a
        /// *sheet* has no toolbar to put it in and leaves this `true` — which
        /// is also what keeps `HelpPopoverController` an anchor to hang off.
        public var showsHelpButton: Bool = true {
            didSet {
                self.claimHelpAnchorIfShown()
                self.updateHelpButton()
            }
        }

        /// Points the presenter's anchor at this view's `?`, but only while this
        /// view is the one showing it.
        ///
        /// A window that carries help in its toolbar sets `showsHelpButton`
        /// false and anchors on the toolbar button instead. Claiming the anchor
        /// unconditionally meant any later reassignment of `helpPresenter`
        /// silently took it back — and handed a popover presenter a hidden,
        /// zero-size view to hang off.
        private func claimHelpAnchorIfShown() {
            guard self.showsHelpButton else { return }
            self.helpPresenter?.helpAnchorView = self.helpButton
        }

        /// Fired after help is disclosed or dismissed, so chrome outside this
        /// view — a toolbar button — can report the same state the inline
        /// button does.
        ///
        /// It exists because `onVisibilityChange` has exactly one slot and this
        /// view claims it above. Anything else that needs the news has to be
        /// told by whoever took the slot, rather than quietly overwriting it.
        public var onHelpVisibilityChange: (() -> Void)?

        /// Shows or hides help. The action of this view's own button, and the
        /// way chrome outside it — a toolbar `?` — asks for the same thing:
        /// routed through here rather than reaching `helpPresenter` directly,
        /// so there stays one owner of the presenter.
        @objc public func toggleHelp() {
            self.helpPresenter?.toggleHelp()
        }

        public var isHelpVisible: Bool { self.helpPresenter?.isHelpVisible ?? false }

        private func helpVisibilityDidChange() {
            self.updateHelpButton()
            self.onHelpVisibilityChange?()
        }

        public init() {
            super.init(frame: .zero)
            self.translatesAutoresizingMaskIntoConstraints = false

            self.contentContainer.translatesAutoresizingMaskIntoConstraints = false
            self.addSubview(self.contentContainer)
            // Added last so it floats above the panel's own content; it is a child
            // of `self`, not of the content, so swapping panels never disturbs it.
            self.configureHelpButton()
            self.addSubview(self.helpButton)

            NSLayoutConstraint.activate([
                self.contentContainer.topAnchor.constraint(equalTo: self.topAnchor),
                self.contentContainer.leadingAnchor.constraint(equalTo: self.leadingAnchor),
                self.contentContainer.bottomAnchor.constraint(equalTo: self.bottomAnchor),
                self.contentContainer.trailingAnchor.constraint(equalTo: self.trailingAnchor),

                self.helpButton.topAnchor.constraint(
                    equalTo: self.contentContainer.topAnchor, constant: Self.buttonInset),
                self.helpButton.trailingAnchor.constraint(
                    equalTo: self.contentContainer.trailingAnchor, constant: -Self.buttonInset)
            ])

            self.themeObserver = ThemePaletteObserver(host: self) { [weak self] _ in
                self?.updateHelpButton()
            }

            self.updateHelpButton()
        }

        @available(*, unavailable)
        public required init?(coder: NSCoder) { fatalError() }

        // MARK: - Content

        /// Installs the selected panel's view (or the scroll view wrapping it),
        /// replacing whatever was there. `nil` empties the pane.
        public func setContent(_ view: NSView?) {
            self.contentContainer.subviews.forEach { $0.removeFromSuperview() }
            guard let view else { return }
            view.translatesAutoresizingMaskIntoConstraints = false
            self.contentContainer.addSubview(view)
            Self.pinToEdges(view, of: self.contentContainer)
        }

        /// Hands the panel's help to the presenter and restyles the button.
        /// `nil` is passed through rather than filtered out: the drawer shows its
        /// own empty state for a panel with no prose, and the button stays where
        /// it is either way.
        public func setHelp(_ help: PanelHelp?) {
            self.help = help
            self.helpPresenter?.setHelp(help)
            self.updateHelpButton()
        }

        // MARK: - Help button

        private func configureHelpButton() {
            self.helpButton.translatesAutoresizingMaskIntoConstraints = false
            self.helpButton.isBordered = false
            self.helpButton.imagePosition = .imageOnly
            self.helpButton.setButtonType(.momentaryChange)
            self.helpButton.target = self
            self.helpButton.action = #selector(self.toggleHelp)
            self.helpButton.setAccessibilityLabel("Help")
        }

        private func updateHelpButton() {
            let disclosed = self.helpPresenter?.isHelpVisible ?? false
            let palette = self.resolvedThemeScope.palette
            // Shown for every panel this split hosts, whether or not that panel
            // has prose. It used to come and go with `help != nil`, which put a
            // control in the corner of some panels and not others and made the
            // drawer look like a property of the panel rather than of the window.
            // A nested split still has no button at all — it has no presenter —
            // and neither does a split whose window puts the `?` in its toolbar.
            self.helpButton.isHidden = !self.showsHelpButton || self.helpPresenter == nil
            // Filled while open, outlined while closed — the button reports the
            // drawer's state as well as toggling it, which matters because the
            // drawer is remembered across launches.
            let symbol = disclosed ? "questionmark.circle.fill" : "questionmark.circle"
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Help")
            self.helpButton.image = image?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 15, weight: .regular))
            self.helpButton.contentTintColor = disclosed
                ? palette.accentColor
                : palette.secondaryTextColor
            self.helpButton.toolTip = disclosed ? "Hide Help" : "Show Help"
        }
    }
}
