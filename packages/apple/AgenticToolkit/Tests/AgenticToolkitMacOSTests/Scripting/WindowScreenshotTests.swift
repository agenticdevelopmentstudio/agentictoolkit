import AppKit
import XCTest
@testable import AgenticToolkitScripting

@MainActor
final class WindowScreenshotTests: XCTestCase {

    func testCaptureReturnsNilForBogusID() {
        // 0 is never a valid CGWindowID; the legacy call returns nil.
        XCTAssertNil(WindowScreenshot.captureOwnWindow(CGWindowID(0)))
    }

    func testWritePNGReturnsFalseForOrderedOutWindow() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        // Not ordered-in: windowNumber is <= 0, so writePNG should bail.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(
            "window-screenshot-test-\(UUID()).png"
        )
        XCTAssertFalse(WindowScreenshot.writePNG(of: window, to: tmp))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.path))
    }
}
