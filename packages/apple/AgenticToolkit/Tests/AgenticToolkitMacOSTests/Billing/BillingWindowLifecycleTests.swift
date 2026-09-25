import XCTest
import AppKit
import AgenticToolkitCore
@testable import AgenticToolkitMacOS

/// The three billing windows as an app opens them: through `present(context:)`,
/// one of each, and gone again once closed.
@MainActor
final class BillingWindowLifecycleTests: XCTestCase {

    /// A closed billing window is released, so it is not rebuilt on every
    /// poll for the rest of the session, and the model stops polling for it.
    func testClosingABillingWindowReleasesItsController() async throws {
        let model = BillingModel(service: FakeBillingClient.seeded(), refreshInterval: 999)
        await model.refresh()
        let context = BillingUIContext.forTests(model: model)

        ProjectsWindowController.present(context: context)
        ClientsWindowController.present(context: context)
        BillingActivityWindowController.present(context: context)
        let windows = [
            try XCTUnwrap(ProjectsWindowController.current?.windowController.window),
            try XCTUnwrap(ClientsWindowController.current?.windowController.window),
            try XCTUnwrap(BillingActivityWindowController.current?.window)
        ]
        XCTAssertTrue(model.anyConsumerShowing())

        weak let projects = ProjectsWindowController.current
        for window in windows { window.close() }
        await drainMainQueue()

        XCTAssertNil(ProjectsWindowController.current)
        XCTAssertNil(ClientsWindowController.current)
        XCTAssertNil(BillingActivityWindowController.current)
        XCTAssertNil(projects, "nothing else keeps the closed window's controller alive")
        XCTAssertFalse(model.anyConsumerShowing())

        ProjectsWindowController.present(context: context)
        let reopened = try XCTUnwrap(ProjectsWindowController.current)
        XCTAssertEqual(reopened.windowController.window?.isVisible, true, "opening it again builds a fresh one")
        reopened.windowController.window?.close()
        await drainMainQueue()
    }

    /// Opening a window that is already open brings that one forward rather
    /// than building a second.
    func testEnsureCurrentReusesTheOpenWindow() async throws {
        let model = BillingModel(service: FakeBillingClient.seeded(), refreshInterval: 999)
        let context = BillingUIContext.forTests(model: model)

        let first = ClientsWindowController.ensureCurrent(context: context)
        XCTAssertTrue(ClientsWindowController.ensureCurrent(context: context) === first)
        first.windowController.showWindow()
        first.windowController.window?.close()
        await drainMainQueue()
        XCTAssertNil(ClientsWindowController.current)
    }
}
