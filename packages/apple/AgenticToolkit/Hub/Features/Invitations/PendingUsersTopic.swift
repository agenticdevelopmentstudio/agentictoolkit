import AgenticToolkitHTDV
import Foundation

@MainActor
public final class PendingUsersTopic: EcosystemTopicProvider {
    public static let entry = EcosystemTopicEntry(
        id: "pending-users", label: "Pending users", systemImage: "person.crop.circle.badge.clock",
        description: "Approved sign-ups that haven't completed registration yet."
    )
    public static let contactMessage = "Enter an email address or a phone number."
    public var entry: EcosystemTopicEntry { Self.entry }

    private let dataSource: any InvitationsDataSource

    public init(dataSource: any InvitationsDataSource) { self.dataSource = dataSource }

    public func child(for ecosystem: Ecosystem, path: [HTDVItem], rail: any EcosystemRail) async throws -> HTDVChild {
        let users: [PendingUser]
        do { users = try await dataSource.pendingUsers(ecosystemID: ecosystem.id) } catch { throw HubError.wrap(error) }
        guard let userID = RailPath.id(at: 0, in: path) else {
            let items = users.map {
                HTDVItem(
                    id: $0.id, label: $0.name, sublabel: $0.contact,
                    systemImage: "person.crop.circle.badge.clock", leadsTo: .list
                )
            }
            let spec = addUsersSpec(for: ecosystem)
            let action = HTDVCreateAction(title: "Add users") { presenter in
                _ = await FormSheet.present(title: "Add user", spec: spec, from: presenter)
            }
            return .level(
                HTDVLevel(
                    id: "pending-users-list", title: "Pending users", items: items,
                    emptyMessage: "No pending users.", createAction: action
                )
            )
        }
        guard let user = users.first(where: { $0.id == userID }) else { return .empty }
        let notes = AdminNotesRail(
            dataSource: dataSource, ecosystemID: ecosystem.id, subject: .pendingUsers, subjectID: user.id
        )
        switch RailPath.id(at: 1, in: path) {
        case nil:
            return .level(
                HTDVLevel(id: "pending-user:\(user.id)", title: user.name, items: [
                    HTDVItem(
                        id: "details", label: "Details", sublabel: "Contact, counts and their note.",
                        systemImage: "person.text.rectangle", leadsTo: .detail
                    ),
                    HTDVItem(
                        id: "invite", label: "Send invitation", sublabel: "Email or text them a sign-up link.",
                        systemImage: "paperplane", leadsTo: .detail
                    ),
                    AdminNotesRail.item
                ])
            )
        case "details":
            return .detail(try await detail(for: user, in: ecosystem))
        case "invite":
            return .detail(inviteDetail(for: user, in: ecosystem))
        case "notes":
            return try await notes.child(path: Array(path.dropFirst(2)))
        default:
            return .empty
        }
    }

