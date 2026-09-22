import AppKit
import XCTest
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// The line over the Conversations composer that says what the shown session is
/// doing, and the prompt in front of the composer itself.
///
/// In single mode the agent's work output moves out of the transcript and onto
/// that one line: a stack of "let me check X" bubbles buries what the agent
/// actually said, while one line replaced as it moves says what it is doing now.
@MainActor
final class ConversationsStatusLineTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        try await super.tearDown()
    }

    // MARK: - The prompt

    func testTheFeedsComposerWearsAPrompt() async throws {
        let controller = try await loadedFeed(messages: [reply("done")])
        XCTAssertEqual(chat(of: controller).composerPrompt, ">")
    }

    func testAChatViewHasNoPromptUntilOneIsSet() {
        let chat = ChatView(viewModel: AIChatViewModel(session: MockChatSession()))
        XCTAssertNil(chat.composerPrompt, "an ordinary chat reads as a message box, not a shell")
    }

    // MARK: - The status line

    func testSingleModeSaysWhatTheWorkingAgentIsDoing() async throws {
        let controller = try await loadedFeed(messages: [
            reply("here is the plan"),
            work("Reading ConversationsViewController.swift\nand then some")
        ])
        controller.selectionMode = .single
        controller.activity = ["s1": .working]

        try await waitUntil("the status line said what the agent is doing") {
            controller.statusText == "Reading ConversationsViewController.swift"
        }
    }

    func testAnIdleSessionHasNoStatusLine() async throws {
        let controller = try await loadedFeed(messages: [work("Reading a file")])
        controller.selectionMode = .single
        controller.activity = ["s1": .idle]
        await settle()

        XCTAssertNil(controller.statusText, "a finished turn still claimed the agent was busy")
    }

    func testTheMergedFeedHasNoStatusLine() async throws {
        let controller = try await loadedFeed(messages: [work("Reading a file")])
        controller.activity = ["s1": .working]
        await settle()

        XCTAssertNil(controller.statusText, "the merged feed picked one conversation to talk about")
    }

    /// A reply from before the turn started says nothing about the turn.
    func testWorkingWithNothingNewSaysOnlyThatItIsWorking() async throws {
        let controller = try await loadedFeed(messages: [work("Reading a file"), reply("done")])
        controller.selectionMode = .single
        controller.activity = ["s1": .working]

        try await waitUntil("the status line came up") { controller.statusText != nil }
        XCTAssertEqual(controller.statusText, "Working…")
    }

    func testAWaitingAgentSaysItIsWaitingForTheReader() async throws {
        let controller = try await loadedFeed(messages: [reply("may I?")])
        controller.selectionMode = .single
        controller.activity = ["s1": .waiting]

        try await waitUntil("the status line came up") { controller.statusText != nil }
        XCTAssertEqual(controller.statusText, "Waiting for you…")
    }

    func testTheStatusLineGoesWhenTheTurnEnds() async throws {
        let controller = try await loadedFeed(messages: [work("Reading a file")])
        controller.selectionMode = .single
        controller.activity = ["s1": .working]
        try await waitUntil("the status line came up") { controller.statusText != nil }

        controller.activity = ["s1": .idle]
        XCTAssertNil(controller.statusText)
    }

    // MARK: - Work output leaves the transcript

    func testSingleModeTakesWorkOutputOutOfTheTranscript() async throws {
        let controller = try await loadedFeed(messages: [reply("here is the plan"), work("Reading a file")])
        controller.selectionMode = .single

        try await waitUntil("the work bubble left") { self.rowCount(of: controller) == 1 }
    }

    func testAReaderWhoAskedForWorkOutputKeepsItsBubblesInSingleMode() async throws {
        let controller = try await loadedFeed(messages: [reply("here is the plan"), work("Reading a file")])
        controller.includeWorkOutput = true
        controller.selectionMode = .single
        await settle()

        XCTAssertEqual(rowCount(of: controller), 2)
    }

    func testTurningWorkOutputOnInSingleModeBringsItsBubblesBack() async throws {
        let controller = try await loadedFeed(messages: [reply("here is the plan"), work("Reading a file")])
        controller.selectionMode = .single
        try await waitUntil("the work bubble left") { self.rowCount(of: controller) == 1 }

        controller.includeWorkOutput = true
        try await waitUntil("the work bubble came back") { self.rowCount(of: controller) == 2 }
    }

    // MARK: - Fixtures

    private func reply(_ text: String) -> ChatMessage {
        message(text, isWorkOutput: false)
    }

    private func work(_ text: String) -> ChatMessage {
        message(text, isWorkOutput: true)
    }

    private func message(_ text: String, isWorkOutput: Bool) -> ChatMessage {
        ChatMessage(
            id: "s1-\(text)",
            role: .assistant,
            text: text,
            attribution: .init(
                sourceID: "s1", context: ["proj", "main"], name: "a session",
                iconSymbol: "sparkles"),
            isWorkOutput: isWorkOutput
        )
    }

    /// A one-session feed, loaded. An hour's refresh interval, so every read
    /// is one the code under test asked for.
    private func loadedFeed(messages: [ChatMessage]) async throws -> ConversationsViewController {
        let controller = ConversationsViewController(refreshInterval: .seconds(3600)) { _, _, _ in
            messages
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = controller.view
        windows.append(window)

        try await waitUntil("the feed loaded") { self.rowCount(of: controller) > 0 }
        await settle()
        return controller
    }

    private func chat(of controller: ConversationsViewController) -> ChatView {
        controller.view.subviews.compactMap { $0 as? ChatView }.first!
    }

    private func rowCount(of controller: ConversationsViewController) -> Int {
        let chat = chat(of: controller)
        guard let scroll = chat.subviews.compactMap({ $0 as? NSScrollView }).first,
              let stack = scroll.documentView as? NSStackView else { return 0 }
        return stack.arrangedSubviews.compactMap { $0 as? ChatTranscriptRowView }.count
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

    private func settle() async {
        for _ in 0..<5 {
            windows.last?.contentView?.layoutSubtreeIfNeeded()
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}
