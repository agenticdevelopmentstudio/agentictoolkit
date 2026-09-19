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
/// sieved client-side still renders rows, and a peek that never ends still
/// looks right in a screenshot.
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

    /// "Centred on the top line" only differs from "centred on the bubble" once
    /// a bubble is more than one line tall — so the test is that a one-line
    /// bubble and a forty-line one put the control the same distance below their
    /// own top edge.
    func testTheJumpControlIsCenteredOnTheFirstLineHoweverTallTheBubbleIs() throws {
        let (shortBubble, shortButton) = try laidOutRow(role: .assistant, text: "one line")
        let paragraph = (0..<40).map { "line \($0) of a long reply" }.joined(separator: "\n")
        let (tallBubble, tallButton) = try laidOutRow(role: .assistant, text: paragraph)

        XCTAssertGreaterThan(
            tallBubble.frame.height, shortBubble.frame.height * 4,
            "the fixture is wrong: the bubbles have to differ in height for this to mean anything")

        // Neither view is flipped, so a bubble's top edge is its `maxY`.
        let shortDrop = shortBubble.frame.maxY - shortButton.frame.midY
        let tallDrop = tallBubble.frame.maxY - tallButton.frame.midY
        XCTAssertEqual(
            shortDrop, tallDrop, accuracy: 0.5,
            "the control follows the bubble's centre, not its first line: \(shortDrop) vs \(tallDrop)")
    }

    func testARowWithNoJumpActionShowsNoJumpControl() throws {
        let row = ChatTranscriptRowView(
            message: message(role: .assistant, text: "hello", sourceID: "s1"),
            maxBubbleWidth: 300,
            actions: .init(onTap: { _ in })
        )
        XCTAssertTrue(try jumpButton(in: row).isHidden)
    }

    // MARK: - The overlay

    func testClickingARowOpensAnOverlayHoldingThatSessionAlone() async throws {
        let (controller, asked) = try await loadedFeed()

        click(try firstRow(of: controller))
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
        click(try firstRow(of: controller))
        let overlay = try XCTUnwrap(focusOverlay(in: controller))
        await settle()

        XCTAssertEqual(overlay.frame, controller.view.bounds,
                       "the overlay has to cover the whole window, composer and all")
    }

    func testEscapeDismissesTheOverlay() async throws {
        let (controller, _) = try await loadedFeed()
        click(try firstRow(of: controller))
        let overlay = try XCTUnwrap(focusOverlay(in: controller))

        XCTAssertTrue(overlay.performKeyEquivalent(with: key(code: 53)))
        try await waitForRemoval(of: overlay)
    }

    func testReturnDismissesTheOverlay() async throws {
        let (controller, _) = try await loadedFeed()
        click(try firstRow(of: controller))
        let overlay = try XCTUnwrap(focusOverlay(in: controller))

        XCTAssertTrue(overlay.performKeyEquivalent(with: key(code: 36)))
        try await waitForRemoval(of: overlay)
    }

    func testAnOrdinaryKeyLeavesTheOverlayUp() async throws {
        let (controller, _) = try await loadedFeed()
        click(try firstRow(of: controller))
        let overlay = try XCTUnwrap(focusOverlay(in: controller))

        // Down-arrow: the transcript still has to be readable while it is up.
        XCTAssertFalse(overlay.performKeyEquivalent(with: key(code: 125)))
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNotNil(overlay.superview)
    }

    func testAPressThatNoControlTookDismissesTheOverlay() async throws {
        let (controller, _) = try await loadedFeed()
        click(try firstRow(of: controller))
        let overlay = try XCTUnwrap(focusOverlay(in: controller))
        await settle()

        // A press an enabled control did not consume walks up the responder
        // chain and arrives here — the overlay's whole click-anywhere rule.
        overlay.mouseDown(with: mouseEvent(.leftMouseDown, in: overlay))
        try await waitForRemoval(of: overlay)
    }

    func testHoldingARowPeeksAndReleasingPutsItBack() async throws {
        let (controller, _) = try await loadedFeed()
        let row = try firstRow(of: controller)

        row.mouseDown(with: mouseEvent(.leftMouseDown, in: row))
        XCTAssertNil(focusOverlay(in: controller), "a press is not a peek until it has been held")

        try await waitUntil("the held press peeked") { self.focusOverlay(in: controller) != nil }
        let overlay = try XCTUnwrap(focusOverlay(in: controller))

        row.mouseUp(with: mouseEvent(.leftMouseUp, in: row))
        try await waitForRemoval(of: overlay)
    }

    func testReleasingAPeekDoesNotAlsoCountAsAClick() async throws {
        let (controller, _) = try await loadedFeed()
        let row = try firstRow(of: controller)

        row.mouseDown(with: mouseEvent(.leftMouseDown, in: row))
        try await waitUntil("the held press peeked") { self.focusOverlay(in: controller) != nil }
        row.mouseUp(with: mouseEvent(.leftMouseUp, in: row))
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertNil(focusOverlay(in: controller),
                     "the release fired the tap as well, so the peek came back as a stay")
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

    private func mouseEvent(_ type: NSEvent.EventType, in view: NSView) -> NSEvent {
        let centre = NSPoint(x: view.bounds.midX, y: view.bounds.midY)
        return NSEvent.mouseEvent(
            with: type,
            location: view.convert(centre, to: nil),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: view.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
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
    /// feed's read, the peek's delay and the fade are all real time.
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
