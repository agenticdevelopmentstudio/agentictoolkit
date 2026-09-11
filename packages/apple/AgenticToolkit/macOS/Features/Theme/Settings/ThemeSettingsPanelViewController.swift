import AppKit
import UniformTypeIdentifiers
import AgenticToolkitCore

/// The "Theme" settings panel — a topic/detail split (like "Claude"/"AI") with
/// one sub-panel per theme. The sidebar lists the themes (name + color swatch);
/// selecting one activates it and shows its preview + editor in the detail. A
/// footer under the list carries the structural actions: add / remove and a
/// menu of duplicate / import JSON / export JSON. The list is user-resizable via
/// the split's draggable divider.
@MainActor
public final class ThemeSettingsPanelViewController: ComposableSettings.SettingsPanelSplitViewController {

    private let store = ThemeStore()

    /// The +/− control, kept so its "remove" segment can be disabled when the
    /// selected theme is a built-in (permanent).
    private var addRemoveControl: NSSegmentedControl?
    /// Keeps the footer's enabled state in sync with the selected/active theme.
    private var activeThemeObserver: UserSettingObserver<String>?

    public init() {
        super.init(with: ComposableSettings.SettingsPanelDescriptor(
            title: "Theme",
            icon: NSImage(systemSymbolName: "paintpalette", accessibilityDescription: nil)
        ))
        // The sidebar lists multiple themes, so title it in the plural.
        sidebarTitle = "Themes"
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var helpContent: ComposableSettings.PanelHelp? {
        ComposableSettings.PanelHelp(topics: [
            .init(
                title: "Themes",
                body: "Selecting a theme activates it immediately — there is no separate "
                    + "apply step, so you can click down the list and watch every window "
                    + "change as you go. The colors and fonts here drive the whole app, "
                    + "not just this window."
            ),
            .init(
                title: "Editing",
                body: "Built-in and imported themes are locked, so the editor shows them "
                    + "read-only. Duplicate one to get an editable copy — that is the "
                    + "intended way to start from a theme you like rather than from "
                    + "nothing."
            ),
            .init(
                title: "Adding and Sharing",
                body: "The controls under the list add, remove, duplicate, and import or "
                    + "export a theme as JSON. An exported theme is a single file you can "
                    + "keep in a dotfiles repo or hand to someone else."
            )
        ])
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        listViewController.setFooterView(makeFooter())
        rebuildPanels(selecting: UserSettings.activeThemeID.value)
        // Selecting a theme row activates it (updating activeThemeID), so this
        // also fires whenever the selection changes — keeping "remove" enabled
        // only for deletable themes.
        activeThemeObserver = UserSettingObserver(UserSettings.activeThemeID) { [weak self] id in
            self?.updateFooterState(for: id)
        }
    }

    /// The theme backing the selected row. Selecting a row activates it, so the
    /// active theme *is* the selected one — the target for remove/duplicate/export.
    private var selectedTheme: ColorTheme? {
        store.theme(withID: UserSettings.activeThemeID.value)
    }

    /// Rebuilds one detail panel per theme and selects `selectID` (the active
    /// theme, or a freshly added/imported/duplicated one). Called on load and
    /// after any structural change to the theme list.
    private func rebuildPanels(selecting selectID: String?) {
        let themes = store.allThemes
        let panels = themes.map { theme in
            ThemeDetailPanelViewController(
                theme: theme,
                store: store,
                onRowInvalidated: { [weak self] in self?.refreshRows() }
            )
        }
        setPanels(panels)
        let targetID = selectID ?? themes.first?.id
        // Track which theme actually ends up selected so the footer reflects it
        // immediately — activeThemeID isn't updated until the new panel's
        // viewWillAppear runs, which is too late for the updateFooterState below.
        let selectedID: String?
        if let index = themes.firstIndex(where: { $0.id == targetID }) {
            selectPanel(at: index)
            selectedID = targetID
        } else if !panels.isEmpty {
            selectPanel(at: 0)
            selectedID = themes.first?.id
        } else {
            selectedID = nil
        }
        updateFooterState(for: selectedID)
    }

    /// Re-reads the sidebar rows (titles/swatches) from the existing panels after
    /// an in-place edit (a rename), without recreating them or re-showing the
    /// detail, then keeps the active theme's row highlighted.
    private func refreshRows() {
        listViewController.setPanels(panels)
        let activeID = UserSettings.activeThemeID.value
        if let index = panels.firstIndex(where: { ($0 as? ThemeDetailPanelViewController)?.themeID == activeID }) {
            listViewController.selectPanel(at: index)
        }
    }

    // MARK: - Footer

    private func makeFooter() -> NSView {
        let addRemove = NSSegmentedControl()
        addRemove.segmentCount = 2
        addRemove.setImage(NSImage(systemSymbolName: "plus", accessibilityDescription: "Add theme"), forSegment: 0)
        addRemove.setImage(NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove theme"), forSegment: 1)
        addRemove.setWidth(28, forSegment: 0)
        addRemove.setWidth(28, forSegment: 1)
        addRemove.trackingMode = .momentary
        addRemove.segmentStyle = .smallSquare
        addRemove.target = self
        addRemove.action = #selector(addRemoveClicked(_:))
        addRemove.setToolTip("Add a new theme", forSegment: 0)
        addRemove.setToolTip("Remove the selected theme", forSegment: 1)
        addRemoveControl = addRemove

        let gear = NSPopUpButton(frame: .zero, pullsDown: true)
        gear.bezelStyle = .texturedRounded
        gear.imagePosition = .imageOnly
        let menu = NSMenu()
        // The pull-down's first item is the button face (an ellipsis glyph).
        let face = NSMenuItem()
        face.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "More actions")
        menu.addItem(face)
        menu.addItem(actionItem("Duplicate", #selector(duplicateSelected)))
        menu.addItem(.separator())
        menu.addItem(actionItem("Import JSON…", #selector(importJSONAction)))
        menu.addItem(actionItem("Export JSON…", #selector(exportJSONAction)))
        gear.menu = menu
        gear.toolTip = "More theme actions"

        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        bar.spacing = 6
        bar.addView(addRemove, in: .leading)
        bar.addView(gear, in: .trailing)
        bar.translatesAutoresizingMaskIntoConstraints = false

        let separator = ThemedSeparatorView(role: .border)
        let footer = NSStackView(views: [separator, bar])
        footer.orientation = .vertical
        footer.alignment = .leading
        footer.spacing = 0
        footer.translatesAutoresizingMaskIntoConstraints = false
        for sub in [separator, bar] {
            sub.widthAnchor.constraint(equalTo: footer.widthAnchor).isActive = true
        }
        return footer
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    /// Enables the remove(−) segment only for a deletable theme. Callers pass the
    /// theme that is (about to be) selected: the active-theme observer passes the
    /// live `activeThemeID`, while a structural action passes the id it just
    /// selected, so the footer is correct immediately rather than lagging until
    /// the new panel's `viewWillAppear` updates `activeThemeID`.
    private func updateFooterState(for themeID: String?) {
        let deletable = themeID.flatMap { store.theme(withID: $0) }?.isDeletable ?? false
        addRemoveControl?.setEnabled(deletable, forSegment: 1)
    }

    // MARK: - Structural actions

    @objc private func addRemoveClicked(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: addTheme()
        case 1: removeSelectedTheme()
        default: break
        }
    }

    private func addTheme() {
        let created = store.addNewTheme(basedOn: selectedTheme ?? BuiltInThemes.solarizedDark)
        rebuildPanels(selecting: created.id)
    }

    private func removeSelectedTheme() {
        guard let theme = selectedTheme, theme.isDeletable else { RefusalFeedback.announce(); return }
        // Land on the previous row (or the first) after the delete.
        let ids = store.allThemes.map(\.id)
        let previousID = ids.firstIndex(of: theme.id).flatMap { $0 > 0 ? ids[$0 - 1] : nil }
        store.delete(id: theme.id)
        rebuildPanels(selecting: previousID ?? store.allThemes.first?.id)
    }

    @objc private func duplicateSelected() {
        guard let theme = selectedTheme else { RefusalFeedback.announce(); return }
        rebuildPanels(selecting: store.duplicate(theme).id)
    }

    @objc private func importJSONAction() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        var types: [UTType] = [.json]
        if let iterm = UTType(filenameExtension: "itermcolors") { types.append(iterm) }
        panel.allowedContentTypes = types
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // Routes by file content (not extension), so a mis-named file still
            // lands in the right parser.
            let imported = try store.importTheme(contentsOf: url)
            rebuildPanels(selecting: imported.id)
        } catch {
            present(error, title: "Couldn’t import theme")
        }
    }

    @objc private func exportJSONAction() {
        guard let theme = selectedTheme else { RefusalFeedback.announce(); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(Self.sanitizedFilename(theme.name)).json"
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportJSON(theme).write(to: url)
        } catch {
            present(error, title: "Couldn’t export theme")
        }
    }

    private func present(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    /// Strips path separators (and other filename-illegal characters) from a
    /// free-text theme name so it can seed a save panel's default file name —
    /// otherwise a name like "Light/Dark" would be read as a path component.
    private static func sanitizedFilename(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/:\\")
        let cleaned = name.components(separatedBy: illegal).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Theme" : cleaned
    }
}
