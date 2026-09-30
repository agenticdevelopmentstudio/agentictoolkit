import AgenticToolkitCore
import Foundation

/// Runs `claude setup-token` and lifts the minted long-lived token out of what
/// it printed.
///
/// Two things make this its own runner rather than another `ClaudeAuthCLI.run`
/// call. First, `setup-token` is a browser flow: it wants a terminal, so it is
/// run under `script(1)`, which hands it a pseudo-terminal while still piping
/// the output here. Second, it need not have *exited* for the token to be on
/// screen — a TUI that redraws and waits at the end would otherwise cost the
/// user a ten-minute timeout for a token already printed — so the output is
/// scanned as it arrives and the child is stopped the moment the token appears.
///
/// A pty means ANSI escapes and `\r`, and a token carrying control characters is
/// a bad paste rather than a token — it must be clean before it is saved. So the
/// scan runs over text with the escapes stripped, and matches the token shape
/// rather than a line position, which no redraw can move.
public enum ClaudeSetupTokenMinter {

    /// How long to wait for a person to finish a browser flow before giving up.
    public static let timeout: TimeInterval = 600

    /// Mints a token and returns it. Throws `CLIError.noTokenInOutput` with
    /// what the command actually said when none appeared — a refusal from
    /// `claude` (no subscription, not logged in) is far more useful in front of
    /// the user than "minting failed".
    public static func mint() async throws -> String {
        guard let claude = ClaudeAuthCLI.claudeBinary() else {
            throw ClaudeAuthCLI.CLIError.binaryNotFound("claude")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        // `-q` suppresses script's own start/stop banner; /dev/null is the
        // typescript file we don't want. Everything after is the command.
        process.arguments = ["-q", "/dev/null", claude, "setup-token"]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "AGENTIC_TOOLKIT_HEADLESS": "1"
        ]) { _, new in new }

        let outputPipe = Pipe()
        // An open-but-silent stdin: a TUI handed a closed stdin can decide it
        // is not interactive and bail before it ever opens the browser.
        let stdinPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        let transcript = TranscriptBox()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { transcript.append(chunk) }
        }

        do {
            try process.run()
        } catch {
            throw ClaudeAuthCLI.CLIError.launchFailed(error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(timeout)
        var found: String?
        while found == nil {
            if let token = token(in: transcript.text) {
                found = token
                break
            }
            if !process.isRunning { break }
            if Date() >= deadline {
                process.terminate()
                break
            }
            try? await Task.sleep(for: .milliseconds(250))
        }

        if process.isRunning { process.terminate() }
        await waitForExit(process)
        outputPipe.fileHandleForReading.readabilityHandler = nil
        // One last look: the child may have printed the token in the same
        // breath as it exited, after the final poll.
        let text = transcript.text
        guard let token = found ?? self.token(in: text) else {
            throw ClaudeAuthCLI.CLIError.noTokenInOutput(
                readable(text).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return token
    }

    // MARK: - Reading a pty's mind

    /// Anthropic's token shape: `sk-ant-<kind>-<secret>`. Matched by shape and
    /// not by line, because a redrawing TUI moves lines and this cannot be
    /// moved.
    private static let tokenPattern = try? NSRegularExpression(
        pattern: "sk-ant-[A-Za-z0-9]+-[A-Za-z0-9_-]{20,}")

    public static func token(in transcript: String) -> String? {
        let text = readable(transcript)
        guard let tokenPattern else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = tokenPattern.firstMatch(in: text, range: range),
              let matched = Range(match.range, in: text)
        else { return nil }
        return String(text[matched])
    }

    /// A pty transcript with the escape sequences taken out, so a token is not
    /// split by a colour change and `save` is never handed a control character.
    public static func readable(_ transcript: String) -> String {
        var out = ""
        out.reserveCapacity(transcript.count)
        var iterator = transcript.makeIterator()
        var pending: Character?
        while let character = pending ?? iterator.next() {
            pending = nil
            guard character == "\u{1B}" else {
                out.append(character == "\r" ? "\n" : character)
                continue
            }
            // CSI/OSC and friends: skip the introducer, then everything up to
            // the first byte that can end the sequence.
            guard let next = iterator.next() else { break }
            if next == "[" || next == "]" || next == "(" || next == ")" {
                while let scan = iterator.next() {
                    if scan == "\u{07}" { break }                       // OSC bell terminator
                    if scan.isLetter || scan == "@" || scan == "~" { break }
                }
            }
        }
        return out
    }

    private static func waitForExit(_ process: Process) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .utility).async {
                process.waitUntilExit()
                continuation.resume()
            }
        }
    }

    /// The child writes from a background queue while the poll loop reads; one
    /// lock covers both.
    private final class TranscriptBox: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func append(_ chunk: Data) {
            lock.lock()
            data.append(chunk)
            lock.unlock()
        }

        /// The transcript so far, or "" while the child has emitted nothing
        /// decodable — the poll loop reads this mid-stream, so a chunk cut
        /// through a multi-byte character is normal and simply reads as empty
        /// until the rest of it arrives.
        var text: String {
            lock.lock()
            defer { lock.unlock() }
            return String(bytes: data, encoding: .utf8) ?? ""
        }
    }
}
