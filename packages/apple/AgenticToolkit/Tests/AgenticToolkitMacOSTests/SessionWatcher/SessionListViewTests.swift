import XCTest
import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS
@testable import AgenticToolkitMacOS

/// Minimal `SessionListSource` double for driving the view's Combine bindings.
private final class FakeViewSource: SessionWatcher.SessionListSource, @unchecked Sendable {
    var sessions: [SessionWatcher.SessionWatcherSession]
    private var onChange: (@Sendable () -> Void)?

    init(_ sessions: [SessionWatcher.SessionWatcherSession]) { self.sessions = sessions }
    func fetchSessions() async throws -> [SessionWatcher.SessionWatcherSession] { sessions }
    func startObserving(onChange: @escaping @Sendable () -> Void) { self.onChange = onChange }
    func stopObserving() { onChange = nil }
}

@MainActor
final class SessionListViewTests: XCTestCase {

    /// Held so tearDown can stop the timers/observer the view model starts in init.
    private var viewModel: SessionWatcher.SessionListViewModel?

    /// Wiring for `testPopulatedListReportsStackHeight`'s content-size observer.
    private var observedView: SessionWatcher.SessionListView?
    private var populatedExpectation: XCTestExpectation?

    override func tearDown() async throws {
        viewModel?.stopListening()
        viewModel = nil
        // The content-size observer registered with `object:` the (now-discarded)
        // view is auto-removed on dealloc; no explicit detachment needed.
        observedView = nil
        populatedExpectation = nil
        try await super.tearDown()
    }

    private func makeSession(_ id: String, cwd: String, projectRoot: String) -> SessionWatcher.SessionWatcherSession {
        SessionWatcher.SessionWatcherSession(
            sessionId: id,
            cwd: cwd,
            startedAt: "2026-01-01T00:00:01Z",
            status: .active,
            termProgram: "iTerm.app",
            projectRoot: projectRoot
        )
    }

    private func makeView(_ source: FakeViewSource) -> SessionWatcher.SessionListView {
        let viewModel = SessionWatcher.SessionListViewModel(source: source, settingsStore: UserSettings.shared)
        self.viewModel = viewModel
        let view = SessionWatcher.SessionListView(viewModel: viewModel)
        // Give it a concrete width so width-dependent layout (card widths, wrapping)
        // resolves when computing fitting sizes.
        view.frame = NSRect(x: 0, y: 0, width: 340, height: 600)
        return view
    }

    /// The empty state must claim a real footprint, not zero — otherwise the host
    /// window collapses the list area and the centered content overflows the header.
    func testEmptyStateViewVendsDisplayableHeight() {
        let emptyState = SessionWatcher.SessionWatcherEmptyStateView()
        let height = emptyState.intrinsicContentSize.height
        XCTAssertEqual(height, SessionWatcher.SessionWatcherEmptyStateView.preferredHeight)
        XCTAssertGreaterThanOrEqual(height, 60,
                                    "empty state needs enough height to show the icon + label uncrushed")
    }

    /// Regression for the "mangled empty UI" bug: with no sessions the list view
    /// reported the empty stack's collapsed inset height (~12pt), shrinking the host
    /// window's list area to nothing so the centered "No Active Sessions" content
    /// overflowed up into the header. It must instead report the empty-state height.
    func testEmptyListReportsEmptyStateHeightNotCollapsed() {
        let view = makeView(FakeViewSource([]))

        // Right after construction (before the async binding runs) there are no
        // session cards, so the empty state is what would be shown.
        XCTAssertTrue(view.intrinsicContentSize.height >= SessionWatcher.SessionWatcherEmptyStateView.preferredHeight,
                      "empty list must report at least the empty-state height, not a collapsed inset height")
    }

    /// Fulfills the populated expectation once the observed list has resized past
    /// the empty-state height. Selector-based (not a `@Sendable` closure) so it can
    /// touch the main-actor view; the production window controller observes the same
    /// notification the same way.
    @objc private func handleContentSizeChanged() {
        guard let view = observedView,
              view.intrinsicContentSize.height > SessionWatcher.SessionWatcherEmptyStateView.preferredHeight
        else { return }
        populatedExpectation?.fulfill()
        populatedExpectation = nil
    }

    /// Once sessions exist the list must size to the rendered cards, not the
    /// empty-state height — i.e. the empty branch only applies when truly empty.
    func testPopulatedListReportsStackHeight() async {
        let view = makeView(FakeViewSource([
            makeSession("alpha", cwd: "/Users/me/projA", projectRoot: "/Users/me/projA"),
            makeSession("bravo", cwd: "/Users/me/projB", projectRoot: "/Users/me/projB")
        ]))
        observedView = view

        let populated = expectation(description: "list populated and resized")
        populatedExpectation = populated
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleContentSizeChanged),
            name: SessionWatcher.SessionListView.contentSizeDidChangeNotification,
            object: view
        )
        await viewModel?.reloadSessions()
        await fulfillment(of: [populated], timeout: 3)

        XCTAssertGreaterThan(view.intrinsicContentSize.height,
                             SessionWatcher.SessionWatcherEmptyStateView.preferredHeight,
                             "a populated list should size to its cards, not the empty-state height")
    }

    // MARK: - Last-output line

    private typealias Row = SessionWatcher.SessionWatcherRowAppKitView

    /// The row's one-line preview showed the agent's markdown verbatim —
    /// `**Shipped.**`, backticked hashes, list dashes.
    func testOutputLineShowsMarkdownAsPlainText() {
        XCTAssertEqual(
            Row.plainText(fromMarkdown: "**Shipped.** Both landed on `main`:\n- **`c4c2ed2`** fix it\n- `abc123` more"),
            "Shipped. Both landed on main: c4c2ed2 fix it abc123 more"
        )
    }

    /// The parser drops block boundaries, so without a separator a heading ran
    /// straight into the paragraph beneath it.
    func testOutputLineKeepsBlocksApart() {
        XCTAssertEqual(
            Row.plainText(fromMarkdown: "# Done\nSome *text*, a [link](https://x.io).\n\n```\nlet x = 1\n```\nAfter."),
            "Done Some text, a link. let x = 1 After."
        )
    }

    /// A single-line label only ever showed a multi-line message's first line.
    func testOutputLineJoinsPlainLines() {
        XCTAssertEqual(Row.plainText(fromMarkdown: "line one\nline two\n\n  line three  "),
                       "line one line two line three")
    }

    func testOutputLineShowsUnbalancedMarkupAsWritten() {
        XCTAssertEqual(Row.plainText(fromMarkdown: "unbalanced **bold"), "unbalanced **bold")
    }

    func testOutputLinePlaceholderForASilentSession() {
        let session = makeSession("quiet", cwd: "/Users/me/p", projectRoot: "/Users/me/p")
        XCTAssertEqual(Row.outputText(for: session), "No output yet.")
    }
}
