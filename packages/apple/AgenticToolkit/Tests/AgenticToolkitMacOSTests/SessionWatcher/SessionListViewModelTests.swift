import XCTest
import Combine
import AgenticToolkitCore
import AgenticToolkitCoreMacOS
@testable import AgenticToolkitMacOS

/// A `SessionListSource` test double: returns canned sessions and lets the test
/// fire the change signal on demand — so the view model can be exercised with no
/// SQLite, no daemon, and no NotificationCenter.
private final class FakeSessionListSource: SessionWatcher.SessionListSource, @unchecked Sendable {
    var sessions: [SessionWatcher.SessionWatcherSession]
    private(set) var isObserving = false
    private var onChange: (@Sendable () -> Void)?

    init(_ sessions: [SessionWatcher.SessionWatcherSession]) {
        self.sessions = sessions
    }

    func fetchSessions() async throws -> [SessionWatcher.SessionWatcherSession] {
        sessions
    }

    func startObserving(onChange: @escaping @Sendable () -> Void) {
        isObserving = true
        self.onChange = onChange
    }

    func stopObserving() {
        isObserving = false
        onChange = nil
    }

    /// Simulate the backing store changing.
    func fireChange() {
        onChange?()
    }
}

@MainActor
final class SessionListViewModelTests: XCTestCase {

    /// The view model under test, tracked so tearDown can stop its timers/observer.
    private var viewModel: SessionWatcher.SessionListViewModel?

    override func tearDown() async throws {
        // Explicit teardown: the view model's init starts two repeating timers and a
        // notification observer. stopListening() tears them down deterministically
        // instead of relying on `deinit` firing promptly when the local goes out of
        // scope (which only holds while the test bodies never spin the run loop).
        viewModel?.stopListening()
        viewModel = nil
        try await super.tearDown()
    }

    private func makeSession(
        _ identifier: String,
        term: String = "iTerm.app",
        cwd: String,
        startedAt: String = "",
        status: SessionWatcher.SessionWatcherStatus = .active,
        projectRoot: String = ""
    ) -> SessionWatcher.SessionWatcherSession {
        SessionWatcher.SessionWatcherSession(
            sessionId: identifier,
            cwd: cwd,
            startedAt: startedAt,
            status: status,
            termProgram: term,
            projectRoot: projectRoot
        )
    }

    private func makeViewModel(
        _ source: FakeSessionListSource
    ) -> SessionWatcher.SessionListViewModel {
        let viewModel = SessionWatcher.SessionListViewModel(source: source, settingsStore: UserSettings.shared)
        self.viewModel = viewModel
        return viewModel
    }

    func testKeepsSessionsOfOneProjectRootAdjacent() async {
        // Two sessions share a project root (one runs in a submodule subdir); a
        // third is a different project. The list is flat, but the two that share a
        // root stay adjacent, regardless of terminal app.
        let source = FakeSessionListSource([
            makeSession("alpha", term: "iTerm.app", cwd: "/Users/me/top",
                        startedAt: "2026-01-01T00:00:01Z", projectRoot: "/Users/me/top"),
            makeSession("bravo", term: "WarpTerminal", cwd: "/Users/me/top/external/sub",
                        startedAt: "2026-01-01T00:00:02Z", projectRoot: "/Users/me/top"),
            makeSession("charlie", term: "iTerm.app", cwd: "/Users/me/other",
                        startedAt: "2026-01-01T00:00:03Z", projectRoot: "/Users/me/other")
        ])

        let viewModel = makeViewModel(source)
        await viewModel.reloadSessions()

        XCTAssertEqual(viewModel.sessionCount, 3)
        XCTAssertEqual(viewModel.activeSessionCount, 3)
        XCTAssertEqual(viewModel.sessions.map(\.sessionId), ["alpha", "bravo", "charlie"])
        // The row's project segment is the project root's name, not the cwd's — the
        // submodule session reads "top", not "sub".
        XCTAssertEqual(viewModel.sessions.map(\.projectGroupName), ["top", "top", "other"])
    }

