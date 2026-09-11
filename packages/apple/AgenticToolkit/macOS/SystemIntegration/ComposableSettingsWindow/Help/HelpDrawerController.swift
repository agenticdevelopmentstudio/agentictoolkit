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

        /// Named apart from the `helpTabID` requirement below: one is the id
        /// this drawer builds its tab under, the other is the id it is
        /// showing, and two names one word apart in one class invite a reader
        /// to assume they are the same thing.
        private static let helpTabIdentifier = "help"

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
        ///
        /// `weak`, as it is on `HelpPopoverController`. This controller lives as
        /// long as its window, and a toolbar hands it a fresh button on every
        /// rebuild — strongly held, each of those buttons and the view subtree,
        /// target chain and theme observer behind it would be kept alive
        /// forever, with only the last one visible.
        public weak var helpAnchorView: NSView?

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
        ///
        /// Cleared again when the window comes back, in the `reapplyVisibility`
        /// closure below. This presenter outlives its window:
        /// `SingleWindowController` builds it once from `loadWindow()` and
        /// keeps the window with `isReleasedWhenClosed = false`, so a latch
        /// that never lifted would swallow every dragged-shut drawer after the
        /// first ⌘W for the rest of the app's life.
        /// `ProjectHelpDrawerController` needs no such reset because its whole
        /// controller is dropped when its window closes.
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
                        id: Self.helpTabIdentifier,
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
            //
            // It is also the moment the window is live again — it is fired
            // from `didBecomeKey`/`didBecomeMain` — so this is where the
            // teardown latch is lifted, rather than inside `applyVisibility()`,
            // which also runs on every `setHelp(_:)` and would therefore unlatch
            // a window that is on its way out. That placement is pinned by
            // `testHelpChangingDuringTeardownDoesNotUnlatchTheClose`. Whether
            // the clear lands before or after the re-assert is immaterial and
            // deliberately not asserted: `applyVisibility()` masks its own
            // callbacks with `isApplyingVisibility` for the whole of its body.
            self.drawer.reapplyVisibility = { [weak self] in
                guard let self else { return }
                self.isTearingDown = false
                self.applyVisibility()
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

        /// Which tab the drawer is showing. The settings drawer has exactly one
        /// tab, but this answers from the drawer rather than returning the
        /// constant: the protocol's whole reason for making this a requirement
        /// is that a presenter with tabs must not fall through to the `nil`
        /// default, and a hard-coded answer would go stale the day a second tab
        /// arrives.
        public var helpTabID: String? { self.drawer.selectedTabID }

        private func applyVisibility() {
            self.isApplyingVisibility = true
            defer { self.isApplyingVisibility = false }

            if self.isHelpVisible {
                self.drawer.open(selecting: Self.helpTabIdentifier)
            } else {
                self.drawer.close()
            }
            self.onVisibilityChange?()
        }
    }
}
