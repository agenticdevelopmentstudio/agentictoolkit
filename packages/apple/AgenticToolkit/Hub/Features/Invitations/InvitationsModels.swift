import Foundation

/// Named `Hub`-prefixed to avoid colliding with the identically-named,
/// independently-defined TypeScript wire types in `web-adh-ui`
/// (`packages/web/packages/adh-ui/src/lib/invitations-types.ts`), which
/// `abstractr`'s duplicate-name check flags across the whole export index
/// regardless of language. These describe the same backend JSON contract but
/// are a different platform's own DTOs — there is nothing here to "build on
/// or extend" across languages, so the disambiguating prefix is the fix.
public struct HubInvitationRequest: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var pendingUserId: String?
    public var name: String
    public var email: String?
    public var phone: String?
    public var source: String?
    public var note: String?
    public var createdAt: String
    public var userNumber: Int?

    public init(
        id: String, pendingUserId: String? = nil, name: String, email: String? = nil, phone: String? = nil,
        source: String? = nil, note: String? = nil, createdAt: String, userNumber: Int? = nil
    ) {
        self.id = id; self.pendingUserId = pendingUserId; self.name = name; self.email = email; self.phone = phone
        self.source = source; self.note = note; self.createdAt = createdAt; self.userNumber = userNumber
    }

    public var contact: String { HubText.nonBlank(email) ?? HubText.nonBlank(phone) ?? "—" }
}

public struct HubPendingUser: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var userNumber: Int
    public var name: String
    public var email: String?
    public var phone: String?
    public var invitedCount: Int
    public var requestCount: Int
    public var lastRequestAt: String?
    public var lastInviteSentAt: String?
    public var firstRequestedAt: String
    public var lastSource: String?
    public var lastNote: String?
    public var status: String?

    public init(
        id: String, userNumber: Int, name: String, email: String? = nil, phone: String? = nil, invitedCount: Int,
        requestCount: Int, lastRequestAt: String? = nil, lastInviteSentAt: String? = nil, firstRequestedAt: String,
        lastSource: String? = nil, lastNote: String? = nil, status: String? = nil
    ) {
        self.id = id; self.userNumber = userNumber; self.name = name; self.email = email; self.phone = phone
        self.invitedCount = invitedCount; self.requestCount = requestCount; self.lastRequestAt = lastRequestAt
        self.lastInviteSentAt = lastInviteSentAt; self.firstRequestedAt = firstRequestedAt
        self.lastSource = lastSource; self.lastNote = lastNote; self.status = status
    }

    public var contact: String { HubText.nonBlank(email) ?? HubText.nonBlank(phone) ?? "—" }
}

public struct HubInvite: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var channel: String
    public var destination: String
    public var sentBy: String
    public var sentAt: String
    public var status: String?

    public init(
        id: String, name: String, channel: String, destination: String, sentBy: String, sentAt: String,
        status: String? = nil
    ) {
        self.id = id; self.name = name; self.channel = channel; self.destination = destination
        self.sentBy = sentBy; self.sentAt = sentAt; self.status = status
    }

    /// "Email" / "SMS" / the raw channel for anything else.
    public var channelTitle: String {
        switch channel.lowercased() {
        case "email": return "Email"
        case "sms": return "SMS"
        default: return channel
        }
    }
}

public struct DraftUser: Codable, Hashable, Sendable {
    public var name: String
    public var email: String?
    public var phone: String?
    public var note: String?
    public init(name: String, email: String? = nil, phone: String? = nil, note: String? = nil) {
        self.name = name; self.email = email; self.phone = phone; self.note = note
    }
}

public struct InvitationChannelNote: Codable, Hashable, Sendable {
    public var note: String?
    public init(note: String? = nil) { self.note = note }
}

public struct InvitationSend: Codable, Hashable, Sendable {
    public var pendingUserIds: [String]
    public var email: InvitationChannelNote?
    public var sms: InvitationChannelNote?
    public init(pendingUserIds: [String], email: InvitationChannelNote? = nil, sms: InvitationChannelNote? = nil) {
        self.pendingUserIds = pendingUserIds; self.email = email; self.sms = sms
    }
}

public struct HubAdminNote: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var content: String
    public var createdBy: String
    public var subjectTable: String
    public var subjectId: String
    public var createdAt: String
    public var updatedAt: String

    public init(
        id: String, content: String, createdBy: String, subjectTable: String, subjectId: String,
        createdAt: String, updatedAt: String
    ) {
        self.id = id; self.content = content; self.createdBy = createdBy; self.subjectTable = subjectTable
        self.subjectId = subjectId; self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    /// First non-empty line of the content, for list rows.
    public var headline: String {
        content.split(whereSeparator: \.isNewline).map(String.init)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "(empty note)"
    }
    public var input: AdminNoteInput { AdminNoteInput(id: id, content: content) }
}

public struct AdminNoteInput: Codable, Hashable, Sendable {
    public var id: String?
    public var content: String
    public init(id: String? = nil, content: String) { self.id = id; self.content = content }
}

public struct HubHistoryEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var actorLabel: String?
    public var actorId: String?
    public var action: String
    public var createdAt: String

    public init(id: String, actorLabel: String? = nil, actorId: String? = nil, action: String, createdAt: String) {
        self.id = id; self.actorLabel = actorLabel; self.actorId = actorId; self.action = action
        self.createdAt = createdAt
    }

    public var actor: String { actorLabel ?? actorId ?? "system" }
    public var line: String { "\(HubDates.display(createdAt)) — \(actor) \(action)" }
}

public enum AdminNoteSubject: String, Sendable {
    case invitationRequests = "invitation_requests"
    case pendingUsers = "pending_users"
    case invitations = "invitations"
}

public protocol InvitationsDataSource: AnyObject, Sendable {
    func requests(ecosystemID: String) async throws -> [HubInvitationRequest]
    func deleteRequest(ecosystemID: String, id: String) async throws
    func pendingUsers(ecosystemID: String) async throws -> [HubPendingUser]
    func addPendingUsers(ecosystemID: String, _ users: [DraftUser]) async throws
    func deletePendingUser(ecosystemID: String, id: String) async throws
    func invites(ecosystemID: String) async throws -> [HubInvite]
    func sendInvitation(ecosystemID: String, _ send: InvitationSend) async throws
    func deleteInvite(ecosystemID: String, id: String) async throws
    func notes(ecosystemID: String, subject: AdminNoteSubject, subjectID: String) async throws -> [HubAdminNote]
    func saveNotes(
        ecosystemID: String, subject: AdminNoteSubject, subjectID: String, _ notes: [AdminNoteInput]
    ) async throws
    func history(ecosystemID: String, subject: AdminNoteSubject, subjectID: String) async throws -> [HubHistoryEntry]
}
