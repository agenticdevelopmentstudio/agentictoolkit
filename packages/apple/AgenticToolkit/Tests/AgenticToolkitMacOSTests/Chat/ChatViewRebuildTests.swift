// Tests/AgenticToolkitMacOSTests/Chat/ChatViewRebuildTests.swift
import AppKit
import XCTest
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// A feed rebuilds its whole transcript on every poll that changed anything.
/// What the reader was doing has to survive that: where they had scrolled to,
/// the text they were dragging across, the row they picked from the keyboard.
/// A rebuild that loses any of these still renders a correct transcript, so
/// nothing but a test notices.
@MainActor
final class ChatViewRebuildTests: XCTestCase {
    private var window: NSWindow?
    private var viewModel: AIChatViewModel?

    override func tearDown() async throws {
        window?.orderOut(nil)
        window = nil
        try await super.tearDown()
    }

    // MARK: - Scroll position

    func testAReaderScrolledBackKeepsTheirPlaceWhenAMessageArrives() async throws {
        let feed = Feed(count: 60)
        let (view, session) = try await loadedTranscript(feed)
        let scroll = try transcriptScroll(of: view)

        // Somewhere in the middle, well away from the bottom.
        let target = try row("m20", in: view)
        target.scrollToVisible(target.bounds)
        await settle()
        let before = try topmostShowing(in: view)

        feed.append(ChatMessage(id: "m60", role: .assistant, text: "message 60"))
        session.refresh()
        await waitUntil { self.existingRow("m60", in: view) != nil }
        await settle()

        let after = try topmostShowing(in: view)
        XCTAssertEqual(after.id, before.id, "the rebuild put a different message at the top")
        XCTAssertEqual(after.offset, before.offset, accuracy: 1,
                       "the same message came back at a different place")
        XCTAssertFalse(scroll.documentVisibleRect.intersects(try row("m60", in: view).frame),
                       "a reader scrolled back was dragged down to the new message")
    }

    // MARK: - Text selection

    func testARebuildWaitsForTheReaderToFinishSelectingText() async throws {
        let feed = Feed(count: 3)
        let (view, session) = try await loadedTranscript(feed)
        let text = try XCTUnwrap(textView(in: try row("m1", in: view)))
        window?.makeFirstResponder(text)
        text.setSelectedRange(NSRange(location: 0, length: 4))

        feed.append(ChatMessage(id: "m3", role: .assistant, text: "message 3"))
        session.refresh()
        await settle()
        await settle()
        XCTAssertNil(existingRow("m3", in: view),
                     "the transcript was rebuilt under a live selection, and the selection with it")
        XCTAssertTrue(text.window != nil && text.selectedRange().length == 4,
                      "the selected text is no longer on screen")

        // Letting go — a click in the text collapses it to a caret.
        text.setSelectedRange(NSRange(location: 0, length: 0))
        await waitUntil { self.existingRow("m3", in: view) != nil }
        XCTAssertNotNil(existingRow("m3", in: view), "the held rebuild never ran")
    }

    // MARK: - Keyboard selection

    func testAPickFromTheKeyboardScrollsItsRowIntoView() async throws {
        let (view, _) = try await loadedTranscript(Feed(count: 60, attributed: true))
        view.isRowSelectionEnabled = true
        await settle()
        let scroll = try transcriptScroll(of: view)
        XCTAssertFalse(scroll.documentVisibleRect.intersects(try row("m0", in: view).frame),
                       "precondition: the oldest message starts off screen")

        view.select("m0")
        await settle()
        XCTAssertTrue(scroll.documentVisibleRect.intersects(try row("m0", in: view).frame),
                      "the picked row is still off screen")
    }

    func testAClickedPickDoesNotScroll() async throws {
        let (view, _) = try await loadedTranscript(Feed(count: 60, attributed: true))
        view.isRowSelectionEnabled = true
        await settle()
        let scroll = try transcriptScroll(of: view)
        let before = scroll.documentVisibleRect

        view.select("m0", reveal: false)
        await settle()
        XCTAssertEqual(scroll.documentVisibleRect, before, "a pick that asked not to reveal scrolled")
    }

