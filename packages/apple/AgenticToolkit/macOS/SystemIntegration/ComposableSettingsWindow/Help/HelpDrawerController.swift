import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS
import AgenticDeveloperToolkitUI

extension ComposableSettings {

    /// The settings window's help drawer.
    ///
    /// Everything about *being* a drawer — the slide, the edge, the window
    /// tracking, the fact that opening on a window not yet on screen is
    /// silently dropped — belongs to `WindowDrawer` now. What is left here is
    /// the only part that was ever about settings: that the drawer is
    /// remembered in `settingsHelpDrawerVisible`, and that its one tab is Help.
    ///
    /// The deprecation annotation stays because `WindowDrawer` carries one, and
    /// naming a deprecated type is only warning-free from inside another.
    @available(macOS, deprecated: 10.13, message: "Wraps NSDrawer, deprecated since macOS 10.13")
    @MainActor
    public final class HelpDrawerController: NSObject, HelpPresenting {

        public static let contentWidth: CGFloat = WindowDrawer.defaultContentWidth

        private static let helpTabID = "help"

        private let helpView = HelpContentView()
        private let preference: UserSettingObserver<Bool>
        private var drawer: WindowDrawer!

        public var onVisibilityChange: (() -> Void)?

        /// Unused: a drawer comes out of the window's edge, not out of a button.
        /// `HelpPresenting` still requires it, because the popover presenter
        /// does need somewhere to hang its help from.
        public var helpAnchorView: NSView?

        /// The drawer is open because the reader asked for it to be open, and
        /// for no other reason.
        ///
        /// It used to be `hasHelp && preference`, which made the drawer slam
        /// shut on the way to a panel that had no prose and slide open again on
        /// the way out — an animation triggered by clicking the sidebar, which
        /// nobody asked for and which reads as the window flinching. A panel
        /// with nothing to say now says so *inside* the drawer, where it costs
        /// a line of text instead of a change of layout.
        public var isHelpVisible: Bool { self.preference.value }

        public init(parentWindow: NSWindow) {
            self.preference = UserSettingObserver(UserSettings.settingsHelpDrawerVisible)
            super.init()

            let helpView = self.helpView
            self.drawer = WindowDrawer(
                parentWindow: parentWindow,
                accessibilityPrefix: "settings.drawer",
                tabs: [
                    DrawerTab(
                        id: Self.helpTabID,
                        title: "Help",
                        symbolName: "questionmark.circle",
                        makeView: { helpView })
                ],
                contentWidth: Self.contentWidth)

            self.preference.onChange = { [weak self] _ in
                self?.applyVisibility()
            }
            // `WindowDrawer` remembers nothing; this is what it re-asserts when
            // the window finally appears, so a remembered-open drawer opens on
            // launch rather than on the second try.
            self.drawer.reapplyVisibility = { [weak self] in
                self?.applyVisibility()
            }
        }

        // MARK: - HelpPresenting

        public func setHelp(_ content: HelpContent?) {
            self.helpView.setHelp(content)
            self.applyVisibility()
        }

        public func toggleHelp() {
            self.preference.value.toggle()
        }

        private func applyVisibility() {
            if self.isHelpVisible {
                self.drawer.open(selecting: Self.helpTabID)
            } else {
                self.drawer.close()
            }
            self.onVisibilityChange?()
        }
    }
}
