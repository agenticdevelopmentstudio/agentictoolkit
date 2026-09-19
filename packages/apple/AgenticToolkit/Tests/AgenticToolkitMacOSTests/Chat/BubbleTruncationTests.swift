// Tests/AgenticToolkitMacOSTests/Chat/BubbleTruncationTests.swift
import AppKit
import XCTest
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// A long message in a feed: where it stops, how it says so, and the way back
/// to the rest of it.
///
/// None of this is visible to a build. A bubble that truncated at the wrong
/// count still lays out, a cut that landed mid-word still renders, and an
/// expansion overlay showing the *truncated* copy looks exactly like one
/// showing the whole message until you read it.
@MainActor
final class BubbleTruncationTests: XCTestCase {

    /// Every window a test made, kept alive for its duration — a view whose
    /// window has gone is a view whose layout nobody is maintaining.
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        try await super.tearDown()
    }

    // MARK: - The cut

    func testALongMessageStopsAtTheLineLimit() throws {
        let bubble = try laidOutBubble(text: paragraph(of: 40), lineLimit: 8)
        XCTAssertTrue(bubble.isTruncated, "a forty-line message under an eight-line cap fit whole")
        XCTAssertEqual(try lineCount(of: bubble), 8,
                       "the bubble shows a different number of lines than it was capped at")
    }

    func testAMessageThatFitsIsLeftWhole() throws {
        let bubble = try laidOutBubble(text: paragraph(of: 3), lineLimit: 8)
        XCTAssertFalse(bubble.isTruncated)
        XCTAssertEqual(try text(of: bubble), paragraph(of: 3),
                       "a message shorter than the cap came back changed")
    }

    func testAMessageWithNoLimitIsLeftWholeHoweverLongItIs() throws {
        let bubble = try laidOutBubble(text: paragraph(of: 40), lineLimit: nil)
        XCTAssertFalse(bubble.isTruncated)
        XCTAssertEqual(try lineCount(of: bubble), 40)
    }

    /// The ellipsis is the whole of what tells a reader the message continues —
    /// the **More…** control says there is a way in, not that anything is
    /// missing from what they just read.
    func testTheCutTextEndsInAnEllipsis() throws {
        let bubble = try laidOutBubble(text: paragraph(of: 40), lineLimit: 8)
        XCTAssertTrue(try text(of: bubble).hasSuffix("…"),
                      "a truncated bubble ended flush, as if the message stopped there")
    }

    /// Cut on laid-out lines, not characters: the same cap has to mean eight
    /// lines whether the text wrapped to get there or arrived pre-broken.
    func testTheCutCountsWrappedLinesTheSameAsWrittenOnes() throws {
        let wrapped = String(repeating: "a long unbroken sentence that has to wrap. ", count: 40)
        let bubble = try laidOutBubble(text: wrapped, lineLimit: 8)
        XCTAssertTrue(bubble.isTruncated)
        XCTAssertEqual(try lineCount(of: bubble), 8,
                       "wrapped lines were counted differently from written ones")
    }

    // MARK: - The More… control

    func testOnlyATruncatedBubbleOffersMore() throws {
        let short = try laidOutBubble(text: paragraph(of: 3), lineLimit: 8)
        let long = try laidOutBubble(text: paragraph(of: 40), lineLimit: 8)

        XCTAssertTrue(try moreButton(in: short).isHidden,
                      "a message shown whole still offered to show the rest of itself")
        XCTAssertFalse(try moreButton(in: long).isHidden)
    }

    /// Enabled by having somewhere to go, not by being visible: a control that
    /// looks live and does nothing is worse than no control.
    func testTheMoreControlIsDeadUntilExpandingIsWired() throws {
        let bubble = try laidOutBubble(text: paragraph(of: 40), lineLimit: 8)
        XCTAssertFalse(try moreButton(in: bubble).isEnabled)

        bubble.onExpand = {}
        XCTAssertTrue(try moreButton(in: bubble).isEnabled)
    }

    func testTheMoreControlNeverWidensPastTheBubblesLimit() throws {
        // One short word, so the text is far narrower than "More…" — the bubble
        // has to fit the offer as well as the message.
        let bubble = try laidOutBubble(text: "hi\nthere\nyou\nand\nyou\ntwo\nand\nyou\nthree",
                                       lineLimit: 8, maxWidth: 300)
        XCTAssertTrue(bubble.isTruncated)
        let more = try moreButton(in: bubble)
        XCTAssertLessThanOrEqual(bubble.frame.width, 300)
        XCTAssertGreaterThanOrEqual(
            bubble.frame.width, more.intrinsicContentSize.width,
            "the bubble is narrower than the control it is showing, so More… is clipped")
    }

    // MARK: - The expansion overlay

    func testMoreOpensAnOverlayShowingTheWholeMessage() async throws {
        let (controller, chat) = try await loadedFeed()
        try moreButton(in: try firstBubble(of: chat)).performClick(nil)

        let overlay = try XCTUnwrap(expansion(in: chat), "More… opened nothing")
        await settle()

        let expanded = try XCTUnwrap(expandedBubble(in: overlay), "the overlay holds no bubble")
        XCTAssertFalse(expanded.isTruncated,
                       "the overlay showed the truncated copy, which is the message it was opened to escape")
        XCTAssertTrue(try text(of: expanded).hasPrefix(Self.longText),
                      "the expanded bubble is not the whole message")
        XCTAssertNotNil(controller.view.window)
    }

    func testTheExpansionOverlayCoversTheWholeChat() async throws {
        let (_, chat) = try await loadedFeed()
        try moreButton(in: try firstBubble(of: chat)).performClick(nil)
        let overlay = try XCTUnwrap(expansion(in: chat))
        await settle()

        XCTAssertEqual(overlay.frame, chat.bounds,
                       "the overlay has to cover the whole chat, composer and all")
    }

    func testEscapeDismissesTheExpansionOverlay() async throws {
        let (_, chat) = try await loadedFeed()
        try moreButton(in: try firstBubble(of: chat)).performClick(nil)
        let overlay = try XCTUnwrap(expansion(in: chat))

        XCTAssertTrue(overlay.performKeyEquivalent(with: key(code: 53)))
        try await waitUntil("the overlay went away") { overlay.superview == nil }
    }

    func testReturnDismissesTheExpansionOverlay() async throws {
        let (_, chat) = try await loadedFeed()
        try moreButton(in: try firstBubble(of: chat)).performClick(nil)
        let overlay = try XCTUnwrap(expansion(in: chat))

        XCTAssertTrue(overlay.performKeyEquivalent(with: key(code: 36)))
        try await waitUntil("the overlay went away") { overlay.superview == nil }
    }

    func testAPressThatNoControlTookDismissesTheExpansionOverlay() async throws {
        let (_, chat) = try await loadedFeed()
        try moreButton(in: try firstBubble(of: chat)).performClick(nil)
        let overlay = try XCTUnwrap(expansion(in: chat))
        await settle()

        overlay.mouseDown(with: mouseEvent(.leftMouseDown, in: overlay))
        try await waitUntil("the overlay went away") { overlay.superview == nil }
    }

    /// The reason the overlay exists at all is to be read, and reading a
    /// message this long usually ends in copying part of it — so the press that
    /// starts a selection must not be the press that closes it.
    func testClickingTheExpandedBubbleDoesNotDismissTheOverlay() async throws {
        let (_, chat) = try await loadedFeed()
        try moreButton(in: try firstBubble(of: chat)).performClick(nil)
        let overlay = try XCTUnwrap(expansion(in: chat))
        await settle()
        let expanded = try XCTUnwrap(expandedBubble(in: overlay))

        // Inside the bubble's padding, where the text view is not: the point a
        // reader's click lands on when they miss the first word by a hair.
        let hit = overlay.hitTest(expanded.convert(NSPoint(x: 4, y: 4), to: overlay.superview))
        XCTAssertTrue(
            hit?.isDescendant(of: expanded) ?? false,
            "a press on the expanded bubble reached \(String(describing: hit)) instead")

        expanded.mouseDown(with: mouseEvent(.leftMouseDown, in: expanded))
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNotNil(overlay.superview,
                        "clicking the message closed it, so none of it can be copied")
    }

    // MARK: - Fixtures

    private static let longText = (0..<40)
        .map { "line \($0) of a long reply" }
        .joined(separator: "\n")

    private func paragraph(of lines: Int) -> String {
        (0..<lines).map { "line \($0) of a long reply" }.joined(separator: "\n")
    }

    /// A bubble on its own, in a window, laid out — the state it measures itself
    /// in, since the measurement is redone on every theme application.
    private func laidOutBubble(
        text: String, lineLimit: Int?, maxWidth: CGFloat = 300
    ) throws -> AIChatBubbleView {
        let bubble = AIChatBubbleView(
            message: ChatMessage(id: "m", role: .assistant, text: text),
            maxWidth: maxWidth,
            showsInlineTimestamp: false,
            isTextSelectable: true,
            lineLimit: lineLimit
        )
        let host = NSView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 800),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = host
        windows.append(window)

        host.addSubview(bubble)
        NSLayoutConstraint.activate([
            bubble.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            bubble.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        host.layoutSubtreeIfNeeded()
        return bubble
    }

    /// A one-row feed whose single message is long enough to truncate, in a
    /// window — the shape the **More…** control actually ships in.
    private func loadedFeed() async throws -> (ConversationsViewController, ChatView) {
        let messages = [
            ChatMessage(
                id: "m1", role: .assistant, text: Self.longText,
                attribution: .init(sourceID: "s1", context: "proj/main",
                                   name: "a session", iconSymbol: "sparkles")
            )
        ]
        // An hour's refresh: the first read is the whole of what these tests want.
        let controller = ConversationsViewController(refreshInterval: .seconds(3600)) { _, _ in
            messages
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = controller.view
        windows.append(window)

        let chat = try XCTUnwrap(
            controller.view.subviews.compactMap { $0 as? ChatView }.first,
            "the controller is not hosting a chat view")
        try await waitUntil("the feed loaded") { !self.rows(in: chat).isEmpty }
        await settle()
        return (controller, chat)
    }

    // MARK: - Reaching into the view tree

    private func rows(in chat: ChatView) -> [ChatTranscriptRowView] {
        guard let scroll = chat.subviews.compactMap({ $0 as? NSScrollView }).first,
              let stack = scroll.documentView as? NSStackView else { return [] }
        return stack.arrangedSubviews.compactMap { $0 as? ChatTranscriptRowView }
    }

    private func firstBubble(of chat: ChatView) throws -> AIChatBubbleView {
        try XCTUnwrap(
            rows(in: chat).first?.subviews.compactMap { $0 as? AIChatBubbleView }.first,
            "the feed has no bubbles")
    }

    private func expansion(in chat: ChatView) -> BubbleExpansionOverlay? {
        chat.subviews.compactMap { $0 as? BubbleExpansionOverlay }.first
    }

    private func expandedBubble(in overlay: BubbleExpansionOverlay) -> AIChatBubbleView? {
        overlay.subviews
            .compactMap { ($0 as? NSScrollView)?.documentView as? AIChatBubbleView }
            .first
    }

    private func moreButton(in bubble: AIChatBubbleView) throws -> NSButton {
        try XCTUnwrap(
            bubble.subviews
                .compactMap { $0 as? NSButton }
                .first { $0.accessibilityIdentifier() == "chat-bubble.more" },
            "the bubble has no More… control")
    }

    private func textView(of bubble: AIChatBubbleView) throws -> NSTextView {
        try XCTUnwrap(bubble.subviews.compactMap { $0 as? NSTextView }.first,
                      "the bubble has no text view")
    }

    private func text(of bubble: AIChatBubbleView) throws -> String {
        try textView(of: bubble).string
    }

    /// What the bubble is *showing*, counted off its own laid-out fragments —
    /// the only count that means anything here, since the cap is a cap on lines
    /// after wrapping rather than on newlines in the source.
    private func lineCount(of bubble: AIChatBubbleView) throws -> Int {
        let view = try textView(of: bubble)
        let layoutManager = try XCTUnwrap(view.layoutManager)
        let container = try XCTUnwrap(view.textContainer)
        layoutManager.ensureLayout(for: container)

        var lines = 0
        var glyph = 0
        while glyph < layoutManager.numberOfGlyphs {
            var range = NSRange()
            _ = layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: &range)
            lines += 1
            guard range.length > 0 else { break }
            glyph = NSMaxRange(range)
        }
        return lines
    }

    // MARK: - Driving and waiting

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

    /// Lets the coalesced rebuild, the fade and the scroll they schedule run.
    private func settle() async {
        for _ in 0..<5 {
            windows.last?.contentView?.layoutSubtreeIfNeeded()
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(60))
        }
        windows.last?.contentView?.layoutSubtreeIfNeeded()
    }
}
