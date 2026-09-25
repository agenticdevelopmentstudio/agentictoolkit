import AgenticDeveloperHubClient
import AgenticToolkitHub
import Foundation
import HTTPTypes
import XCTest
@testable import AgenticToolkitHubService

@MainActor
final class MessagingAdapterTests: XCTestCase {
    private var stub: StubClientTransport!
    private var adapter: MessagingAdapter!
    private let base = "/messaging/ecosystems/org.acme.shop"

    override func setUp() async throws {
        try await super.setUp()
        stub = StubClientTransport()
        let store = InMemorySessionStore(
            Session(credentials: Credentials(token: "jwt", kind: .jwt), refreshToken: "r")
        )
        let environment = HubEnvironment(
            sessionStore: store,
            transportSource: StaticTransportSource(.direct(transport: stub)),
            initialTransport: .direct(transport: stub)
        )
        adapter = MessagingAdapter(
            environment: environment,
            workspace: HubWorkspace(slug: "acme", name: "Acme", type: .organization)
        )
    }

    private let entryJSON = #"""
    {"id":"m-1","customerId":"c-jane","ecosystemId":"org.acme.shop","channel":"email",
     "recipient":"jane@example.com","subject":"Your order","body":"Shipped.",
     "templateId":null,"status":"sent","providerId":"pm-1","errorMessage":null,
     "sentBy":"owner@acme.test","origin":"ecosystem","createdAt":"2026-09-03T12:00:00.000Z"}
    """#

    func testStatus() async throws {
        stub.on(.get, "\(base)/status", json: #"{"email":true,"sms":false}"#)
        let status = try await adapter.status(ecosystemID: "org.acme.shop")
        XCTAssertEqual(status, MessagingStatus(email: true, sms: false))
        XCTAssertEqual(stub.lastRequest(.get, "\(base)/status")?.path, "\(base)/status?workspace=acme")
    }

    private let templatesJSON = #"""
    [{"id":"tpl-welcome","name":"Welcome","subject":"Hi {{name}}","htmlBody":"<p>x</p>",
      "textBody":"Hi {{name}}","smsBody":null,"category":"onboarding"}]
    """#

    func testTemplates() async throws {
        stub.on(.get, "/messaging/templates", json: templatesJSON)
        let templates = try await adapter.templates()
        XCTAssertEqual(templates.map(\.id), ["tpl-welcome"])
        XCTAssertEqual(templates.first?.placeholders, ["name"])
        XCTAssertEqual(
            stub.lastRequest(.get, "/messaging/templates")?.path, "/messaging/templates?workspace=acme"
        )
    }

    func testLogPassesPaging() async throws {
        stub.on(.get, "\(base)/log", json: #"{"items":[\#(entryJSON)],"total":1,"page":1,"pageSize":100}"#)
        let page = try await adapter.log(ecosystemID: "org.acme.shop", page: 1, pageSize: 100)
        XCTAssertEqual(page.items.map(\.id), ["m-1"])
        XCTAssertEqual(page.items.first?.channel, .email)
        XCTAssertEqual(
            stub.lastRequest(.get, "\(base)/log")?.path,
            "\(base)/log?page=1&pageSize=100&workspace=acme"
        )
    }

    func testSendPostsBodyWithoutNils() async throws {
        stub.on(.post, "\(base)/send", json: #"{"status":"sent","providerId":"pm-9","error":null}"#)
        let result = try await adapter.send(
            ecosystemID: "org.acme.shop",
            MessagingSend(userId: "c-jane", channel: .email, subject: "S", body: "B")
        )
        XCTAssertEqual(result, MessagingSendResult(status: "sent", providerId: "pm-9"))
        XCTAssertEqual(stub.lastRequest(.post, "\(base)/send")?.path, "\(base)/send?workspace=acme")
        let sent = stub.lastBody(.post, "\(base)/send")
        XCTAssertEqual(sent?["userId"] as? String, "c-jane")
        XCTAssertEqual(sent?["channel"] as? String, "email")
        XCTAssertEqual(sent?["subject"] as? String, "S")
        XCTAssertNil(sent?["templateId"] ?? nil)
        XCTAssertNil(sent?["recipient"] ?? nil)
    }

    func testSendTemplateVars() async throws {
        stub.on(.post, "\(base)/send", json: #"{"status":"sent"}"#)
        _ = try await adapter.send(
            ecosystemID: "org.acme.shop",
            MessagingSend(
                userId: "c-jane", channel: .sms, templateId: "tpl-welcome",
                templateVars: ["name": "Jane"], recipient: "+15555550123"
            )
        )
        XCTAssertEqual(stub.lastRequest(.post, "\(base)/send")?.path, "\(base)/send?workspace=acme")
        let sent = stub.lastBody(.post, "\(base)/send")
        XCTAssertEqual(sent?["templateId"] as? String, "tpl-welcome")
        XCTAssertEqual(sent?["templateVars"] as? [String: String], ["name": "Jane"])
        XCTAssertEqual(sent?["recipient"] as? String, "+15555550123")
    }

    func testFailedSendReturns422BodyAsResult() async throws {
        stub.on(
            .post, "\(base)/send", status: 422,
            json: #"{"status":"failed","providerId":null,"error":"Recipient rejected"}"#
        )
        let result = try await adapter.send(
            ecosystemID: "org.acme.shop",
            MessagingSend(userId: "c-jane", channel: .email, subject: "S", body: "B")
        )
        XCTAssertEqual(result, MessagingSendResult(status: "failed", error: "Recipient rejected"))
        XCTAssertEqual(stub.lastRequest(.post, "\(base)/send")?.path, "\(base)/send?workspace=acme")
    }

    func testUnreadable422StillThrowsValidation() async throws {
        stub.on(.post, "\(base)/send", status: 422, json: #"{"detail":"userId missing"}"#)
        do {
            _ = try await adapter.send(
                ecosystemID: "org.acme.shop",
                MessagingSend(userId: "", channel: .email, subject: "S", body: "B")
            )
            XCTFail("expected throw")
        } catch let error as HubError {
            guard case .validation = error else { return XCTFail("expected validation, got \(error)") }
        }
        XCTAssertEqual(stub.lastRequest(.post, "\(base)/send")?.path, "\(base)/send?workspace=acme")
    }

    /// F-17: `send()` does NOT go through `HubAPI` — it drives `rawJSON` itself and maps errors in its
    /// own `catch` ladder. Every other error test in this suite exercised `status()`/`log()`, i.e.
    /// `HubAPI`'s ladder, so `send()`'s non-422 branch had no coverage at all.
    func testSendNon422ErrorMapsThroughSendsOwnLadder() async throws {
        stub.on(.post, "\(base)/send", status: 403, json: #"{"detail":"messaging disabled"}"#)
        do {
            _ = try await adapter.send(
                ecosystemID: "org.acme.shop",
                MessagingSend(userId: "c-jane", channel: .email, subject: "S", body: "B")
            )
            XCTFail("expected throw")
        } catch let error as HubError {
            XCTAssertEqual(error, .forbidden)
        }
        XCTAssertEqual(stub.lastRequest(.post, "\(base)/send")?.path, "\(base)/send?workspace=acme")
    }

    func testSendConflictAndServerErrorsMapThroughSendsOwnLadder() async throws {
        stub.on(.post, "\(base)/send", status: 409, json: #"{"error":"already sent"}"#)
        do {
            _ = try await adapter.send(
                ecosystemID: "org.acme.shop",
                MessagingSend(userId: "c-jane", channel: .email, subject: "S", body: "B")
            )
            XCTFail("expected throw")
        } catch let error as HubError {
            XCTAssertEqual(error, .conflict("already sent"))
        }

        stub.on(.post, "\(base)/send", status: 500, json: #"{"error":"provider exploded"}"#)
        do {
            _ = try await adapter.send(
                ecosystemID: "org.acme.shop",
                MessagingSend(userId: "c-jane", channel: .email, subject: "S", body: "B")
            )
            XCTFail("expected throw")
        } catch let error as HubError {
            XCTAssertEqual(error, .transport("HTTP 500"))
        }
    }

    func testOtherErrorsMapToHubError() async throws {
        stub.on(.get, "\(base)/status", status: 401, json: "{}")
        do {
            _ = try await adapter.status(ecosystemID: "org.acme.shop")
            XCTFail("expected throw")
        } catch let error as HubError {
            XCTAssertEqual(error, .unauthorized)
        }
        XCTAssertEqual(stub.lastRequest(.get, "\(base)/status")?.path, "\(base)/status?workspace=acme")
    }
}
