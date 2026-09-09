import AppKit
import OSLog
import AgenticToolkitCore

/// Owns the terminal-window subsystem: the live array of
/// `TerminalSessionWindowController` instances, the lifecycle delegate that
/// removes them when they close, and the AppleScript `new terminal`
/// command target. Contributes the File-menu and status-item terminal
/// items + the `terminalSessions` scripting key set.
@MainActor
public final class TerminalCoordinator: AppFeature, TerminalSessionWindowLifecycleDelegate {

    public private(set) var windowControllers: [TerminalSessionWindowController] = []

    // MARK: - Public API

    /// The ids this feature's actions answer to. "New Terminal Window" appears
    /// twice in the menus (File and the status item) and is one command here.
    public enum CommandID {
        public static let newWindow = "terminal.action.newWindow"
        public static let newSession = "terminal.action.newSession"
        public static let toggleSidebar = "terminal.action.toggleSidebar"
    }

    /// - Parameter commandRegistry: See `ProjectsCoordinator.init` — `nil`
    ///   gives this feature a private registry and behaves exactly as before,
    ///   which is what keeps `TerminalCoordinator()` compiling unchanged.
    public init(commandRegistry: CommandRegistry? = nil) {
        super.init()

        self.scriptingKeys.insert("terminalSessions")

        let registry = commandRegistry ?? CommandRegistry()
        registry.register(AppCommand(
            id: CommandID.newWindow,
            title: "New Terminal Window",
            category: "Terminal",
            run: { [weak self] in self?.openNewTerminalWindow() }
        ))
        registry.register(AppCommand(
            id: CommandID.newSession,
            title: "New Terminal Session",
            category: "Terminal",
            run: { [weak self] in self?.openNewTerminalSession() }
        ))
        registry.register(AppCommand(
            id: CommandID.toggleSidebar,
            title: "Toggle Sidebar",
            category: "Terminal",
            run: { [weak self] in self?.toggleSidebar() }
        ))

        self.menuContributions = [
            MenuContribution(
                slot: .file, title: "New Terminal Window",
                commandID: CommandID.newWindow, registry: registry,
                order: 0, key: "t"
            ),
            MenuContribution(
                slot: .file, title: "New Terminal Session",
                commandID: CommandID.newSession, registry: registry,
                order: 10
            ),
            MenuContribution(
                slot: .view, title: "Toggle Sidebar",
                commandID: CommandID.toggleSidebar, registry: registry,
                order: 0, key: "s", modifiers: [.command, .option]
            ),
            MenuContribution(
                slot: .statusItem(section: 1), title: "New Terminal Window",
                commandID: CommandID.newWindow, registry: registry,
                order: 30
            )
        ]

        self.newItemProviders = [
            NewItemProvider(
                // Unlike Notes, there is no single instance to ask: each
                // window gets its own fresh `TerminalSessionWindowController`
                // (see `openNewTerminalWindow()`), so the claim has to be a
                // type check against the key window's controller rather than
                // an identity check against a captured controller.
                claimsKeyWindow: {
                    NSApp.keyWindow?.windowController is TerminalSessionWindowController
                },
                title: { "New Terminal Session" },
                action: { [weak self] in
                    self?.openNewTerminalSession()
                }
            )
        ]
    }

    public func openNewTerminalWindow() {
        let controller = TerminalSessionWindowController()
        controller.lifecycleDelegate = self
        windowControllers.append(controller)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        Self.logger.info("Opened terminal window, total: \(self.windowControllers.count, privacy: .public)")
    }

    public func openNewTerminalSession() {
        if let controller = NSApp.mainWindow?.windowController as? TerminalSessionWindowController {
            controller.sessionManager.addSession()
        } else {
            openNewTerminalWindow()
        }
    }

    public func toggleSidebar() {
        (NSApp.mainWindow?.windowController as? TerminalSessionWindowController)?.toggleSidebar()
    }

    /// The frontmost terminal-session window controller, or the first one,
    /// or nil if none are open.
    public var frontmostWindowController: TerminalSessionWindowController? {
        NSApp.mainWindow?.windowController as? TerminalSessionWindowController
            ?? windowControllers.first
    }

    // MARK: - TerminalSessionWindowLifecycleDelegate

    public func terminalWindowWillClose(_ controller: TerminalSessionWindowController) {
        windowControllers.removeAll { $0 === controller }
        // swiftlint:disable:next line_length
        Self.logger.info("Removed terminal window controller, remaining: \(self.windowControllers.count, privacy: .public)")
    }

    public override func value(forScriptingKey key: String) -> Any? {
        switch key {
        case "terminalSessions":
            return windowControllers.flatMap { controller in
                controller.sessionManager.sessions.map(ScriptableTerminalSession.init(terminalSession:))
            }
        default:
            return nil
        }
    }

    /// Cocoa Scripting indexed accessor: `tell application "Whippet" to get terminal session "X"`.
    public func terminalSession(uniqueID: String) -> ScriptableTerminalSession? {
        for controller in windowControllers {
            if let session = controller.sessionManager.sessions.first(where: { $0.id.uuidString == uniqueID }) {
                return ScriptableTerminalSession(terminalSession: session)
            }
        }
        return nil
    }
}

extension TerminalCoordinator: Loggable {
    public static nonisolated let logger = makeLogger()
}
