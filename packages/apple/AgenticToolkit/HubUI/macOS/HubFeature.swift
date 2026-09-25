#if canImport(AppKit)
import AgenticDeveloperToolkitUI
import AgenticToolkitCoreMacOS
import AgenticToolkitHTDV
import AgenticToolkitHubService
import AgenticToolkitPermissions
import AgenticToolkitPermissionsUI
import AgenticToolkitScripting
import AppKit

/// The hub, as one component a macOS host includes: the main window, the
/// composition behind it, and the permission walkthrough, with every
/// operation a menu item or script can ask of them.
///
/// It builds no menu and is no app delegate. A host arranges its own menu and
/// forwards each receiver here in one line (`hub.reload()`); that arrangement
/// is the host's choice, what the item does is this type's.
@MainActor
public final class HubFeature {

    /// The one process-wide handle, read by the hub's script commands —
    /// Cocoa Scripting instantiates commands itself, so they cannot be handed
    /// the feature.
    public private(set) static var current: HubFeature?

    public let permissions: [AgenticToolkitPermissions.Permission]
    public let permissionWalkthrough: PermissionWalkthrough
    public private(set) var mainWindow: MainWindowController?
    public private(set) var composition: HubAppComposition?

    public init(permissions: [AgenticToolkitPermissions.Permission]) {
        self.permissions = permissions
        self.permissionWalkthrough = PermissionWalkthrough(permissions: permissions)
        HubFeature.current = self
    }

    /// Everything the hub does at `applicationDidFinishLaunching`.
    ///
    /// Window first, composition second: building the composition probes for
    /// the daemon, so it is only as fast as the network is reachable, and the
    /// window must not wait on that. The walkthrough comes last and is skipped
    /// under quiet presentation — it is app-modal and would block the
    /// Apple-event bridge a scripted launch is waiting on.
    public func launch(themeManager: ThemeManager) {
        // Under xcodebuild test the app is only a host; never open windows.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        NSApp.setActivationPolicy(.regular)
        // The web app's colour-mode preference answers only for a theme that
        // makes no claim of its own — the question `autoAppearance` asks.
        (themeManager.appearanceDriver as? AppKitAppearanceDriver)?.autoAppearance = {
            AppearanceController.current.nsAppearance
        }
        themeManager.refreshApplicationAppearance()

        let controller = MainWindowController()
        mainWindow = controller
        controller.start()
        controller.presentQuietly()
        NSApp.activateUnlessQuiet()

        Task {
            let composition = await HubAppComposition.macOS()
            self.composition = composition
            controller.attach(composition: composition)
        }

        if !QuietWindowPresentation.isEnabled {
            permissionWalkthrough.runIfNeeded {}
        }
    }

    /// Brings the hub window forward (quietly under automation).
    public func showMainWindow() {
        mainWindow?.presentQuietly()
    }

    /// Reloads the hierarchy from the root; silent when it is not on screen.
    public func reload() {
        guard let controller = mainWindow?.root?.htdvViewController?.controller else { return }
        Task { await controller.load() }
    }

    /// Opens the hub's web app in the default browser.
    public func openWebsite() {
        NSWorkspace.shared.open(HubLinks.webBase)
    }

    /// Forward from the host's `applicationDidBecomeActive`.
    public func applicationDidBecomeActive() {
        guard let composition else { return }
        Task { await composition.coordinator.applicationDidBecomeActive() }
    }

    /// Shows the walkthrough whatever its "already seen" flag says.
    @discardableResult
    public func runPermissionWalkthrough() -> Bool {
        permissionWalkthrough.run()
        return true
    }

    /// Forgets that the walkthrough has run, for this feature's permissions.
    public func resetPermissionWalkthrough() {
        PermissionWalkthrough.reset(permissions: permissions)
    }

    /// The hub window as scripts name it: `main`.
    public var mainScriptWindow: ScriptWindow {
        ScriptWindow(
            name: "main",
            window: { [weak self] in self?.mainWindow?.window },
            present: { [weak self] in self?.showMainWindow() }
        )
    }
}
#endif
