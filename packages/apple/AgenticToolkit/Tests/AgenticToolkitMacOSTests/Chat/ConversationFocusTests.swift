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
        let (_, bubble, button) = try laidOutRow(role: .assistant, text: "a short reply")
        XCTAssertEqual(
            button.frame.minX - bubble.frame.maxX, 10, accuracy: 0.5,
            "the agent's column runs left, so its bubble's inside edge is the trailing one")
    }

    func testTheJumpControlSitsTenPointsOffAUserBubblesInsideEdge() throws {
        let (_, bubble, button) = try laidOutRow(role: .user, text: "a short prompt")
        XCTAssertEqual(
            bubble.frame.minX - button.frame.maxX, 10, accuracy: 0.5,
            "the human's column runs right, so its bubble's inside edge is the leading one")
    }

    /// "Level with the bubble's top" only differs from "centred on the bubble"
    /// once a bubble is more than one line tall — so the test is that a one-line
    /// bubble and a forty-line one put the control the same distance below their
    /// own top edge.
    func testTheJumpControlSitsLevelWithTheBubblesTopHoweverTallTheBubbleIs() throws {
        let (_, shortBubble, shortButton) = try laidOutRow(role: .assistant, text: "one line")
        let paragraph = (0..<40).map { "line \($0) of a long reply" }.joined(separator: "\n")
        let (_, tallBubble, tallButton) = try laidOutRow(role: .assistant, text: paragraph)

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
        let (_, _, button) = try laidOutRow(role: .assistant, text: "one line")
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

    /// A feed throws away every row and builds it again on each poll, so a
    /// selection held as a view would last until the next read. It is held by
    /// message id for exactly this.
    func testThePickSurvivesTheNextPoll() async throws {
        let (controller, _) = try await loadedFeed()
        let picked = try firstRow(of: controller)
        click(picked)
        let id = picked.shownMessage.id

        controller.refresh()
        try await waitUntil("the feed was rebuilt") { self.rows(in: controller).first !== picked }
        await settle()

        let row = try XCTUnwrap(rows(in: controller).first { $0.shownMessage.id == id })
        XCTAssertTrue(row.isSelected, "the poll dropped the reader's selection")
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