    // MARK: - Fixtures

    /// The source a test changes between polls.
    private final class Feed: @unchecked Sendable {
        private let lock = NSLock()
        private var messages: [ChatMessage]

        init(count: Int, attributed: Bool = false) {
            let attribution = ChatMessage.Attribution(
                sourceID: "s1", context: ["proj"], name: "session", iconSymbol: "terminal")
            messages = (0..<count).map {
                ChatMessage(id: "m\($0)", role: $0.isMultiple(of: 2) ? .user : .assistant,
                            text: "message \($0)", attribution: attributed ? attribution : nil)
            }
        }

        var current: [ChatMessage] { lock.lock(); defer { lock.unlock() }; return messages }

        func append(_ message: ChatMessage) {
            lock.lock(); defer { lock.unlock() }; messages.append(message)
        }
    }

    private func loadedTranscript(_ feed: Feed) async throws -> (ChatView, FeedChatSession) {
        // An hour's refresh: every read after the first is one the test asks for.
        let session = FeedChatSession(refreshInterval: .seconds(3600)) { feed.current }
        let viewModel = AIChatViewModel(session: session)
        self.viewModel = viewModel
        let view = ChatView(viewModel: viewModel)
        view.isComposerEnabled = false

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = view
        self.window = window

        await waitUntil { !viewModel.messages.isEmpty }
        await settle()
        return (view, session)
    }

    private func settle() async {
        for _ in 0..<5 {
            window?.contentView?.layoutSubtreeIfNeeded()
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(20))
        }
        window?.contentView?.layoutSubtreeIfNeeded()
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<150 where !condition() {
            try? await Task.sleep(for: .milliseconds(20))
            window?.contentView?.layoutSubtreeIfNeeded()
        }
    }

    private func transcriptScroll(of view: ChatView) throws -> NSScrollView {
        try XCTUnwrap(view.subviews.compactMap { $0 as? NSScrollView }.first)
    }

    private func row(_ id: String, in view: ChatView) throws -> NSView {
        try XCTUnwrap(existingRow(id, in: view), "no row for \(id)")
    }

    /// The row for `id`, or nil — for the checks where "not there (yet)" is the
    /// answer. `XCTUnwrap` records a failure even under `try?`, so a poll built
    /// on ``row(_:in:)`` fails the test on every miss before the row arrives.
    private func existingRow(_ id: String, in view: ChatView) -> NSView? {
        let scroll = view.subviews.compactMap { $0 as? NSScrollView }.first
        let stack = scroll?.documentView as? NSStackView
        return stack?.arrangedSubviews.first { $0.identifier?.rawValue == id }
    }

    /// The topmost message on screen and how far the visible top sits below
    /// that message's own top — the reader's place, as they would describe it.
    private func topmostShowing(in view: ChatView) throws -> (id: String, offset: CGFloat) {
        let scroll = try transcriptScroll(of: view)
        let stack = try XCTUnwrap(scroll.documentView as? NSStackView)
        let visible = scroll.documentVisibleRect
        let showing = stack.arrangedSubviews.filter { $0.identifier != nil && $0.frame.intersects(visible) }
        let flipped = stack.isFlipped
        let top = try XCTUnwrap(flipped
            ? showing.min { $0.frame.minY < $1.frame.minY }
            : showing.max { $0.frame.maxY < $1.frame.maxY })
        let offset = flipped ? visible.minY - top.frame.minY : top.frame.maxY - visible.maxY
        return (try XCTUnwrap(top.identifier?.rawValue), offset)
    }

    private func textView(in view: NSView) -> NSTextView? {
        if let text = view as? NSTextView { return text }
        for sub in view.subviews { if let found = textView(in: sub) { return found } }
        return nil
    }
}
