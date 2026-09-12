import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreUI
import AgenticToolkitCoreMacOS
import AgenticToolkitMacOS

@MainActor
class Features {
    let appearanceManager: AppearanceManager
    let permissionWalkthrough: PermissionWalkthrough
    let terminalCoordinator: TerminalCoordinator
    let aiPluginsCoordinator: AIPluginsCoordinator
    let chatConfigProvider: PluginChatConfigProvider
    let aiChatCoordinator: AIChatCoordinator
    let windowContextsCoordinator: WindowContextsCoordinator
    let settingsCoordinator: ComposableSettings.AppCoordinator

    /// Every named action this app can run, in one place. Built before any
    /// coordinator so all three register into the same registry — which is what
    /// a command palette, a shortcut or an extension would enumerate.
    let commandRegistry: CommandRegistry
    let menuManager: MenuManager

    init() {
        let commandRegistry = CommandRegistry()
        self.commandRegistry = commandRegistry

        self.appearanceManager = AppearanceManager()
        self.permissionWalkthrough = PermissionWalkthrough()
        let aiPluginsCoordinator = AIPluginsCoordinator(appName: "AgenticPluginTester")
        self.aiPluginsCoordinator = aiPluginsCoordinator
        self.terminalCoordinator = TerminalCoordinator(commandRegistry: commandRegistry)
        self.windowContextsCoordinator = WindowContextsCoordinator()

        // Chat runs through the loaded plugins: the config provider reports the
        // user's selection (from the AI settings panel) and the backend asks the
        // selected plugin to describe each request.
        let chatConfigProvider = PluginChatConfigProvider(pluginManager: aiPluginsCoordinator.pluginManager)
        self.chatConfigProvider = chatConfigProvider
        self.aiChatCoordinator = AIChatCoordinator(makeBackend: {
            AIPluginChatBackend(
                pluginManager: aiPluginsCoordinator.pluginManager,
                configProvider: chatConfigProvider
            )
        }, commandRegistry: commandRegistry)

        self.settingsCoordinator = ComposableSettings.AppCoordinator(
            windowTitle: "Agentic Toolkit Settings",
            settingsPanels: [
                AppearanceSettingsPanelViewController(),
                GeneralSettingsPanelViewController(),
                PermissionsSettingsPanelViewController()
            ],
            commandRegistry: commandRegistry
        )

        self.menuManager = MenuManager()
    }

    func start() {
        logger.info("Agentic Toolkit launching")

        settingsCoordinator.addPanel(aiPluginsCoordinator.settingsPanel())

        for feature in AppFeatureRegistry.shared.features {
            do {
                try feature.start()
            } catch {
                let name = String(describing: type(of: feature))
                logger.error(
                    "Feature start failed: \(name, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        menuManager.install(contributors: AppFeatureRegistry.shared.features)

        logger.info("Agentic Toolkit launch complete — all subsystems initialized")

        permissionWalkthrough.runIfNeeded { [weak self] in
            guard let self else { return }
            logger.info("finished walkthrough: \(type(of: self))")
        }
    }

    /// The synchronous half of shutdown: everything that can be done before
    /// the process is allowed to go.
    func stop() {
        logger.info("Agentic Toolkit terminating")
        AppFeatureRegistry.shared.stopAll()
    }

    /// The asynchronous half: every feature's pending writes, flushed.
    ///
    /// This used to be an un-awaited `Task` inside `stop()`, launched from a
    /// synchronous `applicationWillTerminate(_:)` — so the process exited
    /// before any of it ran and no feature's `terminate()` ever happened. It
    /// is a separate method now because the delegate has to be able to await
    /// it; `ApplicationShutdownCoordinator` is what holds the quit open while
    /// it runs.
    func terminate() async {
        await AppFeatureRegistry.shared.terminateAll()
        logger.info("Agentic Toolkit shutdown complete")
    }
}

extension Features: Loggable {
    public static nonisolated let logger = makeLogger()
}
