import AppKit
import XCTest
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// Switching conversations in single mode: the screen changes on the keystroke,
/// never after the read, and never shows the previous conversation under the
/// new pick.
@MainActor
final class ConversationsSwitchTests: XCTestCase {

    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        try await super.tearDown()
    }

    func testASwitchToAnUnreadConversationClearsTheScreenAtOnce() async throws {
        let controller = try await singleFeed(showing: "s1")
        XCTAssertTrue(texts(of: controller).allSatisfy { $0.hasPrefix("s1") })

        controller.soloSessionID = "s3"
        await layout()

        XCTAssertEqual(rowCount(of: controller), 0,
                       "s1's rows stayed on screen under the s3 pick")
    }

    func testASwitchToAConversationReadBeforeDrawsItAtOnce() async throws {
        let controller = try await singleFeed(showing: "s1")
        controller.soloSessionID = "s2"
        try await waitUntil("s2 was read") {
            self.texts(of: controller).contains("s2 one")
        }

        controller.soloSessionID = "s1"
        await layout()

        XCTAssertEqual(texts(of: controller).sorted(), ["s1 one", "s1 two"],
                       "a conversation already read waited for another read")
    }

    func testPrefetchFillsTheCacheSoTheSwitchIsInstant() async throws {
        let controller = try await singleFeed(showing: "s1")
        XCTAssertFalse(controller.hasCachedTranscript(for: "s3"))

        controller.prefetch(["s2", "s3"])
        try await waitUntil("the prefetch landed") {
            controller.hasCachedTranscript(for: "s2") && controller.hasCachedTranscript(for: "s3")
        }

        controller.soloSessionID = "s3"
        await layout()
        XCTAssertEqual(texts(of: controller), ["s3 one"])
    }

    // MARK: - Fixtures

    private nonisolated static let rows: [String: [String]] = [
        "s1": ["s1 one", "s1 two"],
        "s2": ["s2 one"],
        "s3": ["s3 one"]
    ]

    private nonisolated static func message(_ text: String, in id: String) -> ChatMessage {
        ChatMessage(
            id: "\(id)-\(text)",
            role: .assistant,
            text: text,
            attribution: .init(
                sourceID: id, context: ["proj", "main"], name: id, iconSymbol: "sparkles")
        )
    }

    /// A three-session feed in single mode, showing `id`. A read for one
    /// session returns only its rows; the merged read returns all of them.
    private func singleFeed(showing id: String) async throws -> ConversationsViewController {
        let controller = ConversationsViewController(refreshInterval: .seconds(3600)) { _, source, _ in
            let ids = source.map { [$0] } ?? Self.rows.keys.sorted()
            return ids.flatMap { id in (Self.rows[id] ?? []).map { Self.message($0, in: id) } }
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = controller.view
        windows.append(window)

        controller.soloSessionID = id
        controller.selectionMode = .single
        try await waitUntil("\(id) loaded") { self.texts(of: controller).contains("\(id) one") }
        return controller
    }

    private func texts(of controller: ConversationsViewController) -> [String] {
        rowViews(of: controller).map(\.message.text)
    }

    private func rowCount(of controller: ConversationsViewController) -> Int {
        rowViews(of: controller).count
    }

    private func rowViews(of controller: ConversationsViewController) -> [ChatTranscriptRowView] {
        guard let chat = controller.view.subviews.compactMap({ $0 as? ChatView }).first,
              let scroll = chat.subviews.compactMap({ $0 as? NSScrollView }).first,
              let stack = scroll.documentView as? NSStackView else { return [] }
        return stack.arrangedSubviews.compactMap { $0 as? ChatTranscriptRowView }
    }

    /// Lets the transcript's publish reach the view — one runloop turn, far
    /// short of the settle a re-read waits out.
    private func layout() async {
        for _ in 0..<3 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
            windows.last?.contentView?.layoutSubtreeIfNeeded()
        }
    }

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
}
