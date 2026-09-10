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
    public static func run(_ configuration: Configuration, budget: TimeInterval) async throws -> RunResult {
        let channel = SubprocessChannel(configuration: configuration)
        let started = Date()
        do {
            return try await withWallClockBudget(budget) {
                try await channel.launch()
                await channel.closeInput()
                // `.newlineDelimited` frames already carry their own trailing
                // `0x0A` (see `MessageFramingDecoder.consumeNewlineDelimited`,
                // which cuts each frame through and including the delimiter,
                // and `finish()`, which returns a final unterminated remainder
                // verbatim). So concatenating frames as they arrive reproduces
                // the child's raw stdout byte-for-byte; inserting a separator
                // between frames would double every newline that was already
                // present in the stream.
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
                let status = await channel.waitUntilExit()
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
