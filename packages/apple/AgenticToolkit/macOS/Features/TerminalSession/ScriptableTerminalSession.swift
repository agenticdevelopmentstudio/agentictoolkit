import AppKit

/// KVC-compliant wrapper around a `TerminalSession` for Cocoa Scripting.
/// Each property maps to a key declared in the host's `.sdef` scripting dictionary.
@MainActor
@objc(ScriptableTerminalSession)
public class ScriptableTerminalSession: NSObject {

    public let terminalSession: TerminalSession

    public init(terminalSession: TerminalSession) {
        self.terminalSession = terminalSession
        super.init()
    }

    // MARK: - Scripting Properties

    @objc var uniqueID: String { terminalSession.id.uuidString }
    @objc var name: String { terminalSession.name }
    @objc var title: String { terminalSession.title ?? "" }
    @objc var workingDirectory: String { terminalSession.currentDirectory ?? "" }
    @objc var termGitBranch: String { terminalSession.gitBranch ?? "" }
    @objc var foregroundProcess: String { terminalSession.foregroundProcess ?? "" }
    @objc var termSummary: String { terminalSession.summary ?? "" }

    // MARK: - Object Specifier

    public override nonisolated var objectSpecifier: NSScriptObjectSpecifier? {
        applicationElementSpecifier(key: "terminalSessions") { self.uniqueID }
    }
}
