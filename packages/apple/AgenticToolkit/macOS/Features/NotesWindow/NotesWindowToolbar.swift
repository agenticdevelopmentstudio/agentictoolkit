import AppKit
import AgenticToolkitCoreMacOS

/// The window toolbar's item identifiers (task-7 spec §3), private to this
/// file the same way `SettingsWindow.swift` keeps its own — nothing outside
/// this delegate needs to name them, and Whippet's UI suite (task-7-grounding
/// G7) reaches these controls by their string value, not by this extension.
private extension NSToolbarItem.Identifier {
    static let notesToggleFolders = NSToolbarItem.Identifier("notes.toolbar.toggle-folders")
    static let notesNewFolder = NSToolbarItem.Identifier("notes.toolbar.new-folder")
    static let notesCompose = NSToolbarItem.Identifier("notes.toolbar.compose")
    static let notesShare = NSToolbarItem.Identifier("notes.toolbar.share")
    static let notesMore = NSToolbarItem.Identifier("notes.toolbar.more")
    static let notesSearch = NSToolbarItem.Identifier("notes.toolbar.search")
    static let notesHelp = NSToolbarItem.Identifier("notes.toolbar.help")
}

/// Builds and drives the Notes window's titlebar toolbar (spec §3): the
/// folders/help disclosure buttons, new-folder and compose, share, the `⋯`
/// menu (content added by Task 8), a live search field, and the help toggle.
///
/// A stored property on `NotesWindowController`, built in `init` — never
/// inside `configureWindow` — because `NSToolbar.delegate` is `weak`
/// (task-7-grounding G4): a delegate with no other owner is deallocated the
/// instant `configureWindow` returns, and the toolbar renders no items at all
/// with no error.
///
/// Holds the split controller weakly: the window controller owns both this
/// toolbar and the split controller, and a strong back-reference here would
/// make a cycle.
///
/// Every button is a **custom-view** item, not a standard one. `NSToolbarItem`
/// itself has no accessibility conformance — it is a plain `NSObject`, and
/// `setAccessibilityIdentifier` is only reachable on something that conforms
/// to `NSAccessibility`, which `NSView` does and `NSToolbarItem` does not.
/// task-7-grounding G7 requires every item's accessibility identifier to
/// equal its toolbar identifier, so the identifier has to land on a real view
/// — the same reason `ComposableSettings.SettingsWindow` wraps its own
/// toolbar controls in views rather than using standard items. The cost is
/// G5's preferred `NSToolbarItemValidation` cycle: AppKit's own header says
/// validation "will not send this message for items that have custom views,"
/// so enablement and the help glyph are refreshed manually, from
/// `NotesSplitViewController.onToolbarRelevantStateChange` — the same manual
/// pattern `SettingsWindow.updateToolbarState()` already uses for its own
/// custom-view items.
@MainActor
public final class NotesWindowToolbar: NSObject, NSToolbarDelegate {

    private weak var splitViewController: NotesSplitViewController?

    private var shareButton: NSButton?
    private var moreButton: NSButton?
    private var helpButton: NSButton?

    /// Repaints the help button on every theme change, the same way
    /// `PanelHostView` and `NotesSplitViewController.helpThemeObserver` keep
    /// their own help glyphs live: reading `ThemePaletteObserver.currentPalette`
    /// only on demand (the original version of this file) left the tint stale
    /// until some unrelated refresh — a selection change or a help toggle —
    /// happened to call `refreshDynamicState()` next. A stored, live observer
    /// applies immediately on creation and again on every subsequent theme
    /// change, whether or not anything else asked.
    private var helpThemeObserver: ThemePaletteObserver?

    public init(splitViewController: NotesSplitViewController) {
        self.splitViewController = splitViewController
        super.init()
        splitViewController.onToolbarRelevantStateChange = { [weak self] in
            self?.refreshDynamicState()
        }
    }

