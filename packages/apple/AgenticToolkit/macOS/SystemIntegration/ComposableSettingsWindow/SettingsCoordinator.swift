import AppKit
import OSLog
import AgenticToolkitCore

extension ComposableSettings {
    /// Owns the Whippet settings window and the gear-button bridge from the
    /// session-watcher panel. Whippet-local because the window is Whippet-local.
    @MainActor
    open class AppCoordinator: AppFeature {

        public let settingsWindow: ComposableSettings.SettingsWindow

        /// The ids this feature's actions answer to.
        public enum CommandID {
            public static let showSettings = "settings.action.showSettings"
        }

        /// - Parameter commandRegistry: See `ProjectsCoordinator.init` — `nil`
        ///   gives this feature a private registry and behaves exactly as
        ///   before.
        public init(
            windowTitle: String = "Settings",
            settingsPanels: [any ComposableSettingsPanel],
            commandRegistry: CommandRegistry? = nil
        ) {
            let settingsWindow = ComposableSettings.SettingsWindow()
            settingsWindow.windowTitle = windowTitle
            settingsWindow.settingPanels = Self.sortedByTitle(settingsPanels)

            settingsWindow.windowSpec = WindowSpec(
                defaultSize: NSSize(width: 720, height: 480),
                minSize: NSSize(width: 550, height: 420),
                defaultPosition: .center,
                persistsFrame: true
            )

            self.settingsWindow = settingsWindow
            super.init()

            let registry = commandRegistry ?? CommandRegistry()
            registry.register(AppCommand(
                id: CommandID.showSettings,
                title: "Settings…",
                category: "Settings",
                run: { [weak self] in self?.showWindow() }
            ))

            self.menuContributions = [
                MenuContribution(
                    slot: .app,
                    title: "Settings…",
                    commandID: CommandID.showSettings,
                    registry: registry,
                    order: 10,
                    key: ","
                )
            ]

            self.scriptingKeys = [
                "scriptingSettingsVisible"
            ]
        }

        public func showWindow() {
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow.showWindow()
        }

        /// Append a panel to the settings sidebar after construction. Used for
        /// panels whose dependencies (plugin managers, coordinators) aren't
        /// available when `SettingsCoordinator` is built.
        public func addPanel(_ panel: any ComposableSettingsPanel) {
            settingsWindow.settingPanels = Self.sortedByTitle(settingsWindow.settingPanels + [panel])
        }

        /// The sidebar is alphabetical, so a panel added late lands where its name
        /// says rather than at the bottom. Sorting lives here and not in
        /// `SplitViewController` because that class also backs *nested* topic lists
        /// (a theme's Details/Colors/Typography), where authored order is meaning.
        private static func sortedByTitle(
            _ panels: [any ComposableSettingsPanel]
        ) -> [any ComposableSettingsPanel] {
            panels.sorted {
                $0.descriptor.title.localizedStandardCompare($1.descriptor.title) == .orderedAscending
            }
        }

        public override func value(forScriptingKey key: String) -> Any? {
            switch key {
            case "scriptingSettingsVisible": return settingsWindow.isVisible
            default: return nil
            }
        }

        public override func setValue(_ value: Any?, forScriptingKey key: String) {
            switch key {
            case "scriptingSettingsVisible":
                if (value as? Bool) == true {
                    settingsWindow.showWindow()
                } else {
                    settingsWindow.dismiss()
                }
            default:
                break
            }
        }
    }

}
