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

    public override init() {
        super.init()

        self.scriptingKeys.insert("terminalSessions")
        self.menuContributions =  [
            MenuContribution(slot: .file, title: "New Terminal Window", order: 0, key: "t") { [weak self] in
                self?.openNewTerminalWindow()
            },
            MenuContribution(slot: .file, title: "New Terminal Session", order: 10) { [weak self] in
                self?.openNewTerminalSession()
            },
            MenuContribution(slot: .view, title: "Toggle Sidebar", order: 0, key: "s",
                             modifiers: [.command, .option]) { [weak self] in
                self?.toggleSidebar()
            },
            MenuContribution(slot: .statusItem(section: 1), title: "New Terminal Window", order: 30) { [weak self] in
                self?.openNewTerminalWindow()
            }
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
