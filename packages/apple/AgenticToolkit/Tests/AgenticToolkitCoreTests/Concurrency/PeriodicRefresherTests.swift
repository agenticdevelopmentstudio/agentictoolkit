import XCTest
@testable import AgenticToolkitCore

@MainActor
final class PeriodicRefresherTests: XCTestCase {

    private final class Owner {
        var passes = 0
    }

    func testRunsAtOnceThenEveryInterval() async throws {
        let owner = Owner()
        let refresher = PeriodicRefresher(interval: 0.02)
        refresher.start(for: owner) { $0.passes += 1 }
        XCTAssertTrue(refresher.isRunning)

        let deadline = Date().addingTimeInterval(5)
        while owner.passes < 3, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertGreaterThanOrEqual(owner.passes, 3)

        refresher.stop()
        XCTAssertFalse(refresher.isRunning)
        let stopped = owner.passes
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(owner.passes, stopped, "no pass starts after stop()")
    }

    /// The owner is held weakly: a model nobody keeps is freed without `stop()`.
    func testDoesNotKeepItsOwnerAlive() async throws {
        let refresher = PeriodicRefresher(interval: 0.02)
        weak var released: Owner?
        do {
            let owner = Owner()
            released = owner
            refresher.start(for: owner) { $0.passes += 1 }
        }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(released)
        refresher.stop()
    }
}
