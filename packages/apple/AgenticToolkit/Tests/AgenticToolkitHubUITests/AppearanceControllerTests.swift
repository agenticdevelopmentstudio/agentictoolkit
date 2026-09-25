import AgenticDeveloperHubClient
import XCTest
import AgenticToolkitHubService
@testable import AgenticToolkitHubUI

@MainActor
final class AppearanceControllerTests: XCTestCase {
    private func make() -> (AppearanceController, StubClientTransport) {
        let stub = StubClientTransport()
        let environment = HubEnvironment(
            sessionStore: InMemorySessionStore(
                Session(credentials: Credentials(token: "jwt", kind: .jwt), refreshToken: "r")
            ),
            transportSource: StaticTransportSource(.direct(transport: stub)),
            initialTransport: .direct(transport: stub)
        )
        return (AppearanceController(environment: environment), stub)
    }

    func testRefreshAppliesTheServerColorMode() async {
        let (controller, stub) = make()
        stub.on(.get, "/me/appearance", status: 200, json: #"{"prefs":{"colorMode":"dark","reduceMotion":"auto"}}"#)
        var seen: [HubColorMode] = []
        controller.onChange = { seen.append($0) }
        await controller.refresh()
        XCTAssertEqual(controller.colorMode, .dark)
        XCTAssertEqual(seen, [.dark])
    }

    func testEmptyPrefsMeanAuto() async {
        let (controller, stub) = make()
        stub.on(.get, "/me/appearance", status: 200, json: #"{"prefs":{"colorMode":"dark"}}"#)
        await controller.refresh()
        XCTAssertEqual(controller.colorMode, .dark)
        stub.on(.get, "/me/appearance", status: 200, json: #"{"prefs":{}}"#)
        await controller.refresh()
        XCTAssertEqual(controller.colorMode, .auto)
    }

    func testFailuresKeepTheCurrentMode() async {
        let (controller, stub) = make()
        stub.on(.get, "/me/appearance", status: 200, json: #"{"prefs":{"colorMode":"light"}}"#)
        await controller.refresh()
        XCTAssertEqual(controller.colorMode, .light)
        stub.on(.get, "/me/appearance", status: 401, json: #"{"error":{"message":"nope"}}"#)
        await controller.refresh()
        XCTAssertEqual(controller.colorMode, .light)
        stub.on(.get, "/me/appearance") { _, _ in throw URLError(.notConnectedToInternet) }
        await controller.refresh()
        XCTAssertEqual(controller.colorMode, .light)
        controller.reset()
        XCTAssertEqual(controller.colorMode, .auto)
    }

    func testModeMapping() {
        var settings = Components.Schemas.AppearanceSettings(prefs: .init())
        XCTAssertEqual(AppearanceController.mode(from: settings), .auto)
        settings.prefs.colorMode = .light
        XCTAssertEqual(AppearanceController.mode(from: settings), .light)
        settings.prefs.colorMode = .dark
        XCTAssertEqual(AppearanceController.mode(from: settings), .dark)
    }
}
