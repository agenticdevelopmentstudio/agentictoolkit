import AppKit
import AgenticToolkitCoreMacOS
import AgenticDeveloperToolkitUI

private extension NSToolbarItem.Identifier {
    static let settingsNavigation = NSToolbarItem.Identifier("ComposableSettings.navigation")
    static let settingsPanelTitle = NSToolbarItem.Identifier("ComposableSettings.panelTitle")
    static let settingsHelp = NSToolbarItem.Identifier("ComposableSettings.help")
}

extension ComposableSettings {

    /// A reusable settings window controller. Subclass and override
    /// `makeSettingsPanels()` to compose the panels shown in the sidebar.
    ///
    /// ```swift
    /// final class AppSettingsWindowController: ComposableSettings.SettingsWindow {
    ///     override func makeSettingsPanels() -> [ComposableSettings.SettingsPanelViewController] {
    ///         [GeneralPanel(), AppearancePanel(), PluginsPanel()]
    ///     }
    /// }
    /// ```
    ///
    /// Panels are fetched lazily when the window loads, so any state the
    /// subclass needs to inject (managers, view models, configuration)
    /// can be set up before the first call to `showWindow()`.
    @MainActor
    open class SettingsWindow: WindowController<SplitViewController>, NSToolbarDelegate {

        private static let windowID = "settings"

        public init() {
            super.init(windowID: Self.windowID, contentViewController: SplitViewController())
            self.windowTitle = "Settings"
            // `.fullSizeContentView` is what lets the sidebar run the *whole*
            // height of the window, with the close/minimise/zoom buttons sitting
            // on top of it — the shape System Settings has. Without it the
            // content view starts below the titlebar, and the sidebar reads as a
            // panel hanging under the chrome rather than as the window's spine.
            self.windowStyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            // No sidebar title: the search field takes the top of the sidebar (as
            // in System Settings), and the name of what's on screen is in the
            // toolbar beside the back/forward arrows, where the reader is already
            // looking to change it.
            self.viewController?.sidebarTitle = nil
            self.viewController?.showsSidebarSearch = true
        }

        public var settingPanels: [any ComposableSettingsPanel] {
            get { viewController?.panels ?? [] }
            set { viewController?.setPanels(newValue) }
        }

        /// Whether `showWindow()` activates the app and makes the window key. A
        /// settings window is normally opened to be *used* right away — and shown
        /// from an `LSUIElement` / menubar context the base `showWindow()` leaves it
        /// visible on top but **non-key**, so its sidebar selection and text fields
        /// don't respond until the user clicks it first. Defaults to `true` for that
        /// reason; a host that would rather not steal focus can override it to
        /// `false`, so this isn't forced on every consumer.
        open var activatesOnShow: Bool { true }

        /// Attaches the help drawer and the unified toolbar to the window.
        ///
        /// Deliberately deprecated: `HelpDrawerController` wraps `NSDrawer`, and
        /// naming it inside a deprecated declaration is what keeps the wrapper's
        /// deprecation from leaking outward. Nothing of ours calls this override —
        /// `loadWindow()` calls the base method — so the annotation warns nobody.
        @available(macOS, deprecated: 10.13, message: "Builds the NSDrawer-backed help presenter")
        open override func configureWindow(_ window: NSWindow) {
            super.configureWindow(window)
            viewController?.helpPresenter = HelpDrawerController(parentWindow: window)
            installToolbar(on: window)
        }

