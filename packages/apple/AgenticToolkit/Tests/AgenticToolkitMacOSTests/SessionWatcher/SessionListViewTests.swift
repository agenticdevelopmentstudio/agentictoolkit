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

    /// Agents report in tables; the row showed every pipe and dash of the rule.
    func testOutputLineShowsATableAsItsCells() {
        XCTAssertEqual(
            Row.plainText(fromMarkdown: "Wrote:\n\n| File | What |\n|---|---|\n| `a.md` | the **notes** |\n\nDone."),
            "Wrote: File What a.md the notes Done."
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

    // MARK: - Terminal block

    /// The output reads like a terminal: a "> " prompt in its own colour, then the text.
    func testTerminalTextLeadsWithAPrompt() {
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let text = Row.terminalText("all green", font: font, promptColor: .systemBlue, textColor: .systemGray)

        XCTAssertEqual(text.string, "> all green")
        XCTAssertEqual(text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .systemBlue)
        XCTAssertEqual(text.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor, .systemGray)
    }

    /// Wrapped lines hang under the text, not under the prompt, so the prompt stands
    /// alone in the left margin the way a shell's does.
    func testTerminalTextHangsWrappedLinesUnderTheText() throws {
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let text = Row.terminalText("x", font: font, promptColor: .systemBlue, textColor: .systemGray)
        let style = try XCTUnwrap(text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        let promptWidth = ("> " as NSString).size(withAttributes: [.font: font]).width

        XCTAssertEqual(style.firstLineHeadIndent, 0)
        XCTAssertEqual(style.headIndent, ceil(promptWidth))
    }

    /// The output and summary are sized in whole lines of their font, which is what
    /// keeps every row the same height whatever its text.
    func testHeightOfLinesIsWholeLinesOfTheFont() {
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let one = NSLayoutManager().defaultLineHeight(for: font)

        XCTAssertEqual(Row.height(ofLines: 4, in: font), ceil(one * 4))
        XCTAssertGreaterThan(Row.height(ofLines: 4, in: font), Row.height(ofLines: 2, in: font))
    }

    // MARK: - Breadcrumb width

    private func makeRow(branch: String = "", name: String = "") -> Row {
        let session = SessionWatcher.SessionWatcherSession(
            sessionId: "row",
            cwd: "/Users/me/stenographer",
            gitBranch: branch,
            termProgram: "iTerm.app",
            projectRoot: "/Users/me/stenographer",
            sessionName: name
        )
        return Row(
            session: session, onTap: nil, isSummarizing: false,
            onSummarize: nil, isFrontmost: false, summariesEnabled: false
        )
    }

    /// The window is kept at least this wide, so it has to grow with every segment of
    /// the breadcrumb — a longer branch or session name needs a wider window.
    func testMinimumWidthGrowsWithTheBreadcrumb() {
        let bare = makeRow().minimumWidth
        let branched = makeRow(branch: "session-window").minimumWidth
        let named = makeRow(branch: "session-window", name: "rearrange the session window").minimumWidth

        XCTAssertGreaterThan(bare, 0)
        XCTAssertGreaterThan(branched, bare)
        XCTAssertGreaterThan(named, branched)
    }

    /// At its minimum width the row lays the breadcrumb out whole: no segment is
    /// narrower than its text.
    func testBreadcrumbFitsAtTheMinimumWidth() {
        let row = makeRow(branch: "session-window", name: "rearrange the session window")
        row.frame = NSRect(x: 0, y: 0, width: row.minimumWidth, height: 200)
        row.layoutSubtreeIfNeeded()

        for label in row.breadcrumb.segmentLabels {
            XCTAssertGreaterThanOrEqual(ceil(label.frame.width) + 0.5, ceil(label.intrinsicContentSize.width),
                                        "\(label.stringValue) was truncated at the row's minimum width")
        }
    }

    /// Every breadcrumb segment is the same size, whatever its colour.
    func testBreadcrumbSegmentsShareOneFont() {
        let row = makeRow(branch: "session-window", name: "tidy")
        let fonts = row.breadcrumb.segmentLabels.compactMap { $0.font?.pointSize }

        XCTAssertEqual(fonts.count, 3)
        XCTAssertEqual(Set(fonts).count, 1)
    }

    private func makeSession(branch: String, name: String) -> SessionWatcher.SessionWatcherSession {
        SessionWatcher.SessionWatcherSession(
            sessionId: "row",
            cwd: "/Users/me/stenographer",
            gitBranch: branch,
            termProgram: "iTerm.app",
            projectRoot: "/Users/me/stenographer",
            sessionName: name
        )
    }

    /// Checking out another branch, or renaming the session, changes a label's text
    /// and nothing about the row's shape — so it must go down the in-place path.
    /// Refusing it rebuilt the whole list, which resets the scroll, drops the hover
    /// and restarts every spinner.
    func testRenamingABreadcrumbSegmentUpdatesInPlace() {
        let row = makeRow(branch: "main", name: "first name")

        let moved = row.update(
            session: makeSession(branch: "session-window", name: "second name"),
            isSummarizing: false, isFrontmost: false, summariesEnabled: false
        )

        XCTAssertTrue(moved, "a renamed branch or session is new text, not a new shape")
        XCTAssertEqual(row.breadcrumb.contextLabels.last?.stringValue, "session-window")
        XCTAssertEqual(row.breadcrumb.nameLabel?.stringValue, "second name")
    }

    /// A segment that appears or vanishes *is* a shape change: the row has no label
    /// to write into, so the caller has to build a new one.
    func testASegmentAppearingForcesARebuild() {
        let row = makeRow(branch: "main", name: "")

        XCTAssertFalse(
            row.update(
                session: makeSession(branch: "main", name: "now named"),
                isSummarizing: false, isFrontmost: false, summariesEnabled: false
            ),
            "a session name that appeared needs a label the row doesn't have"
        )
    }

    /// With no rows there is no breadcrumb to keep whole, so the list asks for no
    /// width and the host's own floor applies.
    func testListMinimumContentWidthIsZeroWithoutRows() {
        XCTAssertEqual(makeView(FakeViewSource([])).minimumContentWidth, 0)
    }

    /// A legacy scroller takes its width out of the clip view the rows are
    /// pinned to, so the list has to ask for that much more — measured without
    /// it, the widest breadcrumb truncated by a scroller's width.
    func testALegacyScrollerWidensTheMinimumByItsOwnWidth() async throws {
        let view = makeView(FakeViewSource([
            makeSession("alpha", cwd: "/Users/me/projA", projectRoot: "/Users/me/projA")
        ]))
        observedView = view
        let populated = expectation(description: "list populated")
        populatedExpectation = populated
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleContentSizeChanged),
            name: SessionWatcher.SessionListView.contentSizeDidChangeNotification, object: view)
        await viewModel?.reloadSessions()
        await fulfillment(of: [populated], timeout: 3)

        let scroll = try XCTUnwrap(view.subviews.compactMap { $0 as? NSScrollView }.first)
        scroll.scrollerStyle = .overlay
        let overlay = view.minimumContentWidth
        XCTAssertGreaterThan(overlay, 0)
        scroll.scrollerStyle = .legacy
        let legacy = view.minimumContentWidth
        XCTAssertEqual(
            legacy - overlay,
            NSScroller.scrollerWidth(for: scroll.verticalScroller?.controlSize ?? .regular,
                                     scrollerStyle: .legacy),
            accuracy: 0.5)
    }
}
