import AgenticToolkitHTDV
import XCTest
@testable import AgenticToolkitHub

final class FakeInvitationsDataSource: InvitationsDataSource, @unchecked Sendable {
    var requests: [HubInvitationRequest]
    var pending: [HubPendingUser]
    var invites: [HubInvite]
    var notes: [String: [HubAdminNote]] = [:]          // "<subject>:<subjectID>" → notes
    var history: [String: [HubHistoryEntry]] = [:]
    var deletedRequests: [String] = []
    var deletedPending: [String] = []
    var deletedInvites: [String] = []
    var added: [[DraftUser]] = []
    var sends: [InvitationSend] = []
    var noteSaves: [(key: String, notes: [AdminNoteInput])] = []
    var failure: Error?

    init(requests: [HubInvitationRequest] = [], pending: [HubPendingUser] = [], invites: [HubInvite] = []) {
        self.requests = requests; self.pending = pending; self.invites = invites
    }

    private func key(_ subject: AdminNoteSubject, _ id: String) -> String { "\(subject.rawValue):\(id)" }
    private func check() throws { if let failure { throw failure } }

    func requests(ecosystemID: String) async throws -> [HubInvitationRequest] { try check(); return requests }
    func deleteRequest(ecosystemID: String, id: String) async throws {
        try check(); deletedRequests.append(id); requests.removeAll { $0.id == id }
    }
    func pendingUsers(ecosystemID: String) async throws -> [HubPendingUser] { try check(); return pending }
    func addPendingUsers(ecosystemID: String, _ users: [DraftUser]) async throws { try check(); added.append(users) }
    func deletePendingUser(ecosystemID: String, id: String) async throws { try check(); deletedPending.append(id) }
    func invites(ecosystemID: String) async throws -> [HubInvite] { try check(); return invites }
    func sendInvitation(ecosystemID: String, _ send: InvitationSend) async throws { try check(); sends.append(send) }
    func deleteInvite(ecosystemID: String, id: String) async throws { try check(); deletedInvites.append(id) }
    func notes(ecosystemID: String, subject: AdminNoteSubject, subjectID: String) async throws -> [HubAdminNote] {
        try check(); return notes[key(subject, subjectID)] ?? []
    }
    func saveNotes(
        ecosystemID: String, subject: AdminNoteSubject, subjectID: String, _ notes: [AdminNoteInput]
    ) async throws {
        try check()
        noteSaves.append((key(subject, subjectID), notes))
        self.notes[key(subject, subjectID)] = notes.enumerated().map { index, input in
            HubAdminNote(
                id: input.id ?? "n-new-\(index)", content: input.content, createdBy: "me@acme.test",
                subjectTable: subject.rawValue, subjectId: subjectID,
                createdAt: "2026-09-03T00:00:00.000Z", updatedAt: "2026-09-03T00:00:00.000Z"
            )
        }
    }
    func history(ecosystemID: String, subject: AdminNoteSubject, subjectID: String) async throws -> [HubHistoryEntry] {
        try check(); return history[key(subject, subjectID)] ?? []
    }
}

extension HubInvitationRequest {
    static func fixture(
        id: String = "req-1", name: String = "Sam Lee", email: String? = "sam@example.com", phone: String? = nil
    ) -> HubInvitationRequest {
        HubInvitationRequest(
            id: id, pendingUserId: nil, name: name, email: email, phone: phone, source: "landing-page",
            note: "Please let me in", createdAt: "2026-09-01T10:00:00.000Z", userNumber: 42
        )
    }
}

extension HubPendingUser {
    static func fixture(
        id: String = "pu-1", name: String = "Ada Park", email: String? = "ada@example.com",
        phone: String? = "+15555550123"
    ) -> HubPendingUser {
        HubPendingUser(
            id: id, userNumber: 7, name: name, email: email, phone: phone, invitedCount: 1, requestCount: 2,
            lastRequestAt: "2026-09-02T00:00:00.000Z", lastInviteSentAt: nil,
            firstRequestedAt: "2026-08-30T00:00:00.000Z", lastSource: "referral", lastNote: "Met at the meetup",
            status: "pending"
        )
    }
}

extension HubInvite {
    static func fixture(id: String = "inv-1", name: String = "Ada Park") -> HubInvite {
        HubInvite(
            id: id, name: name, channel: "email", destination: "ada@example.com", sentBy: "owner@acme.test",
            sentAt: "2026-09-03T00:00:00.000Z", status: "sent"
        )
    }
}

@MainActor
final class InvitationsTopicsTests: XCTestCase {
    private var data: FakeInvitationsDataSource!

    override func setUp() async throws {
        try await super.setUp()
        data = FakeInvitationsDataSource(requests: [.fixture()], pending: [.fixture()], invites: [.fixture()])
    }

