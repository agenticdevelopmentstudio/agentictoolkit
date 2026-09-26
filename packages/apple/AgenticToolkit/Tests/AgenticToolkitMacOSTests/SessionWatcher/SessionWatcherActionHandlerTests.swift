import XCTest
import AgenticToolkitCore
import AgenticToolkitPermissions
@testable import AgenticToolkitMacOS

@MainActor
final class SessionWatcherActionHandlerTests: XCTestCase {

    /// A session in a terminal nothing knows how to reach: no iTerm2 or
    /// Terminal.app tab to select, no bundle to bring forward — so activation
    /// falls all the way through to the Accessibility window scan.
    private func unreachableSession() -> SessionWatcher.SessionWatcherSession {
        SessionWatcher.SessionWatcherSession(
            sessionId: "s1",
            cwd: "/Users/me/project",
            startedAt: "",
            status: .active,
            termProgram: "NoSuchTerminal",
            projectRoot: ""
        )
    }

    private func makeHandler(
        usesAccessibility: Bool,
        probe: TrustProbe
    ) -> SessionWatcher.SessionWatcherActionHandler {
        SessionWatcher.SessionWatcherActionHandler(
            settingsStore: UserSettings.shared,
            usesAccessibility: usesAccessibility,
            isAccessibilityTrusted: { probe.check() }
        )
    }

    func testHandlerUsesNoAccessibilityByDefault() {
        let handler = SessionWatcher.SessionWatcherActionHandler(settingsStore: UserSettings.shared)
        XCTAssertFalse(handler.usesAccessibility)
    }

    func testActivationNeverProbesAccessibilityUnlessTheHostOptsIn() {
        // `AXIsProcessTrusted()` from an app without the grant stalls tccd, and
        // with it the whole machine, for ~10s. An opted-out host must not make
        // that call even when every permission-free route has missed.
        let probe = TrustProbe()
        let handler = makeHandler(usesAccessibility: false, probe: probe)

        let result = handler.execute(action: .activateWindow, for: unreachableSession())

        XCTAssertEqual(probe.calls, 0)
        guard case .failure(.commandFailed) = result else {
            return XCTFail("expected a plain failure, not a permission prompt: \(result)")
        }
    }

    func testOptedInHostChecksTheGrantBeforeScanningWindows() {
        let probe = TrustProbe()
        let handler = makeHandler(usesAccessibility: true, probe: probe)

        let result = handler.execute(action: .activateWindow, for: unreachableSession())

        XCTAssertEqual(probe.calls, 1)
        guard case .failure(.permissionDenied(_, let permission)) = result else {
            return XCTFail("an untrusted opted-in host should report the missing grant: \(result)")
        }
        XCTAssertEqual(permission, .accessibility)
    }

    func testTheStoredClickActionDefaultIsARealAction() {
        // The default used to be "openTerminal" — not a raw value of any case —
        // so it silently fell back to whatever `currentAction` chose instead.
        let stored = UserSettings.clickAction.defaultValue
        XCTAssertEqual(SessionWatcher.SessionWatcherClickAction(rawValue: stored), .defaultAction)
    }
}
