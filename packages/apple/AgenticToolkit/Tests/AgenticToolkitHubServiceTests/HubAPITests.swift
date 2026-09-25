import AgenticDeveloperHubClient
import AgenticToolkitHub
import Foundation
import HTTPTypes
import XCTest
@testable import AgenticToolkitHubService

@MainActor
final class HubAPITests: XCTestCase {
    private struct Row: Codable, Equatable { let id: String; let name: String }
    private struct Body: Codable { let name: String; let enabled: Bool }

    private func makeAPI() -> (HubAPI, StubClientTransport) {
        let stub = StubClientTransport()
        let store = InMemorySessionStore(Session(credentials: Credentials(token: "jwt", kind: .jwt), refreshToken: "r"))
        let environment = HubEnvironment(
            sessionStore: store,
            transportSource: StaticTransportSource(.direct(transport: stub)),
            initialTransport: .direct(transport: stub)
        )
        return (HubAPI(environment: environment), stub)
    }

    func testGetDecodesArray() async throws {
        let (api, stub) = makeAPI()
        stub.on(.get, "/persona/personas", json: #"[{"id":"p1","name":"Ada"},{"id":"p2","name":"Bob"}]"#)
        let rows = try await api.get("/persona/personas", query: ["workspace": "me"], as: [Row].self)
        XCTAssertEqual(rows, [Row(id: "p1", name: "Ada"), Row(id: "p2", name: "Bob")])
        let request = stub.lastRequest(.get, "/persona/personas")
        XCTAssertEqual(request?.path, "/persona/personas?workspace=me")
        XCTAssertEqual(request?.headerFields[.authorization], "Bearer jwt")
    }

    func testSendEncodesBodyAndDecodesResponse() async throws {
        let (api, stub) = makeAPI()
        stub.on(.post, "/ecosystem/feature-flags/eco1", status: 201, json: #"{"id":"f1","name":"beta"}"#)
        let row = try await api.send(
            .post, "/ecosystem/feature-flags/eco1", body: Body(name: "beta", enabled: true), as: Row.self
        )
        XCTAssertEqual(row, Row(id: "f1", name: "beta"))
        let body = stub.lastBody(.post, "/ecosystem/feature-flags/eco1")
        XCTAssertEqual(body?["name"] as? String, "beta")
        XCTAssertEqual(body?["enabled"] as? Bool, true)
        XCTAssertEqual(
            stub.lastRequest(.post, "/ecosystem/feature-flags/eco1")?.headerFields[.contentType], "application/json"
        )
    }

    func testSendWithoutResponseIgnoresBody() async throws {
        let (api, stub) = makeAPI()
        stub.on(.delete, "/auth/tokens/t1", status: 204, json: "")
        try await api.send(.delete, "/auth/tokens/t1")
        XCTAssertEqual(stub.requestCount(.delete, "/auth/tokens/t1"), 1)
    }

    func testHTTPErrorsBecomeHubErrors() async {
        let (api, stub) = makeAPI()
        stub.on(.get, "/persona/personas/p9", status: 404, json: #"{"error":"missing"}"#)
        stub.on(.post, "/tokens", status: 409, json: #"{"error":"That name is already in use."}"#)
        stub.on(.get, "/usage/storage", status: 403, json: "{}")
        do { _ = try await api.get("/persona/personas/p9", as: Row.self); XCTFail("expected throw") } catch {
            XCTAssertEqual(error as? HubError, .notFound)
        }
        do {
            _ = try await api.send(.post, "/tokens", body: Body(name: "x", enabled: false), as: Row.self)
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? HubError, .conflict("That name is already in use."))
        }
        do { _ = try await api.get("/usage/storage", as: Row.self); XCTFail("expected throw") } catch {
            XCTAssertEqual(error as? HubError, .forbidden)
        }
    }

    func testDecodeFailureIsUnexpected() async {
        let (api, stub) = makeAPI()
        stub.on(.get, "/persona/personas", json: #"{"not":"an array"}"#)
        do { _ = try await api.get("/persona/personas", as: [Row].self); XCTFail("expected throw") } catch {
            guard case .unexpected(let message)? = error as? HubError else { return XCTFail("wrong error \(error)") }
            XCTAssertTrue(message.hasPrefix("Unreadable response for GET /persona/personas"), message)
        }
    }

    func testQueryHelperDropsNils() {
        XCTAssertEqual(
            HubAPI.query(["workspace": "acme", "parent": nil, "infrastructure": "true"]),
            ["workspace": "acme", "infrastructure": "true"]
        )
    }

    func testQueryIsSortedByKey() async throws {
        let (api, stub) = makeAPI()
        stub.on(.get, "/tokens", json: "[]")
        _ = try await api.get("/tokens", query: ["workspace": "w", "ecosystemId": "e"], as: [Row].self)
        XCTAssertEqual(stub.lastRequest(.get, "/tokens")?.path, "/tokens?ecosystemId=e&workspace=w")
    }
}
