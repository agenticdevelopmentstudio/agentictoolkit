import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS
import AgenticDeveloperToolkitUI

/// A reusable `NSWindowController` base that lazily builds a single
/// `NSWindow` from subclass-supplied configuration and persists its frame
/// through `WindowManager`. Subclasses provide title, size, style mask, and
/// content by overriding the open properties and factory methods below.
///
/// Usage:
/// ```swift
/// final class MyWindowController: SingleWindowController {
///     init() { super.init(windowID: "mine") }
///
///     override var windowTitle: String { "My Window" }
///     override var defaultContentRect: NSRect { NSRect(x: 0, y: 0, width: 800, height: 600) }
///     override func makeContentViewController() -> NSViewController? {
///         MyViewController()
///     }
/// }
/// ```
///
/// The window is built by the first call to `showWindow(_:)`, and `window` is
/// `nil` before then — reading it does **not** lazy-load it, despite that
/// being AppKit's usual `NSWindowController` behavior. `init(window: nil)`
/// leaves `isWindowLoaded` `true` even though no window exists yet, which is
/// exactly what stops both AppKit's lazy `window` getter and the default
/// `showWindow(_:)` from calling `loadWindow()` on their own — so this class
/// forces that call itself, the first time `showWindow(_:)` runs. The window
/// is reused on subsequent calls. Prefer `makeContentViewController()` — the
/// NSViewController lifecycle fires correctly. Override `makeContentView()`
/// if you only need an `NSView`.
@MainActor
open class SingleWindowController: NSWindowController, NSWindowDelegate {

    public static let defaultSize = NSSize(width: 600, height: 480)

    /// Whether `showWindow(_:)` may pull the window above *other applications'*
    /// windows with `orderFrontRegardless()`.
    ///
    /// True in a shipping app — that call is the whole reason a menubar
    /// (LSUIElement) host can show a window at all. False under quiet
    /// presentation, where it is pure damage: a suite that exercises window
    /// controllers, or an automated session driving a Debug build, throws
    /// opaque, fully-drawn windows over whatever the person at the keyboard is
    /// doing, for as long as the run lasts. Nothing in the suite asserts
    /// front-ordering; the tests assert `isVisible`, restored frames and
    /// delegate wiring, all of which the `makeKeyAndOrderFront` inside
    /// `super.showWindow` still provides. Settable so a host that genuinely
    /// wants the old behavior back — including a future test *of*
    /// front-ordering — can say so.
    public static var forcesWindowFront = !QuietWindowPresentation.isEnabled

    public var windowID: String = ""

    /// Set by `configureAsHUD()`. Tells `loadWindow()` to apply the HUD
    /// chrome (borderless, no shadow chrome, floating, transparent backing)
    /// after the NSWindow is created.
    private var hudConfiguration: HUDConfiguration?

    /// Initializes the controller and registers it with
    /// `WindowManager.shared.registry` under `windowID`. The host's launch
    /// path then calls `WindowManager.shared.restoreOnLaunch()` once to
    /// re-show every registered window whose spec opts in to visibility
    /// persistence — no per-controller restore call is needed.
    public init(windowID: String, contentViewController: NSViewController) {
        self.windowID = windowID
        super.init(window: nil)
        self.contentViewController = contentViewController
        WindowManager.shared.registry.register(self)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for SingleWindowController")
    }

    // MARK: - Overridable configuration

    /// Title shown in the window's title bar.
    open var windowTitle: String = ""

    /// Initial content rect used when the window is first created. Frame
    /// persistence via `WindowManager` may override size/position on
    /// subsequent launches if a saved frame exists for `windowID`.
    open var defaultContentRect: NSRect {
        guard let size = windowSpec?.defaultSize else {
            return NSRect(origin: .zero, size: Self.defaultSize)
        }
        return NSRect(origin: .zero, size: size)
    }

    /// Style mask for the window.
    open var windowStyleMask: NSWindow.StyleMask = [.titled, .closable, .resizable]

    /// Optional minimum size. If non-nil it is applied to the window after
    /// creation.
    open var minSize: NSSize?

    /// Called once the window exists and its content view controller is set,
    /// and *before* its saved frame is restored or it is ordered in. Override
    /// for post-creation mutation — installing a toolbar, wiring extra
    /// observers.
    ///
    /// Running before the frame restore is deliberate, and `loadWindow()`
    /// spells out why: chrome installed here changes how much of the window is
    /// titlebar, so the frame has to be restored onto the window this method
    /// has finished shaping. The cost is that `window.frame` in here is the
    /// default rect, not the restored one — anything that needs the final
    /// geometry has to read it later than this.
    open func configureWindow(_ window: NSWindow) {}