        open override func showWindow() {
            super.showWindow()
            guard activatesOnShow else { return }
            // Quiet presentation still makes the window key — the sidebar
            // selection and text fields have to answer, and that is what being
            // key buys — but it neither activates the app nor draws above
            // anyone else's windows. That is the whole difference between a
            // settings window opened to be used and one opened to be driven.
            guard !QuietWindowPresentation.isEnabled else {
                window?.makeKeyAndOrderFrontQuietly()
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        }

        // MARK: - Toolbar

        /// The `‹ ›` control. A momentary two-segment control rather than two
        /// buttons: it is one control with one meaning — where in the trail you
        /// are — and the shared bezel is how System Settings says so.
        private lazy var navigationControl: NSSegmentedControl = {
            let control = NSSegmentedControl(
                images: [
                    NSImage(systemSymbolName: "chevron.backward", accessibilityDescription: "Back"),
                    NSImage(systemSymbolName: "chevron.forward", accessibilityDescription: "Forward")
                ].compactMap { $0 },
                trackingMode: .momentary,
                target: self,
                action: #selector(navigationClicked(_:)))
            control.segmentStyle = .separated
            control.setAccessibilityLabel("Back and forward")
            return control
        }()

        /// The name of the panel on screen, shown in the toolbar over the detail
        /// pane. The window's own title is hidden in favour of it — the window is
        /// always "Settings", which tells the reader nothing they don't know.
        private lazy var panelTitleLabel: ThemedLabel = {
            let label = ThemedLabel(string: "", role: .primaryText, textRole: .heading)
            label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            label.lineBreakMode = .byTruncatingTail
            return label
        }()

        /// The `?`. Built here rather than left in the detail pane because help
        /// is disclosed on the *window* — the drawer slides out beside it — so
        /// its control belongs in the titlebar with the window's other chrome,
        /// at the far right where AppKit centres it in the band for free.
        private var helpButton: NSButton?
        private var helpButtonThemeObserver: ThemePaletteObserver?

        private func installToolbar(on window: NSWindow) {
            let toolbar = NSToolbar(identifier: "ComposableSettings.Toolbar")
            toolbar.delegate = self
            toolbar.displayMode = .iconOnly
            toolbar.allowsUserCustomization = false
            window.toolbar = toolbar
            // Unified: one band across the titlebar, split at the sidebar divider
            // by the tracking separator below, which is what makes a sidebar look
            // like it runs the full height of the window.
            window.toolbarStyle = .unified
            window.titleVisibility = .hidden
            // Transparent titlebar and no separators, so what is under the
            // toolbar band is the sidebar's own fill on one side and the detail
            // pane's on the other — one continuous colour top to bottom, rather
            // than a strip of system chrome laid across both.
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none

            viewController?.onNavigationChange = { [weak self] in
                self?.updateToolbarState()
            }
            // The detail pane's floating `?` stands down now that the titlebar
            // carries one: two buttons reporting one drawer is one too many.
            // A settings split shown in a sheet has no toolbar and keeps its own.
            viewController?.showsInlineHelpButton = false
            viewController?.onHelpVisibilityChange = { [weak self] in
                self?.updateHelpButton()
            }
            updateToolbarState()
        }

        private func updateToolbarState() {
            guard let split = viewController else { return }
            // A custom-view toolbar item never gets AppKit's validation pass, so
            // the arrows are enabled here, from the same trail that answers them.
            navigationControl.setEnabled(split.canGoBack, forSegment: 0)
            navigationControl.setEnabled(split.canGoForward, forSegment: 1)
            panelTitleLabel.stringValue = split.currentPanelTitle ?? ""
            updateHelpButton()
        }

        /// Makes the `?` report the drawer as well as toggle it — filled while
        /// open, outlined while shut — which matters because the drawer is
        /// remembered across launches and may already be open on the first draw.
        private func updateHelpButton() {
            guard let button = helpButton else { return }
            WindowToolbarBuilder.applyDisclosureAppearance(
                to: button,
                disclosed: viewController?.isHelpVisible ?? false,
                outlineSymbol: "questionmark.circle",
                filledSymbol: "questionmark.circle.fill",
                showTooltip: "Show Help",
                hideTooltip: "Hide Help")
        }

        @objc private func helpClicked(_ sender: NSButton) {
            viewController?.toggleHelp()
        }

        @objc private func navigationClicked(_ sender: NSSegmentedControl) {
            // Named segments, not "0 or anything else": `selectedSegment` is -1
            // when the control has no selection, and a bare `else` turned that
            // into a forward step nobody asked for.
            switch sender.selectedSegment {
            case 0: viewController?.goBack()
            case 1: viewController?.goForward()
            default: break
            }
        }

        // The flexible space is what right-justifies the `?`: everything before
        // it packs against the panel title, everything after against the
        // trailing edge.
        private static let itemIdentifiers: [NSToolbarItem.Identifier] = [
            .sidebarTrackingSeparator, .settingsNavigation, .settingsPanelTitle,
            .flexibleSpace, .settingsHelp
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
            case .sidebarTrackingSeparator:
                guard let splitView = viewController?.splitView else { return nil }
                return NSTrackingSeparatorToolbarItem(
                    identifier: itemIdentifier, splitView: splitView, dividerIndex: 0)

            case .settingsNavigation:
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.label = "Back/Forward"
                item.paletteLabel = item.label
                item.view = navigationControl
                item.visibilityPriority = .high
                return item

            case .settingsPanelTitle:
                let item = NSToolbarItem(itemIdentifier: itemIdentifier)
                item.label = "Panel"
                item.paletteLabel = item.label
                item.view = panelTitleLabel
                item.visibilityPriority = .high
                return item

            case .settingsHelp:
                let (item, button) = WindowToolbarBuilder.iconButtonItem(
                    identifier: itemIdentifier,
                    symbol: "questionmark.circle",
                    label: "Help",
                    target: self,
                    action: #selector(helpClicked(_:)))
                item.visibilityPriority = .high
                // Only an item on its way *into* the toolbar becomes the live
                // one. AppKit calls this again to build a sample for the
                // customization palette and on every toolbar rebuild, and
                // adopting one of those would point `helpButton`, the help
                // anchor and the theme observer at a button that is not on
                // screen — leaving the visible `?` unthemed and unreported.
                guard flag else { return item }
                helpButton = button
                // The presenter anchors a popover on this view when the host is
                // one that shows help as a popover rather than a drawer; for the
                // drawer it is harmless, and it keeps the two interchangeable.
                viewController?.helpPresenter?.helpAnchorView = button
                // Read on demand, not once: the tint is the palette's, and a
                // theme change has to reach a button AppKit owns the drawing of.
                // The observer applies its closure as it is built, so the
                // button's first appearance is set here too.
                helpButtonThemeObserver = ThemePaletteObserver(host: button) { [weak self] _ in
                    self?.updateHelpButton()
                }
                return item

            default:
                return nil
            }
        }
    }
}
