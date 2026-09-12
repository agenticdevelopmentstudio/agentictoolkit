import AppKit
import XCTest
@testable import AgenticToolkitMacOS

/// A content-hugging window is sized and placed for the screen it is on: it
/// holds whichever edge it is nearest, and stops growing only when there is no
/// screen left to move into. Moving it changes which edge that is and how much
/// room lies beyond it, so the fit has to be recomputed — otherwise a window
/// dragged toward an edge keeps a placement that no longer suits where it is.
@MainActor
final class SingleWindowControllerMoveRefitTests: XCTestCase {

    private final class HuggingWC: SingleWindowController {
        init(id: String) {
            super.init(windowID: id, contentViewController: NSViewController())
            windowStyleMask = [.titled, .closable]
            minSize = NSSize(width: 120, height: 80)
        }
        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }
    }

    private let contentSize = NSSize(width: 400, height: 300)

    private func makeShownController() throws -> (HuggingWC, NSWindow, NSRect) {
        let controller = HuggingWC(id: "test.move.refit.\(UUID().uuidString)")
        controller.showWindow()
        let window = try XCTUnwrap(controller.window)
        let visible = try XCTUnwrap(window.screen ?? NSScreen.main).visibleFrame
        controller.contentSizeProvider = { [contentSize] in contentSize }
        return (controller, window, visible)
    }

    /// The frame size the window takes when the content fits with room to spare.
    private func fittedSize(of window: NSWindow) -> NSSize {
        window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
    }

    /// Parks the window `roomToTheRight` points from the visible area's right
    /// edge, high enough that vertical room is never the binding constraint.
    private func park(_ window: NSWindow, in visible: NSRect, roomToTheRight: CGFloat) {
        let size = fittedSize(of: window)
        window.setFrame(
            NSRect(x: visible.maxX - roomToTheRight,
                   y: visible.maxY - 60 - size.height,
                   width: size.width,
                   height: size.height),
            display: false
        )
    }

    func testOnlyAContentHuggingWindowRefitsAfterAMove() throws {
        let controller = HuggingWC(id: "test.move.gate.\(UUID().uuidString)")
        controller.showWindow()

        XCTAssertFalse(
            controller.wantsRefitAfterMove,
            "a window with no content-size provider doesn't own its size — a move is just a move"
        )
        controller.contentSizeProvider = { NSSize(width: 320, height: 200) }
        XCTAssertTrue(controller.wantsRefitAfterMove)
    }

    /// The content wants the same size before and after; what changed is the
    /// room on the side the window is now nearest. The window keeps the size
    /// and gives up the position, which is the whole of the new rule.
    func testTheFitIsRecomputedAfterAMoveEvenThoughTheContentDidNotChange() throws {
        let (controller, window, visible) = try makeShownController()

        // Fit once with room to spare: the window now measures exactly what the
        // content asked for, which is the case a size-only bail short-circuits.
        let wanted = fittedSize(of: window)
        park(window, in: visible, roomToTheRight: wanted.width + 80)
        controller.performContentRefit()
        XCTAssertEqual(window.frame.size, wanted, "fits outright when there is room")

        // Move it so its right edge hangs off the screen. It is now nearest the
        // right edge, so that is the edge it holds.
        let room = wanted.width - 40
        park(window, in: visible, roomToTheRight: room)
        controller.performContentRefit()
        XCTAssertEqual(window.frame.width, wanted.width, "the size the content asked for is kept")
        XCTAssertEqual(window.frame.maxX, visible.maxX, "the window moved in to make room for it")
    }

    /// A window with no screen left to move into is the one case where the size
    /// gives way: it is capped at the visible width rather than overhanging.
    func testAWindowWiderThanTheScreenIsCappedRatherThanMoved() throws {
        let controller = HuggingWC(id: "test.move.cap.\(UUID().uuidString)")
        controller.showWindow()
        let window = try XCTUnwrap(controller.window)
        let visible = try XCTUnwrap(window.screen ?? NSScreen.main).visibleFrame
        controller.contentSizeProvider = { NSSize(width: visible.width * 2, height: 200) }

        controller.performContentRefit()

        XCTAssertEqual(window.frame.width, visible.width, "growth stops at the screen")
        XCTAssertEqual(window.frame.minX, visible.minX)
    }

    func testAMoveNotificationDrivesTheRefitOnItsOwn() throws {
        let (controller, window, visible) = try makeShownController()
        let wanted = fittedSize(of: window)
        park(window, in: visible, roomToTheRight: wanted.width + 80)
        controller.performContentRefit()

        // Exactly what a drag toward the right edge does: origin changes, size
        // doesn't. `windowDidMove` schedules the settle; nothing else runs.
        let room = wanted.width - 40
        window.setFrame(
            NSRect(origin: NSPoint(x: visible.maxX - room, y: window.frame.minY),
                   size: window.frame.size),
            display: false
        )

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, window.frame.maxX > visible.maxX {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertEqual(window.frame.maxX, visible.maxX, "the move alone pulled the window back on screen")
        XCTAssertEqual(window.frame.width, wanted.width, "without giving up the size the content asked for")
    }
}
