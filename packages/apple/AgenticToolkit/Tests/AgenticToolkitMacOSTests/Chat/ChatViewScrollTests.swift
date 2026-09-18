// Tests/AgenticToolkitMacOSTests/Chat/ChatViewScrollTests.swift
import AppKit
import XCTest
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// A transcript taller than its window has to open on its newest message, and a
/// feed that reloads the whole transcript has to stay there. Getting the scroll
/// geometry backwards is invisible to a build and to every other test: the
/// window renders correctly, it just shows the oldest message it has and never
/// moves again.
@MainActor
final class ChatViewScrollTests: XCTestCase {
    private var window: NSWindow?

    override func tearDown() async throws {
        window?.orderOut(nil)
        window = nil
        try await super.tearDown()
    }

    func testALongTranscriptOpensOnItsNewestMessage() async throws {
        let (view, viewModel) = try await loadedTranscript(count: 60)
        XCTAssertEqual(viewModel.messages.count, 60)

        let (scroll, rows) = try transcriptRows(of: view)
        let newest = try XCTUnwrap(rows.last)
        let oldest = try XCTUnwrap(rows.first)

        XCTAssertTrue(
            scroll.documentVisibleRect.intersects(newest.frame),
            "the newest message is off screen: visible \(scroll.documentVisibleRect), newest \(newest.frame)")
        XCTAssertFalse(
            scroll.documentVisibleRect.intersects(oldest.frame),
            "the whole 60-message transcript cannot fit — showing the oldest means it never scrolled")
    }

    func testReloadingTheTranscriptKeepsTheNewestMessageInView() async throws {
        let (view, _) = try await loadedTranscript(count: 60)

        // A feed replaces its transcript wholesale on every poll. The rebuild
        // empties the stack, which is a clip-view bounds change the reader never
        // made — if it counts as one, the view stops following the feed.
        for _ in 0..<3 {
            NotificationCenter.default.post(
                name: NSView.boundsDidChangeNotification,
                object: try transcriptRows(of: view).0.contentView)
            await settle()
        }

        let (scroll, rows) = try transcriptRows(of: view)
        let newest = try XCTUnwrap(rows.last)
        XCTAssertTrue(
            scroll.documentVisibleRect.intersects(newest.frame),
            "after a reload the newest message is off screen: visible \(scroll.documentVisibleRect)")
    }

    // MARK: - Fixtures

    /// A `ChatView` in a window, showing `count` messages of a read-only feed.
    private func loadedTranscript(count: Int) async throws -> (ChatView, AIChatViewModel) {
        let messages = (0..<count).map {
            ChatMessage(role: $0.isMultiple(of: 2) ? .user : .assistant, text: "message \($0)")
        }
        // An hour's refresh: the first load is the whole of what this test wants.
        let session = FeedChatSession(refreshInterval: .seconds(3600)) { messages }
        let viewModel = AIChatViewModel(session: session)
        let view = ChatView(viewModel: viewModel)
        view.isComposerEnabled = false

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        self.window = window

        for _ in 0..<100 where viewModel.messages.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        await settle()
        return (view, viewModel)
    }

    /// Lets the coalesced rebuild and the scroll it schedules actually run.
    private func settle() async {
        for _ in 0..<5 {
            window?.contentView?.layoutSubtreeIfNeeded()
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(20))
        }
        window?.contentView?.layoutSubtreeIfNeeded()
    }

    /// The transcript scroll view and its message rows, oldest first. The first
    /// arranged subview is the spacer `ChatView` puts above the transcript.
    private func transcriptRows(of view: ChatView) throws -> (NSScrollView, [NSView]) {
        let scroll = try XCTUnwrap(view.subviews.compactMap { $0 as? NSScrollView }.first)
        let stack = try XCTUnwrap(scroll.documentView as? NSStackView)
        return (scroll, Array(stack.arrangedSubviews.dropFirst()))
    }
}
