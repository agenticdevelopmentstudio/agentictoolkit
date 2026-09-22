import XCTest
@testable import AgenticToolkitMacOS

final class SessionWatcherSessionActivityTests: XCTestCase {

    private func activity(
        _ lastEventType: String,
        status: SessionWatcher.SessionWatcherStatus = .active,
        subagentWorking: Bool = false
    ) -> SessionWatcher.SessionWatcherActivity {
        SessionWatcher.SessionWatcherSession(
            sessionId: "s", status: status,
            lastEventType: lastEventType, subagentWorking: subagentWorking
        ).activity
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

    // MARK: - Waiting on a subagent

    /// The main agent has handed back, but a background subagent is still going:
    /// work is in flight, so the row says so.
    func testASessionWaitingOnASubagentReadsAsWorking() {
        for type in ["Stop", "StopFailure", "Interrupted", "SessionStart", ""] {
            XCTAssertEqual(activity(type, subagentWorking: true), .working, type)
        }
    }

    /// A session blocked on a permission prompt still needs the user, whatever its
    /// subagents are doing — the quieter reading must not bury the louder one.
    func testALiveSubagentNeverOverridesWaiting() {
        for type in ["Notification", "PermissionRequest", "Elicitation"] {
            XCTAssertEqual(activity(type, subagentWorking: true), .waiting, type)
        }
    }

    func testAnEndedSessionIsIdleEvenWithASubagentStampLeftBehind() {
        XCTAssertEqual(activity("Stop", status: .ended, subagentWorking: true), .idle)
    }
}
