import Foundation
import XCTest
@testable import AgenticToolkitMacOS

@MainActor
final class WindowStateNamespaceTests: XCTestCase {

    override func tearDown() {
        WindowStateNamespace.reset()
        super.tearDown()
    }

    func testWindowStateIsUnNamespacedUntilAHostAsksForOne() {
        // The on-disk format every existing installation already has: a new
        // namespace must never be the default, or one toolkit update silently
        // forgets where everyone's windows were.
        XCTAssertEqual(WindowStateNamespace.current, "")
        XCTAssertEqual(WindowStateNamespace.qualify("WindowState_log"), "WindowState_log")
    }

    func testTheNamespaceIsStableForOnePathAndDiffersBetweenTwo() {
        WindowStateNamespace.isolate(toPath: "/a/worktree/Stenographer.app")
        let first = WindowStateNamespace.current
        WindowStateNamespace.isolate(toPath: "/another/worktree/Stenographer.app")
        let second = WindowStateNamespace.current
        WindowStateNamespace.isolate(toPath: "/a/worktree/Stenographer.app")

        // Stable, because a worktree's app must find its own saved layout again
        // on the next launch...
        XCTAssertEqual(WindowStateNamespace.current, first)
        // ...and distinct, because that is the entire point.
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(first.isEmpty)
    }

    func testTheNamespaceDoesNotCarryTheDeveloperSDirectoryNamesIntoPreferences() {
        WindowStateNamespace.isolate(toPath: "/Users/someone/secret-project/Stenographer.app")

        XCTAssertFalse(WindowStateNamespace.current.contains("secret-project"))
        XCTAssertFalse(WindowStateNamespace.current.contains("someone"))
    }

    // MARK: - What the namespace is for

    func testANamespacedInstanceNeitherReadsNorClobbersTheSharedLayout() throws {
        let storage = UserDefaultsWindowStateStorage(
            keyPrefix: "TestWindowState_\(UUID().uuidString)_",
            visibilityKeyPrefix: "TestWindowVisible_\(UUID().uuidString)_")
        addTeardownBlock {
            WindowStateNamespace.reset()
            storage.removeState(for: "log")
            storage.removeVisibility(for: "log")
            WindowStateNamespace.isolate(toPath: "/a/worktree/Stenographer.app")
            storage.removeState(for: "log")
            storage.removeVisibility(for: "log")
            WindowStateNamespace.reset()
        }

        let shared = PersistedWindowState(placements: [:])
        storage.saveState(shared, for: "log")
        storage.saveVisibility(true, for: "log")

        WindowStateNamespace.isolate(toPath: "/a/worktree/Stenographer.app")

        // The second copy starts with no opinion about this window rather than
        // inheriting — and reopening — what the user's own app left visible.
        XCTAssertNil(storage.loadState(for: "log"))
        XCTAssertNil(storage.loadVisibility(for: "log"))
        XCTAssertFalse(storage.visibleWindowIDs().contains("log"))

        storage.saveVisibility(false, for: "log")

        WindowStateNamespace.reset()
        // And writing it did not reach across into the user's layout.
        XCTAssertEqual(storage.loadVisibility(for: "log"), true)
        XCTAssertTrue(storage.visibleWindowIDs().contains("log"))
    }
}
