import AppKit
import XCTest
@testable import AgenticToolkitMacOS

/// The two obligations a `.terminateLater` carries: exactly one reply, and a
/// reply even when the flush never arrives.
///
/// Every coordinator here is built with a reply closure of its own —
/// `reply(toApplicationShouldTerminate:)` with no termination pending is not a
/// defined thing to do to a test runner.
@MainActor
final class ApplicationShutdownCoordinatorTests: XCTestCase {

    /// What the closures did, held on the main actor rather than in captured
    /// locals: the closures outlive the call that made them.
    @MainActor
    private final class Log {
        var replies: [Bool] = []
        var flushes = 0
        var finishes = 0
    }

    func testTheFlushRunsAndTheReplyFollowsIt() async {
        let log = Log()
        let coordinator = ApplicationShutdownCoordinator(reply: { log.replies.append($0) })

        let answer = coordinator.begin {
            log.flushes += 1
        } then: {
            log.finishes += 1
        }

        XCTAssertEqual(answer, .terminateLater)
        XCTAssertTrue(coordinator.isTerminating)
        await Task.yield()
        XCTAssertEqual(log.flushes, 1)
        XCTAssertEqual(log.finishes, 1, "`then` runs before the reply, not after the process has gone")
        XCTAssertEqual(log.replies, [true])
    }

    /// A second quit gesture inside the budget — an impatient ⌘Q, a Dock
    /// "Quit", a logout — must not start a second flush racing the first, and
    /// must not add a second reply to the one already owed.
    func testASecondBeginNeitherFlushesAgainNorRepliesAgain() async {
        let log = Log()
        let coordinator = ApplicationShutdownCoordinator(reply: { log.replies.append($0) })

        XCTAssertEqual(coordinator.begin(flush: { log.flushes += 1 }), .terminateLater)
        XCTAssertEqual(coordinator.begin(flush: { log.flushes += 1 }), .terminateLater)
        await Task.yield()

        XCTAssertEqual(log.flushes, 1)
        XCTAssertEqual(log.replies, [true])
    }

    /// A flush that never finishes must not leave an app that cannot be quit.
    /// The budget replies on its behalf and cancels it, and the cancelled
    /// flush adds no second reply on its way out.
    func testAWedgedFlushStillQuitsOnceTheBudgetRunsOut() async throws {
        let log = Log()
        let coordinator = ApplicationShutdownCoordinator(
            flushBudget: .milliseconds(20),
            reply: { log.replies.append($0) }
        )

        coordinator.begin {
            // Cancelled by the budget: the sleep throws and the flush ends
            // without ever reaching its own `finish`.
            try? await Task.sleep(for: .seconds(60))
            log.flushes += 1
        } then: {
            log.finishes += 1
        }

        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(log.replies, [true], "the quit must go through even with writes outstanding")
        XCTAssertEqual(log.finishes, 1)
    }
}
