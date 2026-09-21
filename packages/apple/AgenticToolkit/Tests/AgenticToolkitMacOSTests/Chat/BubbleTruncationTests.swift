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
        // The terminal font is real user state, shared with every other test in
        // the process and with the developer running them.
        UserSettings.terminalFontName.value = UserSettings.terminalFontName.defaultValue
        UserSettings.terminalFontSize.value = UserSettings.terminalFontSize.defaultValue
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

    /// The control follows the ellipsis on the same line: that is where the
    /// sentence stopped, so it is where "what else did it say" gets asked.
    func testTheMoreControlFollowsTheEllipsisOnTheLastLine() throws {
        let bubble = try laidOutBubble(text: paragraph(of: 40), lineLimit: 8)
        XCTAssertTrue(bubble.isTruncated)
        let more = try moreButton(in: bubble)
        let lastLine = try lastLineRect(of: bubble)

        XCTAssertGreaterThanOrEqual(
            more.frame.minX, lastLine.maxX,
            "the control is drawn over the text it is offering to complete")
        XCTAssertEqual(
            more.frame.minX, lastLine.maxX + 4, accuracy: 1,
            "the control is not right after the ellipsis")
        XCTAssertEqual(
            more.frame.midY, lastLine.midY, accuracy: 1,
            "the control is not on the last line — it is above or below it")
    }

    /// Being on the line rather than under it is also what makes a truncated row
    /// cost no more height than a full one: the control used to add a line that
    /// carried no words, on every truncated row in the feed.
    func testATruncatedBubbleIsNoTallerThanAFullOne() throws {
        let truncated = try laidOutBubble(text: paragraph(of: 40), lineLimit: 8)
        let whole = try laidOutBubble(text: paragraph(of: 8), lineLimit: 8)

        XCTAssertTrue(truncated.isTruncated)
        XCTAssertFalse(whole.isTruncated)
        XCTAssertEqual(
            truncated.frame.height, whole.frame.height, accuracy: 0.5,
            "the More… control is still costing the row a line of its own")
    }

    /// The cut lands where the text wrapped, so the last line normally ends at
    /// the far edge — with the ellipsis standing in for the space that wrapped
    /// it. Something has to give for the control to follow it, and it is the
    /// text: a couple of characters, not the bubble's edge.
    func testTheCutLeavesRoomOnTheLastLineForTheControl() throws {
        let wrapped = String(repeating: "a long unbroken sentence that has to wrap. ", count: 40)
        let bubble = try laidOutBubble(text: wrapped, lineLimit: 8, fillsWidthWhenWrapped: true)
        XCTAssertTrue(bubble.isTruncated)
        let more = try moreButton(in: bubble)

        XCTAssertLessThanOrEqual(
            more.frame.maxX, bubble.frame.width - 12 + 0.5,
            "the control ran out through the bubble's own padding")
        XCTAssertGreaterThanOrEqual(
            more.frame.minX, try lastLineRect(of: bubble).maxX,
            "the control slid back over the ellipsis instead of the text making room")
        XCTAssertTrue(try text(of: bubble).hasSuffix("…"),
                      "making room cost the ellipsis")
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

    // MARK: - The face

    /// A bubble is set in the terminal's font, not in the theme's body role.
    ///
    /// Nothing about the layout says which of the two it took: a bubble in the
    /// wrong face measures, wraps and truncates exactly as well as one in the
    /// right face, and only a reader looking at both windows can tell.
    func testABubbleIsSetInTheFaceTheTerminalIs() throws {
        try requireATerminalFontThatComesFromSettings()
        UserSettings.terminalFontName.value = "Courier"
        UserSettings.terminalFontSize.value = 17

        let font = try bodyFont(of: try laidOutBubble(text: "one short line", lineLimit: nil))
        XCTAssertEqual(font.fontName, "Courier",
                       "the bubble is drawn in \(font.fontName), not the terminal's face")
        XCTAssertEqual(font.pointSize, 17, accuracy: 0.01,
                       "the bubble is drawn at its own size rather than the terminal's")
    }

    /// The theme's terminal override wins over the Terminal settings panel —
    /// the same precedence the terminal itself resolves by, since a reader who
    /// gave one theme its own face meant the transcript of that theme's
    /// sessions too.
    func testAThemesOwnTerminalFontBeatsTheSettingsPanels() {
        UserSettings.terminalFontName.value = "Courier"
        UserSettings.terminalFontSize.value = 17

        var theme = BuiltInThemes.dracula
        theme.terminal = ThemeTerminalOptions(fontName: "Menlo-Bold", fontSize: 21)
        let palette = SemanticPalette(theme: theme)

        let font = AIChatBubbleView.bodyFont(for: palette)
        XCTAssertEqual(font.fontName, "Menlo-Bold",
                       "the settings panel outranked the theme the reader is looking at")
        XCTAssertEqual(font.pointSize, 21, accuracy: 0.01)
        XCTAssertNotEqual(font.fontName, palette.font(.body).fontName,
                          "this theme cannot tell the two faces apart, so it proves nothing")
    }

    /// The timestamp trailing a message is the message's own face, smaller —
    /// not the theme's caption face, which would put two typefaces on one line.
    func testTheInlineTimestampIsTheBodysFaceOneStepSmaller() {
        UserSettings.terminalFontName.value = "Courier"
        UserSettings.terminalFontSize.value = 18

        let palette = SemanticPalette(theme: BuiltInThemes.dracula)
        let body = AIChatBubbleView.bodyFont(for: palette)
        let time = AIChatBubbleView.timestampFont(for: palette)

        XCTAssertEqual(time.familyName, body.familyName,
                       "the time is set in a different family than the words it trails")
        XCTAssertLessThan(time.pointSize, body.pointSize,
                          "the time is as loud as the message")
        // The theme says how much smaller a caption is than body text; that
        // ratio is what the terminal's size is read through.
        let ratio = palette.size(.caption) / palette.size(.body)
        XCTAssertEqual(time.pointSize, body.pointSize * CGFloat(ratio), accuracy: 0.01,
                       "the timestamp does not keep the theme's caption-to-body relationship")
    }

    /// Half the answer to "what face is this" lives in Terminal settings rather
    /// than in the theme, and a settings change posts no theme notification —
    /// so the bubbles, which each re-measure themselves on a theme change, would
    /// otherwise stay in the old face until something else rebuilt the feed.
    func testChangingTheTerminalFontRedrawsTheFeed() async throws {
        try requireATerminalFontThatComesFromSettings()
        UserSettings.terminalFontSize.value = 13

        let (_, chat) = try await loadedFeed()
        XCTAssertEqual(try bodyFont(of: try firstBubble(of: chat)).pointSize, 13, accuracy: 0.01)

        UserSettings.terminalFontSize.value = 21
        try await waitUntil("the feed is redrawn at the new size") {
            ((try? self.bodyFont(of: try self.firstBubble(of: chat)).pointSize) ?? 0) == 21
        }
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
        text: String, lineLimit: Int?, maxWidth: CGFloat = 300,
        fillsWidthWhenWrapped: Bool = false
    ) throws -> AIChatBubbleView {
        let bubble = AIChatBubbleView(
            message: ChatMessage(id: "m", role: .assistant, text: text),
            maxWidth: maxWidth,
            showsInlineTimestamp: false,
            isTextSelectable: true,
            lineLimit: lineLimit,
            fillsWidthWhenWrapped: fillsWidthWhenWrapped
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
                attribution: .init(sourceID: "s1", context: ["proj", "main"],
                                   name: "a session", iconSymbol: "sparkles")
            )
        ]
        // An hour's refresh: the first read is the whole of what these tests want.
        let controller = ConversationsViewController(refreshInterval: .seconds(3600)) { _, _, _ in
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

    /// The tests that drive the face through Terminal settings only mean
    /// anything while the theme in effect has no font of its own — the theme
    /// wins, so an overriding one makes them pass without testing anything.
    /// Stated as an assertion rather than assumed: a test bundle that starts
    /// installing a `ThemeManager` should fail here, loudly, once.
    private func requireATerminalFontThatComesFromSettings(
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let terminal = ThemePaletteObserver.currentPalette.theme.terminal
        XCTAssertNil(terminal?.fontName, "the active theme names its own terminal face",
                     file: file, line: line)
        XCTAssertNil(terminal?.fontSize, "the active theme sets its own terminal size",
                     file: file, line: line)
    }

    /// The face the bubble actually drew its first character in.
    private func bodyFont(of bubble: AIChatBubbleView) throws -> NSFont {
        let storage = try XCTUnwrap(textView(of: bubble).textStorage, "the bubble holds no text")
        XCTAssertGreaterThan(storage.length, 0, "the bubble is empty")
        return try XCTUnwrap(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont,
                             "the bubble's text carries no font")
    }

    private func textView(of bubble: AIChatBubbleView) throws -> NSTextView {
        try XCTUnwrap(bubble.subviews.compactMap { $0 as? NSTextView }.first,
                      "the bubble has no text view")
    }

    private func text(of bubble: AIChatBubbleView) throws -> String {
        try textView(of: bubble).string
    }

    /// Where the last laid-out line ends, in the bubble's own coordinates —
    /// which is where the ellipsis is, and so where anything following it has
    /// to start. Converted rather than compared raw: a text view is flipped and
    /// a bubble is not.
    private func lastLineRect(of bubble: AIChatBubbleView) throws -> NSRect {
        let view = try textView(of: bubble)
        let layoutManager = try XCTUnwrap(view.layoutManager)
        let container = try XCTUnwrap(view.textContainer)
        layoutManager.ensureLayout(for: container)

        var rect = NSRect.zero
        var glyph = 0
        while glyph < layoutManager.numberOfGlyphs {
            var range = NSRange()
            rect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: &range)
            guard range.length > 0 else { break }
            glyph = NSMaxRange(range)
        }
        return bubble.convert(rect, from: view)
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
