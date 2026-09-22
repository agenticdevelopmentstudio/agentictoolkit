// Tests/AgenticToolkitMacOSTests/Chat/ConversationsWorkOutputTests.swift
import AppKit
import XCTest
@testable import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// Who decides whether the merged feed carries the agent's work output.
///
/// The reader does, except in single mode, where the argument for hiding it
/// does not apply: narration only buries a conversation when there are other
/// conversations to bury it under. None of this is visible in a screenshot —
/// what it changes is the `includeWorkOutput` argument the loader is handed —
/// so it is asserted on the reads themselves.
@MainActor
final class ConversationsWorkOutputTests: XCTestCase {

    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        try await super.tearDown()
    }

    // MARK: - The rule

    func testTheReaderGetsWhatTheyAskedForInMultiMode() async throws {
        let (controller, asked) = try await loadedFeed()
        XCTAssertEqual(asked.latest, false, "off by default")

        controller.includeWorkOutput = true
        try await waitUntil("the feed re-read with work output") { asked.latest == true }

        controller.includeWorkOutput = false
        try await waitUntil("the feed re-read without it") { asked.latest == false }
    }

    func testSingleModeShowsWorkOutputWhateverTheReaderAskedFor() async throws {
        let (controller, asked) = try await loadedFeed()
        XCTAssertFalse(controller.includeWorkOutput)

        controller.selectionMode = .single
        try await waitUntil("the feed re-read with work output") { asked.latest == true }
        XCTAssertTrue(controller.isWorkOutputForced)
    }

    /// The reader's own setting is the one they get back — not whatever the mode
    /// left behind, in either direction.
    func testLeavingSingleModeRestoresTheReadersOwnSetting() async throws {
        let (controller, asked) = try await loadedFeed()

        controller.selectionMode = .single
        try await waitUntil("work output came on") { asked.latest == true }
        XCTAssertFalse(controller.includeWorkOutput, "the mode is not the reader")

        controller.selectionMode = .multi
        try await waitUntil("work output went off again") { asked.latest == false }
        XCTAssertFalse(controller.isWorkOutputForced)
    }

    func testAReaderWhoWantedWorkOutputKeepsItAcrossARoundTrip() async throws {
        let (controller, asked) = try await loadedFeed()
        controller.includeWorkOutput = true
        try await waitUntil("work output came on") { asked.latest == true }

        controller.selectionMode = .single
        controller.selectionMode = .multi
        await settle()

        XCTAssertTrue(controller.includeWorkOutput)
        XCTAssertEqual(asked.latest, true, "the mode must not switch off what the reader chose")
    }

    /// Entering single mode with the setting already on has nothing to change,
    /// and a refresh that asks the same question costs the reader their rows.
    func testNoRedundantRereadWhenTheSettingIsAlreadyOn() async throws {
        let (controller, asked) = try await loadedFeed()
        controller.includeWorkOutput = true
        try await waitUntil("work output came on") { asked.latest == true }
        await settle()

        let before = asked.count
        controller.selectionMode = .single
        await settle()
        XCTAssertEqual(asked.count, before, "nothing moved, so nothing should have been re-read")
    }

    // MARK: - Fixtures

    /// Every `includeWorkOutput` the loader was asked for, in order.
    private final class ReadLog: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [Bool] = []
        func note(_ includeWorkOutput: Bool) {
            lock.lock(); stored.append(includeWorkOutput); lock.unlock()
        }
        var latest: Bool? {
            lock.lock(); defer { lock.unlock() }; return stored.last
        }
        var count: Int {
            lock.lock(); defer { lock.unlock() }; return stored.count
        }
    }

    private func message(text: String, sourceID: String) -> ChatMessage {
        ChatMessage(
            id: "\(sourceID)-\(text)",
            role: .assistant,
            text: text,
            attribution: .init(
                sourceID: sourceID, context: ["proj", "main"], name: "a session",
                iconSymbol: "sparkles")
        )
    }

    /// A controller over a one-session feed whose loader records what it is
    /// asked for. An hour's refresh interval, so every read in these tests is
    /// one the code under test asked for rather than the poll coming round.
    private func loadedFeed() async throws -> (ConversationsViewController, ReadLog) {
        let asked = ReadLog()
        let messages = [message(text: "s1 said something", sourceID: "s1")]
        let controller = ConversationsViewController(
            refreshInterval: .seconds(3600)
        ) { includeWorkOutput, sourceID, _ in
            guard sourceID == nil else { return messages }
            asked.note(includeWorkOutput)
            return messages
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = controller.view
        windows.append(window)

        try await waitUntil("the feed loaded") { asked.count > 0 }
        await settle()
        return (controller, asked)
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
