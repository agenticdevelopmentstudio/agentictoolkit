import XCTest
@testable import AgenticToolkitHub

final class HubErrorTests: XCTestCase {
    func testMessages() {
        XCTAssertEqual(HubError.unauthorized.message, "You need to sign in again.")
        XCTAssertEqual(HubError.forbidden.message, "You don't have permission to do that.")
        XCTAssertEqual(HubError.notFound.message, "That item no longer exists.")
        XCTAssertEqual(HubError.offline.message, "The hub can't be reached right now.")
        XCTAssertEqual(HubError.conflict("Name taken").message, "Name taken")
        XCTAssertEqual(HubError.validation("Slug is invalid").message, "Slug is invalid")
        XCTAssertEqual(HubError.transport("timeout").message, "Connection problem: timeout")
        XCTAssertEqual(HubError.unexpected("HTTP 500").message, "Something went wrong: HTTP 500")
    }

    func testLocalizedErrorUsesMessage() {
        let error: any Error = HubError.notFound
        XCTAssertEqual(error.localizedDescription, "That item no longer exists.")
    }

    func testEquatable() {
        XCTAssertEqual(HubError.conflict("a"), HubError.conflict("a"))
        XCTAssertNotEqual(HubError.conflict("a"), HubError.conflict("b"))
    }
}