    // MARK: Requests

    func testRequestsListAndDetail() async throws {
        let rail = SingleTopicRail(topic: RequestsTopic(dataSource: data))
        let list = try await rail.level([])
        XCTAssertEqual(list.id, "requests-list")
        XCTAssertEqual(list.title, "Requests")
        XCTAssertEqual(list.items.map(\.label), ["Sam Lee"])
        XCTAssertEqual(list.items.first?.sublabel, "sam@example.com")
        XCTAssertEqual(list.items.first?.leadsTo, .list)
        XCTAssertEqual(list.emptyMessage, "No invitation requests.")
        XCTAssertNil(list.createAction)

        let request = try await rail.level(["req-1"])
        XCTAssertEqual(request.id, "request:req-1")
        XCTAssertEqual(request.title, "Sam Lee")
        XCTAssertEqual(request.items.map(\.id), ["details", "notes"])

        let (detail, form) = try await rail.form(["req-1", "details"])
        XCTAssertEqual(detail.id, "request:req-1:details")
        XCTAssertEqual(detail.title, "Request")
        XCTAssertEqual(
            form.state.spec.fields.map(\.key),
            ["userNumber", "name", "phone", "email", "requested", "source", "note", "history"]
        )
        XCTAssertEqual(form.state.value(for: "userNumber"), .string("42"))
        XCTAssertEqual(form.state.value(for: "phone"), .string("—"))
        XCTAssertEqual(form.state.value(for: "note"), .string("Please let me in"))
        XCTAssertEqual(form.state.value(for: "history"), .string("No history."))
        XCTAssertNil(form.state.spec.actions.save)
        XCTAssertEqual(form.state.spec.actions.delete?.title, "Delete request")
        XCTAssertEqual(
            form.state.spec.actions.delete?.confirmationText,
            "Delete the request from \"Sam Lee\"? This removes the invitation request."
        )
        try await form.state.spec.actions.delete!.perform()
        XCTAssertEqual(data.deletedRequests, ["req-1"])
    }

    func testRequestsListLoadFailureWraps() async throws {
        data.failure = HubError.offline
        let rail = SingleTopicRail(topic: RequestsTopic(dataSource: data))
        do { _ = try await rail.child([]); XCTFail("expected throw") } catch let error as HubError {
            XCTAssertEqual(error, .offline)
        }
    }

    func testHistoryRendersOneLinePerEntry() async throws {
        data.history["invitation_requests:req-1"] = [
            HubHistoryEntry(
                id: "h1", actorLabel: "Owner", actorId: "u1", action: "approved", createdAt: "2026-09-02T00:00:00.000Z"
            ),
            HubHistoryEntry(
                id: "h2", actorLabel: nil, actorId: nil, action: "created", createdAt: "2026-09-01T00:00:00.000Z"
            )
        ]
        let rail = SingleTopicRail(topic: RequestsTopic(dataSource: data))
        let (_, form) = try await rail.form(["req-1", "details"])
        let expected = "\(HubDates.display("2026-09-02T00:00:00.000Z")) — Owner approved\n"
            + "\(HubDates.display("2026-09-01T00:00:00.000Z")) — system created"
        XCTAssertEqual(form.state.value(for: "history"), .string(expected))
    }

    // MARK: Admin notes (shared)

    func testNotesLevelListsAndCreates() async throws {
        data.notes["invitation_requests:req-1"] = [
            HubAdminNote(
                id: "n1", content: "First line\nMore", createdBy: "owner@acme.test",
                subjectTable: "invitation_requests", subjectId: "req-1",
                createdAt: "2026-09-01T00:00:00.000Z", updatedAt: "2026-09-02T00:00:00.000Z"
            )
        ]
        let rail = SingleTopicRail(topic: RequestsTopic(dataSource: data))
        let level = try await rail.level(["req-1", "notes"])
        XCTAssertEqual(level.id, "admin-notes:invitation_requests:req-1")
        XCTAssertEqual(level.title, "Admin notes")
        XCTAssertEqual(level.items.map(\.label), ["First line"])
        XCTAssertEqual(
            level.items.first?.sublabel, "owner@acme.test · \(HubDates.display("2026-09-02T00:00:00.000Z"))"
        )
        XCTAssertEqual(level.emptyMessage, "No admin notes yet.")
        XCTAssertEqual(level.createAction?.title, "New note")

        let notesRail = AdminNotesRail(
            dataSource: data, ecosystemID: "org.acme.shop", subject: .invitationRequests, subjectID: "req-1"
        )
        let state = FormState(spec: notesRail.createSpec())
        let firstSave = await state.save()
        XCTAssertFalse(firstSave)
        XCTAssertEqual(state.errors["content"], "Note is required")
        state.set(.string("Called them back"), for: "content")
        let secondSave = await state.save()
        XCTAssertTrue(secondSave)
        XCTAssertEqual(data.noteSaves.last?.key, "invitation_requests:req-1")
        XCTAssertEqual(
            data.noteSaves.last?.notes,
            [
                AdminNoteInput(id: "n1", content: "First line\nMore"),
                AdminNoteInput(id: nil, content: "Called them back")
            ]
        )
    }