    func testFallsBackToCwdWhenProjectRootEmpty() async {
        // A session whose project root hasn't been resolved (not a git working
        // tree, or not yet enriched) groups by its cwd.
        let source = FakeSessionListSource([
            makeSession("alpha", cwd: "/Users/me/projA")
        ])

        let viewModel = makeViewModel(source)
        await viewModel.reloadSessions()

        XCTAssertEqual(viewModel.sessions.count, 1)
        XCTAssertEqual(viewModel.sessions[0].projectGroupKey, "/Users/me/projA")
        XCTAssertEqual(viewModel.sessions[0].projectGroupName, "projA")
    }

    func testSortsByStartTimeWithinAndAcrossProjects() async {
        // Sessions arrive out of order; within a project they sort oldest-first, and
        // the projects order by their earliest session's start (so the project whose
        // first session started earliest comes first).
        let source = FakeSessionListSource([
            makeSession("a-late", cwd: "/p/a", startedAt: "2026-01-01T00:00:05Z", projectRoot: "/p/a"),
            makeSession("b-mid", cwd: "/p/b", startedAt: "2026-01-01T00:00:02Z", projectRoot: "/p/b"),
            makeSession("a-early", cwd: "/p/a", startedAt: "2026-01-01T00:00:01Z", projectRoot: "/p/a")
        ])

        let viewModel = makeViewModel(source)
        await viewModel.reloadSessions()

        // Project A's earliest (00:00:01) precedes project B's (00:00:02), and
        // A's own two sessions stay together, oldest first.
        XCTAssertEqual(viewModel.sessions.map(\.sessionId), ["a-early", "a-late", "b-mid"])
    }

    func testExcludesEndedEmptyAndRootCwdSessions() async {
        let source = FakeSessionListSource([
            makeSession("live", term: "iTerm.app", cwd: "/Users/me/projA", status: .active),
            makeSession("ended", term: "iTerm.app", cwd: "/Users/me/projB", status: .ended),
            makeSession("root", term: "iTerm.app", cwd: "/", status: .active),
            makeSession("empty", term: "iTerm.app", cwd: "", status: .active)
        ])

        let viewModel = makeViewModel(source)
        await viewModel.reloadSessions()

        XCTAssertEqual(viewModel.sessionCount, 1)
    }

    func testSubscribesToSourceAndReloadsOnChange() async {
        let source = FakeSessionListSource([])
        let viewModel = makeViewModel(source)

        // The view controller starts observation on viewWillAppear; the model no
        // longer subscribes in init, so drive it explicitly here.
        XCTAssertFalse(source.isObserving, "model should not observe until started")
        viewModel.startListening()
        XCTAssertTrue(source.isObserving, "startListening should subscribe to the source")
        await viewModel.reloadSessions()
        XCTAssertEqual(viewModel.sessionCount, 0)

        // The change signal triggers an async reload; wait for the republished count.
        source.sessions = [makeSession("alpha", term: "iTerm.app", cwd: "/Users/me/projA")]
        let reloaded = expectation(description: "reload after change signal")
        let token = viewModel.$sessionCount
            .dropFirst()
            .sink { if $0 == 1 { reloaded.fulfill() } }
        source.fireChange()
        await fulfillment(of: [reloaded], timeout: 2)
        token.cancel()

        XCTAssertEqual(viewModel.sessionCount, 1, "change signal should trigger a reload")
    }

    func testStopListeningUnsubscribesFromSource() {
        let source = FakeSessionListSource([])
        let viewModel = makeViewModel(source)
        viewModel.startListening()
        XCTAssertTrue(source.isObserving)

        viewModel.stopListening()

        XCTAssertFalse(source.isObserving)
    }

    func testStartListeningIsIdempotent() {
        let source = FakeSessionListSource([])
        let viewModel = makeViewModel(source)
        viewModel.startListening()
        viewModel.startListening()  // second call must not re-subscribe/stack timers
        XCTAssertTrue(source.isObserving)

        // A single stop fully unsubscribes (no leaked second subscription).
        viewModel.stopListening()
        XCTAssertFalse(source.isObserving)
    }
}
