import AppKit
import KeyboardShortcuts

/// Where the user rebinds the palette's global shortcut.
///
/// Its own panel rather than another group on General: General lives in this
/// shared framework and every consuming app shows it, and Stenographer must not
/// be made to advertise a command palette it does not build (`srp`).
@MainActor
public final class KeyboardSettingsPanelViewController: ComposableSettings.SettingsPanelViewController {

    public init() {
        super.init(with: ComposableSettings.SettingsPanelDescriptor(
            title: "Keyboard",
            icon: NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
        ))
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The sidebar's search reads the controls of a panel only once that panel
    /// has been built, and this one is a single third-party recorder with no
    /// text of its own to match — so everything a user might type to find it
    /// has to be named here.
    public override var searchKeywords: [String] {
        ["keyboard", "shortcut", "palette", "command"]
    }

    public override var helpContent: ComposableSettings.PanelHelp? {
        ComposableSettings.PanelHelp(topics: [
            .init(
                title: "Show All Commands",
                body: "Opens the command palette: a search field listing every command in "
                    + "the app, including the ones extensions add. This shortcut is "
                    + "registered system-wide, so it works while another app is frontmost "
                    + "— which also means it is taken away from that app. If a combination "
                    + "does nothing, another app or a macOS shortcut already claimed it; "
                    + "record a different one here."
            )
        ])
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        self.settingsView.addGroup(createShortcutsGroup())
    }

    private func createShortcutsGroup() -> ComposableSettings.GroupView {
        let group = ComposableSettings.GroupView(withTitle: "Shortcuts")

        let recorder = KeyboardShortcuts.RecorderCocoa(for: .showCommandPalette)
        recorder.accessibilityID("settings.keyboard.show-command-palette")

        // The library's recorder is the whole control — it draws the current
        // binding, records a new one and persists it — but it brings no label,
        // so the row is assembled the way every other labelled row here is.
        let row = ComposableSettings.HorizontalStackView()
        // "Command Palette:", not the command's own title "Show All Commands":
        // this row binds the shortcut that *opens* the palette, and the surface
        // the user is looking for it from is the View menu's "Command Palette…".
        row.addArrangedSubview(ComposableSettings.makeRowLabel("Command Palette:"))
        row.addArrangedSubview(recorder)
        group.addSettingSubview(row)

        return group
    }
}