    private static let itemIdentifiers: [NSToolbarItem.Identifier] = [
        .notesToggleFolders,
        .notesNewFolder,
        .notesCompose,
        .notesShare,
        .notesMore,
        .flexibleSpace,
        .notesSearch,
        .notesHelp
    ]

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.itemIdentifiers
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.itemIdentifiers
    }

    public func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .notesToggleFolders:
            return makeButtonItem(
                identifier: itemIdentifier,
                symbol: "sidebar.left",
                label: "Folders",
                action: #selector(toggleFoldersTapped)).item

        case .notesNewFolder:
            return makeButtonItem(
                identifier: itemIdentifier,
                symbol: "folder.badge.plus",
                label: "New Folder",
                action: #selector(newFolderTapped)).item

        case .notesCompose:
            return makeButtonItem(
                identifier: itemIdentifier,
                symbol: "square.and.pencil",
                label: "New Note",
                action: #selector(composeTapped)).item

        case .notesShare:
            let (item, button) = makeButtonItem(
                identifier: itemIdentifier,
                symbol: "square.and.arrow.up",
                label: "Share",
                action: #selector(shareTapped))
            shareButton = button
            button.isEnabled = splitViewController?.selectedNote() != nil
            return item

        case .notesMore:
            let (item, button) = makeButtonItem(
                identifier: itemIdentifier,
                symbol: "ellipsis.circle",
                label: "More",
                action: #selector(moreTapped))
            moreButton = button
            button.isEnabled = splitViewController?.selectedNote() != nil
            return item

        case .notesHelp:
            let (item, button) = makeButtonItem(
                identifier: itemIdentifier,
                symbol: "questionmark.circle",
                label: "Help",
                action: #selector(helpTapped))
            helpButton = button
            // `host: button` mirrors `NotesSplitViewController.helpThemeObserver`
            // (`host: view`) rather than `PanelHostView` (`host: self`): this
            // toolbar is an `NSObject`, not a view, so the button itself — the
            // real thing that ends up in the window's view hierarchy — is the
            // only candidate that can resolve a `ThemeScope`. The observer
            // applies immediately on creation, so this replaces the old
            // seed-then-never-update call to `applyHelpAppearance(to: button)`.
            helpThemeObserver = ThemePaletteObserver(host: button) { [weak self] _ in
                guard let self, let helpButton = self.helpButton else { return }
                self.applyHelpAppearance(to: helpButton)
            }
            return item

        case .notesSearch:
            return makeSearchItem()

        default:
            return nil
        }
    }

    // MARK: - Item construction

    /// A borderless, image-only button in an `NSToolbarItem`'s custom `view` —
    /// the exact idiom `PanelHostView`'s help button uses
    /// (`isBordered = false`, `imagePosition = .imageOnly`,
    /// `setButtonType(.momentaryChange)`), which is this codebase's established
    /// "toolbar-style icon button," now reused here for the same look.
    private func makeButtonItem(
        identifier: NSToolbarItem.Identifier,
        symbol: String,
        label: String,
        action: Selector
    ) -> (item: NSToolbarItem, button: NSButton) {
        let button = NSButton(
            image: NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage(),
            target: self,
            action: action)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.setButtonType(.momentaryChange)
        button.toolTip = label
        // task-7-grounding G7: Whippet's UI suite (Task 11) reaches every one
        // of these controls by an accessibility identifier equal to the
        // toolbar identifier itself.
        button.accessibilityID(identifier.rawValue)

        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.view = button
        return (item, button)
    }

    private func makeSearchItem() -> NSSearchToolbarItem {
        let item = NSSearchToolbarItem(itemIdentifier: .notesSearch)
        item.searchField.placeholderString = "Search"
        item.searchField.delegate = self
        item.searchField.accessibilityID(NSToolbarItem.Identifier.notesSearch.rawValue)
        return item
    }

    // MARK: - Actions

    @objc private func toggleFoldersTapped() {
        splitViewController?.toggleFolders()
    }

    @objc private func newFolderTapped() {
        splitViewController?.createFolderUnderSelection()
    }

    @objc private func composeTapped() {
        // Reuses the split controller's existing new-note flow
        // (`NotesListViewControllerDelegate.notesListDidRequestNewNote()`) —
        // it already does exactly what "compose" needs (create, keep the
        // current folder filter, select and show the new note), so the
        // toolbar calls the same public entry point the list's own button
        // used to, rather than duplicating it.
        splitViewController?.notesListDidRequestNewNote()
    }

    @objc private func shareTapped(_ sender: NSButton) {
        guard let note = splitViewController?.selectedNote() else { return }
        let picker = NSSharingServicePicker(items: [note.content])
        picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }

    @objc private func moreTapped(_ sender: NSButton) {
        // Task 8 populates this menu's contents (move to folder, lock,
        // delete, ...); Task 7's job is the button, its enabled state, and
        // somewhere for that content to land.
        let menu = NSMenu(title: "More")
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    @objc private func helpTapped() {
        // `toggleHelp()` itself calls `onToolbarRelevantStateChange`, which
        // refreshes `helpButton`'s glyph/tint/tooltip — no separate call
        // needed here.
        splitViewController?.toggleHelp()
    }

    // MARK: - Dynamic state (task-7-grounding G5, adapted for custom views)

    /// Re-checks everything a selection change or a help-visibility change can
    /// affect. Wired to `NotesSplitViewController.onToolbarRelevantStateChange`
    /// in `init`, since custom-view toolbar items never receive AppKit's
    /// `NSToolbarItemValidation` pass.
    private func refreshDynamicState() {
        let hasSelection = splitViewController?.selectedNote() != nil
        shareButton?.isEnabled = hasSelection
        moreButton?.isEnabled = hasSelection
        if let helpButton {
            applyHelpAppearance(to: helpButton)
        }
    }

    /// The help symbol swap (task-7-grounding G3), copied whole: filled while
    /// the pane is open, outlined while closed, at `pointSize: 15, weight:
    /// .regular`, with the tint and tooltip that go with it — the button
    /// reports the pane's state as well as toggling it.
    private func applyHelpAppearance(to button: NSButton) {
        let disclosed = splitViewController?.isHelpVisible ?? false
        let symbol = disclosed ? "questionmark.circle.fill" : "questionmark.circle"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Help")
        button.image = image?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 15, weight: .regular))
        // The button's own resolved scope (task-7 fix round 1), not
        // `ThemePaletteObserver.currentPalette` — matches
        // `NotesSplitViewController`'s `view.resolvedThemeScope.palette` and
        // `PanelHostView`'s `self.resolvedThemeScope.palette`: this toolbar may
        // run inside a window with its own theme scope, and the static
        // app-wide accessor would ignore that.
        let palette = button.resolvedThemeScope.palette
        button.contentTintColor = disclosed ? palette.accentColor : palette.secondaryTextColor
        button.toolTip = disclosed ? "Hide Help" : "Show Help"
    }
}

// MARK: - NSSearchFieldDelegate

extension NotesWindowToolbar: NSSearchFieldDelegate {

    public func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else { return }
        splitViewController?.setSearchQuery(field.stringValue)
    }
}
