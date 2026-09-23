// Tests/AgenticToolkitMacOSTests/Chat/BubbleStyleTests.swift
import AppKit
import XCTest
@testable import AgenticToolkitCore
@testable import AgenticToolkitCoreMacOS
@testable import AgenticToolkitMacOS

/// What a bubble is painted in: the terminal box the Sessions window draws,
/// and the muted text that sets work output back from the conversation.
@MainActor
final class BubbleStyleTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        try await super.tearDown()
    }

    func testWorkOutputIsDrawnMutedInEitherStyle() throws {
        let palette = ThemePaletteObserver.currentPalette
        for style in [AIChatBubbleView.Style.speaker, .terminal] {
            let work = try textColor(of: bubble(style: style, isWorkOutput: true))
            let said = try textColor(of: bubble(style: style, isWorkOutput: false))
            XCTAssertEqual(work, palette.nsColor(.secondaryText), "\(style): work output is not muted")
            XCTAssertNotEqual(work, said, "\(style): work output reads the same as the agent talking")
        }
    }

    func testTheTerminalBubbleIsTheSessionsWindowsBox() throws {
        let palette = ThemePaletteObserver.currentPalette
        let box = bubble(style: .terminal, isWorkOutput: false)
        let layer = try XCTUnwrap(box.layer)
        XCTAssertEqual(layer.cornerRadius, TerminalBoxStyle.cornerRadius)
        XCTAssertEqual(layer.borderWidth, TerminalBoxStyle.borderWidth)
        XCTAssertEqual(layer.backgroundColor, TerminalBoxStyle.fill(palette).cgColor)
        XCTAssertEqual(layer.borderColor, TerminalBoxStyle.border(palette).cgColor)
    }

    // MARK: - Fixtures

    private func bubble(style: AIChatBubbleView.Style, isWorkOutput: Bool) -> AIChatBubbleView {
        let bubble = AIChatBubbleView(
            message: ChatMessage(id: "m", role: .assistant, text: "Read(file.swift)",
                                 isWorkOutput: isWorkOutput),
            maxWidth: 300, style: style, showsInlineTimestamp: false)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false)
        let host = NSView()
        window.contentView = host
        windows.append(window)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(bubble)
        NSLayoutConstraint.activate([
            bubble.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            bubble.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        host.layoutSubtreeIfNeeded()
        return bubble
    }

    private func textColor(of bubble: AIChatBubbleView) throws -> NSColor {
        let text = try XCTUnwrap(bubble.subviews.compactMap { $0 as? NSTextView }.first)
        let storage = try XCTUnwrap(text.textStorage)
        return try XCTUnwrap(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
    }
}
