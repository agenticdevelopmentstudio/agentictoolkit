// Tests/AgenticToolkitMacOSTests/Chat/TranscriptWidthTests.swift
import AppKit
import XCTest
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// Whether a window holding a transcript can be made narrower again.
///
/// A transcript measures its bubbles against the width it is being laid out at,
/// and writes each measurement down as a constraint. Left required, those
/// measurements become the window's own minimum — so the window can be widened
/// and never narrowed, and every widening raises the floor. The reader sees a
/// window that ratchets: drag it out once and the edge will not come back.
///
/// It is invisible to every other test here, because it is not about what a
/// transcript draws at a width — it is about what the *last* width did to the
/// next one.
@MainActor
final class TranscriptWidthTests: XCTestCase {
    private var window: NSWindow?

    override func tearDown() async throws {
        window?.orderOut(nil)
        window = nil
        try await super.tearDown()
    }

    /// The ratchet itself: laid out wide, then asked to be narrow.
    func testATranscriptLaidOutWideCanBeMadeNarrowAgain() async throws {
        let view = try await transcriptView(width: 1400)
        let window = try XCTUnwrap(self.window)

        window.setContentSize(NSSize(width: 420, height: 800))
        view.layoutSubtreeIfNeeded()
        await Task.yield()
        view.layoutSubtreeIfNeeded()

        XCTAssertLessThanOrEqual(
            window.contentView?.frame.width ?? 0, 460,
            "the window would not go back below the width its bubbles were measured at")
    }

    /// The same thing said about the view rather than the window, which is where
    /// the window's minimum comes from: a transcript's smallest satisfiable
    /// width must not be the width it happens to be at.
    func testATranscriptDoesNotMakeItsOwnLayoutWidthAMinimum() async throws {
        let view = try await transcriptView(width: 1400)
        XCTAssertLessThanOrEqual(
            view.fittingSize.width, 460,
            "a transcript laid out at 1400 insists on \(view.fittingSize.width) points")
    }

    // MARK: - Fixtures

    /// A merged-feed transcript — attributed rows, the kind the Conversations
    /// window draws — laid out in a resizable window of the given width.
    private func transcriptView(width: CGFloat) async throws -> ChatView {
        let now = Date()
        let messages = (0..<4).map { index in
            ChatMessage(
                id: "m\(index)",
                role: index.isMultiple(of: 2) ? .assistant : .user,
                text: String(repeating: "a long line of transcript ", count: 6),
                timestamp: now.addingTimeInterval(Double(index) * 60),
                attribution: .init(
                    sourceID: "s\(index % 2)",
                    context: ["stenographer", "conversations"],
                    name: "a session",
                    iconSymbol: "sparkles"))
        }
        let session = FeedChatSession(refreshInterval: .seconds(3600)) { messages }
        let viewModel = AIChatViewModel(session: session)
        let view = ChatView(viewModel: viewModel)
        view.isComposerEnabled = false

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 800),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false)
        window.contentView = view
        self.window = window

        for _ in 0..<100 where viewModel.messages.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        for _ in 0..<5 {
            view.layoutSubtreeIfNeeded()
            await Task.yield()
            try await Task.sleep(for: .milliseconds(20))
        }
        view.layoutSubtreeIfNeeded()
        return view
    }
}
