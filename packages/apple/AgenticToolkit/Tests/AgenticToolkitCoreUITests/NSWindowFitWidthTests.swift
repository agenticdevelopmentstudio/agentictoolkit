import AppKit
import Testing
@testable import AgenticToolkitCoreUI

@MainActor
@Suite("NSWindow.ensureMinimumContentWidth")
struct NSWindowFitWidthTests {
    private func makeWindow(left: CGFloat = 100, width: CGFloat) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: left, y: 100, width: width, height: 200),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        return window
    }

    /// The frame width that holds `contentWidth` of content in `window`.
    private func frameWidth(_ window: NSWindow, content contentWidth: CGFloat) -> CGFloat {
        window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: contentWidth, height: 0)).width
    }

    @Test("a narrower window widens to the content and can't be dragged back")
    func widensNarrowWindow() {
        let window = makeWindow(width: 300)
        window.ensureMinimumContentWidth(420)

        #expect(window.contentLayoutRect.width == 420)
        #expect(window.minSize.width == window.frame.width)
    }

    @Test("a wider window keeps the width the user gave it")
    func leavesWiderWindowAlone() {
        let window = makeWindow(width: 600)
        window.ensureMinimumContentWidth(420)

        #expect(window.contentLayoutRect.width == 600)
        #expect(window.minSize.width == frameWidth(window, content: 420))
    }

    @Test("the minimum follows the content back down")
    func lowersMinimum() {
        let window = makeWindow(width: 600)
        window.ensureMinimumContentWidth(500)
        window.ensureMinimumContentWidth(320)

        #expect(window.minSize.width == frameWidth(window, content: 320))
    }

    @Test("a window at the screen's right edge grows leftwards")
    func growsLeftAtRightEdge() throws {
        let visible = try #require(NSScreen.main?.visibleFrame)
        let window = makeWindow(left: visible.maxX - 300, width: 300)
        window.ensureMinimumContentWidth(500)

        #expect(abs(window.frame.maxX - visible.maxX) <= 1)
        #expect(window.frame.minX >= visible.minX)
    }
}
