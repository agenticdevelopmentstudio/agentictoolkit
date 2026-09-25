import AgenticDeveloperHubClient
import AgenticToolkitHub
import Foundation
import OpenAPIRuntime
import XCTest
@testable import AgenticToolkitHubService

final class HubErrorMappingTests: XCTestCase {
    func testStatusMapping() {
        let body = Data(#"{"error":"Slug is taken"}"#.utf8)
        XCTAssertEqual(HubError.fromStatus(401, body: Data()), .unauthorized)
        XCTAssertEqual(HubError.fromStatus(403, body: Data()), .forbidden)
        XCTAssertEqual(HubError.fromStatus(404, body: Data()), .notFound)
        XCTAssertEqual(HubError.fromStatus(409, body: body), .conflict("Slug is taken"))
        XCTAssertEqual(HubError.fromStatus(422, body: body), .validation("Slug is taken"))
        XCTAssertEqual(HubError.fromStatus(400, body: Data()), .validation("HTTP 400"))
        XCTAssertEqual(HubError.fromStatus(503, body: Data()), .transport("HTTP 503"))
        XCTAssertEqual(HubError.fromStatus(418, body: Data()), .unexpected("HTTP 418"))
    }

    func testErrorMapping() {
        XCTAssertEqual(HubError.from(HubError.offline), .offline)
        XCTAssertEqual(HubError.from(RawRequestError.http(status: 404, body: Data())), .notFound)
        XCTAssertEqual(HubError.from(SessionError.invalidCredentials), .unauthorized)
        XCTAssertEqual(
            HubError.from(URLError(.notConnectedToInternet)),
            .transport(URLError(.notConnectedToInternet).localizedDescription)
        )
        let wrapped = ClientError(
            operationID: "getWorkspaces", operationInput: "", causeDescription: "", underlyingError: URLError(.timedOut)
        )
        XCTAssertEqual(HubError.from(wrapped), .transport(URLError(.timedOut).localizedDescription))
        XCTAssertEqual(HubError.message(fromBody: Data(#"{"message":"Nope"}"#.utf8), fallback: "x"), "Nope")
        XCTAssertEqual(HubError.message(fromBody: Data("garbage".utf8), fallback: "x"), "x")
    }

    /// `testErrorMapping` above leaves four `from(_:)` branches unexercised:
    /// `RawRequestError.invalidPath`, the two remaining `SessionError` cases,
    /// and `CancellationError`. Added per Task 6's exhaustiveness rule so a
    /// dropped branch there can actually fail a test.
    func testErrorMappingRemainingBranches() {
        XCTAssertEqual(HubError.from(RawRequestError.invalidPath("bad")), .unexpected("Invalid path bad"))
        XCTAssertEqual(
            HubError.from(SessionError.notASessionClient),
            .unexpected("This client cannot sign in.")
        )
        XCTAssertEqual(HubError.from(SessionError.unexpectedResponse("weird")), .unexpected("weird"))
        XCTAssertEqual(HubError.from(CancellationError()), .transport("Cancelled"))
    }

    /// Direct coverage of `message(fromBody:fallback:)`'s shapes: the nested
    /// `{"error":{"message": ...}}` envelope `Components.Schemas._Error`
    /// actually uses, the flat `"error"` envelope, the flat `"message"`
    /// envelope, a nested `"error"` object with no `message`, malformed
    /// JSON, and an empty body. `testErrorMapping` and `testStatusMapping`
    /// only exercise the flat shapes indirectly through `fromStatus`.
    func testMessageExtractionShapes() {
        XCTAssertEqual(
            HubError.message(fromBody: Data(#"{"error":{"message":"nested"}}"#.utf8), fallback: "x"),
            "nested"
        )
        XCTAssertEqual(HubError.message(fromBody: Data(#"{"error":"Nope"}"#.utf8), fallback: "x"), "Nope")
        XCTAssertEqual(HubError.message(fromBody: Data(#"{"message":"Nope"}"#.utf8), fallback: "x"), "Nope")
        XCTAssertEqual(HubError.message(fromBody: Data(#"{"error":{}}"#.utf8), fallback: "x"), "x")
        XCTAssertEqual(HubError.message(fromBody: Data("not json".utf8), fallback: "x"), "x")
        XCTAssertEqual(HubError.message(fromBody: Data(), fallback: "x"), "x")
    }

    /// Pins the `fromStatus` 5xx boundary (`500...599`) so a narrowed range
    /// cannot silently regress: 429 stays `.unexpected` (no rate-limit case
    /// exists), 499 stays `.unexpected`, 500 and 599 are the inclusive
    /// edges of `.transport`, and 600 falls back out to `.unexpected`.
    func testFromStatusBoundaries() {
        XCTAssertEqual(HubError.fromStatus(429, body: Data()), .unexpected("HTTP 429"))
        XCTAssertEqual(HubError.fromStatus(499, body: Data()), .unexpected("HTTP 499"))
        XCTAssertEqual(HubError.fromStatus(500, body: Data()), .transport("HTTP 500"))
        XCTAssertEqual(HubError.fromStatus(599, body: Data()), .transport("HTTP 599"))
        XCTAssertEqual(HubError.fromStatus(600, body: Data()), .unexpected("HTTP 600"))
    }
}
