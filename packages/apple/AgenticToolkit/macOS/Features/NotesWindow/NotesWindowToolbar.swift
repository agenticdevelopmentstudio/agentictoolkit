import AppKit
import AgenticDeveloperToolkitUI
import AgenticToolkitCoreMacOS
import AgenticToolkitMarkdown

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

    /// Delegates to `WindowToolbarBuilder`, which owns the custom-view idiom
    /// and the accessibility-identifier rule this file discovered. The
    /// wrapper stays because every call site here passes `target: self`.
    private func makeButtonItem(
        identifier: NSToolbarItem.Identifier,
        symbol: String,
        label: String,
        action: Selector
    ) -> (item: NSToolbarItem, button: NSButton) {
        WindowToolbarBuilder.iconButtonItem(
            identifier: identifier,
            symbol: symbol,
            label: label,
            target: self,
            action: action)
    }

    private func makeSearchItem() -> NSSearchToolbarItem {
        WindowToolbarBuilder.searchItem(
            identifier: .notesSearch,
            placeholder: "Search",
            delegate: self)
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
        let menu = buildMoreMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    // MARK: - The ⋯ menu (Task 8, spec §3)

    /// Built fresh on every open rather than kept as a persistent `NSMenu`
    /// refreshed through `NSMenuDelegate.menuNeedsUpdate(_:)` (the shape
    /// task-8-grounding G7 sketches). Both guarantee the pin item's title and
    /// the Move to checkmarks are current the moment the menu opens; building
    /// fresh is the one a plain XCTest can drive directly — the same reason
    /// `NotesFolderListViewControllerTests` exercises `deleteFolder(_:)`
    /// itself rather than a live `NSMenu` tracking session. `internal`, not
    /// `private`, so those tests can call it.
    ///
    /// Order matches spec §3: Pin/Unpin · Find in Note · Move to ▸ · Duplicate
    /// Note · Share… · separator · Delete Note. Every item requires a
    /// selected note, so enablement is a single `hasSelection` check; Move to
    /// additionally needs a store (task-8-grounding G5).
    func buildMoreMenu() -> NSMenu {
        let menu = NSMenu(title: "More")
        // `autoenablesItems` defaults to `true`, which has AppKit recompute
        // every item's enabled state at popup time from whether `target`
        // responds to `action` — discarding every manual `isEnabled` below,
        // including "Move to"'s (L4 in the review this fixes). This menu's
        // enablement is a deliberate, precomputed fact about the current
        // selection and store, not something AppKit's default guess should
        // override.
        menu.autoenablesItems = false
        let note = splitViewController?.selectedNote()
        let hasSelection = note != nil

        let pinItem = NSMenuItem(
            title: (note?.isPinned == true) ? "Unpin Note" : "Pin Note",
            action: #selector(pinMenuItemClicked), keyEquivalent: "")
        pinItem.target = self
        pinItem.isEnabled = hasSelection
        pinItem.accessibilityID("notes.menu.pin")
        menu.addItem(pinItem)

        let findItem = NSMenuItem(
            title: "Find in Note", action: #selector(findMenuItemClicked), keyEquivalent: "")
        findItem.target = self
        findItem.isEnabled = hasSelection
        findItem.accessibilityID("notes.menu.find")
        menu.addItem(findItem)

        let moveToItem = NSMenuItem(title: "Move to", action: nil, keyEquivalent: "")
        moveToItem.isEnabled = hasSelection && splitViewController?.markdownStore != nil
        moveToItem.submenu = buildMoveToSubmenu(for: note)
        moveToItem.accessibilityID("notes.menu.move-to")
        menu.addItem(moveToItem)

        let duplicateItem = NSMenuItem(
            title: "Duplicate Note", action: #selector(duplicateMenuItemClicked), keyEquivalent: "")
        duplicateItem.target = self
        duplicateItem.isEnabled = hasSelection
        duplicateItem.accessibilityID("notes.menu.duplicate")
        menu.addItem(duplicateItem)

        let shareItem = NSMenuItem(
            title: "Share…", action: #selector(shareMenuItemClicked), keyEquivalent: "")
        shareItem.target = self
        shareItem.isEnabled = hasSelection
        shareItem.accessibilityID("notes.menu.share")
        menu.addItem(shareItem)

        menu.addItem(.separator())

        let deleteItem = NSMenuItem(
            title: "Delete Note", action: #selector(deleteMenuItemClicked), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.isEnabled = hasSelection
        deleteItem.accessibilityID("notes.menu.delete")
        menu.addItem(deleteItem)

        return menu
    }

    /// "None" plus the folder tree (task-8-grounding G5), flattened into one
    /// indented list — the same shape Apple Notes' own Move to menu uses —
    /// rather than folders nested in cascading submenus of their own: an
    /// `NSMenuItem` that owns a submenu does not fire its own action on
    /// click, so a folder with children would have no way to be picked
    /// directly if it were also the item that opens its children's submenu.
    /// A checkmark marks every folder the note already belongs to; picking a
    /// checked folder or an unchecked one is `moveSelectedNote(toFolder:)`'s
    /// call to make, not this menu's.
    private func buildMoveToSubmenu(for note: Note?) -> NSMenu {
        let submenu = NSMenu(title: "Move to")
        guard let store = splitViewController?.markdownStore else { return submenu }

        let currentCategoryIDs: Set<String>
        if let note {
            currentCategoryIDs = Set(
                (try? store.categories(forDocument: note.id.uuidString.lowercased()))?.map(\.id) ?? [])
        } else {
            currentCategoryIDs = []
        }

        let noneItem = NSMenuItem(title: "None", action: #selector(moveToFolderClicked(_:)), keyEquivalent: "")
        noneItem.target = self
        noneItem.representedObject = ""
        noneItem.state = currentCategoryIDs.isEmpty ? .on : .off
        submenu.addItem(noneItem)
        submenu.addItem(.separator())

        let categories = (try? store.categories()) ?? []
        let counts = (try? store.categoryNoteCounts()) ?? [:]
        let edges = (try? store.categoryEdges()) ?? []
        let total = (try? store.noteCount(marker: .note)) ?? 0
        let tree = NoteFolder.tree(from: categories, counts: counts, edges: edges, total: total)

        func addItems(_ folders: [NoteFolder], depth: Int) {
            for folder in folders {
                let item = NSMenuItem(
                    title: folder.name, action: #selector(moveToFolderClicked(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = folder.id
                item.indentationLevel = depth
                item.state = currentCategoryIDs.contains(folder.id) ? .on : .off
                submenu.addItem(item)
                addItems(folder.children, depth: depth + 1)
            }
        }
        addItems(tree, depth: 0)

        return submenu
    }

    @objc private func pinMenuItemClicked() {
        splitViewController?.togglePinOnSelectedNote()
    }

    @objc private func findMenuItemClicked() {
        splitViewController?.findInNote()
    }

    @objc private func duplicateMenuItemClicked() {
        splitViewController?.duplicateSelectedNote()
    }

    @objc private func shareMenuItemClicked() {
        guard let button = moreButton else { return }
        splitViewController?.shareSelectedNote(from: button)
    }

    @objc private func deleteMenuItemClicked() {
        splitViewController?.deleteSelectedNote()
    }

    @objc private func moveToFolderClicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        splitViewController?.moveSelectedNote(toFolder: id)
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

    /// The help symbol swap: filled while the pane is open, outlined while
    /// closed, tinted from the button's own resolved scope — all three now
    /// `WindowToolbarBuilder`'s to know. What stays here is the only part that
    /// is about Notes: which flag counts as "disclosed."
    private func applyHelpAppearance(to button: NSButton) {
        WindowToolbarBuilder.applyDisclosureAppearance(
            to: button,
            disclosed: splitViewController?.isHelpVisible ?? false,
            outlineSymbol: "questionmark.circle",
            filledSymbol: "questionmark.circle.fill",
            showTooltip: "Show Help",
            hideTooltip: "Hide Help")
    }
}

// MARK: - NSSearchFieldDelegate

extension NotesWindowToolbar: NSSearchFieldDelegate {

    public func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else { return }
        splitViewController?.setSearchQuery(field.stringValue)
    }
}
