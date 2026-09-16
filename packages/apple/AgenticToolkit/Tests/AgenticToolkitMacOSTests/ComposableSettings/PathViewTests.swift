import Foundation
import Testing
import AppKit
import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// `PathView` exists because the drawn text is deliberately lossy: at the
/// settings window's minimum width a real path is wider than the card, and
/// wrapping it as prose broke it across nine hyphenated lines. What is pinned
/// here is the other half of that bargain — that truncating the drawing never
/// truncates the value.
@Suite("PathView")
@MainActor
struct PathViewTests {

    private static let longPath =
        "/private/tmp/claude-501/-Users-someone-Development-projects-whippet/"
        + "scratchpad/throwaway-home/.agenticextensions/alert-check"

    @Test("the whole path survives the truncation, in all three places that answer for it")
    func wholePathIsReachable() {
        let view = ComposableSettings.PathView(withPath: Self.longPath)
        #expect(view.path == Self.longPath)
        #expect(view.label.toolTip == Self.longPath)
        #expect(view.label.accessibilityValue() == Self.longPath)
    }

    @Test("one line, truncated in the middle")
    func drawsOnOneTruncatedLine() {
        let view = ComposableSettings.PathView(withPath: Self.longPath)
        #expect(view.label.maximumNumberOfLines == 1)
        #expect(view.label.lineBreakMode == .byTruncatingMiddle)
        // `wraps` is what the wrap policy actually hangs off; `usesSingleLineMode`
        // would make the cell ignore `lineBreakMode` and truncate at the tail.
        #expect(view.label.cell?.wraps == false)
        #expect(view.label.cell?.usesSingleLineMode == false)
    }

    @Test("the caption is drawn at the head, where middle truncation cannot eat it")
    func captionLeadsTheValue() {
        let view = ComposableSettings.PathView(withPath: Self.longPath, caption: "Folder")
        #expect(view.label.stringValue == "Folder: \(Self.longPath)")
        // The caption is a label for the row, never part of the value.
        #expect(view.path == Self.longPath)
        #expect(view.label.toolTip == Self.longPath)
    }

    @Test("a path yields its width rather than widening the window")
    func yieldsHorizontally() {
        let view = ComposableSettings.PathView(withPath: Self.longPath)
        #expect(view.label.contentCompressionResistancePriority(for: .horizontal) == .defaultLow)
    }
}
