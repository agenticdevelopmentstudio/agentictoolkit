import XCTest
@testable import AgenticToolkitMacOS

final class SessionWatcherSessionActivityTests: XCTestCase {

    private func activity(
        _ lastEventType: String,
        status: SessionWatcher.SessionWatcherStatus = .active
    ) -> SessionWatcher.SessionWatcherActivity {
        SessionWatcher.SessionWatcherSession(sessionId: "s", status: status, lastEventType: lastEventType).activity
    }

    /// A turn that ended — normally, on an API error, or cut short by the user — and a
    /// session sitting at its first prompt all read as idle, not working.
    func testFinishedTurnsReadAsIdle() {
        for type in ["Stop", "StopFailure", "Interrupted", "SessionStart", "SessionEnd", ""] {
            XCTAssertEqual(activity(type), .idle, type)
        }
    }

    func testRequestsForTheUserReadAsWaiting() {
        for type in ["Notification", "PermissionRequest", "Elicitation"] {
            XCTAssertEqual(activity(type), .waiting, type)
        }
    }

    func testTurnInFlightReadsAsWorking() {
        for type in ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure"] {
            XCTAssertEqual(activity(type), .working, type)
        }
    }

    func testAnEndedSessionIsIdleWhateverItLastDid() {
        XCTAssertEqual(activity("PreToolUse", status: .ended), .idle)
    }
}
