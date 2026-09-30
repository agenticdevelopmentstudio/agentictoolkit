import AgenticToolkitCore
import Foundation

/// Runs `claude` on the app's behalf.
///
/// **Only `claude`, and only for what `claude` alone can answer**: whether a
/// login is live, and logging out. Credentials are not read or written here —
/// The app's own items go through `ClaudeKeychain`, and Claude Code's item
/// through `ClaudeCodeKeychainItem`.
///
/// Nothing here mints. `claude setup-token` does, and it has its own runner
/// (`ClaudeSetupTokenMinter`) reached only when the user asks for a token.
public enum ClaudeAuthCLI {

    public enum CLIError: Error, LocalizedError, Sendable {
        case binaryNotFound(String)
        case launchFailed(String)
        case nonZeroExit(command: String, code: Int32, message: String)
        case timedOut(String)
        case noTokenInOutput(String)

        public var errorDescription: String? {
            switch self {
            case .binaryNotFound(let name):
                return "\(name) not found — looked in ~/.local/bin, /usr/local/bin and /opt/homebrew/bin."
            case .launchFailed(let message):
                return "Couldn't launch the command: \(message)"
            case .nonZeroExit(let command, let code, let message):
                return message.isEmpty ? "\(command) failed (exit \(code))" : message
            case .timedOut(let command):
                return "\(command) took too long and was stopped."
            case .noTokenInOutput(let message):
                return message.isEmpty
                    ? "No token appeared in the output of `claude setup-token`."
                    : "No token appeared in the output of `claude setup-token`:\n\(message)"
            }
        }
    }

    /// What a finished command said.
    public struct Output: Sendable {
        public let stdout: String
        public let stderr: String
        public let status: Int32

        public var isSuccess: Bool { status == 0 }

        /// What to put in front of a person: these CLIs write their refusals to
        /// stderr and their answers to stdout, so prefer stderr and fall back.
        public var message: String { stderr.isEmpty ? stdout : stderr }
    }

    // MARK: - Binaries

    public static func claudeBinary() -> String? { findBinary(named: "claude") }

    /// The same three install locations `ClaudeCLI.findBinary()` searches, in
    /// the same order — an app launched from Finder inherits no login shell, so
    /// `PATH` is not an answer here.
    private static func findBinary(named name: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/opt/homebrew/bin/\(name)"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - The CLI

    /// Runs `claude <arguments>`, throwing on a non-zero exit.
    @discardableResult
    public static func claude(
        _ arguments: [String],
        timeout: TimeInterval = 120
    ) async throws -> Output {
        guard let binary = claudeBinary() else { throw CLIError.binaryNotFound("claude") }
        let output = try await run(executable: binary, arguments: arguments, timeout: timeout)
        guard output.isSuccess else {
            throw CLIError.nonZeroExit(
                command: "claude " + arguments.joined(separator: " "),
                code: output.status,
                message: output.message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    // MARK: - Process plumbing

    /// Runs `executable` and returns everything it said.
    ///
    /// The shape is `ClaudeCLI.run`'s, for the same reasons: stdout and stderr
    /// are drained CONCURRENTLY with the child (one that outran the ~64KB pipe
    /// buffer would otherwise deadlock against the wait), and the wait happens
    /// off the cooperative pool.
    ///
    /// `input` is written to the child's stdin before it is closed — how a
    /// secret reaches `security -i` without ever appearing in an argv that `ps`
    /// can show.
    public static func run(
        executable: String,
        arguments: [String],
        input: Data? = nil,
        timeout: TimeInterval = 180
    ) async throws -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = childEnvironment()

        let stdinPipe = Pipe(), stdoutPipe = Pipe(), stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw CLIError.launchFailed(error.localizedDescription)
        }

        // Closed immediately after any input: a `claude` that decides to prompt
        // must see EOF and give up, rather than block forever on a terminal that
        // isn't there.
        if let input { try? stdinPipe.fileHandleForWriting.write(contentsOf: input) }
        try? stdinPipe.fileHandleForWriting.close()

        let timedOut = FlagBox()
        let timeoutTask = Task {
            try? await Task.sleep(for: .seconds(timeout))
            if process.isRunning {
                timedOut.raise()
                process.terminate()
            }
        }
        async let stdoutData = readToEnd(stdoutPipe.fileHandleForReading)
        async let stderrData = readToEnd(stderrPipe.fileHandleForReading)
        await waitForExit(process)
        timeoutTask.cancel()

        let out = String(data: await stdoutData, encoding: .utf8) ?? ""
        let err = String(data: await stderrData, encoding: .utf8) ?? ""
        if timedOut.isRaised {
            throw CLIError.timedOut(([executable] + arguments).joined(separator: " "))
        }
        return Output(stdout: out, stderr: err, status: process.terminationStatus)
    }

    /// The environment a child of *this app* should run in.
    ///
    /// Two deliberate edits. `AGENTIC_TOOLKIT_HEADLESS` marks these as
    /// programmatic invocations so a session tracker's hooks don't record them
    /// as sessions. And the per-terminal account pins are **removed**: the app
    /// may itself have been launched from a terminal carrying a credential of
    /// its own in the environment, and a panel about the machine-wide login must
    /// not answer for whichever account that terminal happened to be billing.
    private static func childEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extras = ["\(home)/.local/bin", "/usr/local/bin", "/opt/homebrew/bin"]
        env["PATH"] = (extras + [env["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
        env["AGENTIC_TOOLKIT_HEADLESS"] = "1"
        env["CLAUDE_CODE_OAUTH_TOKEN"] = nil
        env["ANTHROPIC_API_KEY"] = nil
        env["ANTHROPIC_AUTH_TOKEN"] = nil
        env["CLAUDE_ACCT_TOKENS"] = nil
        env["CLAUDE_ACCT_NAME"] = nil
        return env
    }

    private static func readToEnd(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { (continuation: CheckedContinuation<Data, Never>) in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: (try? handle.readToEnd()) ?? Data())
            }
        }
    }

    private static func waitForExit(_ process: Process) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
                continuation.resume()
            }
        }
    }

    /// A one-way flag two tasks share — the timeout task raises it, the caller
    /// reads it after the wait, so a terminated child is reported as a timeout
    /// rather than as an ordinary non-zero exit.
    private final class FlagBox: @unchecked Sendable {
        private let lock = NSLock()
        private var raised = false
        func raise() { lock.lock(); raised = true; lock.unlock() }
        var isRaised: Bool { lock.lock(); defer { lock.unlock() }; return raised }
    }
}
