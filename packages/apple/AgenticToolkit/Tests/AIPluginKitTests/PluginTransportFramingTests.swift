import Testing
import Foundation
@testable import AIPluginKit

/// The framing parity that matters for the command transport.
///
/// `PluginTransport` used to frame a child's stdout with its own byte pump:
/// accumulate bytes, cut a frame at every `0x0A` *including* that byte, and
/// hand any unterminated remainder to the decoder before flushing it. It now
/// delegates that to `SubprocessChannel`'s `.newlineDelimited` framing. The
/// decoder must not be able to tell the difference.
///
/// This suite is the automated substitute for watching a multi-line reply
/// arrive in the UI with its line breaks intact: strip the trailing newline
/// anywhere in the framing path and `PlainTextDecoder` sees one run-on
/// paragraph. Here it shows up as the very first payload comparing unequal.
@Suite("PluginTransport framing parity")
struct PluginTransportFramingTests {

    /// Thread-safe record of every payload the decoder was handed. The decoder
    /// is created and driven inside `PluginTransport`'s own task, so the test
    /// reads this from a different isolation domain than the one writing it.
    private final class FrameLog: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [Data] = []
        private var finished = false

        func record(_ data: Data) {
            lock.lock()
            defer { lock.unlock() }
            storage.append(data)
        }

        func markFinished() {
            lock.lock()
            defer { lock.unlock() }
            finished = true
        }

        var payloads: [Data] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        var didFinish: Bool {
            lock.lock()
            defer { lock.unlock() }
            return finished
        }
    }

    private final class RecordingDecoder: AIStreamDecoder {
        private let log: FrameLog

        init(log: FrameLog) { self.log = log }

        func consume(_ data: Data) -> [AIStreamEvent] {
            log.record(data)
            guard let text = String(bytes: data, encoding: .utf8), !text.isEmpty else { return [] }
            return [.textDelta(text)]
        }

        func finish() -> [AIStreamEvent] {
            log.markFinished()
            return []
        }
    }

    private final class RecordingPlugin: AIPlugin {
        private let log: FrameLog

        init() { self.log = FrameLog() }
        init(log: FrameLog) { self.log = log }

        func buildRequest(_ context: AIChatContext) throws -> AIRequestSpec {
            fatalError("unused: specs are built directly in the tests")
        }

        func makeDecoder() -> any AIStreamDecoder { RecordingDecoder(log: log) }
    }

    /// Three newline-terminated lines then an unterminated trailing fragment
    /// must reach the decoder as exactly four payloads, the first three
    /// keeping their `0x0A`, followed by one `finish()`.
    @Test("stdout reaches the decoder as newline-terminated frames plus a trailing fragment")
    func commandFramingMatchesOldBytePump() async throws {
        let log = FrameLog()
        let spec = AIRequestSpec.command(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'a\\nb\\nc\\ntail'"],
            timeout: 10
        )

        var reply = ""
        for try await event in PluginTransport.run(spec: spec, plugin: RecordingPlugin(log: log)) {
            if case .textDelta(let text) = event { reply += text }
        }

        let payloads = log.payloads.map { String(bytes: $0, encoding: .utf8) ?? "" }
        #expect(payloads == ["a\n", "b\n", "c\n", "tail"])
        #expect(log.didFinish, "the decoder is still flushed once the child's output ends")
        #expect(reply == "a\nb\nc\ntail", "the reassembled reply keeps every line break")
    }

    /// A child whose output ends *with* a newline must not produce a spurious
    /// empty final frame — the old pump only forwarded a remainder when one
    /// was actually left over.
    @Test("output ending in a newline produces no trailing empty frame")
    func trailingNewlineProducesNoEmptyFrame() async throws {
        let log = FrameLog()
        let spec = AIRequestSpec.command(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf 'one\\ntwo\\n'"],
            timeout: 10
        )

        for try await _ in PluginTransport.run(spec: spec, plugin: RecordingPlugin(log: log)) {}

        let payloads = log.payloads.map { String(bytes: $0, encoding: .utf8) ?? "" }
        #expect(payloads == ["one\n", "two\n"])
    }
}
