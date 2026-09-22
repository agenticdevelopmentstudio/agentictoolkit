// Tests/AgenticToolkitMacOSTests/Chat/BubbleTruncationTests.swift
import AppKit
import XCTest
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// A long message in a feed: where it stops, how it says so, and the way back
/// to the rest of it.
///
/// None of this is visible to a build. A bubble that truncated at the wrong
/// count still lays out, a cut that landed mid-word still renders, and a
/// toggle that opens the *truncated* copy out looks exactly like one that
/// opens the whole message until you read it.
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
    /// the toggle beneath it says there is a way in, not that anything is
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

    // MARK: - The expand toggle

    func testOnlyAnOverlongBubbleOffersTheToggle() throws {
        let short = try laidOutBubble(text: paragraph(of: 3), lineLimit: 8)
        let long = try laidOutBubble(text: paragraph(of: 40), lineLimit: 8)

        XCTAssertTrue(try moreButton(in: short).isHidden,
                      "a message shown whole still offered to show the rest of itself")
        XCTAssertFalse(try moreButton(in: long).isHidden)
    }

    /// Enabled by having somewhere to go, not by being visible: a control that
    /// looks live and does nothing is worse than no control.
    func testTheToggleIsDeadUntilExpandingIsWired() throws {
        let bubble = try laidOutBubble(text: paragraph(of: 40), lineLimit: 8)
        XCTAssertFalse(try moreButton(in: bubble).isEnabled)

        bubble.onToggleExpanded = {}
        XCTAssertTrue(try moreButton(in: bubble).isEnabled)
    }

    func testTheToggleNeverWidensPastTheBubblesLimit() throws {
        // One short word per line, so the text is far narrower than the toggle
        // — the bubble has to fit the offer as well as the message.
        let bubble = try laidOutBubble(text: "hi\nthere\nyou\nand\nyou\ntwo\nand\nyou\nthree",
                                       lineLimit: 8, maxWidth: 300)
        XCTAssertTrue(bubble.isTruncated)
        let more = try moreButton(in: bubble)
        XCTAssertLessThanOrEqual(bubble.frame.width, 300)
        XCTAssertGreaterThanOrEqual(
            more.frame.minX, 0,
            "the bubble is narrower than the control it is showing, so the toggle is clipped")
        XCTAssertLessThanOrEqual(more.frame.maxX, bubble.frame.width)
    }

    /// Under the text, at the bubble's trailing edge: out of the way of the
    /// words, and in the corner the eye is already at when the message stops.
    func testTheToggleSitsInTheBubblesLowerRight() throws {
        let bubble = try laidOutBubble(text: paragraph(of: 40), lineLimit: 8)
        XCTAssertTrue(bubble.isTruncated)
        let lastLine = try lastLineRect(of: bubble)
        // Where the button was *placed*, not the frame it draws in: a button's
        // frame is its alignment rect grown by the bezel insets, so the frame
        // overhangs the padding by a couple of points at every edge.
        let more = try placement(of: moreButton(in: bubble))

        XCTAssertEqual(
            more.maxX, bubble.frame.width - 12, accuracy: 0.5,
            "the toggle is not on the bubble's trailing edge")
        XCTAssertLessThanOrEqual(
            more.maxY, lastLine.minY + 0.5,
            "the toggle is drawn over the text it is offering to complete")
        XCTAssertEqual(
            more.minY, 8, accuracy: 0.5,
            "the toggle is not sitting on the bubble's bottom padding")
    }

    /// The toggle costs the row the control's own height and nothing else: a
    /// truncated bubble is a full one plus the button, not plus a blank line of
    /// text. The bubble measures itself from the toggle on every row, so a row
    /// with nothing to expand has to come out exactly as it always did.
    func testTheToggleCostsARowTheControlAndNothingElse() throws {
        let truncated = try laidOutBubble(text: paragraph(of: 40), lineLimit: 8)
        let whole = try laidOutBubble(text: paragraph(of: 8), lineLimit: 8)

        XCTAssertTrue(truncated.isTruncated)
        XCTAssertFalse(whole.isTruncated)
        XCTAssertTrue(try moreButton(in: whole).isHidden)
        XCTAssertEqual(
            truncated.frame.height, whole.frame.height + 2 + 22, accuracy: 0.5,
            "a truncated row costs more than the toggle that made it one")
    }

    /// The cut lands where the text wrapped, so the last line normally ends at
    /// the far edge — with the ellipsis standing in for the space that wrapped
    /// it. Appending that ellipsis can re-wrap the line it lands on, and a cut
    /// that came back one line longer than the limit is no cut at all.
    func testTheCutStaysWithinTheLimitWhenTheEllipsisWouldWrap() throws {
        let wrapped = String(repeating: "a long unbroken sentence that has to wrap. ", count: 40)
        let bubble = try laidOutBubble(text: wrapped, lineLimit: 8, fillsWidthWhenWrapped: true)

        XCTAssertTrue(bubble.isTruncated)
        XCTAssertEqual(try lineCount(of: bubble), 8,
                       "the ellipsis wrapped onto a line of its own")
        XCTAssertTrue(try text(of: bubble).hasSuffix("…"),
                      "staying within the limit cost the ellipsis")
    }

    /// An open bubble is showing everything, so it is not truncated — and it
    /// still has to offer the way back, which is what the second flag is for.
    func testAnOpenBubbleIsWholeAndStillOffersTheWayBack() throws {
        let bubble = try laidOutBubble(text: paragraph(of: 40), lineLimit: 8)
        XCTAssertTrue(bubble.isTruncated)

        bubble.isExpanded = true

        XCTAssertFalse(bubble.isTruncated, "an opened bubble is still reporting itself cut off")
        XCTAssertTrue(bubble.isExpandable, "an opened bubble stopped offering the way back")
        XCTAssertFalse(try moreButton(in: bubble).isHidden)
        XCTAssertEqual(try lineCount(of: bubble), 40)
        XCTAssertEqual(try text(of: bubble), paragraph(of: 40))
    }

    // MARK: - Opening a message out in place

    func testTheToggleOpensTheMessageInPlace() async throws {
        let (controller, chat) = try await loadedFeed()
        let bubble = try firstBubble(of: chat)
        XCTAssertTrue(bubble.isTruncated, "the fixture is wrong: nothing was cut off")

        try moreButton(in: bubble).performClick(nil)
        await settle()

        XCTAssertFalse(bubble.isTruncated,
                       "the toggle left the message cut off, which is what it was there to undo")
        XCTAssertEqual(try text(of: bubble), Self.longText,
                       "the opened bubble is not the whole message")
        XCTAssertTrue(bubble.isDescendant(of: chat),
                      "the message opened somewhere other than where it was being read")
        XCTAssertNotNil(controller.view.window)
    }

    func testTheToggleClosesTheMessageAgain() async throws {
        let (_, chat) = try await loadedFeed()
        let bubble = try firstBubble(of: chat)

        try moreButton(in: bubble).performClick(nil)
        await settle()
        try moreButton(in: bubble).performClick(nil)
        await settle()

        XCTAssertTrue(bubble.isTruncated, "the toggle only goes one way")
        XCTAssertTrue(try text(of: bubble).hasSuffix("…"))
    }

    /// A watched feed throws its rows away and builds new ones every few
    /// seconds. A message the reader opened has to come back open, or it closes
    /// itself under them mid-sentence.
    func testAMessageLeftOpenComesBackOpenAfterARebuild() async throws {
        let (controller, chat) = try await loadedFeed()
        let row = try XCTUnwrap(rows(in: chat).first)
        try moreButton(in: try firstBubble(of: chat)).performClick(nil)
        await settle()

        // Resizing is a rebuild the transcript really does do: the bubbles are
        // measured against the width, so a new width is a new transcript.
        controller.view.window?.setContentSize(NSSize(width: 460, height: 640))
        try await waitUntil("the transcript was rebuilt") {
            self.rows(in: chat).first !== row
        }
        await settle()

        XCTAssertFalse(try firstBubble(of: chat).isTruncated,
                       "the rebuild closed a message the reader had opened")
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
    /// window — the shape the expand toggle actually ships in.
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

    /// The rect Auto Layout actually placed a control at — its frame minus the
    /// bezel insets AppKit grows it by.
    private func placement(of control: NSView) -> NSRect {
        control.alignmentRect(forFrame: control.frame)
    }

    private func moreButton(in bubble: AIChatBubbleView) throws -> NSButton {
        try XCTUnwrap(
            bubble.subviews
                .compactMap { $0 as? NSButton }
                .first { $0.accessibilityIdentifier() == "chat-bubble.more" },
            "the bubble has no expand toggle")
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

    /// Polls `condition` for up to two seconds, laying out between tries — the
    /// feed's read and the transcript's rebuild are both real time.
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