    // MARK: - NSWindowController lazy-load hook

    open override func loadWindow() {
        let newWindow = NSWindow(
            contentRect: defaultContentRect,
            styleMask: windowStyleMask,
            backing: .buffered,
            defer: false
        )
        newWindow.title = windowTitle
        newWindow.isReleasedWhenClosed = false
        // Default accessibility id derived from the windowID. Subclasses
        // can overwrite this in `configureWindow(_:)` if a different
        // namespace is preferred.
        newWindow.accessibilityID("\(AccessibilityID.slug(windowID)).window")
        if let minSize = minSize {
            newWindow.minSize = minSize
        }

        newWindow.contentViewController = contentViewController

        self.window = newWindow
        // Chrome first, frame second. Each of the three calls below can change
        // how much of the window is chrome rather than content — a subclass's
        // `configureWindow` is where a toolbar gets installed, and a unified
        // toolbar makes the titlebar taller. AppKit grows the frame downward
        // from a fixed top edge to make room, so a window positioned *before*
        // its toolbar exists ends up half the toolbar's height below where it
        // was put, and a *saved* frame — which was recorded with the toolbar in
        // it — is restored onto a shorter window and then grows past the size
        // it was saved at, a little more every session.
        applyToolbarButtonMask(to: newWindow)
        if let hudConfiguration {
            applyHUDChrome(hudConfiguration, to: newWindow)
        }
        configureWindow(newWindow)
        // WindowManager.restoreFrame handles positioning in every path:
        // saved geometry → restored; no saved state but spec registered →
        // applyDefaultPosition (geometric center via FrameCalculator); no
        // spec → geometric center fallback. A post-call `window.center()`
        // here would override that with AppKit's upper-center (y ≈ 1/3
        // from top), which is what it does despite the misleading name.
        WindowManager.shared.frames.restoreFrame(for: newWindow, id: windowID)
        // Wire the delegate last — setting `contentViewController` above
        // resizes the window to the view's size and posts
        // `NSWindowDidResizeNotification`. If the delegate were attached
        // before that, `windowDidResize` would call `saveFrame` with the
        // default-NSWindow pre-restore frame, clobbering any prior saved
        // state (and then `restoreFrame` would read back that just-written
        // default frame instead of the spec's geometric center).
        newWindow.delegate = self
    }

    // MARK: - Public API

    /// Shows the window, creating it lazily on first call. Subsequent calls
    /// bring the existing window to front. Thin no-arg wrapper over
    /// `NSWindowController.showWindow(_:)` so existing call sites keep
    /// working.
    open func showWindow() {
        showWindow(nil)
    }

    open override func showWindow(_ sender: Any?) {
        // `NSWindowController.init(window: nil)` leaves `isWindowLoaded = true`
        // despite no window existing, so the default `showWindow(_:)` skips
        // `loadWindow()`. Force it so the first call actually builds the
        // window (subclasses previously duplicated this guard at every call
        // site).
        if window == nil { loadWindow() }
        super.showWindow(sender)
        // Window-scoped front-ordering. `super.showWindow` calls
        // `makeKeyAndOrderFront`, which respects app-activation state — a
        // window shown from an LSUIElement / menubar context can stay behind
        // other apps' windows. `orderFrontRegardless` brings *this* window
        // forward without touching NSApp activation (which is app-scoped and
        // the wrong tool here, and nil in headless `swift test`).
        //
        // Skipped in a test host — see `forcesWindowFront`.
        if Self.forcesWindowFront {
            window?.orderFrontRegardless()
        } else if let window {
            // The window has to stay genuinely on screen — `isVisible`, the
            // restored frame and `window.screen` are all things the suite
            // asserts, and all three evaporate if it is ordered out or moved
            // off the display. So leave the geometry alone and sink it behind
            // the desktop picture instead: still a real, laid-out, visible
            // window to AppKit, invisible to whoever is using the machine.
            // The suite's own bare `NSWindow`s take the same treatment, which
            // is why it is `sinkBehindDesktop()` and not two lines here.
            window.sinkBehindDesktop()
            window.orderBack(nil)
        }
        WindowManager.shared.frames.saveVisibility(true, for: windowID)
        WindowManager.shared.windowDidInteract(self, kind: .show)
    }

