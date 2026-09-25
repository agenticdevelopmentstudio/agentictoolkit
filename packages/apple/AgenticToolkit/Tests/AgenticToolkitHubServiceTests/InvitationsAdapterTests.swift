import AgenticDeveloperHubClient
import AgenticToolkitHub
import Foundation
import HTTPTypes
import XCTest
@testable import AgenticToolkitHubService

@MainActor
final class InvitationsAdapterTests: XCTestCase {
    private var stub: StubClientTransport!
    private var adapter: InvitationsAdapter!
    private let base = "/auth/ecosystems/org.acme.shop"

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
        adapter = InvitationsAdapter(
            environment: environment,
            workspace: HubWorkspace(slug: "acme", name: "Acme", type: .organization)
        )
    }

    private let requestJSON = #"""
    {"id":"req-1","pendingUserId":"pu-1","name":"Sam Lee","email":"sam@example.com","phone":null,"source":"web",
     "note":"Please",
     "createdAt":"2026-09-01T00:00:00.000Z","userNumber":7}
    """#
    private let pendingJSON = #"""
    {"id":"pu-1","userNumber":7,"name":"Ada Park","email":"ada@example.com","phone":"+15555550123",
     "invitedCount":1,"requestCount":2,
     "lastRequestAt":"2026-09-02T00:00:00.000Z","lastInviteSentAt":null,
     "firstRequestedAt":"2026-09-01T00:00:00.000Z","lastSource":"web","lastNote":null,"status":"pending"}
    """#
    private let inviteJSON = #"""
    {"id":"inv-1","name":"Ada Park","channel":"email","destination":"ada@example.com",
     "sentBy":"owner@acme.test","sentAt":"2026-09-03T00:00:00.000Z","status":"sent"}
    """#
    private let noteJSON = #"""
    {"id":"n-1","content":"Met at the meetup","createdBy":"owner@acme.test","subjectTable":"pending_users",
     "subjectId":"pu-1",
     "createdAt":"2026-09-01T00:00:00.000Z","updatedAt":"2026-09-01T00:00:00.000Z"}
    """#

    func testRequestsList() async throws {
        stub.on(.get, "\(base)/invitation-requests", json: "[\(requestJSON)]")
        let rows = try await adapter.requests(ecosystemID: "org.acme.shop")
        XCTAssertEqual(rows.map(\.id), ["req-1"])
        XCTAssertEqual(rows.first?.userNumber, 7)
        XCTAssertEqual(
            stub.lastRequest(.get, "\(base)/invitation-requests")?.path,
            "\(base)/invitation-requests?workspace=acme"
        )
    }

    func testDeleteRequest() async throws {
        stub.on(.delete, "\(base)/invitation-requests/req-1", status: 204, json: "")
        try await adapter.deleteRequest(ecosystemID: "org.acme.shop", id: "req-1")
        XCTAssertEqual(stub.requestCount(.delete, "\(base)/invitation-requests/req-1"), 1)
        XCTAssertEqual(
            stub.lastRequest(.delete, "\(base)/invitation-requests/req-1")?.path,
            "\(base)/invitation-requests/req-1?workspace=acme"
        )
    }

    func testPendingUsersListAndAdd() async throws {
        stub.on(.get, "\(base)/pending-users", json: "[\(pendingJSON)]")
        stub.on(.post, "\(base)/pending-users", status: 201, json: "[\(pendingJSON)]")
        let rows = try await adapter.pendingUsers(ecosystemID: "org.acme.shop")
        XCTAssertEqual(rows.first?.contact, "ada@example.com")
        XCTAssertEqual(
            stub.lastRequest(.get, "\(base)/pending-users")?.path, "\(base)/pending-users?workspace=acme"
        )

        try await adapter.addPendingUsers(
            ecosystemID: "org.acme.shop",
            [DraftUser(name: "Ada Park", email: "ada@example.com", phone: nil, note: nil)]
        )
        XCTAssertEqual(
            stub.lastRequest(.post, "\(base)/pending-users")?.path, "\(base)/pending-users?workspace=acme"
        )
        let sent = stub.lastBody(.post, "\(base)/pending-users")
        let users = sent?["users"] as? [[String: Any]]
        XCTAssertEqual(users?.count, 1)
        XCTAssertEqual(users?.first?["name"] as? String, "Ada Park")
        XCTAssertEqual(users?.first?["email"] as? String, "ada@example.com")
        XCTAssertNil(users?.first?["phone"] ?? nil)
    }

    func testDeletePendingUser() async throws {
        stub.on(.delete, "\(base)/pending-users/pu-1", status: 204, json: "")
        try await adapter.deletePendingUser(ecosystemID: "org.acme.shop", id: "pu-1")
        XCTAssertEqual(
            stub.lastRequest(.delete, "\(base)/pending-users/pu-1")?.path,
            "\(base)/pending-users/pu-1?workspace=acme"
        )
    }

    func testInvitesListSendAndDelete() async throws {
        stub.on(.get, "\(base)/invitations", json: "[\(inviteJSON)]")
        stub.on(.post, "\(base)/invitations", status: 201, json: "{}")
        stub.on(.delete, "\(base)/invitations/inv-1", status: 204, json: "")
        let rows = try await adapter.invites(ecosystemID: "org.acme.shop")
        XCTAssertEqual(rows.first?.channelTitle, "Email")
        XCTAssertEqual(stub.lastRequest(.get, "\(base)/invitations")?.path, "\(base)/invitations?workspace=acme")

        try await adapter.sendInvitation(
            ecosystemID: "org.acme.shop",
            InvitationSend(pendingUserIds: ["pu-1"], email: InvitationChannelNote(note: "Welcome!"), sms: nil)
        )
        XCTAssertEqual(stub.lastRequest(.post, "\(base)/invitations")?.path, "\(base)/invitations?workspace=acme")
        let sent = stub.lastBody(.post, "\(base)/invitations")
        XCTAssertEqual(sent?["pendingUserIds"] as? [String], ["pu-1"])
        XCTAssertEqual((sent?["email"] as? [String: Any])?["note"] as? String, "Welcome!")
        XCTAssertNil(sent?["sms"] ?? nil)

        try await adapter.deleteInvite(ecosystemID: "org.acme.shop", id: "inv-1")
        XCTAssertEqual(stub.requestCount(.delete, "\(base)/invitations/inv-1"), 1)
        XCTAssertEqual(
            stub.lastRequest(.delete, "\(base)/invitations/inv-1")?.path,
            "\(base)/invitations/inv-1?workspace=acme"
        )
    }

    func testNotesGetAndSave() async throws {
        stub.on(.get, "\(base)/admin-notes", json: "[\(noteJSON)]")
        stub.on(.put, "\(base)/admin-notes", json: "[\(noteJSON)]")
        let notes = try await adapter.notes(ecosystemID: "org.acme.shop", subject: .pendingUsers, subjectID: "pu-1")
        XCTAssertEqual(notes.map(\.id), ["n-1"])
        XCTAssertEqual(
            stub.lastRequest(.get, "\(base)/admin-notes")?.path,
            "\(base)/admin-notes?subjectId=pu-1&subjectTable=pending_users&workspace=acme"
        )

        // `InvitationsDataSource.saveNotes` (as landed in Task 11) returns `Void`, not `[AdminNote]` —
        // see task-13-report.md "Deviations from the brief". Assert on the request body only.
        try await adapter.saveNotes(
            ecosystemID: "org.acme.shop", subject: .pendingUsers, subjectID: "pu-1",
            [AdminNoteInput(id: "n-1", content: "Met at the meetup"), AdminNoteInput(content: "Follow up")]
        )
        // The PUT carries the subject in its BODY, so only `workspace` belongs in its query.
        XCTAssertEqual(stub.lastRequest(.put, "\(base)/admin-notes")?.path, "\(base)/admin-notes?workspace=acme")
        let body = stub.lastBody(.put, "\(base)/admin-notes")
        XCTAssertEqual(body?["subjectTable"] as? String, "pending_users")
        XCTAssertEqual(body?["subjectId"] as? String, "pu-1")
        let sentNotes = body?["notes"] as? [[String: Any]]
        XCTAssertEqual(sentNotes?.count, 2)
        XCTAssertEqual(sentNotes?[0]["id"] as? String, "n-1")
        XCTAssertNil(sentNotes?[1]["id"] ?? nil)
        XCTAssertEqual(sentNotes?[1]["content"] as? String, "Follow up")
    }

    private let historyJSON = #"""
    [{"id":"h-1","actorLabel":"Mike","actorId":"u-1","action":"sent an invitation",
      "createdAt":"2026-09-03T00:00:00.000Z"}]
    """#

    func testHistory() async throws {
        stub.on(.get, "\(base)/entity-history", json: historyJSON)
        let rows = try await adapter.history(ecosystemID: "org.acme.shop", subject: .invitations, subjectID: "inv-1")
        XCTAssertEqual(rows.first?.actor, "Mike")
        XCTAssertEqual(
            stub.lastRequest(.get, "\(base)/entity-history")?.path,
            "\(base)/entity-history?subjectId=inv-1&subjectTable=invitations&workspace=acme"
        )
    }

    func testErrorsMapToHubError() async throws {
        stub.on(.get, "\(base)/invitation-requests", status: 403, json: #"{"detail":"nope"}"#)
        do {
            _ = try await adapter.requests(ecosystemID: "org.acme.shop")
            XCTFail("expected throw")
        } catch let error as HubError {
            XCTAssertEqual(error, .forbidden)
        }
        XCTAssertEqual(
            stub.lastRequest(.get, "\(base)/invitation-requests")?.path,
            "\(base)/invitation-requests?workspace=acme"
        )
    }
}
