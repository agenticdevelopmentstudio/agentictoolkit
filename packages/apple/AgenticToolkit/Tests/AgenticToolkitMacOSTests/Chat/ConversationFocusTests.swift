// Tests/AgenticToolkitMacOSTests/Chat/ConversationFocusTests.swift
import AppKit
import XCTest
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// Following one conversation inside a merged feed: the control that leaves for
/// it, and the overlay that shows it without leaving at all.
///
/// Every assertion here is about something a build cannot see. A jump control
/// constrained to the wrong edge still lays out, an overlay whose feed was
/// sieved client-side still renders rows, and an overlay that opens on the
/// first click still looks right in a screenshot — until you try to copy a
/// line out of it.
@MainActor
final class ConversationFocusTests: XCTestCase {

    /// Every window a test made, kept alive for its duration — a view whose
    /// window has gone is a view whose layout nobody is maintaining.
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        try await super.tearDown()
    }

    // MARK: - The jump control

    func testTheJumpControlSitsTenPointsOffAnAssistantBubblesInsideEdge() throws {
        let (bubble, button) = try laidOutRow(role: .assistant, text: "a short reply")
        XCTAssertEqual(
            button.frame.minX - bubble.frame.maxX, 10, accuracy: 0.5,
            "the agent's column runs left, so its bubble's inside edge is the trailing one")
    }

    func testTheJumpControlSitsTenPointsOffAUserBubblesInsideEdge() throws {
        let (bubble, button) = try laidOutRow(role: .user, text: "a short prompt")
        XCTAssertEqual(
            bubble.frame.minX - button.frame.maxX, 10, accuracy: 0.5,
            "the human's column runs right, so its bubble's inside edge is the leading one")
    }

    /// "Level with the bubble's top" only differs from "centred on the bubble"
    /// once a bubble is more than one line tall — so the test is that a one-line
    /// bubble and a forty-line one put the control the same distance below their
    /// own top edge.
    func testTheJumpControlSitsLevelWithTheBubblesTopHoweverTallTheBubbleIs() throws {
        let (shortBubble, shortButton) = try laidOutRow(role: .assistant, text: "one line")
        let paragraph = (0..<40).map { "line \($0) of a long reply" }.joined(separator: "\n")
        let (tallBubble, tallButton) = try laidOutRow(role: .assistant, text: paragraph)

        XCTAssertGreaterThan(
            tallBubble.frame.height, shortBubble.frame.height * 4,
            "the fixture is wrong: the bubbles have to differ in height for this to mean anything")

        // Compared on alignment rects, not frames: a bezelled control's frame
        // carries a couple of points of slack its constraints never see, and
        // the constraint is what this is about. Neither view is flipped, so a
        // top edge is a `maxY`.
        func alignedTop(_ view: NSView) -> CGFloat {
            view.alignmentRect(forFrame: view.frame).maxY
        }
        let shortDrop = alignedTop(shortBubble) - alignedTop(shortButton)
        let tallDrop = alignedTop(tallBubble) - alignedTop(tallButton)
        XCTAssertEqual(
            shortDrop, 0, accuracy: 0.5,
            "the control hangs off the bubble's top edge, not its centre")
        XCTAssertEqual(
            shortDrop, tallDrop, accuracy: 0.5,
            "the control follows the bubble's centre, not its top: \(shortDrop) vs \(tallDrop)")
    }

    /// A 44pt control beside a one-line bubble is taller than the row's own
    /// content — and a row's ``ChatTranscriptRowView/hitTest(_:)`` refuses
    /// anything outside its bounds, so a control hanging past the bottom edge
    /// would be drawn and unclickable.
    func testTheRowIsTallEnoughToHoldTheJumpControl() throws {
        let (_, button) = try laidOutRow(role: .assistant, text: "one line")
        let row = try XCTUnwrap(button.superview as? ChatTranscriptRowView)
        XCTAssertTrue(
            row.bounds.contains(button.frame),
            "the jump control hangs outside the row: \(button.frame) in \(row.bounds)")
    }

    func testARowWithNoJumpActionShowsNoJumpControl() throws {
        let row = ChatTranscriptRowView(
            message: message(role: .assistant, text: "hello", sourceID: "s1"),
            maxBubbleWidth: 300,
            actions: .init(onOpen: { _ in })
        )
        XCTAssertTrue(try jumpButton(in: row).isHidden)
    }

    // MARK: - The overlay

    func testDoubleClickingARowOpensAnOverlayHoldingThatSessionAlone() async throws {
        let (controller, asked) = try await loadedFeed()

        doubleClick(try firstRow(of: controller))
        let overlay = try XCTUnwrap(focusOverlay(in: controller), "a row click did not open the overlay")
        try await waitUntil("the overlay's transcript loaded") { !self.rowTexts(in: overlay).isEmpty }

        XCTAssertEqual(
            Set(asked.values), ["s1"],
            "the overlay read something other than the one session it is showing")
        XCTAssertEqual(rowTexts(in: overlay), ["s1 first", "s1 second"],
                       "the overlay is not filtered to the clicked session")
    }

    func testTheOverlayCoversTheWholeFeed() async throws {
        let (controller, _) = try await loadedFeed()
        doubleClick(try firstRow(of: controller))
        let overlay = try XCTUnwrap(focusOverlay(in: controller))
        await settle()

        XCTAssertEqual(overlay.frame, controller.view.bounds,
                       "the overlay has to cover the whole window, composer and all")
    }

    func testEscapeDismissesTheOverlay() async throws {
        let (controller, _) = try await loadedFeed()
        doubleClick(try firstRow(of: controller))
        let overlay = try XCTUnwrap(focusOverlay(in: controller))

        XCTAssertTrue(overlay.performKeyEquivalent(with: key(code: 53)))
        try await waitForRemoval(of: overlay)
    }

    func testReturnDismissesTheOverlay() async throws {
        let (controller, _) = try await loadedFeed()
        doubleClick(try firstRow(of: controller))
        let overlay = try XCTUnwrap(focusOverlay(in: controller))

        XCTAssertTrue(overlay.performKeyEquivalent(with: key(code: 36)))
        try await waitForRemoval(of: overlay)
    }

    func testAnOrdinaryKeyLeavesTheOverlayUp() async throws {
        let (controller, _) = try await loadedFeed()
        doubleClick(try firstRow(of: controller))
        let overlay = try XCTUnwrap(focusOverlay(in: controller))

        // Down-arrow: the transcript still has to be readable while it is up.
        XCTAssertFalse(overlay.performKeyEquivalent(with: key(code: 125)))
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNotNil(overlay.superview)
    }

    func testAPressThatNoControlTookDismissesTheOverlay() async throws {
        let (controller, _) = try await loadedFeed()
        doubleClick(try firstRow(of: controller))
        let overlay = try XCTUnwrap(focusOverlay(in: controller))
        await settle()

        // A press an enabled control did not consume walks up the responder
        // chain and arrives here — the overlay's whole click-anywhere rule.
        overlay.mouseDown(with: mouseEvent(.leftMouseDown, in: overlay))
        try await waitForRemoval(of: overlay)
    }

    /// The whole reason opening moved to the second click: a single click is
    /// where a reader starts a drag across the text they are about to copy, and
    /// an overlay that opened on it would take the selection away mid-drag.
    func testASingleClickOnARowOpensNothing() async throws {
        let (controller, _) = try await loadedFeed()

        click(try firstRow(of: controller))
        try await Task.sleep(for: .milliseconds(400))

        XCTAssertNil(focusOverlay(in: controller),
                     "one click opened the overlay, so a drag across a row can never finish")
    }

    /// A double click lands on the *bubble* in practice — the row hands its
    /// subtree's hits to the bubble so text stays selectable — so the gesture
    /// has to survive that hop rather than only working on the row's margins.
    func testDoubleClickingTheBubbleOpensTheOverlay() async throws {
        let (controller, _) = try await loadedFeed()
        let row = try firstRow(of: controller)
        let bubble = try XCTUnwrap(row.subviews.compactMap { $0 as? AIChatBubbleView }.first)

        bubble.mouseDown(with: mouseEvent(.leftMouseDown, in: bubble, clickCount: 2))

        XCTAssertNotNil(focusOverlay(in: controller),
                        "a double click on the text itself did not open the conversation")
    }

    /// The refinement that made the overlay usable: the press that selects a
    /// line must not also be the press that closes what the line is in. The
    /// bubble takes it — hit-testing hands it there, and it is swallowed rather
    /// than passed up the responder chain to the overlay's dismiss.
    func testClickingABubbleInsideTheOverlayDoesNotDismissIt() async throws {
        let (controller, _) = try await loadedFeed()
        doubleClick(try firstRow(of: controller))
        let overlay = try XCTUnwrap(focusOverlay(in: controller))
        try await waitUntil("the overlay's transcript loaded") { !self.rowTexts(in: overlay).isEmpty }
        await settle()

        let bubble = try XCTUnwrap(firstBubble(in: overlay), "the overlay has no bubbles")
        // Inside the bubble's padding, where the text view is not: the point a
        // reader's click lands on when they miss the first word by a hair.
        let padding = NSPoint(x: 4, y: 4)
        let hit = overlay.hitTest(bubble.convert(padding, to: overlay.superview))
        XCTAssertTrue(
            hit?.isDescendant(of: bubble) ?? false,
            "a press on a bubble reached \(String(describing: hit)) rather than the bubble")

        bubble.mouseDown(with: mouseEvent(.leftMouseDown, in: bubble))
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNotNil(overlay.superview,
                        "clicking a bubble closed the overlay, so the text cannot be copied")
    }

    func testTheJumpControlGoesToTheSourceRatherThanOpeningTheOverlay() async throws {
        let (controller, _) = try await loadedFeed()
        let went = Box()
        controller.onGoToSource = { went.values.append($0.attribution?.sourceID ?? "") }

        try jumpButton(in: try firstRow(of: controller)).performClick(nil)

        XCTAssertEqual(went.values, ["s1"])
        XCTAssertNil(focusOverlay(in: controller), "the jump control is not a row click")
    }

    // MARK: - Fixtures

    /// Records what each load was narrowed to, so a test can tell a scoped read
    /// from a client-side sieve. Touched from the feed's poll, which does not
    /// run on the main actor.
    private final class SourceLog: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [String] = []
        func note(_ sourceID: String) {
            lock.lock(); stored.append(sourceID); lock.unlock()
        }
        var values: [String] {
            lock.lock(); defer { lock.unlock() }; return stored
        }
    }

    /// Somewhere for a callback to write that outlives the closure.
    @MainActor private final class Box {
        var values: [String] = []
    }

    private func message(role: ChatMessage.Role, text: String, sourceID: String) -> ChatMessage {
        ChatMessage(
            id: "\(sourceID)-\(text)",
            role: role,
            text: text,
            attribution: .init(
                sourceID: sourceID, context: "proj/main", name: "a session", iconSymbol: "sparkles")
        )
    }

    /// A `ConversationsViewController` in a window over a two-session feed whose
    /// loader records every `sourceID` it is asked for.
    private func loadedFeed() async throws -> (ConversationsViewController, SourceLog) {
        let asked = SourceLog()
        let all = [
            message(role: .assistant, text: "s1 first", sourceID: "s1"),
            message(role: .user, text: "s2 first", sourceID: "s2"),
            message(role: .user, text: "s1 second", sourceID: "s1")
        ]
        // An hour's refresh: the first read is the whole of what these tests want.
        let controller = ConversationsViewController(refreshInterval: .seconds(3600)) { _, sourceID in
            guard let sourceID else { return all }
            asked.note(sourceID)
            return all.filter { $0.attribution?.sourceID == sourceID }
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = controller.view
        windows.append(window)

        try await waitUntil("the feed loaded") { !self.rows(in: controller).isEmpty }
        await settle()
        return (controller, asked)
    }

    /// One row on its own, in a window, laid out — with its bubble and its jump
    /// control picked back out.
    private func laidOutRow(
        role: ChatMessage.Role, text: String
    ) throws -> (AIChatBubbleView, NSButton) {
        let row = ChatTranscriptRowView(
            message: message(role: role, text: text, sourceID: "s1"),
            maxBubbleWidth: 300,
            actions: .init(onJump: { _ in })
        )
        let host = NSView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = host
        windows.append(window)

        host.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            row.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        host.layoutSubtreeIfNeeded()

        let bubble = try XCTUnwrap(row.subviews.compactMap { $0 as? AIChatBubbleView }.first)
        return (bubble, try jumpButton(in: row))
    }

    private func jumpButton(in row: ChatTranscriptRowView) throws -> NSButton {
        try XCTUnwrap(
            row.subviews
                .compactMap { $0 as? NSButton }
                .first { $0.accessibilityIdentifier() == "chat-row.jump" },
            "the row has no jump control"
        )
    }

    // MARK: - Reaching into the view tree
    //
    // Optional rather than throwing, because these are polled: an `XCTUnwrap`
    // that fails while waiting for a load records a failure and the test is
    // already lost.

    private func transcriptRows(of chat: ChatView) -> [ChatTranscriptRowView] {
        guard let scroll = chat.subviews.compactMap({ $0 as? NSScrollView }).first,
              let stack = scroll.documentView as? NSStackView else { return [] }
        return stack.arrangedSubviews.compactMap { $0 as? ChatTranscriptRowView }
    }

    private func rows(in controller: ConversationsViewController) -> [ChatTranscriptRowView] {
        guard let chat = controller.view.subviews.compactMap({ $0 as? ChatView }).first else {
            return []
        }
        return transcriptRows(of: chat)
    }

    private func firstRow(of controller: ConversationsViewController) throws -> ChatTranscriptRowView {
        try XCTUnwrap(rows(in: controller).first, "the feed has no rows")
    }

    private func focusOverlay(in controller: ConversationsViewController) -> ConversationFocusOverlay? {
        controller.view.subviews.compactMap { $0 as? ConversationFocusOverlay }.first
    }

    /// The first bubble in the overlay's own transcript.
    private func firstBubble(in overlay: ConversationFocusOverlay) -> AIChatBubbleView? {
        guard let chat = overlay.subviews.compactMap({ $0 as? ChatView }).first else { return nil }
        return transcriptRows(of: chat)
            .first?
            .subviews
            .compactMap { $0 as? AIChatBubbleView }
            .first
    }

    /// What the overlay is actually showing, oldest first.
    private func rowTexts(in overlay: ConversationFocusOverlay) -> [String] {
        guard let chat = overlay.subviews.compactMap({ $0 as? ChatView }).first else { return [] }
        return transcriptRows(of: chat).compactMap { row in
            row.subviews
                .compactMap { $0 as? AIChatBubbleView }
                .first?
                .subviews
                .compactMap { ($0 as? NSTextView)?.string }
                .first
        }
    }

    // MARK: - Driving and waiting

    private func click(_ row: ChatTranscriptRowView) {
        row.mouseDown(with: mouseEvent(.leftMouseDown, in: row))
        row.mouseUp(with: mouseEvent(.leftMouseUp, in: row))
    }

    /// The second press of a double click, as AppKit delivers it: one event
    /// carrying `clickCount == 2`, not two separate presses.
    private func doubleClick(_ row: ChatTranscriptRowView) {
        row.mouseDown(with: mouseEvent(.leftMouseDown, in: row, clickCount: 2))
        row.mouseUp(with: mouseEvent(.leftMouseUp, in: row, clickCount: 2))
    }

    private func mouseEvent(
        _ type: NSEvent.EventType, in view: NSView, clickCount: Int = 1
    ) -> NSEvent {
        let centre = NSPoint(x: view.bounds.midX, y: view.bounds.midY)
        return NSEvent.mouseEvent(
            with: type,
            location: view.convert(centre, to: nil),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: view.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: 1
        )!
    }

    private func key(code: UInt16) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: windows.last?.windowNumber ?? 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: code
        )!
    }

    /// Polls `condition` for up to two seconds, laying out between tries — the
    /// feed's read and the overlay's fade are both real time.
    private func waitUntil(
        _ what: String,
        file: StaticString = #filePath, line: UInt = #line,
        _ condition: () -> Bool
    ) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
            windows.last?.contentView?.layoutSubtreeIfNeeded()
        }
        XCTFail("timed out waiting until \(what)", file: file, line: line)
    }

    private func waitForRemoval(
        of overlay: ConversationFocusOverlay, file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        try await waitUntil("the overlay went away", file: file, line: line) {
            overlay.superview == nil
        }
    }

    /// Lets the coalesced rebuild and the scroll it schedules actually run.
    private func settle() async {
        for _ in 0..<5 {
            windows.last?.contentView?.layoutSubtreeIfNeeded()
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(20))
        }
        windows.last?.contentView?.layoutSubtreeIfNeeded()
    }
}
