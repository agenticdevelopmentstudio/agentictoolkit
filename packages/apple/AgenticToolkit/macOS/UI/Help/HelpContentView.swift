import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS

/// The content of a help drawer: a fixed "Help" heading over an independently
/// scrolling list of `HelpContent` topics.
///
/// The topics are ordinary `GroupView` + `ExplanationView` pairs — the same two
/// views the settings panels are built from — so help reads in the same type and
/// rhythm as the controls it describes, and gains any future styling those views
/// get for free. Those views still live under `ComposableSettings`; that is a
/// naming debt, not a layering one (it is all one framework), and paying it off
/// is a larger change than this file should make.
///
/// This is only the contents. The sliding, the edge it comes out of and the
/// window tracking belong to `WindowDrawer`.
@MainActor
public final class HelpContentView: NSView {

    private let titleLabel = NSTextField(labelWithString: "Help")
    private let scrollView = ComposableSettings.PanelScrollView()

    private var themeObserver: ThemePaletteObserver?
    private var content: HelpContent?

    public init() {
        super.init(frame: .zero)
        self.translatesAutoresizingMaskIntoConstraints = false
        self.wantsLayer = true

        self.titleLabel.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.titleLabel)
        self.addSubview(self.scrollView)

        let inset = ComposableSettings.SettingsLayout.default[.panelInset]
        NSLayoutConstraint.activate([
            self.titleLabel.topAnchor.constraint(equalTo: self.topAnchor, constant: inset),
            self.titleLabel.leadingAnchor.constraint(
                equalTo: self.leadingAnchor, constant: inset),
            self.titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: self.trailingAnchor, constant: -inset),

            self.scrollView.topAnchor.constraint(equalTo: self.titleLabel.bottomAnchor),
            self.scrollView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.scrollView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.scrollView.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        ])

        self.themeObserver = ThemePaletteObserver(host: self) { [weak self] palette in
            self?.applyTheme(palette)
        }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError() }

    /// What the drawer says when there is no prose. The drawer does not close
    /// itself in that case — that made it slam shut on the way to a panel with
    /// nothing to say and slide open again on the way out, an animation nobody
    /// asked for that reads as the window flinching — so something has to
    /// occupy it, and an honest sentence beats an empty pane that reads as a
    /// rendering failure.
    private static let emptyTitle = "No Help Yet"
    private static let emptyBody =
        "This panel doesn't have any help written for it. Its controls each "
        + "carry their own explanation underneath."

    /// Replaces the contents. `nil` shows the empty state rather than blanking.
    public func setHelp(_ content: HelpContent?) {
        self.content = content
        let topics = content?.topics ?? []
        let panel = ComposableSettings.PanelView()
        if topics.isEmpty {
            let group = ComposableSettings.GroupView(withTitle: Self.emptyTitle)
            group.addSettingSubview(ComposableSettings.ExplanationView(withText: Self.emptyBody))
            panel.addGroup(group)
        }
        for topic in topics {
            let group = ComposableSettings.GroupView(withTitle: topic.title)
            group.addSettingSubview(ComposableSettings.ExplanationView(withText: topic.body))
            panel.addGroup(group)
        }
        self.scrollView.setContent(panel)
    }

    private func applyTheme(_ palette: SemanticPalette) {
        // The same ground as the window, the drawer around it and the
        // `PanelView` of topics below — for the reason `PanelView` gives: the
        // cards are what should stand out, and a heading-shaped band of a
        // second near-identical grey above them only reads as a misprint.
        self.layer?.backgroundColor = palette.windowBackgroundColor.cgColor
        self.titleLabel.font = palette.font(.heading)
        self.titleLabel.textColor = palette.primaryTextColor
    }
}
