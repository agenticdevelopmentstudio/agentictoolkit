import Foundation
import Testing
@testable import AgenticToolkitCore

@Suite("SubprocessChannel.run", .serialized)
struct SubprocessChannelRunTests {
    private static let budget: TimeInterval = 5

    @Test("captures standard output and a zero exit status")
    func capturesOutput() async throws {
        let configuration = SubprocessChannel.Configuration(
            executableURL: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["hello"]
        )
        let result = try await SubprocessChannel.run(configuration, budget: Self.budget)
        #expect(String(bytes: result.standardOutput, encoding: .utf8) == "hello\n")
        #expect(result.exitStatus == 0)
        #expect(result.duration >= 0)
    }

    @Test("reports a non-zero exit status without throwing")
    func nonZeroExit() async throws {
        let configuration = SubprocessChannel.Configuration(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo oops 1>&2; exit 3"]
        )
        let result = try await SubprocessChannel.run(configuration, budget: Self.budget)
        #expect(result.exitStatus == 3)
        #expect(result.standardError.contains("oops"))
    }

    @Test("throws WallClockBudgetExceeded when the budget elapses")
    func budgetExceeded() async {
        let configuration = SubprocessChannel.Configuration(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["5"]
        )
        await #expect(throws: WallClockBudgetExceeded.self) {
            try await SubprocessChannel.run(configuration, budget: 0.2)
        }
    }

    /// A one-shot capture is not a framed stream, and must not be held to a
    /// framed stream's rules. `git status --porcelain -z` on a large
    /// repository produces exactly this shape — megabytes of NUL-separated
    /// records with no `0x0A` anywhere — which, decoded as `.newlineDelimited`,
    /// is a single frame over `MessageFramingDecoder.maximumFrameBytes`: the
    /// whole capture was discarded and the caller was told its output was
    /// malformed.
    @Test("captures delimiter-free output larger than the framing cap")
    func capturesDelimiterFreeOutputLargerThanTheFramingCap() async throws {
        let byteCount = MessageFramingDecoder.maximumFrameBytes + 1024
        let configuration = SubprocessChannel.Configuration(
            executableURL: URL(fileURLWithPath: "/usr/bin/head"),
            arguments: ["-c", "\(byteCount)", "/dev/zero"]
        )
        let result = try await SubprocessChannel.run(configuration, budget: Self.budget)
        #expect(result.exitStatus == 0)
        #expect(result.standardOutput.count == byteCount)
        #expect(result.standardOutput.allSatisfy { $0 == 0 })
    }

    /// The framing a caller happens to have configured describes how it would
    /// talk to a *long-lived* peer; a one-shot run has no messages for it to
    /// describe. Honouring it here would make an ordinary capture fail on the
    /// framing's own end-of-stream rules — `.contentLength` treats output with
    /// no header as a malformed one.
    @Test("ignores the configured framing")
    func ignoresTheConfiguredFraming() async throws {
        let configuration = SubprocessChannel.Configuration(
            executableURL: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["hello"],
            framing: .contentLength
        )
        let result = try await SubprocessChannel.run(configuration, budget: Self.budget)
        #expect(String(bytes: result.standardOutput, encoding: .utf8) == "hello\n")
        #expect(result.exitStatus == 0)
    }

    @Test("runs in the configured working directory")
    func workingDirectory() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("subprocess-run-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = SubprocessChannel.Configuration(
            executableURL: URL(fileURLWithPath: "/bin/pwd"),
            currentDirectoryURL: directory
        )
        let result = try await SubprocessChannel.run(configuration, budget: Self.budget)
        let printed = (String(bytes: result.standardOutput, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(URL(fileURLWithPath: printed).resolvingSymlinksInPath().path
                == directory.resolvingSymlinksInPath().path)
    }
}
