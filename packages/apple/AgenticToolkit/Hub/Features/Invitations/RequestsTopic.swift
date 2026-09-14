import AgenticToolkitHTDV
import Foundation

@MainActor
public final class RequestsTopic: EcosystemTopicProvider {
    public static let entry = EcosystemTopicEntry(
        id: "requests", label: "Requests", systemImage: "tray",
        description: "People asking to join — approve or decline."
    )
    public var entry: EcosystemTopicEntry { Self.entry }

    private let dataSource: any InvitationsDataSource

    public init(dataSource: any InvitationsDataSource) { self.dataSource = dataSource }

    public func child(for ecosystem: Ecosystem, path: [HTDVItem], rail: any EcosystemRail) async throws -> HTDVChild {
        let requests: [HubInvitationRequest]
        do { requests = try await dataSource.requests(ecosystemID: ecosystem.id) } catch { throw HubError.wrap(error) }
        guard let requestID = RailPath.id(at: 0, in: path) else {
            let items = requests.map {
                HTDVItem(id: $0.id, label: $0.name, sublabel: $0.contact, systemImage: "tray", leadsTo: .list)
            }
            return .level(
                HTDVLevel(id: "requests-list", title: "Requests", items: items, emptyMessage: "No invitation requests.")
            )
        }
        guard let request = requests.first(where: { $0.id == requestID }) else { return .empty }
        let notes = AdminNotesRail(
            dataSource: dataSource, ecosystemID: ecosystem.id, subject: .invitationRequests, subjectID: request.id
        )
        switch RailPath.id(at: 1, in: path) {
        case nil:
            return .level(
                HTDVLevel(id: "request:\(request.id)", title: request.name, items: [
                    HTDVItem(
                        id: "details", label: "Details", sublabel: "Who asked, and what they said.",
                        systemImage: "person.text.rectangle", leadsTo: .detail
                    ),
                    AdminNotesRail.item
                ])
            )
        case "details":
            return .detail(try await detail(for: request, in: ecosystem))
        case "notes":
            return try await notes.child(path: Array(path.dropFirst(2)))
        default:
            return .empty
        }
    }

    private func detail(for request: HubInvitationRequest, in ecosystem: Ecosystem) async throws -> HTDVDetail {
        let history: [HubHistoryEntry]
        do {
            history = try await dataSource.history(
                ecosystemID: ecosystem.id, subject: .invitationRequests, subjectID: request.id
            )
        } catch { throw HubError.wrap(error) }
        let dataSource = self.dataSource
        let delete = FormDeleteAction(
            title: "Delete request",
            confirmationText: "Delete the request from \"\(request.name)\"? This removes the invitation request."
        ) {
            do { try await dataSource.deleteRequest(ecosystemID: ecosystem.id, id: request.id) } catch {
                throw HubError.wrap(error)
            }
        }
        let spec = FormSpec(
            sections: [
                FormSection(fields: [
                    .readOnly(FormReadOnlyField(key: "userNumber", label: "User #")),
                    .readOnly(FormReadOnlyField(key: "name", label: "Name")),
                    .readOnly(FormReadOnlyField(key: "phone", label: "Phone")),
                    .readOnly(FormReadOnlyField(key: "email", label: "Email")),
                    .readOnly(FormReadOnlyField(key: "requested", label: "Requested")),
                    .readOnly(FormReadOnlyField(key: "source", label: "Source")),
                    .readOnly(FormReadOnlyField(key: "note", label: "Note to the team"))
                ]),
                FormSection(title: "History", fields: [.readOnly(FormReadOnlyField(key: "history", label: "History"))])
            ],
            actions: FormActions(delete: delete)
        )
        let values: [String: FormValue] = [
            "userNumber": .string(request.userNumber.map(String.init) ?? "—"),
            "name": .string(request.name),
            "phone": .string(HubText.nonBlank(request.phone) ?? "—"),
            "email": .string(HubText.nonBlank(request.email) ?? "—"),
            "requested": .string(HubDates.display(request.createdAt)),
            "source": .string(HubText.nonBlank(request.source) ?? "—"),
            "note": .string(HubText.nonBlank(request.note) ?? "—"),
            "history": .string(AdminNotesRail.historyText(history))
        ]
        return FormDetails.form(id: "request:\(request.id):details", title: "Request", spec: spec, values: values)
    }
}
