import Foundation

extension SubprocessChannel {
    /// What a one-shot command produced.
    public struct RunResult: Sendable {
        public let standardOutput: Data
        public let standardError: String
        public let exitStatus: Int32
        public let duration: TimeInterval

        public init(standardOutput: Data, standardError: String, exitStatus: Int32, duration: TimeInterval) {
            self.standardOutput = standardOutput
            self.standardError = standardError
            self.exitStatus = exitStatus
            self.duration = duration
        }
    }

    /// Launches `configuration`, closes its input, drains standard output until the
    /// child exits, and returns everything it produced. Throws
    /// `WallClockBudgetExceeded` if the child outlives `budget` seconds, in which
    /// case the child is terminated before the error propagates.
    ///
    /// **`configuration.framing` is ignored, deliberately.** A one-shot run has
    /// no messages: it hands back one `Data` holding the whole of stdout, so
    /// there is no boundary any framing could mark and nothing a caller could
    /// do with one. Honouring a framing here would mean subjecting a plain
    /// capture to a *streaming* protocol's malformed-peer guard — the 16 MB
    /// `MessageFramingDecoder.maximumFrameBytes` cap, which fires when no
    /// delimiter has arrived in that many bytes. Output with no `0x0A` in it
    /// at all is then indistinguishable from a peer that has stopped framing,
    /// and git's machine-readable status (`GitClient.status(in:)`, whose records are
    /// NUL-terminated and newline-free) on a large repository is exactly
    /// that: the capture is discarded and the verb fails on output that was
    /// never malformed. The run therefore decodes as
    /// `.unframed`, whose bytes pass straight through.
    public static func run(_ configuration: Configuration, budget: TimeInterval) async throws -> RunResult {
        var configuration = configuration
        configuration.framing = .unframed
        let channel = SubprocessChannel(configuration: configuration)
        let started = Date()
        do {
            return try await withWallClockBudget(budget) {
                try await channel.launch()
                await channel.closeInput()
                // `.unframed` hands each chunk over exactly as it was read, so
                // concatenating them reproduces the child's raw stdout
                // byte-for-byte. Inserting any separator between them would
                // corrupt it.
                var output = Data()
                do {
                    for try await frame in try await channel.messages() {
                        output.append(frame)
                    }
                } catch let error as ChannelError {
                    // `messages()` never actually throws `.exited` today — a
                    // non-zero exit surfaces only through `waitUntilExit()`
                    // below — but tolerate it here too so a future change to
                    // that contract does not turn a clean non-zero exit into
                    // a thrown error for this one-shot caller.
                    guard case .exited = error else { throw error }
                }
                // `waitUntilExit()` refuses to invent a status: an unlaunched
                // channel and a cancelled wait both throw rather than reading
                // as a clean exit. Either one belongs to the caller of a
                // one-shot run, so it propagates through the `catch` below,
                // which terminates the child first.
                let status = try await channel.waitUntilExit()
                let standardError = await channel.standardErrorText()
                return RunResult(
                    standardOutput: output,
                    standardError: standardError,
                    exitStatus: status,
                    duration: Date().timeIntervalSince(started)
                )
            }
        } catch {
            await channel.terminate()
            throw error
        }
    }
}
