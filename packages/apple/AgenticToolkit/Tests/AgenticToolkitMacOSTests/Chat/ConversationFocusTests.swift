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

    /// The control hangs off the bottom of the bubble, and its inside edge lines
    /// up with the *text's* inside edge rather than the bubble's: the text
    /// column is the line a reader's eye holds, and a control flush with a
    /// rounded corner reads as hanging past it.
    func testTheJumpControlLinesUpWithAnAssistantBubblesTextEdge() throws {
        let (_, bubble, button) = try laidOutRow(role: .assistant, text: "a short reply")
        XCTAssertEqual(
            aligned(button).maxX,
            aligned(bubble).maxX - AIChatBubbleView.textInset, accuracy: 0.5,
            "the agent's column runs left, so its bubble's inside edge is the trailing one")
        XCTAssertEqual(
            aligned(button).maxY, aligned(bubble).minY + Self.jumpOverlap, accuracy: 0.5,
            "the control is not hanging off the bottom of the bubble")
    }

    func testTheJumpControlLinesUpWithAUserBubblesTextEdge() throws {
        let (_, bubble, button) = try laidOutRow(role: .user, text: "a short prompt")
        XCTAssertEqual(
            aligned(button).minX,
            aligned(bubble).minX + AIChatBubbleView.textInset, accuracy: 0.5,
            "the human's column runs right, so its bubble's inside edge is the leading one")
        XCTAssertEqual(
            aligned(button).maxY, aligned(bubble).minY + Self.jumpOverlap, accuracy: 0.5,
            "the control is not hanging off the bottom of the bubble")
    }

    /// How far the control leans on its bubble, in points. A few — enough to
    /// say whose bubble it is, little enough that a 30pt disc never lands on
    /// the last line of the message, which is where a truncated bubble keeps
    /// its own **More…** control.
    private static let jumpOverlap: CGFloat = 4

    /// The bottom edge is the one place that is the same on every row: a bubble
    /// is as tall as its text, so a control measured from its middle moves
    /// about. A one-line bubble and a forty-line one have to overlap it by the
    /// same few points.
    func testTheJumpControlLeansOnTheBubbleByTheSameFewPointsHoweverTallItIs() throws {
        let (_, shortBubble, shortButton) = try laidOutRow(role: .assistant, text: "one line")
        let paragraph = (0..<40).map { "line \($0) of a long reply" }.joined(separator: "\n")
        let (_, tallBubble, tallButton) = try laidOutRow(role: .assistant, text: paragraph)

        XCTAssertGreaterThan(
            tallBubble.frame.height, shortBubble.frame.height * 4,
            "the fixture is wrong: the bubbles have to differ in height for this to mean anything")

        let shortOverlap = aligned(shortButton).maxY - aligned(shortBubble).minY
        let tallOverlap = aligned(tallButton).maxY - aligned(tallBubble).minY
        XCTAssertEqual(
            shortOverlap, Self.jumpOverlap, accuracy: 0.5,
            "the control leans on the bubble by \(shortOverlap)pt, not a few")
        XCTAssertLessThan(
            shortOverlap, shortBubble.frame.height,
            "the control covers the whole of a one-line bubble")
        XCTAssertEqual(
            shortOverlap, tallOverlap, accuracy: 0.5,
            "the control follows the bubble's centre, not its bottom: "
                + "\(shortOverlap) vs \(tallOverlap)")
    }

    /// Compared on alignment rects, not frames: a control's frame carries a
    /// couple of points of slack its constraints never see, and the constraint
    /// is what these are about. Neither view is flipped, so a bottom edge is a
    /// `minY`.
    private func aligned(_ view: NSView) -> NSRect {
        view.alignmentRect(forFrame: view.frame)
    }

    /// Nearly all of the control is below the bubble it is pinned to, in the
    /// band the timestamp occupies — and a row's ``ChatTranscriptRowView/hitTest(_:)``
    /// refuses anything outside its bounds, so a control hanging past either
    /// edge would be drawn and unclickable.
    func testTheRowIsTallEnoughToHoldTheJumpControl() throws {
        let (_, _, button) = try laidOutRow(role: .assistant, text: "one line")
        let row = try XCTUnwrap(button.superview as? ChatTranscriptRowView)
        XCTAssertTrue(
            row.bounds.contains(button.frame),
            "the jump control hangs outside the row: \(button.frame) in \(row.bounds)")
    }

    // MARK: - How wide a bubble may grow

    /// One column, both sides. A merged feed is read straight down, and two
    /// columns offset from each other give it four vertical edges where it
    /// meant to have two — while who is talking is already said by the fill,
    /// by the side the header is on, and by the avatar.
    func testBothColumnsRunBetweenTheSameTwoMargins() throws {
        let agent = try laidOutFeedRow(role: .assistant, text: Self.wideText)
        let human = try laidOutFeedRow(role: .user, text: Self.wideText)
        let cap = ChatTranscriptRowView.maxBubbleWidth(forRowWidth: Self.feedRowWidth)

        XCTAssertEqual(
            agent.bubble.frame.minX, human.bubble.frame.minX, accuracy: 0.5,
            "the two columns start on different lines")
        XCTAssertEqual(
            agent.bubble.frame.maxX, human.bubble.frame.maxX, accuracy: 0.5,
            "the two columns end on different lines")

        // And a message that wants the whole of it gets the whole of it, to
        // within the glyph the last line broke on.
        XCTAssertEqual(agent.bubble.frame.width, cap, accuracy: 12,
                       "the agent's bubble left room it was allowed to use")
        XCTAssertEqual(human.bubble.frame.width, cap, accuracy: 12,
                       "the human's bubble left room it was allowed to use")
    }

    /// The exception, and the reason it is one: a bubble fills the column when
    /// its text *wrapped*, because where a wrapped line happened to break says
    /// nothing. A bubble holding one short line keeps its own width — there the
    /// small shape is the message, and filling the column would put the weight
    /// of a paragraph behind "ok".
    func testAWrappedBubbleFillsTheColumnAndAOneLinerKeepsItsOwnWidth() throws {
        let short = try laidOutFeedRow(role: .assistant, text: "yes")
        let wide = try laidOutFeedRow(role: .assistant, text: Self.wideText)
        let human = try laidOutFeedRow(role: .user, text: "ok")
        let wideHuman = try laidOutFeedRow(role: .user, text: Self.wideText)
        let cap = ChatTranscriptRowView.maxBubbleWidth(forRowWidth: Self.feedRowWidth)

        XCTAssertEqual(wide.bubble.frame.width, cap, accuracy: 0.5,
                       "a wrapped message was drawn narrower than the column")
        XCTAssertLessThan(short.bubble.frame.width, cap / 2,
                          "a three-letter message was stretched across the column")
        XCTAssertLessThan(human.bubble.frame.width, cap / 2,
                          "a two-letter message was stretched across the column")

        // A short bubble gives up the *inside* edge, never the outside one:
        // which side it is on is the one thing its width must not blur.
        XCTAssertEqual(short.bubble.frame.minX, wide.bubble.frame.minX, accuracy: 0.5,
                       "a short reply started somewhere other than the agent's margin")
        XCTAssertEqual(human.bubble.frame.maxX, wideHuman.bubble.frame.maxX, accuracy: 0.5,
                       "a short prompt ended somewhere other than the human's margin")
    }

    /// The timestamp and the control come at the band under the bubble from
    /// opposite ends, and a two-letter message puts both of them at the same
    /// margin. The timestamp is what moves: a clock reading is legible anywhere
    /// in that band, while the control's position is what says which bubble it
    /// belongs to — and one drawn over the other is neither.
    func testAShortBubblesTimestampStepsAsideForTheJumpControl() throws {
        for (role, text) in [(ChatMessage.Role.user, "cy"), (.assistant, "ok")] {
            let (row, _, button) = try laidOutRow(role: role, text: text)
            let time = try timeLabel(in: row)
            XCTAssertFalse(
                time.frame.intersects(button.frame),
                "\(role) row: the timestamp \(time.frame) is under the control \(button.frame)")
        }
    }

    /// And it moves only when it has to — a bubble with room in it leaves the
    /// timestamp on the margin, where every other row's is, so the column of
    /// clock readings stays a column.
    func testAnOrdinaryBubblesTimestampStaysOnTheMargin() throws {
        let (userRow, _, _) = try laidOutRow(role: .user, text: "a prompt with some length to it")
        let (agentRow, _, _) = try laidOutRow(role: .assistant, text: "a reply with some length")
        let (shortRow, _, _) = try laidOutRow(role: .user, text: "cy")

        XCTAssertEqual(
            try timeBox(in: userRow).maxX, Self.feedRowWidth - 8, accuracy: 0.5,
            "the human's timestamp is not on the human's margin")
        XCTAssertEqual(
            try timeBox(in: agentRow).minX, 40, accuracy: 0.5,
            "the agent's timestamp is not where the agent's column starts")
        XCTAssertLessThan(
            try timeBox(in: shortRow).maxX, try timeBox(in: userRow).maxX,
            "the short row's timestamp did not move at all, so it must be under the control")
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
        // The narrowed read, not the rows: the overlay opens on what the feed
        // behind it already had, so rows are there before anything is loaded.
        try await waitUntil("the overlay read its session") { !asked.values.isEmpty }

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

    /// The flash: an overlay added and faded in the same turn began its fade on
    /// an empty frame, so the blur arrived first and the conversation landed
    /// inside it a moment later. By the time the fade starts the overlay is laid
    /// out *and* already holding this session's rows.
    func testTheOverlayIsDrawnBeforeItStartsToFadeIn() async throws {
        let (controller, _) = try await loadedFeed()

        doubleClick(try firstRow(of: controller))
        let overlay = try XCTUnwrap(focusOverlay(in: controller))

        // No settle: this is the state of the overlay at the first frame of the
        // fade, which is the frame the reader saw as a flash.
        XCTAssertEqual(overlay.frame, controller.view.bounds,
                       "the overlay had no size yet when its fade began")
        let chat = try XCTUnwrap(overlay.subviews.compactMap { $0 as? ChatView }.first)
        XCTAssertEqual(chat.frame, overlay.bounds,
                       "the overlay's transcript had no size yet when its fade began")
        XCTAssertEqual(rowTexts(in: overlay), ["s1 first", "s1 second"],
                       "the overlay faded in empty and filled itself afterwards")
    }

    /// A tracking area belongs to its view and not to what is drawn over it, so
    /// the rows under the overlay went on lighting up as the pointer crossed
    /// them — bubbles glowing through the conversation the reader had opened.
    func testHoveringOverTheOverlayDoesNotLightUpTheFeedBehindIt() async throws {
        let (controller, _) = try await loadedFeed()
        let row = try firstRow(of: controller)

        row.mouseEntered(with: mouseEvent(.mouseEntered, in: row))
        XCTAssertTrue(isHighlighted(row),
                      "the fixture is wrong: hovering a bare row does highlight it")
        row.mouseExited(with: mouseEvent(.mouseExited, in: row))

        doubleClick(row)
        _ = try XCTUnwrap(focusOverlay(in: controller))
        await settle()

        row.mouseEntered(with: mouseEvent(.mouseEntered, in: row))
        XCTAssertFalse(isHighlighted(row),
                       "a row under the overlay lit up, so the feed glows through the conversation")
    }

    /// The hover fill, read off the layer — the row keeps whether it is hovered
    /// to itself, and what this is about is what the reader can see.
    private func isHighlighted(_ row: ChatTranscriptRowView) -> Bool {
        (row.layer?.backgroundColor?.alpha ?? 0) > 0
    }

    func testTheJumpControlGoesToTheSourceRatherThanOpeningTheOverlay() async throws {
        let (controller, _) = try await loadedFeed()
        let went = Box()
        controller.onGoToSource = { went.values.append($0.attribution?.sourceID ?? "") }

        try jumpButton(in: try firstRow(of: controller)).performClick(nil)

        XCTAssertEqual(went.values, ["s1"])
        XCTAssertNil(focusOverlay(in: controller), "the jump control is not a row click")
    }

    // MARK: - Picking a row

    func testClickingARowPicksIt() async throws {
        let (controller, _) = try await loadedFeed()
        let feed = try feedChat(of: controller)
        let all = rows(in: controller)

        click(all[1])

        XCTAssertEqual(pickedTexts(in: controller), [text(of: all[1])],
                       "a single click picked nothing, or picked more than one row")
        XCTAssertEqual(feed.selectedMessageID, all[1].shownMessage.id)
    }

    /// The frame is the whole of what a reader sees, and it is drawn in the
    /// theme's selection colour — the same colour every other picked thing in
    /// the app is drawn in.
    func testThePickedRowIsFramedInTheHighlightColour() async throws {
        let (controller, _) = try await loadedFeed()
        let row = try firstRow(of: controller)

        click(row)

        XCTAssertGreaterThan(row.layer?.borderWidth ?? 0, 0, "the picked row has no frame")
        XCTAssertEqual(row.layer?.borderColor,
                       ThemePaletteObserver.currentPalette.nsColor(.selection).cgColor,
                       "the frame is not drawn in the highlight colour")
    }

    /// Each arrow enters from its own end, so the first press is never a
    /// no-op — and never a jump to whichever end the view happened to build
    /// first.
    func testWithNothingPickedDownTakesTheTopRowAndUpTheBottom() async throws {
        let (controller, _) = try await loadedFeed()
        let feed = try feedChat(of: controller)
        let all = rows(in: controller)

        feed.keyDown(with: key(code: 125))
        XCTAssertEqual(pickedTexts(in: controller), [text(of: all[0])], "down did not enter at the top")

        feed.select(nil)
        feed.keyDown(with: key(code: 126))
        XCTAssertEqual(pickedTexts(in: controller), [text(of: all[2])], "up did not enter at the bottom")
    }

    func testTheArrowsWalkTheRows() async throws {
        let (controller, _) = try await loadedFeed()
        let feed = try feedChat(of: controller)
        let all = rows(in: controller)

        click(all[0])
        feed.keyDown(with: key(code: 125))
        XCTAssertEqual(pickedTexts(in: controller), [text(of: all[1])])
        feed.keyDown(with: key(code: 126))
        XCTAssertEqual(pickedTexts(in: controller), [text(of: all[0])])
    }

    /// A timeline has two ends and neither one wraps: "one more down" at the
    /// newest message means there is nothing newer, not that the oldest is next.
    func testWalkingPastEitherEndStaysPut() async throws {
        let (controller, _) = try await loadedFeed()
        let feed = try feedChat(of: controller)
        let all = rows(in: controller)

        click(all[0])
        feed.keyDown(with: key(code: 126))
        XCTAssertEqual(pickedTexts(in: controller), [text(of: all[0])], "up wrapped round to the bottom")

        click(all[2])
        feed.keyDown(with: key(code: 125))
        XCTAssertEqual(pickedTexts(in: controller), [text(of: all[2])], "down wrapped round to the top")
    }

    func testReturnOnAPickedRowOpensTheOverlay() async throws {
        let (controller, _) = try await loadedFeed()
        let feed = try feedChat(of: controller)

        click(try firstRow(of: controller))
        feed.keyDown(with: key(code: 36))

        let overlay = try XCTUnwrap(focusOverlay(in: controller), "Return opened nothing")
        try await waitUntil("the overlay's transcript loaded") { !self.rowTexts(in: overlay).isEmpty }
        XCTAssertEqual(rowTexts(in: overlay), ["s1 first", "s1 second"])
    }

    func testShiftReturnOnAPickedRowLeavesForTheSession() async throws {
        let (controller, _) = try await loadedFeed()
        let feed = try feedChat(of: controller)
        let went = Box()
        controller.onGoToSource = { went.values.append($0.attribution?.sourceID ?? "") }

        click(try firstRow(of: controller))
        feed.keyDown(with: key(code: 36, modifiers: .shift))

        XCTAssertEqual(went.values, ["s1"])
        XCTAssertNil(focusOverlay(in: controller), "Shift-Return opened the overlay as well as leaving")
    }

    /// A read that brings something new throws away every row and builds them
    /// again, so a selection held as a view would last until the next poll. It
    /// is held by message id for exactly this.
    func testThePickSurvivesAPollThatBringsSomethingNew() async throws {
        let source = FeedSource(feedMessages)
        let (controller, _) = try await loadedFeed(source: source)
        let picked = try firstRow(of: controller)
        click(picked)
        let id = picked.shownMessage.id

        source.append(message(role: .assistant, text: "s1 third", sourceID: "s1"))
        controller.refresh()
        try await waitUntil("the feed was rebuilt") { self.rows(in: controller).count == 4 }
        await settle()

        XCTAssertFalse(rows(in: controller).contains { $0 === picked },
                       "the fixture is wrong: nothing was rebuilt, so nothing was survived")
        let row = try XCTUnwrap(rows(in: controller).first { $0.shownMessage.id == id })
        XCTAssertTrue(row.isSelected, "the poll dropped the reader's selection")
    }

    /// And a read that brings nothing new rebuilds nothing at all.
    ///
    /// A feed re-reads every few seconds and usually has the same transcript it
    /// had last time. Emptying the stack and refilling it with the same rows is
    /// a visible blink, it drops whatever the reader had selected in a bubble
    /// mid-drag, and — in the overlay, which renders once for its own
    /// construction and again when its bindings deliver the messages it was
    /// built holding — it was most of what a reader saw on the way in.
    func testAPollWithNothingNewLeavesTheRowsWhereTheyAre() async throws {
        let (controller, _) = try await loadedFeed()
        let before = rows(in: controller)
        XCTAssertFalse(before.isEmpty, "the fixture is wrong: there are no rows to leave alone")

        controller.refresh()
        try await Task.sleep(for: .milliseconds(300))
        await settle()

        let after = rows(in: controller)
        XCTAssertEqual(after.count, before.count)
        XCTAssertTrue(zip(before, after).allSatisfy { $0 === $1 },
                      "an unchanged read rebuilt the transcript, which the reader sees as a blink")
    }

    /// Inside one conversation there is nothing for Return to open and nowhere
    /// for the arrows to go that scrolling does not already do better.
    func testTheOverlayHasNoRowSelection() async throws {
        let (controller, _) = try await loadedFeed()
        doubleClick(try firstRow(of: controller))
        let overlay = try XCTUnwrap(focusOverlay(in: controller))
        await settle()

        let chat = try XCTUnwrap(overlay.subviews.compactMap { $0 as? ChatView }.first)
        XCTAssertFalse(chat.isRowSelectionEnabled)
    }

    /// The app icon says which application a row is running in — a question a
    /// *merged* feed asks and this view has already answered, since every row
    /// in it is the same session.
    func testTheOverlayShowsNoAppIconOnItsRows() async throws {
        let (controller, _) = try await loadedFeed()
        doubleClick(try firstRow(of: controller))
        let overlay = try XCTUnwrap(focusOverlay(in: controller))
        try await waitUntil("the overlay's transcript loaded") { !self.rowTexts(in: overlay).isEmpty }
        await settle()

        let chat = try XCTUnwrap(overlayChat(in: overlay))
        let rows = transcriptRows(of: chat)
        XCTAssertFalse(rows.isEmpty, "the fixture is wrong: the overlay has no rows to check")
        for row in rows {
            XCTAssertTrue(try jumpButton(in: row).isHidden,
                          "a row inside one conversation still offers to go to it")
        }
    }

    // MARK: - The letters a picked row answers to

    func testCOnAPickedRowOpensTheOverlay() async throws {
        let (controller, _) = try await loadedFeed()
        let feed = try feedChat(of: controller)

        click(try firstRow(of: controller))
        feed.keyDown(with: letter("c"))

        let overlay = try XCTUnwrap(focusOverlay(in: controller), "c opened nothing")
        try await waitUntil("the overlay's transcript loaded") { !self.rowTexts(in: overlay).isEmpty }
        XCTAssertEqual(rowTexts(in: overlay), ["s1 first", "s1 second"])
    }

    func testGOnAPickedRowLeavesForTheSession() async throws {
        let (controller, _) = try await loadedFeed()
        let feed = try feedChat(of: controller)
        let went = Box()
        controller.onGoToSource = { went.values.append($0.attribution?.sourceID ?? "") }

        click(try firstRow(of: controller))
        feed.keyDown(with: letter("g"))

        XCTAssertEqual(went.values, ["s1"])
        XCTAssertNil(focusOverlay(in: controller), "g opened the overlay as well as leaving")
    }

    func testMOnAPickedRowOpensACappedMessageOut() async throws {
        let (controller, _) = try await loadedFeed(source: FeedSource([longMessage(sourceID: "s1")]))
        let feed = try feedChat(of: controller)
        let row = try firstRow(of: controller)
        XCTAssertTrue(row.isTruncated,
                      "the fixture is wrong: the message has to be capped for m to mean anything")

        click(row)
        feed.keyDown(with: letter("m"))

        XCTAssertNotNil(expansion(in: feed), "m left a capped message capped")
    }

    /// On a message already whole the key means nothing: an overlay that opened
    /// to say "here it is again" would answer a question nobody asked.
    func testMOnAMessageThatIsAlreadyWholeOpensNothing() async throws {
        let (controller, _) = try await loadedFeed()
        let feed = try feedChat(of: controller)

        click(try firstRow(of: controller))
        feed.keyDown(with: letter("m"))

        XCTAssertNil(expansion(in: feed), "m opened a message that was not cut off")
    }

    /// ⌘C is a copy and ⌥G is a character — neither is this view's to take.
    func testALetterWithAModifierIsNotTheRowsToTake() async throws {
        let (controller, _) = try await loadedFeed()
        let feed = try feedChat(of: controller)
        let went = Box()
        controller.onGoToSource = { went.values.append($0.attribution?.sourceID ?? "") }

        click(try firstRow(of: controller))
        feed.keyDown(with: letter("c", modifiers: .command))
        feed.keyDown(with: letter("g", modifiers: .option))

        XCTAssertNil(focusOverlay(in: controller), "⌘C opened the conversation instead of copying")
        XCTAssertEqual(went.values, [], "⌥G left the window instead of typing a character")
    }

    private func expansion(in chat: ChatView) -> BubbleExpansionOverlay? {
        chat.subviews.compactMap { $0 as? BubbleExpansionOverlay }.first
    }

    private func feedChat(of controller: ConversationsViewController) throws -> ChatView {
        try XCTUnwrap(controller.view.subviews.compactMap { $0 as? ChatView }.first)
    }

    private func text(of row: ChatTranscriptRowView) -> String {
        row.shownMessage.text
    }

    /// What is drawn as picked, read off the rows rather than out of the view's
    /// own bookkeeping — a selection nobody can see is not a selection.
    private func pickedTexts(in controller: ConversationsViewController) -> [String] {
        rows(in: controller).filter(\.isSelected).map(text(of:))
    }

    // MARK: - Typing into a session

    /// The feed is a merged one, so a line typed into it has no session to
    /// belong to. The overlay is the opposite — one conversation and nothing
    /// else — which is why the composer wakes up there and only there.
    func testAnOverlayWithNowhereToWriteKeepsItsComposerOff() async throws {
        let (controller, _) = try await loadedFeed()

        doubleClick(try firstRow(of: controller))
        let overlay = try XCTUnwrap(focusOverlay(in: controller))

        XCTAssertEqual(composerIsOn(in: overlay), false,
                       "a host that cannot reach the session still offered to write to it")
    }

    func testAnOverlayTheHostCanWriteToOffersItsComposer() async throws {
        let (controller, _) = try await loadedFeed()
        controller.onSendToSource = { _, _ in nil }

        doubleClick(try firstRow(of: controller))
        let overlay = try XCTUnwrap(focusOverlay(in: controller))

        XCTAssertEqual(composerIsOn(in: overlay), true,
                       "the one view with a session to write to left its composer grey")
    }

    /// The write is a round trip through another application and the read back
    /// is a poll behind that, so "it appeared when it landed" would be seconds
    /// of a composer emptying into nothing.
    func testALineTypedShowsAtOnceAsPending() async throws {
        let session = FeedChatSession(
            refreshInterval: .seconds(3600), send: { _ in nil }, load: { [] })
        let (log, pump) = watch(session)
        defer { pump.cancel(); session.close() }

        session.send("are you still on the migration?")

        try await waitUntil("the typed line was shown") { !log.latest.isEmpty }
        let message = try XCTUnwrap(log.latest.last)
        XCTAssertEqual(message.text, "are you still on the migration?")
        XCTAssertEqual(message.role, .user)
        XCTAssertEqual(message.delivery, .sending,
                       "a line nothing has read back yet is not a settled message")
    }

    /// Read back means delivered, and the row it was standing in for is the one
    /// the source recorded — not a second copy beside it.
    func testALineReadBackStopsBeingPendingAndIsNotDoubled() async throws {
        let echo = SourceLog()
        let session = FeedChatSession(
            refreshInterval: .milliseconds(20),
            send: { text in echo.note(text); return nil },
            load: {
                echo.values.map {
                    ChatMessage(id: "recorded-\($0)", role: .user, text: $0)
                }
            }
        )
        let (log, pump) = watch(session)
        defer { pump.cancel(); session.close() }

        session.send("rebase it onto main")

        try await waitUntil("the source said the line back") {
            log.latest.count == 1 && log.latest[0].delivery == .settled
        }
        XCTAssertEqual(log.latest.map(\.text), ["rebase it onto main"],
                       "the read-back line and the pending one are both on screen")
    }

    /// An agent that is mid-turn answers when it is finished, so waiting is
    /// normal and silence is not — the difference is what the timeout draws.
    func testALineTheSourceNeverSaysBackFails() async throws {
        let session = FeedChatSession(
            refreshInterval: .seconds(3600),
            sendTimeout: .milliseconds(50),
            send: { _ in nil },
            load: { [] }
        )
        let (log, pump) = watch(session)
        defer { pump.cancel(); session.close() }

        session.send("did that land?")

        try await waitUntil("the line was given up on") {
            if case .failed = log.latest.last?.delivery { return true }
            return false
        }
        guard case .failed(let reason) = try XCTUnwrap(log.latest.last).delivery else {
            return XCTFail("the line settled after nothing ever read it back")
        }
        XCTAssertFalse(reason.isEmpty, "a failed line has to say what went wrong")
    }

    func testALineThatCouldNotBeHandedOverFailsWithTheReasonGiven() async throws {
        let session = FeedChatSession(
            refreshInterval: .seconds(3600),
            send: { _ in "this session runs in an unknown terminal." },
            load: { [] }
        )
        let (log, pump) = watch(session)
        defer { pump.cancel(); session.close() }

        session.send("compact")

        try await waitUntil("the write was refused") {
            if case .failed = log.latest.last?.delivery { return true }
            return false
        }
        XCTAssertEqual(log.latest.last?.delivery,
                       .failed("this session runs in an unknown terminal."),
                       "the reader was not told why their line did not go anywhere")
    }

    /// Both marks sit between the bubble and its timestamp, on the speaker's
    /// side: a row that is waiting is the row above the answer, not a banner
    /// somewhere else in the window.
    func testAWaitingRowShowsThinkingDots() throws {
        let row = try laidOutRow(delivery: .sending)
        let bubble = try XCTUnwrap(row.subviews.compactMap { $0 as? AIChatBubbleView }.first)
        let dots = try XCTUnwrap(
            row.subviews.compactMap { $0 as? TypingIndicatorView }.first,
            "a line still waiting to be read back is drawn as a settled one")

        XCTAssertLessThan(dots.frame.maxY, bubble.frame.minY + 0.5,
                          "the dots belong under the bubble they are waiting for")
        XCTAssertEqual(dots.frame.maxX, bubble.frame.maxX, accuracy: 0.5,
                       "the mark is on the speaker's side, like everything else in the row")
    }

    func testAFailedRowShowsItsReasonInTheDangerColour() throws {
        let row = try laidOutRow(delivery: .failed("no answer from that terminal"))
        let label = try XCTUnwrap(
            row.subviews.compactMap { $0 as? NSTextField }
                .first { $0.stringValue == "no answer from that terminal" },
            "a line that failed says nothing about it")

        XCTAssertEqual(label.textColor,
                       ThemePaletteObserver.currentPalette.nsColor(.danger),
                       "the failure reads as ordinary text")
    }

    /// One row on its own, in a window, laid out — for the delivery marks,
    /// which only exist on a message this client wrote.
    private func laidOutRow(delivery: ChatMessage.Delivery) throws -> ChatTranscriptRowView {
        var message = message(role: .user, text: "a line just typed", sourceID: "s1")
        message.delivery = delivery
        let row = ChatTranscriptRowView(
            message: message, maxBubbleWidth: 300, actions: .init())
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
        return row
    }

    /// Whether the overlay's composer takes input. Nil when there is no chat in
    /// it at all, which is a different failure from a disabled composer.
    private func composerIsOn(in overlay: ConversationFocusOverlay) -> Bool? {
        overlay.subviews.compactMap { $0 as? ChatView }.first?.isComposerEnabled
    }

    /// Every transcript a session published, newest last. Written from the
    /// session's own task and read from the test, hence the lock.
    private final class TranscriptLog: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [[ChatMessage]] = []
        func append(_ messages: [ChatMessage]) {
            lock.lock(); stored.append(messages); lock.unlock()
        }
        var latest: [ChatMessage] {
            lock.lock(); defer { lock.unlock() }; return stored.last ?? []
        }
    }

    private func watch(_ session: FeedChatSession) -> (TranscriptLog, Task<Void, Never>) {
        let log = TranscriptLog()
        let pump = Task {
            for await event in session.events() {
                if case .transcriptLoaded(let messages) = event { log.append(messages) }
            }
        }
        return (log, pump)
    }

    // MARK: - The composer, once it is awake

    /// The overlay is opened *to answer* as often as to read, and the keys have
    /// nowhere else to be while it is up.
    func testTheOverlayTakesTheKeysForItsComposer() async throws {
        let (controller, _) = try await loadedFeed()
        controller.onSendToSource = { _, _ in nil }

        doubleClick(try firstRow(of: controller))
        let overlay = try XCTUnwrap(focusOverlay(in: controller))

        XCTAssertEqual(overlayChat(in: overlay)?.isComposerFocused, true,
                       "the reader has to click the composer before they can answer")
    }

    /// Focusing a composer that is switched off would take the keys away from
    /// whatever had them and give them to something that ignores them.
    func testAnOverlayWithNowhereToWriteLeavesTheKeysAlone() async throws {
        let (controller, _) = try await loadedFeed()

        doubleClick(try firstRow(of: controller))
        let overlay = try XCTUnwrap(focusOverlay(in: controller))

        XCTAssertEqual(overlayChat(in: overlay)?.isComposerFocused, false,
                       "a composer that cannot be typed into took the keys anyway")
    }

    // MARK: - The send button

    func testTheSendButtonIsDeadUntilThereIsSomethingToSend() async throws {
        let composer = try await writableComposer()

        XCTAssertFalse(composer.send.isEnabled,
                       "an empty composer offered a send that would do nothing")

        type("hello", into: composer.field)
        XCTAssertTrue(composer.send.isEnabled, "text was typed and send stayed dead")
    }

    /// Whitespace is not something to send, and a composer holding a stray
    /// space should look as empty as it is.
    func testSpacesAloneDoNotWakeTheSendButton() async throws {
        let composer = try await writableComposer()

        type("   ", into: composer.field)

        XCTAssertFalse(composer.send.isEnabled, "whitespace counted as a message")
    }

    /// Nothing tells the delegate the field was emptied in code, so this is the
    /// case that breaks if the button is only re-read on a keystroke.
    func testSendingLeavesTheButtonDeadAgain() async throws {
        let composer = try await writableComposer()

        type("hello", into: composer.field)
        composer.send.performClick(nil)

        XCTAssertEqual(composer.field.stringValue, "")
        XCTAssertFalse(composer.send.isEnabled,
                       "the composer emptied itself and left send lit over nothing")
    }

    // MARK: - How much of a message the overlay shows

    /// The feed truncates so several conversations fit on one timeline. Opening
    /// one of them is how the rest of a message is asked for, so the overlay
    /// that answers has no cap at all.
    func testTheOverlayShowsAMessageWhole() async throws {
        let (controller, _) = try await loadedFeed()

        doubleClick(try firstRow(of: controller))
        let overlay = try XCTUnwrap(focusOverlay(in: controller))

        XCTAssertEqual(try feedChat(of: controller).bubbleLineLimit,
                       ConversationsViewController.bubbleLineLimit)
        XCTAssertNil(overlayChat(in: overlay)?.bubbleLineLimit,
                     "the closer look cut the message off at the same place the feed did")
    }

    /// An overlay whose composer is awake, with its two controls picked out.
    private func writableComposer() async throws -> (field: NSTextField, send: NSButton) {
        let (controller, _) = try await loadedFeed()
        controller.onSendToSource = { _, _ in nil }
        doubleClick(try firstRow(of: controller))
        let overlay = try XCTUnwrap(focusOverlay(in: controller))
        return try XCTUnwrap(composer(in: overlay), "the overlay has no composer")
    }

    /// Typed the way a person types: through the field editor, so the field
    /// tells its delegate about the change the way it would on a keystroke.
    /// Assigning `stringValue` sets the text and notifies nobody.
    private func type(_ text: String, into field: NSTextField) {
        field.window?.makeFirstResponder(field)
        field.currentEditor()?.insertText(text)
    }

    private func overlayChat(in overlay: ConversationFocusOverlay) -> ChatView? {
        overlay.subviews.compactMap { $0 as? ChatView }.first
    }

    private func composer(
        in overlay: ConversationFocusOverlay
    ) -> (field: NSTextField, send: NSButton)? {
        guard let chat = overlayChat(in: overlay) else { return nil }
        let views = descendants(of: chat)
        guard let field = views.compactMap({ $0 as? NSTextField })
                .first(where: { $0.accessibilityIdentifier() == "ai-chat.input" }),
              let send = views.compactMap({ $0 as? NSButton })
                .first(where: { $0.accessibilityIdentifier() == "ai-chat.send-button" })
        else { return nil }
        return (field, send)
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }

    // MARK: - The row's own header

    /// The feed and the Sessions list are looking at the same sessions, so the
    /// trail over a bubble is the *same view* the Sessions list heads its rows
    /// with — not a second rendering of the same three facts that can drift from
    /// it a separator or a colour at a time.
    func testTheRowIsHeadedByTheSessionsWindowsBreadcrumb() throws {
        let row = try laidOutRow(role: .assistant, text: "a short reply").row
        let header = try XCTUnwrap(
            row.subviews.compactMap { $0 as? SessionBreadcrumbView }.first,
            "the row's header is not the shared breadcrumb")

        XCTAssertEqual(header.segmentLabels.map(\.stringValue), ["proj", "main", "a session"])
        XCTAssertEqual(header.nameLabel?.textColor, SessionBreadcrumbView.nameColor)
    }

    /// There is only ever one human here, so an avatar repeated down every
    /// second row is a column of the same fact. The agent's stays: with work
    /// output shown it is which *kind* of line this is.
    func testTheHumansRowHasNoAvatar() throws {
        let human = try laidOutRow(role: .user, text: "a short prompt").row
        let agent = try laidOutRow(role: .assistant, text: "a short reply").row

        XCTAssertFalse(hasAvatar(human), "the human's row still carries an avatar")
        XCTAssertTrue(hasAvatar(agent), "the agent's row lost the icon that says which kind of line it is")
    }

    /// And the hole it left is closed: the human's header starts at the row's
    /// own inset, not where the avatar used to end.
    func testTheHumansRowStartsAtItsOwnEdge() throws {
        let row = try laidOutRow(role: .user, text: "a short prompt").row
        let header = try XCTUnwrap(row.subviews.compactMap { $0 as? SessionBreadcrumbView }.first)

        XCTAssertEqual(row.bounds.maxX - header.frame.maxX, 8, accuracy: 0.5,
                       "the human's row keeps a gap where the avatar was")
    }

    private func hasAvatar(_ row: ChatTranscriptRowView) -> Bool {
        row.subviews.contains { $0.subviews.contains { $0 is NSImageView } }
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
                sourceID: sourceID, context: ["proj", "main"], name: "a session", iconSymbol: "sparkles")
        )
    }

    /// What a fixture feed is reading. Changeable from the test, so a poll can
    /// bring back something the last one did not have; read from the loader,
    /// which does not run on the main actor, hence the lock.
    private final class FeedSource: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [ChatMessage]
        init(_ messages: [ChatMessage]) { stored = messages }
        var values: [ChatMessage] {
            lock.lock(); defer { lock.unlock() }; return stored
        }
        func append(_ message: ChatMessage) {
            lock.lock(); stored.append(message); lock.unlock()
        }
    }

    /// The two-session feed every test here reads, oldest first.
    private var feedMessages: [ChatMessage] {
        [
            message(role: .assistant, text: "s1 first", sourceID: "s1"),
            message(role: .user, text: "s2 first", sourceID: "s2"),
            message(role: .user, text: "s1 second", sourceID: "s1")
        ]
    }

    /// A message long enough that a feed's eight-line cap cuts it off, which is
    /// what makes "open it out" mean anything.
    private func longMessage(sourceID: String) -> ChatMessage {
        message(
            role: .assistant,
            text: (0..<40).map { "line \($0) of a long reply" }.joined(separator: "\n"),
            sourceID: sourceID)
    }

    /// A `ConversationsViewController` in a window over a two-session feed whose
    /// loader records every `sourceID` it is asked for.
    private func loadedFeed(
        source: FeedSource? = nil
    ) async throws -> (ConversationsViewController, SourceLog) {
        let asked = SourceLog()
        let feed = source ?? FeedSource(feedMessages)
        // An hour's refresh: the first read is the whole of what these tests want.
        let controller = ConversationsViewController(refreshInterval: .seconds(3600)) { _, sourceID in
            let all = feed.values
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
    ) throws -> (row: ChatTranscriptRowView, bubble: AIChatBubbleView, button: NSButton) {
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
        return (row, bubble, try jumpButton(in: row))
    }

    /// The width a fixture row is laid out at — a number rather than the
    /// window's, because the rule these tests are about is arithmetic on it.
    private static let feedRowWidth: CGFloat = 420

    /// A message with no spaces in it, so it fills every line it is given
    /// rather than stopping at the last word that fitted. That is what makes
    /// "as wide as it is allowed to be" a number a test can check.
    private static let wideText = String(repeating: "wrapping", count: 120)

    /// One row at the width a feed would give it, with its bubble sized by the
    /// row's own rule rather than by a number the test picked.
    private func laidOutFeedRow(
        role: ChatMessage.Role, text: String
    ) throws -> (row: ChatTranscriptRowView, bubble: AIChatBubbleView) {
        let row = ChatTranscriptRowView(
            message: message(role: role, text: text, sourceID: "s1"),
            maxBubbleWidth: ChatTranscriptRowView.maxBubbleWidth(forRowWidth: Self.feedRowWidth),
            actions: .init(onJump: { _ in })
        )
        let host = NSView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.feedRowWidth, height: 600),
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
        return (row, bubble)
    }

    /// The row's clock reading. The only text field the row holds directly —
    /// the crumbs are inside the header view, which is one subview of its own.
    private func timeLabel(in row: ChatTranscriptRowView) throws -> NSTextField {
        try XCTUnwrap(
            row.subviews.compactMap { $0 as? NSTextField }.first,
            "the row has no timestamp"
        )
    }

    /// Where the clock reading was *pinned*, which is not where its view is: a
    /// label's frame stands a couple of points proud of its text on each side,
    /// so a margin read off the frame misses by that much every time.
    private func timeBox(in row: ChatTranscriptRowView) throws -> NSRect {
        let label = try timeLabel(in: row)
        return label.alignmentRect(forFrame: label.frame)
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
        // Entering and leaving are not mouse events as far as this factory is
        // concerned: handed one, it trips an AppKit assertion and takes the
        // whole test process with it rather than returning nil.
        if type == .mouseEntered || type == .mouseExited {
            return enterExitEvent(type, in: view, at: centre)
        }
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

    private func enterExitEvent(
        _ type: NSEvent.EventType, in view: NSView, at point: NSPoint
    ) -> NSEvent {
        NSEvent.enterExitEvent(
            with: type,
            location: view.convert(point, to: nil),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: view.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 0,
            trackingNumber: 0,
            userData: nil
        )!
    }

    private func key(code: UInt16, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: windows.last?.windowNumber ?? 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: code
        )!
    }

    /// A letter, as a keyboard sends it: the character matters and the key code
    /// does not, which is the opposite way round from the arrows and Return.
    private func letter(_ character: String, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: windows.last?.windowNumber ?? 0,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: 0
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
