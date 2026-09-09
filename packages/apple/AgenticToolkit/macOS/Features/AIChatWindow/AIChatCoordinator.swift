import AppKit
import OSLog
import AgenticToolkitCore

/// Owns the AI Chat window. Lazy: nothing is constructed until
/// `showWindow()` is called or scripting reads `aiChatVisible`. The chat
/// session is host-specific, so the coordinator takes a session-factory closure
/// at init.
@MainActor
public final class AIChatCoordinator: AppFeature {

    private let makeSession: () -> any ChatSession
    public private(set) var viewModel: AIChatViewModel?
    public private(set) var windowController: AIChatWindowController?

    /// The ids this feature's actions answer to. One command, two menu items:
    /// the Window entry and the status-item entry are the same action, and the
    /// registry is what lets them say so instead of each holding its own copy
    /// of the closure (`dry`).
    public enum CommandID {
        public static let showWindow = "aichat.action.showWindow"
    }

    /// - Parameter commandRegistry: See `ProjectsCoordinator.init` — `nil`
    ///   gives this feature a private registry and behaves exactly as before.
    public init(
        makeSession: @escaping () -> any ChatSession,
        commandRegistry: CommandRegistry? = nil
    ) {
        self.makeSession = makeSession
        super.init()

        let registry = commandRegistry ?? CommandRegistry()
        registry.register(AppCommand(
            id: CommandID.showWindow,
            title: "AI Chat",
            category: "AI Chat",
            run: { [weak self] in self?.showWindow() }
        ))

        self.menuContributions = [
            MenuContribution(
                slot: .window,
                title: "AI Chat",
                commandID: CommandID.showWindow,
                registry: registry,
                order: 30,
                key: "3"
            ),
            MenuContribution(
                slot: .statusItem(section: 1),
                title: "AI Chat",
                commandID: CommandID.showWindow,
                registry: registry,
                order: 20
            )
        ]

        self.scriptingKeys.insert("scriptingAIChatVisible")
        self.scriptingKeys.insert("scriptingChatViewModel")
    }

    /// Legacy convenience: wraps a `ChatBackend` factory in `ChatBackendSession`.
    /// Prefer `init(makeSession:)`. Retained until AgenticToolkitApp & Whippet
    /// migrate, then deleted.
    public convenience init(
        makeBackend: @escaping () -> ChatBackend,
        commandRegistry: CommandRegistry? = nil
    ) {
        self.init(
            makeSession: { ChatBackendSession(backend: makeBackend()) },
            commandRegistry: commandRegistry
        )
    }

    // MARK: - Public API

    /// Idempotent — safe to call before reading `viewModel` from scripting.
    public func ensureWindow() {
        guard windowController == nil else { return }
        let chatViewModel = AIChatViewModel(session: makeSession())
        viewModel = chatViewModel
        windowController = AIChatWindowController(viewModel: chatViewModel)
    }

    public func showWindow() {
        ensureWindow()
        windowController?.showWindow()
    }

    public override func value(forScriptingKey key: String) -> Any? {
        switch key {
        case "scriptingAIChatVisible":
            return windowController?.isVisible ?? false
        case "scriptingChatViewModel":
            return viewModel
        default:
            return nil
        }
    }

    public override func setValue(_ value: Any?, forScriptingKey key: String) {
        switch key {
        case "scriptingAIChatVisible":
            if (value as? Bool) == true { showWindow() }
        default:
            break
        }
    }
}

extension AIChatCoordinator: Loggable {
    public static nonisolated let logger = makeLogger()
}
