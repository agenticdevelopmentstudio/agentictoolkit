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
        /// The drawer itself, so the suite that covers this controller can
        /// drive the delegate callbacks AppKit drives. Not `public`: nothing
        /// outside the framework has any business reaching past
        /// `HelpPresenting`.
        private(set) var drawer: WindowDrawer!

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

        /// True only while `applyVisibility()` is moving the drawer itself. The
        /// drawer announces every move, including the ones this controller
        /// asked for — and including an `open()` AppKit dropped because the
        /// window was not on screen yet, which from the outside looks exactly
        /// like the reader dragging the drawer shut.
        private var isApplyingVisibility = false

        /// True from the moment the window says it is closing. AppKit shuts a
        /// drawer along with its window and reports it through the same
        /// callback a drag produces, so without this a settings window that is
        /// simply closed would be read as the reader putting help away.
        private var isTearingDown = false

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
            // A drawer can also be dragged shut by its outer edge, which goes
            // nowhere near the `?`. Without this the preference still says
            // visible and the next window focus slides it back out — the same
            // defect `ProjectHelpDrawerController` reconciles, reached through
            // the same callback.
            self.drawer.onVisibilityChange = { [weak self] in
                self?.drawerVisibilityDidChange()
            }
            // Registered by selector rather than by block so the observation is
            // zeroing-weak and needs no `deinit` to undo.
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.parentWindowWillClose),
                name: NSWindow.willCloseNotification,
                object: parentWindow)
        }

        /// The drawer moved, and it was not `applyVisibility()` that moved it:
        /// the reader dragged it shut. The preference is the truth about what
        /// they want, so it is what gets corrected — and correcting it comes
        /// back round through `preference.onChange` on the next turn, which
        /// finds the drawer already closed and does nothing.
        ///
        /// Idempotent on purpose: one move can be announced twice, once from
        /// `WindowDrawer.close()` and once from `NSDrawer`'s delegate.
        private func drawerVisibilityDidChange() {
            guard !self.isApplyingVisibility, !self.isTearingDown else { return }
            // Whether a shut drawer on this window could be the reader's doing
            // at all is the drawer's question, and `WindowDrawer` answers it for
            // every owner rather than each one re-deriving it.
            guard self.drawer.closeIsAttributableToTheReader, self.isHelpVisible else { return }
            self.preference.value = false
        }

        /// Everything announced from here on is AppKit taking the window apart,
        /// not the reader putting help away.
        @objc private func parentWindowWillClose() {
            self.isTearingDown = true
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
            self.isApplyingVisibility = true
            defer { self.isApplyingVisibility = false }

            if self.isHelpVisible {
                self.drawer.open(selecting: Self.helpTabID)
            } else {
                self.drawer.close()
            }
            self.onVisibilityChange?()
        }
    }
}
