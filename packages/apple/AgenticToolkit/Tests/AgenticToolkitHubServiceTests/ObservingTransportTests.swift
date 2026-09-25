import Foundation
import HTTPTypes
import OpenAPIRuntime
import XCTest
@testable import AgenticToolkitHubService

final class ObservingTransportTests: XCTestCase {
    func testObserverSeesEveryResponseAndBodyPassesThrough() async throws {
        let stub = StubClientTransport()
        stub.on(.get, "/ping", status: 203, headers: ["cache-control": "no-store"], json: #"{"ok":true}"#)
        let seen = Seen()
        let transport = ObservingTransport(base: stub) { response in seen.append(response) }

        let (response, body) = try await transport.send(
            HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/ping"),
            body: nil,
            baseURL: URL(string: "http://127.0.0.1:1")!,
            operationID: "ping"
        )

        XCTAssertEqual(response.status.code, 203)
        let data = try await Data(collecting: XCTUnwrap(body), upTo: 1024)
        let decoded = try XCTUnwrap(String(bytes: data, encoding: .utf8))
        XCTAssertEqual(decoded, #"{"ok":true}"#)
        XCTAssertEqual(seen.responses.count, 1)
        XCTAssertEqual(seen.responses.first?.headerFields[.cacheControl], "no-store")
    }

    func testTransportErrorsPropagateWithoutObservation() async {
        let stub = StubClientTransport()
        stub.on(.get, "/down") { _, _ in throw URLError(.notConnectedToInternet) }
        let seen = Seen()
        let transport = ObservingTransport(base: stub) { response in seen.append(response) }

        do {
            _ = try await transport.send(
                HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/down"),
                body: nil,
                baseURL: URL(string: "http://127.0.0.1:1")!,
                operationID: "down"
            )
            XCTFail("expected the URLError to propagate")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
        XCTAssertTrue(seen.responses.isEmpty)
    }
}

private final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [HTTPResponse] = []
    var responses: [HTTPResponse] { lock.withLock { stored } }
    func append(_ response: HTTPResponse) { lock.withLock { stored.append(response) } }
}