    /// "Add users": one draft user per submission. Name is required; an email or a phone is required.
    public func addUsersSpec(for ecosystem: Ecosystem) -> FormSpec {
        let dataSource = self.dataSource
        let contactMessage = Self.contactMessage
        let save = FormAction(id: "add", title: "Add") { values in
            let name = values["name"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let email = HubText.nonBlank(values["email"]?.stringValue)
            let phone = HubText.nonBlank(values["phone"]?.stringValue)
            guard email != nil || phone != nil else { throw HubError.validation(contactMessage) }
            let draft = DraftUser(
                name: name, email: email, phone: phone, note: HubText.nonBlank(values["note"]?.stringValue)
            )
            do { try await dataSource.addPendingUsers(ecosystemID: ecosystem.id, [draft]) } catch {
                throw HubError.wrap(error)
            }
        }
        return FormSpec(
            sections: [
                FormSection(fields: [
                    .text(FormTextField(key: "name", label: "Name", placeholder: "Jane Doe", isRequired: true)),
                    .text(FormTextField(
                        key: "email", label: "Email", placeholder: "person@example.com",
                        pattern: CustomersTopic.emailPattern, patternMessage: CustomersTopic.emailMessage
                    )),
                    .text(FormTextField(key: "phone", label: "Phone", placeholder: "+15555550123")),
                    .textArea(FormTextAreaField(
                        key: "note", label: "Note", placeholder: "Why they're being added", minLines: 2
                    ))
                ])
            ],
            actions: FormActions(save: save)
        )
    }

    private func detail(for user: PendingUser, in ecosystem: Ecosystem) async throws -> HTDVDetail {
        let history: [HistoryEntry]
        do {
            history = try await dataSource.history(
                ecosystemID: ecosystem.id, subject: .pendingUsers, subjectID: user.id
            )
        } catch { throw HubError.wrap(error) }
        let dataSource = self.dataSource
        let delete = FormDeleteAction(
            title: "Delete pending user",
            confirmationText: "Delete pending user \"\(user.name)\"? This removes the pending user."
        ) {
            do { try await dataSource.deletePendingUser(ecosystemID: ecosystem.id, id: user.id) } catch {
                throw HubError.wrap(error)
            }
        }
        let spec = FormSpec(
            sections: [
                FormSection(fields: [
                    .readOnly(FormReadOnlyField(key: "name", label: "Name")),
                    .readOnly(FormReadOnlyField(key: "phone", label: "Phone")),
                    .readOnly(FormReadOnlyField(key: "email", label: "Email")),
                    .readOnly(FormReadOnlyField(key: "invited", label: "Invited")),
                    .readOnly(FormReadOnlyField(key: "requests", label: "Requests")),
                    .readOnly(FormReadOnlyField(key: "lastRequest", label: "Last request")),
                    .readOnly(FormReadOnlyField(key: "lastInvite", label: "Last invite")),
                    .readOnly(FormReadOnlyField(key: "requested", label: "Requested")),
                    .readOnly(FormReadOnlyField(key: "source", label: "Source")),
                    .readOnly(FormReadOnlyField(key: "note", label: "Note from user"))
                ]),
                FormSection(title: "History", fields: [.readOnly(FormReadOnlyField(key: "history", label: "History"))])
            ],
            actions: FormActions(delete: delete)
        )
        let values: [String: FormValue] = [
            "name": .string(user.name),
            "phone": .string(HubText.nonBlank(user.phone) ?? "—"),
            "email": .string(HubText.nonBlank(user.email) ?? "—"),
            "invited": .string(String(user.invitedCount)),
            "requests": .string(String(user.requestCount)),
            "lastRequest": .string(HubDates.display(user.lastRequestAt)),
            "lastInvite": .string(HubDates.display(user.lastInviteSentAt)),
            "requested": .string(HubDates.display(user.firstRequestedAt)),
            "source": .string(HubText.nonBlank(user.lastSource) ?? "—"),
            "note": .string(HubText.nonBlank(user.lastNote) ?? "—"),
            "history": .string(AdminNotesRail.historyText(history))
        ]
        return FormDetails.form(
            id: "pending-user:\(user.id):details", title: "Pending user", spec: spec, values: values
        )
    }

    private func inviteDetail(for user: PendingUser, in ecosystem: Ecosystem) -> HTDVDetail {
        let dataSource = self.dataSource
        let hasEmail = HubText.nonBlank(user.email) != nil
        let hasPhone = HubText.nonBlank(user.phone) != nil
        let send = FormAction(id: "send", title: "Send") { values in
            let email = values["email"]?.boolValue ?? false
            let sms = values["sms"]?.boolValue ?? false
            guard email || sms else { throw HubError.validation("Choose at least one channel.") }
            if email, !hasEmail { throw HubError.validation("This user has no email address.") }
            if sms, !hasPhone { throw HubError.validation("This user has no phone number.") }
            let payload = InvitationSend(
                pendingUserIds: [user.id],
                email: email ? InvitationChannelNote(note: HubText.nonBlank(values["emailNote"]?.stringValue)) : nil,
                sms: sms ? InvitationChannelNote(note: HubText.nonBlank(values["smsNote"]?.stringValue)) : nil
            )
            do { try await dataSource.sendInvitation(ecosystemID: ecosystem.id, payload) } catch {
                throw HubError.wrap(error)
            }
        }
        let spec = FormSpec(
            sections: [
                FormSection(title: "Email", fields: [
                    .toggle(FormToggleField(
                        key: "email", label: "Send by email",
                        help: hasEmail ? user.email : "This user has no email address."
                    )),
                    .textArea(FormTextAreaField(
                        key: "emailNote", label: "Email note", placeholder: "Optional message included in the email",
                        minLines: 2
                    ))
                ]),
                FormSection(title: "SMS", fields: [
                    .toggle(FormToggleField(
                        key: "sms", label: "Send by SMS", help: hasPhone ? user.phone : "This user has no phone number."
                    )),
                    .textArea(FormTextAreaField(
                        key: "smsNote", label: "SMS note", placeholder: "Optional message included in the text",
                        minLines: 2
                    ))
                ])
            ],
            actions: FormActions(save: send)
        )
        return FormDetails.form(
            id: "pending-user:\(user.id):invite", title: "Send invitation", spec: spec,
            values: ["email": .bool(hasEmail), "sms": .bool(hasPhone)]
        )
    }
}