    /// Hides the window without destroying it. Visibility is persisted as
    /// hidden so `restoreVisibilityIfNeeded()` won't reopen it next launch.
    open func dismiss() {
        WindowManager.shared.frames.saveVisibility(false, for: windowID)
        window?.orderOut(nil)
    }

    /// Whether the window is currently visible.
    public var isVisible: Bool {
        window?.isVisible ?? false
    }

    /// Resizes the window to hug `contentSize`, anchored on whichever screen
    /// edge it sits nearest and moved rather than pushed off when it runs out
    /// of room — `FrameCalculator.contentHuggingFrame` states the rule.
    /// Content-hugging windows call this instead of hand-rolled `setFrame`
    /// math; the resulting resize persists through the normal delegate hooks
    /// (harmless — a fit that moved the window moved it for a reason).
    ///
    /// This is for **non-resizable, content-hugging** windows that own both
    /// dimensions. Resizable list windows that only auto-fit *height* (and let
    /// the user own width) use `NSWindow.fitHeight(toContentHeight:)` instead —
    /// a deliberately separate, simpler mechanism, not a duplicate.
    public func fitWindow(toContentSize contentSize: NSSize) {
        guard let window, contentSize.width > 0, contentSize.height > 0 else { return }
        let frameSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: contentSize)
        ).size
        // Common case on repeated content refits (poll ticks): nothing the fit
        // reads has changed since the last one, so it can only reproduce the
        // frame it produced then. Bail before the screen scan + geometry math
        // rather than after.
        //
        // All three inputs have to match, not just the size. The fit reads
        // *where* the window sits — which screen edge it is nearest, and how
        // much room is left that way — so a window dragged toward an edge, or
        // onto a smaller display, asks for exactly the size it asked for
        // before and gets a different answer. A size-only test would bail on
        // precisely the moves this fit exists to answer.
        let currentVisibleFrame = window.screen?.visibleFrame
        if let currentVisibleFrame,
           lastContentFit == ContentFit(desiredFrameSize: frameSize,
                                        windowFrame: window.frame,
                                        screenVisibleFrame: currentVisibleFrame) {
            return
        }
        let frames = WindowManager.shared.frames
        guard let screen = WindowFrameManager.bestScreen(
            for: window, among: frames.screenProvider.screens
        ) else { return }
        let target = FrameCalculator.contentHuggingFrame(
            currentFrame: window.frame,
            desiredFrameSize: frameSize,
            screenVisibleFrame: screen.visibleFrame,
            minSize: windowSpec?.minSize ?? window.minSize
        )
        // Recorded for the bail above *after* the fit, so it describes what the
        // fit settled on: the frame it produced, on the screen it ended up on
        // (a fit that moves the window can move it onto another one).
        defer {
            lastContentFit = window.screen.map {
                ContentFit(desiredFrameSize: frameSize,
                           windowFrame: window.frame,
                           screenVisibleFrame: $0.visibleFrame)
            }
        }
        guard target != window.frame else { return }
        isApplyingContentFit = true
        window.setFrame(target, display: true, animate: false)
        isApplyingContentFit = false
    }

    /// Everything the last fit read, so an identical re-fit can bail before
    /// doing the work again. Recomputed on every fit, so a screen whose visible
    /// area changes underneath a stationary window (a display swap, the Dock
    /// hiding) re-fits too.
    private struct ContentFit: Equatable {
        var desiredFrameSize: NSSize
        var windowFrame: NSRect
        var screenVisibleFrame: NSRect
    }

    /// `nil` until the first fit, and whenever the window is on no screen at
    /// all (which reads as "unknown", never as "unchanged").
    private var lastContentFit: ContentFit?

    /// True only for the instant `fitWindow` spends applying its own frame.
    /// A content-hugging fit is top-left anchored, so it changes the window's
    /// origin and AppKit posts `windowDidMove` for it; without this the fit
    /// would schedule a follow-up move refit against itself every time.
    private var isApplyingContentFit = false

    // MARK: - Content refit seam

    /// Supplies the window's desired content size on demand. A content-hugging
    /// controller (e.g. the Usage HUD / Details window) registers this once and
    /// `performContentRefit()` recomputes the fit from this single source. A
    /// `nil` result means "no refit yet" (content not built), not zero.
    public var contentSizeProvider: (() -> NSSize?)?

    /// Recomputes the fit from `contentSizeProvider` and applies it — the single
    /// content-refit entry point for content-hugging windows. A no-op before a
    /// provider is registered.
    public func performContentRefit() {
        guard let size = contentSizeProvider?() else { return }
        fitWindow(toContentSize: size)
    }

    /// How long a move waits for further moves before the refit runs. A drag
    /// posts a move notification per event; fitting on each one would resize
    /// the window under the pointer that is holding it, so the moves are
    /// coalesced into one fit at the end.
    static let moveRefitSettleDelay: Duration = .milliseconds(200)

    /// The in-flight settle timer. Cancelled and restarted by every move, so a
    /// drag of any length produces exactly one fit.
    private var moveRefitSettleTask: Task<Void, Never>?

    /// Whether a move should re-fit this window at all: only a content-hugging
    /// window owns its own size (a resizable window's size is the user's).
    /// Overridden by windows that hug their content through some other
    /// mechanism than `contentSizeProvider` — a list window that owns only its
    /// height, say.
    open var wantsRefitAfterMove: Bool {
        contentSizeProvider != nil && !isApplyingContentFit
    }

    /// The fit a settled move applies. The default is the whole-size content
    /// refit; a window that hugs only one dimension overrides this with its own
    /// fit, and inherits the settle timing rather than re-deriving it.
    open func refitContentAfterMove() {
        performContentRefit()
    }

    /// Re-fits a content-hugging window once its move has settled. The window
    /// was sized for the screen it was on: moved to a roomier display it can
    /// grow back to the size its content wanted all along, moved to a smaller
    /// one it has to shrink to what fits there — `fitWindow(toContentSize:)`
    /// recomputes both against the screen the window now sits on.
    ///
    /// The fit is deliberately not applied *during* the drag: it is top-left
    /// anchored, so resizing mid-drag would slide the window's edges around
    /// the pointer that is still holding it. A held mouse button (a drag
    /// paused, not finished) keeps waiting rather than firing early.
    func scheduleContentRefitAfterMove() {
        guard wantsRefitAfterMove else { return }
        moveRefitSettleTask?.cancel()
        moveRefitSettleTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.moveRefitSettleDelay)
                guard !Task.isCancelled, let self else { return }
                guard NSEvent.pressedMouseButtons == 0 else { continue }
                self.moveRefitSettleTask = nil
                self.refitContentAfterMove()
                return
            }
        }
    }

    /// If the spec opts in to visibility persistence and the last saved
    /// state was `true`, show the window. Invoked for every registered
    /// controller by `WindowManager.shared.restoreOnLaunch()`; hosts should
    /// call that single entry point rather than this per-controller method.
    public func restoreVisibilityIfNeeded() {
        guard let spec = windowSpec, spec.persistsVisibility else { return }
        if WindowManager.shared.frames.loadVisibility(for: windowID) == true {
            showWindow()
        }
    }

    // MARK: - HUD configuration

    /// Configuration captured by `configureAsHUD(...)` and replayed in
    /// `loadWindow()` after the NSWindow exists. Keeps the API ergonomic
    /// (subclasses can call `configureAsHUD()` in init, before the window
    /// is built) while keeping the mutation site in one place.
    public struct HUDConfiguration: Sendable {
        public var floating: Bool
        public var transparency: Double

        public init(floating: Bool = true, transparency: Double = 1.0) {
            self.floating = floating
            self.transparency = transparency
        }
    }

    /// Marks the window as a HUD: borderless chrome, floating level, and a
    /// transparent backing layer that respects `transparency`. Subclasses
    /// call this from `init` (before the window is built); `loadWindow()`
    /// applies the chrome after creation. Subsequent live updates flow
    /// through `setFloating(_:)` and `setTransparency(_:)`.
    open func configureAsHUD(floating: Bool = true, transparency: Double = 1.0) {
        windowStyleMask = [.borderless]
        hudConfiguration = HUDConfiguration(floating: floating, transparency: transparency)
    }

    /// Toggles the window between `.floating` and `.normal` levels. Safe to
    /// call before the window has been built — the update will be picked
    /// up on first `loadWindow()` via the stored `hudConfiguration`.
    public func setFloating(_ floating: Bool) {
        hudConfiguration?.floating = floating
        if let window = window {
            window.level = floating ? .floating : .normal
        }
    }

    /// Sets the window's alpha (clamped 0.3...1.0 to avoid an
    /// invisible-but-clickable HUD).
    public func setTransparency(_ alpha: Double) {
        hudConfiguration?.transparency = alpha
        if let window = window {
            let clamped = CGFloat(min(max(alpha, 0.3), 1.0))
            guard window.alphaValue != clamped else { return }
            window.alphaValue = clamped
        }
    }

    // MARK: - NSWindowDelegate

    open func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        WindowManager.shared.frames.saveFrame(for: window, id: windowID)
        scheduleContentRefitAfterMove()
    }

    open func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        WindowManager.shared.frames.saveFrame(for: window, id: windowID)
    }

    open func windowWillClose(_ notification: Notification) {
        // Only a close while the app is *running* means the user dismissed
        // the window — persist hidden so it stays closed next launch. During
        // termination AppKit also sends `windowWillClose:` to still-visible
        // windows; persisting false there would stop a window the user left
        // open from reopening. See `WindowManagerTerminationTests`.
        if !WindowManager.shared.isTerminating {
            WindowManager.shared.frames.saveVisibility(false, for: windowID)
        }
        WindowManager.shared.windowDidInteract(self, kind: .close)
    }

    // MARK: - Helpers

    private func applyToolbarButtonMask(to window: NSWindow) {
        guard let buttons = windowSpec?.toolbarButtons else { return }
        // `standardWindowButton` is nil when the style mask doesn't include
        // the corresponding trait — setting hidden on nil is fine and lets
        // us mask buttons regardless of which traits the window declares.
        window.standardWindowButton(.closeButton)?.isHidden = !buttons.contains(.close)
        window.standardWindowButton(.miniaturizeButton)?.isHidden = !buttons.contains(.miniaturize)
        window.standardWindowButton(.zoomButton)?.isHidden = !buttons.contains(.zoom)
    }

    private func applyHUDChrome(_ config: HUDConfiguration, to window: NSWindow) {
        window.isMovableByWindowBackground = true
        window.hasShadow = true
        // Only the initial color: `ThemeManager` repaints every titled window
        // on a theme change, so a per-window observer here would be a second
        // mechanism doing the same job.
        window.backgroundColor = ThemePaletteObserver.currentPalette.windowBackgroundColor
        window.isOpaque = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.level = config.floating ? .floating : .normal
        let clamped = CGFloat(min(max(config.transparency, 0.3), 1.0))
        window.alphaValue = clamped
    }
}

