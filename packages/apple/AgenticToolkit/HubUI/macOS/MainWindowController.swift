#if canImport(AppKit)
import AgenticToolkitHubService
import AgenticDeveloperToolkitUI
import AgenticToolkitCoreMacOS
import AgenticToolkitHub
import AgenticToolkitPermissionsUI
import AppKit

/// Owns the single main window and swaps its content by coordinator phase.
///
/// The window exists and is on screen before the composition does. Building
/// the composition is asynchronous (it resolves a transport, which probes for
/// a daemon), and a launch that shows nothing until that finishes is
/// indistinguishable from a hang — so `start()` puts the spinner up
/// immediately and `attach(composition:)` hands over once the graph is built.
/// This mirrors the iOS scene delegate, which makes its window key before
/// bootstrapping for the same reason.
public final class MainWindowController: NSWindowController {
    /// The window this controller was built around. `NSWindowController.window`
    /// is optional and every `window?.` call silently does nothing when it is
    /// nil; this one is non-optional, so "the window did not appear" can never
    /// be a no-op nobody notices.
    ///
    /// Public because *how* this window goes on screen is the app target's
    /// decision, not HubKit's: quiet presentation lives in
    /// `AgenticToolkitCoreMacOS`, a macOS-only tier this cross-platform
    /// framework must not link. See `MainWindowController.presentQuietly()` in
    /// the app target.
    public let hubWindow: NSWindow
    private let launch = LaunchViewController()
    private var composition: HubAppComposition?
    /// The two phase-specific children, readable from outside so the app
    /// target's scripting commands can reach the screen that is actually up.
    /// Settable only here: which one exists is the coordinator's phase, not a
    /// caller's choice.
    public private(set) var root: RootViewController?
    public private(set) var signIn: SignInViewController?

    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Agentic Developer Hub"
        window.setAccessibilityIdentifier("main-window")
        hubWindow = window
        super.init(window: window)
        // Content first, then geometry. Assigning `contentViewController`
        // resizes the window to the incoming view (see `setContent`), so any
        // sizing done before this line is thrown away.
        setContent(launch)
        window.contentMinSize = NSSize(width: 720, height: 480)
        // `setFrameAutosaveName` only arms the *saving*. Restoring is a second
        // call, and it reports whether there was anything to restore — so the
        // window comes back where the user left it, and is centred only the
        // first time it is ever shown.
        window.setFrameAutosaveName("HubMainWindow")
        let restored = window.setFrameUsingName("HubMainWindow")
        // A restored frame is honoured only if it is one a person could have
        // produced. The bug `setContent` now guards against collapsed this
        // window to its title bar, and a collapsed frame autosaves like any
        // other — a blind restore would resurrect it on every later launch from
        // a defaults entry the user has no way to see or clear.
        let content = window.contentRect(forFrameRect: window.frame).size
        if !restored
            || content.width < window.contentMinSize.width
            || content.height < window.contentMinSize.height {
            window.setContentSize(NSSize(width: 1100, height: 720))
            window.center()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Fills the window with the launch spinner. Synchronous and free of any
    /// dependency on the network, the daemon, or the composition.
    ///
    /// Deliberately does not order the window front: the host decides how the
    /// window arrives on screen, because under quiet presentation it arrives
    /// behind the desktop picture instead of in front of whatever the user is
    /// doing — and that switch lives in a tier HubKit does not link.
    public func start() {
        launch.showLoading()
        setContent(launch)
    }

    /// Hands over the built object graph: from here the coordinator's phase
    /// drives the window's content.
    public func attach(composition: HubAppComposition) {
        self.composition = composition
        let coordinator = composition.coordinator
        coordinator.onChange = { [weak self] phase in self?.render(phase) }
        coordinator.appearance.onChange = { _ in
            // Not written straight to `NSApp.appearance`: the theme owns that,
            // and this preference is only what an `.auto` theme defers to (see
            // `AppearanceController`). Re-driving the theme is what makes the
            // new answer take effect without overruling a theme that has one.
            ThemeManager.shared?.refreshApplicationAppearance()
        }
        render(coordinator.phase)
        Task { await coordinator.start() }
    }

    private func render(_ phase: AppCoordinator.Phase) {
        switch phase {
        case .launching, .loadingWorkspace:
            launch.showLoading()
            setContent(launch)
        case .error(let message):
            launch.showError(message) { [weak self] in
                Task { await self?.composition?.coordinator.retry() }
            }
            setContent(launch)
        case .signIn:
            guard let composition else { return }
            let controller = signIn ?? SignInViewController(viewModel: composition.makeSignInViewModel())
            signIn = controller
            setContent(controller)
        case .ready, .notMember:
            guard let composition else { return }
            signIn = nil
            let controller = root ?? RootViewController(composition: composition)
            root = controller
            controller.render(phase)
            setContent(controller)
        }
    }

    private func setContent(_ controller: NSViewController) {
        guard hubWindow.contentViewController !== controller else { return }
        // Assigning `contentViewController` resizes the window to the incoming
        // controller's view. Every controller that lands here builds its root as
        // a bare `NSView()` — frame `.zero`, carrying constraints that only
        // place its children and never size the root — so an unguarded
        // assignment collapsed the window to a 1x32 title bar: on launch, and
        // again on every phase change. Carry the size the window already has
        // across the swap; the incoming content's own constraints still set its
        // minimum.
        let contentSize = hubWindow.contentRect(forFrameRect: hubWindow.frame).size
        hubWindow.contentViewController = controller
        hubWindow.setContentSize(contentSize)
    }

    // MARK: Scripting

    /// Everything a script can ask about this window, read in one main-actor
    /// pass so the answers all describe the same moment.
    ///
    /// It is here rather than in the app target because the state is here:
    /// `composition`, `root` and `signIn` are this controller's, and answering
    /// from outside would mean making each of their internals public to a
    /// caller that only ever wants to read them.
    public func captureUIState() -> HubUIState {
        let bundle = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        let window = HubUIState.WindowInfo(
            title: hubWindow.title,
            isVisible: hubWindow.isVisible,
            isKey: hubWindow.isKeyWindow,
            frame: [
                "x": Double(hubWindow.frame.origin.x),
                "y": Double(hubWindow.frame.origin.y),
                "width": Double(hubWindow.frame.size.width),
                "height": Double(hubWindow.frame.size.height)
            ]
        )
        guard let coordinator = composition?.coordinator else {
            return HubUIState(
                pid: pid,
                bundlePath: bundle,
                phase: "launching",
                window: window,
                permissionWalkthroughComplete: PermissionWalkthrough.isComplete,
                quietPresentation: QuietWindowPresentation.isEnabled
            )
        }
        let workspaces = coordinator.workspaces.workspaces.map {
            HubUIState.WorkspaceItem(slug: $0.slug, label: $0.listLabel)
        }
        return HubUIState(
            pid: pid,
            bundlePath: bundle,
            phase: Self.name(of: coordinator.phase),
            errorMessage: Self.errorMessage(of: coordinator.phase),
            notMemberMessage: Self.notMemberMessage(of: coordinator.phase),
            window: window,
            signIn: signIn?.scriptState,
            workspaces: workspaces,
            selectedWorkspaceSlug: coordinator.workspaces.current?.slug,
            accountMenu: coordinator.user == nil ? [] : AccountMenuModel.Item.allCases.map(\.label),
            statusStrip: root?.scriptStatusStripMessage,
            htdv: root?.htdvViewController.map { HubUIState.HTDV(controller: $0.controller) },
            permissionWalkthroughComplete: PermissionWalkthrough.isComplete,
            quietPresentation: QuietWindowPresentation.isEnabled
        )
    }

    /// The phase's case name. Spelled out rather than derived from
    /// `String(describing:)`, which would report `ready(HubWorkspace(...))` —
    /// a whole struct's debug description in a field a script matches on.
    private static func name(of phase: AppCoordinator.Phase) -> String {
        switch phase {
        case .launching: "launching"
        case .signIn: "signIn"
        case .loadingWorkspace: "loadingWorkspace"
        case .ready: "ready"
        case .notMember: "notMember"
        case .error: "error"
        }
    }

    private static func errorMessage(of phase: AppCoordinator.Phase) -> String? {
        if case .error(let message) = phase { return message }
        return nil
    }

    private static func notMemberMessage(of phase: AppCoordinator.Phase) -> String? {
        if case .notMember(let slug) = phase { return slug }
        return nil
    }
}

public extension HubColorMode {
    /// The appearance this mode asks for, or `nil` for "whatever the system
    /// says" — the shape `ThemeAppearanceDriver.autoAppearance` returns, which
    /// is the app delegate's one use for it.
    var nsAppearance: NSAppearance? {
        switch self {
        case .auto: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

extension MainWindowController {
    /// Puts the hub window on screen, sunk behind the desktop picture when
    /// quiet presentation is on, so a driven session never takes focus.
    public func presentQuietly() {
        showWindow(nil)
        hubWindow.makeKeyAndOrderFrontQuietly()
    }
}
#endif
