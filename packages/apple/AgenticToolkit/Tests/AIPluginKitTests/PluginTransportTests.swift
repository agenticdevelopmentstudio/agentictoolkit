import Testing
import Foundation
@testable import AIPluginKit

/// `AIRequestSpec.timeout` is documented as a WALL-CLOCK budget for the whole
/// request. These tests drive the real command transport with a local `/bin/sh`
/// child — hermetic, no network — because an idle-based timeout can never catch a
/// trickling stream that keeps sending bytes.
@Suite("PluginTransport")
struct PluginTransportTests {

    /// Minimal passthrough plugin: each newline-terminated frame becomes one
    /// `textDelta` event.
    private final class LinePlugin: AIPlugin {
        func buildRequest(_ context: AIChatContext) throws -> AIRequestSpec {
            fatalError("unused: specs are built directly in the tests")
        }
        func makeDecoder() -> any AIStreamDecoder { LineDecoder() }
    }

    private final class LineDecoder: AIStreamDecoder {
        func consume(_ data: Data) -> [AIStreamEvent] {
            guard let text = String(bytes: data, encoding: .utf8), !text.isEmpty else { return [] }
            return [.textDelta(text)]
        }
    }

    @Test("spec.timeout cuts off a trickling command by wall clock")
    func wallClockBudgetCutsTricklingCommand() async throws {
        // Emits a line every 50 ms forever: every byte would reset an idle
        // timeout, so only a wall-clock bound can end this stream.
        let spec = AIRequestSpec.command(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "while :; do echo tick; sleep 0.05; done"],
            timeout: 0.5
        )
        let start = Date()
        var sawText = false
        do {
            for try await event in PluginTransport.run(spec: spec, plugin: LinePlugin()) {
                if case .textDelta = event { sawText = true }
            }
            Issue.record("a never-ending trickle must be cut off at the budget")
        } catch let error as PluginTransport.TransportError {
            guard case .timedOut = error else {
                Issue.record("expected timedOut, got \(error)")
                return
            }
        }
        #expect(sawText, "bytes were flowing before the cut-off")
        #expect(Date().timeIntervalSince(start) < 5, "the cut-off is the budget, not an idle timeout")
    }

    @Test("a command that finishes within the budget streams to completion")
    func commandWithinBudgetStreamsToCompletion() async throws {
        let spec = AIRequestSpec.command(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'hello\\n'"],
            timeout: 10
        )
        var reply = ""
        for try await event in PluginTransport.run(spec: spec, plugin: LinePlugin()) {
            if case .textDelta(let text) = event { reply += text }
        }
        #expect(reply.contains("hello"))
    }

    // MARK: - Command-transport behaviour preserved across the SubprocessChannel swap

    /// Surfaces the child's stderr through `describeError`, which the default
    /// implementation does not: it returns `nil`, and `PluginTransport` then
    /// falls back to "Command exited with status N". A test using the default
    /// could not tell a captured stderr from a discarded one.
    private final class StderrReportingPlugin: AIPlugin {
        func buildRequest(_ context: AIChatContext) throws -> AIRequestSpec {
            fatalError("unused: specs are built directly in the tests")
        }
        func makeDecoder() -> any AIStreamDecoder { LineDecoder() }
        func describeError(status: Int, body: Data) -> String? {
            "status \(status): \(String(bytes: body, encoding: .utf8) ?? "")"
        }
    }

    /// Runs `spec` to completion and returns the concatenated `textDelta`s.
    private func collectText(
        _ spec: AIRequestSpec,
        plugin: any AIPlugin = LinePlugin()
    ) async throws -> String {
        var text = ""
        for try await event in PluginTransport.run(spec: spec, plugin: plugin) {
            if case .textDelta(let delta) = event { text += delta }
        }
        return text
    }

    /// `/bin/cat` is the strictest available assertion about stdin: what it
    /// reads is what it writes, so the reply *is* the bytes the child was
    /// given.
    ///
    /// Two things are pinned here. The payload ends without a newline, so a
    /// transport that framed it — `send()` appends the `.newlineDelimited`
    /// delimiter, `sendRaw()` does not — comes back one byte longer. And
    /// `cat` only ever reaches EOF because stdin is closed behind the write,
    /// so dropping `closeInput()` turns this into a hang that the budget ends.
    @Test("stdin reaches the child byte for byte, with no delimiter appended")
    func stdinIsWrittenUnframedAndThenClosed() async throws {
        let payload = "first line\nsecond line, no trailing newline"
        let spec = AIRequestSpec.command(
            executableURL: URL(fileURLWithPath: "/bin/cat"),
            stdin: Data(payload.utf8),
            timeout: 10
        )

        let reply = try await collectText(spec)
        #expect(reply == payload)
    }

    /// A non-zero exit is an error for this transport, and the error has to
    /// carry both halves of the diagnosis: the status, and what the child said
    /// on stderr. Losing the second leaves a plugin author with "exited with
    /// status 3" and nothing else.
    @Test("a non-zero exit becomes commandFailed carrying the status and the child's stderr")
    func nonZeroExitCarriesStatusAndStandardError() async throws {
        let spec = AIRequestSpec.command(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo boom >&2; exit 3"],
            timeout: 10
        )

        do {
            _ = try await collectText(spec, plugin: StderrReportingPlugin())
            Issue.record("a child exiting non-zero must fail the stream")
        } catch let error as PluginTransport.TransportError {
            guard case .commandFailed(let status, let message) = error else {
                Issue.record("expected commandFailed, got \(error)")
                return
            }
            #expect(status == 3)
            #expect(
                message.contains("boom"),
                "the child's stderr must reach describeError; got \(message)"
            )
        }
    }

    /// `.command`'s environment **replaces** the parent's rather than merging
    /// over it, which is the opposite of what the MCP side wants and the
    /// reason `SubprocessChannel.EnvironmentPolicy` is a parameter at all. A
    /// plugin handing over a minimal environment is isolating its child on
    /// purpose; quietly merging the host's back in would hand a plugin
    /// subprocess every secret in this process's environment.
    ///
    /// The probe variable is planted in *this* process rather than assumed:
    /// asserting on a real variable like `PATH` would be unsound, because a
    /// shell invents one for itself when it is missing.
    @Test("a non-empty environment replaces the parent's rather than merging over it")
    func environmentReplacesRatherThanMergesOverTheParent() async throws {
        let parentOnly = "WHIPPET_PARENT_ONLY_"
            + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        setenv(parentOnly, "1", 1)
        defer { unsetenv(parentOnly) }

        // `/usr/bin/env` directly, not through a shell: a shell would add
        // variables of its own and blur what the child actually inherited.
        let spec = AIRequestSpec.command(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            environment: ["WHIPPET_PLUGIN_PROBE": "present"],
            timeout: 10
        )

        let childEnvironment = try await collectText(spec)
        #expect(
            childEnvironment.contains("WHIPPET_PLUGIN_PROBE=present"),
            "the plugin's own variable must reach the child"
        )
        #expect(
            !childEnvironment.contains(parentOnly),
            "a parent variable the plugin never asked for reached the child: \(childEnvironment)"
        )
    }
}
