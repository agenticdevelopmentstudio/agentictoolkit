import AgenticToolkitHTDV
import Foundation

@MainActor
public final class InvitesTopic: EcosystemTopicProvider {
    public static let entry = EcosystemTopicEntry(
        id: "invites", label: "Invites", systemImage: "paperplane",
        description: "Invitations you've sent and their status."
    )
    public var entry: EcosystemTopicEntry { Self.entry }

    private let dataSource: any InvitationsDataSource

    public init(dataSource: any InvitationsDataSource) { self.dataSource = dataSource }

    public func child(for ecosystem: Ecosystem, path: [HTDVItem], rail: any EcosystemRail) async throws -> HTDVChild {
        let invites: [HubInvite]
        do { invites = try await dataSource.invites(ecosystemID: ecosystem.id) } catch { throw HubError.wrap(error) }
        guard let inviteID = RailPath.id(at: 0, in: path) else {
            let items = invites.map {
                HTDVItem(
                    id: $0.id, label: $0.name, sublabel: "\($0.destination) · \(HubDates.display($0.sentAt))",
                    systemImage: "paperplane", leadsTo: .list
                )
            }
            return .level(
                HTDVLevel(id: "invites-list", title: "Invites", items: items, emptyMessage: "No invites sent.")
            )
        }
        guard let invite = invites.first(where: { $0.id == inviteID }) else { return .empty }
        let notes = AdminNotesRail(
            dataSource: dataSource, ecosystemID: ecosystem.id, subject: .invitations, subjectID: invite.id
        )
        switch RailPath.id(at: 1, in: path) {
        case nil:
            return .level(
                HTDVLevel(id: "invite:\(invite.id)", title: invite.name, items: [
                    HTDVItem(
                        id: "details", label: "Details", sublabel: "Where it went and when.",
                        systemImage: "person.text.rectangle", leadsTo: .detail
                    ),
                    AdminNotesRail.item
                ])
            )
        case "details":
            return .detail(try await detail(for: invite, in: ecosystem))
        case "notes":
            return try await notes.child(path: Array(path.dropFirst(2)))
        default:
            return .empty
        }
    }

    private func detail(for invite: HubInvite, in ecosystem: Ecosystem) async throws -> HTDVDetail {
        let history: [HubHistoryEntry]
        do {
            history = try await dataSource.history(
                ecosystemID: ecosystem.id, subject: .invitations, subjectID: invite.id
            )
        } catch { throw HubError.wrap(error) }
        let dataSource = self.dataSource
        let delete = FormDeleteAction(
            title: "Delete invite",
            confirmationText: "Delete the invite to \"\(invite.name)\"? This removes the sent invite."
        ) {
            do { try await dataSource.deleteInvite(ecosystemID: ecosystem.id, id: invite.id) } catch {
                throw HubError.wrap(error)
            }
        }
        let spec = FormSpec(
            sections: [
                FormSection(fields: [
                    .readOnly(FormReadOnlyField(key: "name", label: "Name")),
                    .readOnly(FormReadOnlyField(key: "destination", label: "Sent to")),
                    .readOnly(FormReadOnlyField(key: "channel", label: "Channel")),
                    .readOnly(FormReadOnlyField(key: "sentBy", label: "Sent by")),
                    .readOnly(FormReadOnlyField(key: "sent", label: "Sent")),
                    .readOnly(FormReadOnlyField(key: "status", label: "Status"))
                ]),
                FormSection(title: "History", fields: [.readOnly(FormReadOnlyField(key: "history", label: "History"))])
            ],
            actions: FormActions(delete: delete)
        )
        let values: [String: FormValue] = [
            "name": .string(invite.name),
            "destination": .string(invite.destination),
            "channel": .string(invite.channelTitle),
            "sentBy": .string(invite.sentBy),
            "sent": .string(HubDates.display(invite.sentAt)),
            "status": .string(HubText.nonBlank(invite.status) ?? "—"),
            "history": .string(AdminNotesRail.historyText(history))
        ]
        return FormDetails.form(id: "invite:\(invite.id):details", title: "Invite", spec: spec, values: values)
    }
}