    func testNoteDetailEditsAndDeletes() async throws {
        data.notes["pending_users:pu-1"] = [
            HubAdminNote(
                id: "n1", content: "Keep", createdBy: "a@acme.test",
                subjectTable: "pending_users", subjectId: "pu-1",
                createdAt: "2026-09-01T00:00:00.000Z", updatedAt: "2026-09-01T00:00:00.000Z"
            ),
            HubAdminNote(
                id: "n2", content: "Edit me", createdBy: "b@acme.test",
                subjectTable: "pending_users", subjectId: "pu-1",
                createdAt: "2026-09-01T00:00:00.000Z", updatedAt: "2026-09-01T00:00:00.000Z"
            )
        ]
        let rail = SingleTopicRail(topic: PendingUsersTopic(dataSource: data))
        let (detail, form) = try await rail.form(["pu-1", "notes", "n2"])
        XCTAssertEqual(detail.id, "admin-note:n2")
        XCTAssertEqual(detail.title, "Note")
        XCTAssertEqual(form.state.spec.fields.map(\.key), ["content", "author"])
        XCTAssertEqual(form.state.value(for: "author"), .string("b@acme.test"))
        form.state.set(.string("Edited"), for: "content")
        let saved = await form.state.save()
        XCTAssertTrue(saved)
        XCTAssertEqual(
            data.noteSaves.last?.notes,
            [AdminNoteInput(id: "n1", content: "Keep"), AdminNoteInput(id: "n2", content: "Edited")]
        )

        XCTAssertEqual(form.state.spec.actions.delete?.title, "Delete note")
        XCTAssertEqual(form.state.spec.actions.delete?.confirmationText, "Delete this note?")
        try await form.state.spec.actions.delete!.perform()
        XCTAssertEqual(data.noteSaves.last?.notes, [AdminNoteInput(id: "n1", content: "Keep")])
    }

    func testUnknownNoteIsEmpty() async throws {
        let rail = SingleTopicRail(topic: RequestsTopic(dataSource: data))
        guard case .empty = try await rail.child(["req-1", "notes", "nope"]) else { return XCTFail("expected .empty") }
    }

    // MARK: Pending users

    func testPendingUsersListAndDetail() async throws {
        let rail = SingleTopicRail(topic: PendingUsersTopic(dataSource: data))
        let list = try await rail.level([])
        XCTAssertEqual(list.id, "pending-users-list")
        XCTAssertEqual(list.title, "Pending users")
        XCTAssertEqual(list.items.first?.label, "Ada Park")
        XCTAssertEqual(list.items.first?.sublabel, "ada@example.com")
        XCTAssertEqual(list.emptyMessage, "No pending users.")
        XCTAssertEqual(list.createAction?.title, "Add users")

        let user = try await rail.level(["pu-1"])
        XCTAssertEqual(user.id, "pending-user:pu-1")
        XCTAssertEqual(user.items.map(\.id), ["details", "invite", "notes"])
        XCTAssertEqual(user.items[1].label, "Send invitation")

        let (detail, form) = try await rail.form(["pu-1", "details"])
        XCTAssertEqual(detail.id, "pending-user:pu-1:details")
        XCTAssertEqual(detail.title, "Pending user")
        XCTAssertEqual(
            form.state.spec.fields.map(\.key),
            [
                "name", "phone", "email", "invited", "requests", "lastRequest", "lastInvite",
                "requested", "source", "note", "history"
            ]
        )
        XCTAssertEqual(form.state.value(for: "invited"), .string("1"))
        XCTAssertEqual(form.state.value(for: "requests"), .string("2"))
        XCTAssertEqual(form.state.value(for: "lastInvite"), .string("—"))
        XCTAssertEqual(form.state.value(for: "note"), .string("Met at the meetup"))
        XCTAssertEqual(form.state.spec.actions.delete?.title, "Delete pending user")
        XCTAssertEqual(
            form.state.spec.actions.delete?.confirmationText,
            "Delete pending user \"Ada Park\"? This removes the pending user."
        )
        try await form.state.spec.actions.delete!.perform()
        XCTAssertEqual(data.deletedPending, ["pu-1"])
    }

