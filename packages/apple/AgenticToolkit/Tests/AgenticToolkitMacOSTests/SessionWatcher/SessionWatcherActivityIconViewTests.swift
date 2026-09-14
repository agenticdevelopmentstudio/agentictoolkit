import XCTest
import AppKit
import AgenticToolkitCore
import AgenticToolkitCoreMacOS
@testable import AgenticToolkitMacOS

@MainActor
final class SessionWatcherActivityIconViewTests: XCTestCase {

    private typealias IconView = SessionWatcher.SessionWatcherActivityIconView

    /// Hosts `icon` in a window at `origin` and lays it out, the way a row does.
    private func host(_ icon: IconView, at origin: NSPoint) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        let content = NSView(frame: window.contentLayoutRect)
        content.wantsLayer = true
        window.contentView = content
        content.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: origin.x),
            icon.topAnchor.constraint(equalTo: content.topAnchor, constant: origin.y)
        ])
        content.layoutSubtreeIfNeeded()
        return window
    }

    private func assertSpinsAboutItsCentre(_ icon: IconView, file: StaticString = #filePath, line: UInt = #line) {
        let glyph = icon.glyphLayer
        XCTAssertEqual(glyph.anchorPoint, CGPoint(x: 0.5, y: 0.5), file: file, line: line)
        XCTAssertEqual(glyph.bounds.size, icon.bounds.size, file: file, line: line)
        XCTAssertEqual(glyph.position, CGPoint(x: icon.bounds.midX, y: icon.bounds.midY), file: file, line: line)
    }

    /// The spin was installed on the view's own layer, whose anchor AppKit keeps
    /// resetting to the corner, so the arrows orbited down over the line below.
    func testWorkingGlyphSpinsAboutItsCentre() {
        let icon = IconView(activity: .working, isSummarizing: false)
        let window = host(icon, at: NSPoint(x: 150, y: 10))
        defer { window.close() }

        XCTAssertNotNil(icon.glyphLayer.animation(forKey: "session-activity-rotation"))
        XCTAssertNil(icon.layer?.animation(forKey: "session-activity-rotation"),
                     "the view's own layer pivots on its corner; the spin must not live there")
        assertSpinsAboutItsCentre(icon)
    }

    /// AppKit re-syncs a backing layer whenever the frame moves; the glyph must stay
    /// centred through that.
    func testGlyphStaysCentredWhenTheRowMovesIt() {
        let icon = IconView(activity: .working, isSummarizing: false)
        let window = host(icon, at: NSPoint(x: 150, y: 10))
        defer { window.close() }

        icon.setFrameOrigin(NSPoint(x: 40, y: 60))
        window.contentView?.layoutSubtreeIfNeeded()
        icon.layout()
        assertSpinsAboutItsCentre(icon)
    }

    func testStateChangesSwapTheAnimation() {
        let icon = IconView(activity: .working, isSummarizing: false)
        let window = host(icon, at: NSPoint(x: 150, y: 10))
        defer { window.close() }

        icon.update(activity: .waiting, isSummarizing: false)
        XCTAssertNil(icon.glyphLayer.animation(forKey: "session-activity-rotation"))
        XCTAssertNotNil(icon.glyphLayer.animation(forKey: "session-activity-pulse"))

        icon.update(activity: .idle, isSummarizing: false)
        XCTAssertNil(icon.glyphLayer.animation(forKey: "session-activity-pulse"))
        XCTAssertNotNil(icon.glyphLayer.contents, "an idle session still shows its dot")
        XCTAssertEqual(icon.accessibilityLabel(), "Idle")
    }
}
