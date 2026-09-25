import XCTest
import AppKit
import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// Renders each billing window, populated from the seeded fake, in light and
/// dark, as PNGs for a person to look at. Skipped unless
/// `BILLING_SNAPSHOT_DIR` names a directory: the pictures are the product, not
/// an assertion, so the ordinary suite has no business writing them.
@MainActor
final class BillingWindowSnapshotTests: XCTestCase {

    private var model: BillingModel!
    private var directory: URL!

    override func setUp() async throws {
        guard let path = ProcessInfo.processInfo.environment["BILLING_SNAPSHOT_DIR"], !path.isEmpty else {
            throw XCTSkip("set TEST_RUNNER_BILLING_SNAPSHOT_DIR to render the billing windows")
        }
        directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        model = BillingModel(service: FakeBillingClient.seeded(), refreshInterval: 999)
        await model.refresh()
    }

    func testRenderTheProjectsWindow() throws {
        let controller = ProjectsWindowController(context: .forTests(model: model))
        try render(controller.windowController, as: "projects")
    }

    func testRenderTheClientsWindow() throws {
        let controller = ClientsWindowController(context: .forTests(model: model))
        try render(controller.windowController, as: "clients")
    }

    func testRenderTheActivityWindow() throws {
        let controller = BillingActivityWindowController(model: model)
        try render(controller, as: "activity")
    }

    /// The Billing settings pane, hosted in a window of the size a settings
    /// window gives it.
    func testRenderTheSettingsPanel() throws {
        let panel = BillingSettingsPanel(settings: .forTests)
        let window = NSWindow(contentViewController: panel)
        window.setContentSize(NSSize(width: 640, height: 720))
        try render(window, as: "settings")
    }

    private func render(_ windowController: SingleWindowController, as name: String) throws {
        windowController.showWindow(nil)
        try render(XCTUnwrap(windowController.window), as: name)
    }

    /// Draws the window's content view offscreen, once per appearance. The
    /// appearance goes on the window, the same place the system sets it, so
    /// every themed color resolves the way it does on screen.
    private func render(_ window: NSWindow, as name: String) throws {
        let content = try XCTUnwrap(window.contentView)

        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            content.needsLayout = true
            content.layoutSubtreeIfNeeded()
            content.displayIfNeeded()

            let rep = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
            content.cacheDisplay(in: content.bounds, to: rep)
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            XCTAssertGreaterThan(rep.pixelsWide, 0)

            let url = directory.appendingPathComponent("billing-\(name)-\(suffix).png")
            try png.write(to: url)
            add(XCTAttachment(contentsOfFile: url))
        }
    }
}
