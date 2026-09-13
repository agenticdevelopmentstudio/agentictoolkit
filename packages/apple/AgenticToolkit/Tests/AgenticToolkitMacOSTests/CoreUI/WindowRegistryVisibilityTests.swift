import AppKit
import XCTest
@testable import AgenticToolkitMacOS

/// `hasVisibleWindow` is what a host's launch path consults before activating
/// the app, so the two answers that matter are "a restore put something on
/// screen" and "it didn't" — a menubar app starting at login with every window
/// closed must not take the foreground.
@MainActor
final class WindowRegistryVisibilityTests: XCTestCase {

    private final class FakeVC: NSViewController {
        override func loadView() { view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 120)) }
    }

    private var made: [SingleWindowController] = []

    private func probe() -> SingleWindowController {
        let controller = SingleWindowController(
            windowID: "registry-visibility-\(UUID().uuidString)",
            contentViewController: FakeVC()
        )
        made.append(controller)
        return controller
    }

    override func tearDown() async throws {
        for controller in made {
            WindowManager.shared.frames.clearSavedState(for: controller.windowID)
            WindowManager.shared.frames.clearVisibility(for: controller.windowID)
            controller.window?.orderOut(nil)
        }
        made = []
        try await super.tearDown()
    }

    func testRegisteringAControllerDoesNotMakeItVisible() {
        let registry = WindowRegistry()
        registry.register(probe())
        XCTAssertFalse(registry.hasVisibleWindow, "registering is not showing")
    }

    func testAShownWindowMakesItTrue() {
        let registry = WindowRegistry()
        let controller = probe()
        registry.register(controller)
        controller.showWindow()
        XCTAssertTrue(registry.hasVisibleWindow)
    }

    /// Under quiet presentation `showWindow` sinks the window behind the
    /// desktop instead of ordering it front, and it is still a genuinely
    /// visible window — the launch path must not read the sinking as "nothing
    /// to show". What suppresses activation there is the quiet switch itself,
    /// which is a separate input.
    func testASunkWindowStillCountsAsVisible() {
        let registry = WindowRegistry()
        let controller = probe()
        registry.register(controller)
        controller.showWindow()
        controller.window?.sinkBehindDesktop()
        XCTAssertTrue(registry.hasVisibleWindow)
    }

    func testDismissingTheOnlyWindowMakesItFalseAgain() {
        let registry = WindowRegistry()
        let controller = probe()
        registry.register(controller)
        controller.showWindow()
        controller.dismiss()
        XCTAssertFalse(registry.hasVisibleWindow)
    }

    func testOneVisibleWindowAmongClosedOnesIsEnough() {
        let registry = WindowRegistry()
        let closed = probe()
        let open = probe()
        registry.register(closed)
        registry.register(open)
        open.showWindow()
        XCTAssertTrue(registry.hasVisibleWindow)
    }

    func testADeallocatedControllerLeavesNothingVisible() {
        let registry = WindowRegistry()
        do {
            let controller = SingleWindowController(
                windowID: "registry-visibility-transient",
                contentViewController: FakeVC()
            )
            registry.register(controller)
            controller.showWindow()
            controller.dismiss()
        }
        WindowManager.shared.frames.clearSavedState(for: "registry-visibility-transient")
        WindowManager.shared.frames.clearVisibility(for: "registry-visibility-transient")
        XCTAssertFalse(registry.hasVisibleWindow)
    }
}