// MARK: - Singleton convenience

/// A `SingleWindowController` the app keeps as a process-wide singleton in its
/// `current` slot. Conformers supply the slot and a `makeShared()` factory; the
/// default `ensureCurrent()` centralizes the construct-if-nil guard (and the
/// `WindowManager` registration that construction performs) so it isn't copy-
/// pasted into every controller. Controllers whose construction needs a runtime
/// argument (e.g. the Sessions window's plugin manager) keep a bespoke
/// constructor instead of conforming.
@MainActor
public protocol SingletonWindowController: SingleWindowController {
    static var current: Self? { get set }
    /// Builds the singleton instance. Implemented inside the concrete controller
    /// so it can call a private initializer.
    static func makeShared() -> Self
}

public extension SingletonWindowController {
    /// Constructs the singleton (whose `init` registers it with `WindowManager`)
    /// without showing it, if it doesn't exist yet. `main.swift` calls this at
    /// launch so `restoreOnLaunch()` can reopen a window that was visible last
    /// session — no per-controller boilerplate.
    static func ensureCurrent() {
        if current == nil { current = makeShared() }
    }

    /// Bring the shared window forward, making it first if it does not exist
    /// yet, and activate the app so the window is actually in front of the
    /// user — what every "Show <Window>" menu item and shortcut wants.
    ///
    /// The activation is skipped under quiet presentation. Suppressing the
    /// *ordering* without suppressing this was the gap: a test host sank its
    /// windows behind the desktop and then yanked the foreground anyway, so a
    /// suite still interrupted whoever was working while showing them nothing.
    static func present() {
        ensureCurrent()
        current?.showWindow()
        guard !QuietWindowPresentation.isEnabled else { return }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// True while the shared window exists and is on screen. Never creates it.
    static func isOpen() -> Bool {
        current?.isVisible ?? false
    }
}
