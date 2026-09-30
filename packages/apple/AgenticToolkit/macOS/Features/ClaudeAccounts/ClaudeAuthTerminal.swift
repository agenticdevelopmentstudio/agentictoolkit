import AgenticToolkitCore
import AppKit
import Foundation

/// Opens a terminal window running one command.
///
/// `claude auth login` is a browser handshake with prompts, so it belongs in
/// front of the user in a real terminal rather than inside a pipe the app
/// reads. What comes back is not a return value: the app learns the login
/// landed by watching `~/.claude.json` change (`ClaudeAuthStore`'s watcher),
/// which is also how it notices a login the user did in their own terminal.
///
/// It goes through a `.command` file handed to `NSWorkspace` rather than
/// AppleScript, and that is the whole point of the file: scripting Terminal.app
/// or iTerm2 needs an Automation (TCC) grant, and being refused one would turn
/// "log in" into a permissions detour. Opening a document needs nothing, and it
/// lands in whichever terminal the user's own machine opens `.command` files
/// with.
public enum ClaudeAuthTerminal {

    public enum TerminalError: Error, LocalizedError {
        case couldNotWriteScript(String)
        case couldNotOpen

        public var errorDescription: String? {
            switch self {
            case .couldNotWriteScript(let message):
                return "Couldn't prepare the terminal command: \(message)"
            case .couldNotOpen:
                return "Couldn't open a terminal window."
            }
        }
    }

    /// Runs `command` in a new terminal window. The command is written verbatim
    /// into a shell script, so only ever pass a literal this app composes —
    /// never a user-supplied string.
    public static func run(command: String) throws {
        let url = try writeScript(for: command)
        guard NSWorkspace.shared.open(url) else { throw TerminalError.couldNotOpen }
    }

    /// The script, rewritten on every run so it never goes stale, at a fixed
    /// path so the app leaves one file behind rather than one per login.
    private static func writeScript(for command: String) throws -> URL {
        let directory = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/\(ClaudeAccounts.configuration.identifier)")
        let url = directory.appendingPathComponent("claude-auth.command")
        // The per-terminal account pins are cleared for the same reason
        // `ClaudeAuthCLI` clears them: this window is about the machine-wide
        // login, and a pinned `CLAUDE_CODE_OAUTH_TOKEN` inherited from whatever
        // launched the app would answer as a different account.
        let script = """
            #!/bin/sh
            unset CLAUDE_CODE_OAUTH_TOKEN
            unset ANTHROPIC_API_KEY
            unset ANTHROPIC_AUTH_TOKEN
            unset CLAUDE_ACCT_TOKENS
            unset CLAUDE_ACCT_NAME
            echo "\(ClaudeAccounts.appName) — \(command)"
            echo
            \(command)
            status=$?
            echo
            echo "Finished (exit $status). You can close this window."

            """
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: url.path)
        } catch {
            throw TerminalError.couldNotWriteScript(error.localizedDescription)
        }
        return url
    }
}
