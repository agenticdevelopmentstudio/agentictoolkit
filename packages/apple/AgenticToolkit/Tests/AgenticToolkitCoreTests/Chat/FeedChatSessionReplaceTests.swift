import XCTest
@testable import AgenticToolkitCore

/// `replaceTranscript` is what a feed pointed at a different conversation uses
/// to change the screen on the keystroke. The read that was running for the
/// previous conversation must never land on top of it.
final class FeedChatSessionReplaceTests: XCTestCase {

    /// A load the test releases by hand, so a read can be caught mid-flight.
    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private(set) var started = 0

        func wait() async {
            await withCheckedContinuation { continuation in
                lock.lock(); defer { lock.unlock() }
                started += 1
                waiters.append(continuation)
            }
        }

        var startedCount: Int { lock.lock(); defer { lock.unlock() }; return started }

        func open() {
            lock.lock()
            let released = waiters
            waiters.removeAll()
            lock.unlock()
            released.forEach { $0.resume() }
        }
    }

    private func message(_ text: String) -> ChatMessage {
        ChatMessage(id: text, role: .assistant, text: text)
    }

    func testReplacedTranscriptPublishesAtOnce() async throws {
        let gate = Gate()
        let old = message("old")
        let session = FeedChatSession(refreshInterval: .seconds(3600)) {
            await gate.wait()
            return [old]
        }
        var events = session.events().makeAsyncIterator()

        let new = message("new")
        session.replaceTranscript([new])

        guard case .transcriptLoaded(let shown)? = await events.next() else {
            return XCTFail("replacing the transcript published nothing")
        }
        XCTAssertEqual(shown.map(\.text), ["new"])
        gate.open()
    }

    func testTheReadRunningAtTheSwitchNeverLands() async throws {
        let gate = Gate()
        let previous = message("previous conversation")
        let session = FeedChatSession(refreshInterval: .seconds(3600)) {
            await gate.wait()
            return [previous]
        }
        let stream = session.events()
        try await waitFor { gate.startedCount == 1 }

        session.replaceTranscript([message("picked conversation")])
        gate.open()
        try await Task.sleep(for: .milliseconds(100))
        session.close()

        var last: [String] = []
        for await event in stream {
            if case .transcriptLoaded(let shown) = event { last = shown.map(\.text) }
        }
        XCTAssertEqual(last, ["picked conversation"],
                       "the read for the previous conversation overwrote the switch")
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "timed out")
    }
}
