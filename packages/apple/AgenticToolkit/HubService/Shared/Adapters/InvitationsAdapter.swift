import AgenticToolkitHub
import Foundation
import HTTPTypes

/// `InvitationsDataSource` over `/auth/ecosystems/{id}/…`.
@MainActor
public final class InvitationsAdapter: InvitationsDataSource {
    private let api: HubAPI
    private let workspace: HubWorkspace

    public init(environment: HubEnvironment, workspace: HubWorkspace) {
        self.api = HubAPI(environment: environment)
        self.workspace = workspace
    }

    private struct UsersBody: Encodable { let users: [DraftUser] }
    private struct NotesBody: Encodable { let subjectTable: String; let subjectId: String; let notes: [AdminNoteInput] }

    private func path(_ ecosystemID: String, _ rest: String) -> String { "/auth/ecosystems/\(ecosystemID)/\(rest)" }

    /// The workspace query plus extra pairs; nil values are dropped.
    private func query(_ extra: [String: String?]) -> [String: String] {
        workspace.query.merging(HubAPI.query(extra)) { _, new in new }
    }

    private func subjectQuery(_ subject: AdminNoteSubject, _ subjectID: String) -> [String: String] {
        query(["subjectTable": subject.rawValue, "subjectId": subjectID])
    }

    public func requests(ecosystemID: String) async throws -> [InvitationRequest] {
        try await api.get(
            path(ecosystemID, "invitation-requests"), query: workspace.query, as: [InvitationRequest].self
        )
    }

    public func deleteRequest(ecosystemID: String, id: String) async throws {
        try await api.send(.delete, path(ecosystemID, "invitation-requests/\(id)"), query: workspace.query)
    }

    public func pendingUsers(ecosystemID: String) async throws -> [PendingUser] {
        try await api.get(path(ecosystemID, "pending-users"), query: workspace.query, as: [PendingUser].self)
    }

    public func addPendingUsers(ecosystemID: String, _ users: [DraftUser]) async throws {
        try await api.send(
            .post, path(ecosystemID, "pending-users"), query: workspace.query, body: UsersBody(users: users)
        )
    }

    public func deletePendingUser(ecosystemID: String, id: String) async throws {
        try await api.send(.delete, path(ecosystemID, "pending-users/\(id)"), query: workspace.query)
    }

    public func invites(ecosystemID: String) async throws -> [Invite] {
        try await api.get(path(ecosystemID, "invitations"), query: workspace.query, as: [Invite].self)
    }

    public func sendInvitation(ecosystemID: String, _ send: InvitationSend) async throws {
        try await api.send(.post, path(ecosystemID, "invitations"), query: workspace.query, body: send)
    }

    public func deleteInvite(ecosystemID: String, id: String) async throws {
        try await api.send(.delete, path(ecosystemID, "invitations/\(id)"), query: workspace.query)
    }

    public func notes(
        ecosystemID: String, subject: AdminNoteSubject, subjectID: String
    ) async throws -> [AdminNote] {
        try await api.get(
            path(ecosystemID, "admin-notes"), query: subjectQuery(subject, subjectID), as: [AdminNote].self
        )
    }

    /// The server echoes the saved `[AdminNote]` rows, but `InvitationsDataSource.saveNotes` (as landed in
    /// Task 11) returns `Void` — callers re-fetch via `notes(...)` for the current list. See task-13-report.md
    /// "Deviations from the brief".
    public func saveNotes(
        ecosystemID: String, subject: AdminNoteSubject, subjectID: String, _ notes: [AdminNoteInput]
    ) async throws {
        try await api.send(
            .put, path(ecosystemID, "admin-notes"), query: workspace.query,
            body: NotesBody(subjectTable: subject.rawValue, subjectId: subjectID, notes: notes)
        )
    }

    public func history(
        ecosystemID: String, subject: AdminNoteSubject, subjectID: String
    ) async throws -> [HistoryEntry] {
        try await api.get(
            path(ecosystemID, "entity-history"), query: subjectQuery(subject, subjectID), as: [HistoryEntry].self
        )
    }
}