    func testAddUsersSpecRequiresContact() async throws {
        let topic = PendingUsersTopic(dataSource: data)
        let state = FormState(spec: topic.addUsersSpec(for: .fixture()))
        XCTAssertEqual(state.spec.fields.map(\.key), ["name", "email", "phone", "note"])
        let firstSave = await state.save()
        XCTAssertFalse(firstSave)
        XCTAssertEqual(state.errors["name"], "Name is required")
        state.set(.string("Ben Cho"), for: "name")
        let secondSave = await state.save()
        XCTAssertFalse(secondSave)
        XCTAssertEqual(state.saveError, PendingUsersTopic.contactMessage)
        state.set(.string("ben@example.com"), for: "email")
        state.set(.string("Friend of Ada"), for: "note")
        let thirdSave = await state.save()
        XCTAssertTrue(thirdSave)
        XCTAssertEqual(
            data.added,
            [[DraftUser(name: "Ben Cho", email: "ben@example.com", phone: nil, note: "Friend of Ada")]]
        )
    }

    func testSendInvitationDefaultsToAvailableChannels() async throws {
        let rail = SingleTopicRail(topic: PendingUsersTopic(dataSource: data))
        let (detail, form) = try await rail.form(["pu-1", "invite"])
        XCTAssertEqual(detail.id, "pending-user:pu-1:invite")
        XCTAssertEqual(detail.title, "Send invitation")
        XCTAssertEqual(form.state.spec.fields.map(\.key), ["email", "emailNote", "sms", "smsNote"])
        XCTAssertEqual(form.state.value(for: "email"), .bool(true))
        XCTAssertEqual(form.state.value(for: "sms"), .bool(true))
        XCTAssertEqual(form.state.spec.actions.save?.title, "Send")
        form.state.set(.bool(false), for: "sms")
        form.state.set(.string("Welcome aboard"), for: "emailNote")
        let saved = await form.state.save()
        XCTAssertTrue(saved)
        XCTAssertEqual(
            data.sends,
            [InvitationSend(pendingUserIds: ["pu-1"], email: InvitationChannelNote(note: "Welcome aboard"), sms: nil)]
        )
    }

    func testSendInvitationRejectsNoChannelAndMissingContact() async throws {
        data.pending = [.fixture(email: "ada@example.com", phone: nil)]
        let rail = SingleTopicRail(topic: PendingUsersTopic(dataSource: data))
        let (_, form) = try await rail.form(["pu-1", "invite"])
        XCTAssertEqual(form.state.value(for: "sms"), .bool(false))
        form.state.set(.bool(false), for: "email")
        let firstSave = await form.state.save()
        XCTAssertFalse(firstSave)
        XCTAssertEqual(form.state.saveError, "Choose at least one channel.")
        form.state.set(.bool(true), for: "sms")
        let secondSave = await form.state.save()
        XCTAssertFalse(secondSave)
        XCTAssertEqual(form.state.saveError, "This user has no phone number.")
        XCTAssertTrue(data.sends.isEmpty)
    }

    // MARK: Invites

    func testInvitesListAndDetail() async throws {
        let rail = SingleTopicRail(topic: InvitesTopic(dataSource: data))
        let list = try await rail.level([])
        XCTAssertEqual(list.id, "invites-list")
        XCTAssertEqual(list.title, "Invites")
        XCTAssertEqual(list.items.first?.label, "Ada Park")
        XCTAssertEqual(list.items.first?.sublabel, "ada@example.com · \(HubDates.display("2026-09-03T00:00:00.000Z"))")
        XCTAssertEqual(list.emptyMessage, "No invites sent.")
        XCTAssertNil(list.createAction)

        let invite = try await rail.level(["inv-1"])
        XCTAssertEqual(invite.id, "invite:inv-1")
        XCTAssertEqual(invite.items.map(\.id), ["details", "notes"])

        let (detail, form) = try await rail.form(["inv-1", "details"])
        XCTAssertEqual(detail.id, "invite:inv-1:details")
        XCTAssertEqual(detail.title, "Invite")
        XCTAssertEqual(
            form.state.spec.fields.map(\.key),
            ["name", "destination", "channel", "sentBy", "sent", "status", "history"]
        )
        XCTAssertEqual(form.state.value(for: "channel"), .string("Email"))
        XCTAssertEqual(form.state.value(for: "status"), .string("sent"))
        XCTAssertEqual(form.state.spec.actions.delete?.title, "Delete invite")
        XCTAssertEqual(
            form.state.spec.actions.delete?.confirmationText,
            "Delete the invite to \"Ada Park\"? This removes the sent invite."
        )
        try await form.state.spec.actions.delete!.perform()
        XCTAssertEqual(data.deletedInvites, ["inv-1"])
    }

    func testUnknownRowIsEmpty() async throws {
        let rail = SingleTopicRail(topic: InvitesTopic(dataSource: data))
        guard case .empty = try await rail.child(["nope"]) else { return XCTFail("expected .empty") }
    }
}
