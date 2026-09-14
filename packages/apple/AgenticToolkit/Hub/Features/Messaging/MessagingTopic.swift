import AgenticToolkitHTDV
import Foundation

@MainActor
public final class MessagingTopic: EcosystemTopicProvider {
    public static let entry = EcosystemTopicEntry(
        id: "messaging", label: "Messaging", systemImage: "envelope",
        description: "Send email or SMS to this product's users and review what went out."
    )
    public static let logPageSize = 100
    public static let freeformOption = FormSelectOption(value: "", title: "Freeform message")
    // `nonisolated`: `sendSpec`'s save action reads it from inside a `@Sendable` closure that is not `@MainActor`
    // (precedent: `ApplicationsTopic.rowLevelMessage`, `ApplicationsTopic.noSchemasMessage`).
    public nonisolated static let sendFailedMessage = "Could not send — check the recipient and provider config."
    public var entry: EcosystemTopicEntry { Self.entry }

    private let dataSource: any MessagingDataSource

    public init(dataSource: any MessagingDataSource) { self.dataSource = dataSource }

    // MARK: Copy helpers

    public static func statusLine(_ status: MessagingStatus?) -> String {
        guard let status else { return "Provider status unavailable" }
        return MessagingChannel.allCases
            .map { "\($0.title): \(status.isConnected($0) ? "connected" : "not connected")" }
            .joined(separator: " · ")
    }

    public static func bannerText(for channel: MessagingChannel, status: MessagingStatus?) -> String? {
        guard let status else {
            return "Couldn't check whether \(channel.providerLabel) is connected — sends on this channel may fail."
        }
        if status.isConnected(channel) { return nil }
        return "\(channel.providerLabel) is not connected — sends on this channel will fail. " +
            "Connect a \(channel.providerName) integration on this product's Integrations tab."
    }

    /// `{{name}}` placeholders, trimmed, first-seen order, no duplicates. Pure and stateless, so `nonisolated`:
    /// `MessagingTemplate.placeholders` (a plain, non-isolated struct) calls it synchronously.
    public nonisolated static func placeholders(in text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"\{\{([^}]+)\}\}"#) // swiftlint:disable:this force_try
        var seen: [String] = []
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range(at: 1), in: text) else { continue }
            let name = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, !seen.contains(name) { seen.append(name) }
        }
        return seen
    }

    // MARK: Rail

    public func child(for ecosystem: Ecosystem, path: [HTDVItem], rail: any EcosystemRail) async throws -> HTDVChild {
        switch RailPath.id(at: 0, in: path) {
        case nil:
            let status = try? await dataSource.status(ecosystemID: ecosystem.id)
            return .level(HTDVLevel(id: "messaging:\(ecosystem.id)", title: "Messaging", items: [
                HTDVItem(
                    id: "send", label: "Send a message", sublabel: Self.statusLine(status),
                    systemImage: "paperplane", leadsTo: .detail
                ),
                HTDVItem(
                    id: "log", label: "Message log", sublabel: "What has been sent from this product.",
                    systemImage: "list.bullet.rectangle", leadsTo: .list
                )
            ]))
        case "send":
            return .detail(try await sendDetail(for: ecosystem))
        case "log":
            return try await logChild(for: ecosystem, path: Array(path.dropFirst()))
        default:
            return .empty
        }
    }

    private func sendDetail(for ecosystem: Ecosystem) async throws -> HTDVDetail {
        let templates: [MessagingTemplate]
        do { templates = try await dataSource.templates() } catch { throw HubError.wrap(error) }
        let status = try? await dataSource.status(ecosystemID: ecosystem.id)
        var spec = sendSpec(for: ecosystem, templates: templates)
        var values: [String: FormValue] = [
            "channel": .string(MessagingChannel.email.rawValue), "templateId": .string("")
        ]
        var banners: [FormField] = []
        for channel in MessagingChannel.allCases {
            if let text = Self.bannerText(for: channel, status: status) {
                let key = "\(channel.rawValue)Status"
                banners.append(.readOnly(FormReadOnlyField(key: key, label: channel.providerLabel)))
                values[key] = .string(text)
            }
        }
        if !banners.isEmpty { spec.sections.insert(FormSection(title: "Provider status", fields: banners), at: 0) }
        return FormDetails.form(
            id: "messaging:\(ecosystem.id):send", title: "Send a message", spec: spec, values: values
        )
    }

    /// The compose form. Freeform needs subject (email only) + body; a template needs every placeholder in
    /// `templateVars`.
    public func sendSpec(for ecosystem: Ecosystem, templates: [MessagingTemplate]) -> FormSpec {
        let dataSource = self.dataSource
        let send = FormAction(id: "send", title: "Send") { values in
            let channel = MessagingChannel(rawValue: values["channel"]?.stringValue ?? "") ?? .email
            let userId = values["userId"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let recipient = HubText.nonBlank(values["recipient"]?.stringValue)
            if channel == .sms, recipient == nil {
                throw HubError.validation("A recipient phone number is required for SMS.")
            }
            let templateId = HubText.nonBlank(values["templateId"]?.stringValue)
            var message = MessagingSend(userId: userId, channel: channel, recipient: recipient)
            if let templateId {
                guard let template = templates.first(where: { $0.id == templateId }) else {
                    throw HubError.validation("Choose a template.")
                }
                let vars = try Self.templateVars(from: values["templateVars"]?.stringValue)
                for name in template.placeholders where HubText.nonBlank(vars[name]) == nil {
                    throw HubError.validation("Template needs a value for \"\(name)\".")
                }
                message.templateId = templateId
                message.templateVars = vars
            } else {
                let subject = HubText.nonBlank(values["subject"]?.stringValue)
                let body = HubText.nonBlank(values["body"]?.stringValue)
                if channel == .email, subject == nil { throw HubError.validation("Enter a subject.") }
                guard let body else { throw HubError.validation("Enter a message body.") }
                message.subject = channel == .email ? subject : nil
                message.body = body
            }
            let result: MessagingSendResult
            do { result = try await dataSource.send(ecosystemID: ecosystem.id, message) } catch {
                throw HubError.wrap(error)
            }
            if result.status != "sent" {
                throw HubError.validation(HubText.nonBlank(result.error) ?? Self.sendFailedMessage)
            }
        }
        let options = [Self.freeformOption] + templates.map { FormSelectOption(value: $0.id, title: $0.name) }
        return FormSpec(sections: [
            FormSection(fields: [
                .select(FormSelectField(
                    key: "channel", label: "Channel",
                    options: MessagingChannel.allCases.map { FormSelectOption(value: $0.rawValue, title: $0.title) },
                    isRequired: true
                )),
                .text(FormTextField(key: "userId", label: "Customer ID", placeholder: "customer id", isRequired: true)),
                .text(FormTextField(
                    key: "recipient", label: "Recipient override", placeholder: "name@example.com or +15555550123"
                ))
            ]),
            FormSection(title: "Content", fields: [
                .select(FormSelectField(key: "templateId", label: "Content", options: options)),
                .text(FormTextField(key: "subject", label: "Subject", placeholder: "Email only")),
                .textArea(FormTextAreaField(key: "body", label: "Message body", minLines: 3)),
                .json(FormJSONField(key: "templateVars", label: "Template variables"))
            ])
        ], actions: FormActions(save: send))
    }

    /// Parses the JSON field into `[String: String]`; blank → empty. Pure and stateless, so `nonisolated`:
    /// `sendSpec`'s save action calls it from inside a `@Sendable` closure that is not `@MainActor`.
    private nonisolated static func templateVars(from text: String?) throws -> [String: String] {
        guard let text = HubText.nonBlank(text) else { return [:] }
        let parsed = try JSONValue.parse(text)
        guard let vars = parsed.stringDictionary else {
            throw HubError.validation("Template variables must be a JSON object of strings.")
        }
        return vars
    }

    // MARK: Log

    private func logChild(for ecosystem: Ecosystem, path: [HTDVItem]) async throws -> HTDVChild {
        let page: MessagingLogPage
        do {
            page = try await dataSource.log(ecosystemID: ecosystem.id, page: 1, pageSize: Self.logPageSize)
        } catch {
            throw HubError.wrap(error)
        }
        guard let entryID = RailPath.id(at: 0, in: path) else {
            let items = page.items.map { entry in
                HTDVItem(
                    id: entry.id, label: entry.recipient,
                    sublabel: "\(entry.channel.title) · \(entry.status) · \(HubDates.display(entry.createdAt))",
                    systemImage: entry.channel.systemImage, leadsTo: .detail
                )
            }
            return .level(HTDVLevel(
                id: "messaging-log:\(ecosystem.id)", title: "Message log", items: items,
                emptyMessage: "No messages sent yet."
            ))
        }
        guard let entry = page.items.first(where: { $0.id == entryID }) else { return .empty }
        var fields: [FormField] = [
            .readOnly(FormReadOnlyField(key: "channel", label: "Channel")),
            .readOnly(FormReadOnlyField(key: "recipient", label: "Recipient", isMonospaced: true)),
            .readOnly(FormReadOnlyField(key: "subject", label: "Subject")),
            .readOnly(FormReadOnlyField(key: "status", label: "Status"))
        ]
        var values: [String: FormValue] = [
            "channel": .string(entry.channel.title), "recipient": .string(entry.recipient),
            "subject": .string(HubText.nonBlank(entry.subject) ?? "—"), "status": .string(entry.status),
            "body": .string(entry.body), "sent": .string(HubDates.display(entry.createdAt))
        ]
        if let error = HubText.nonBlank(entry.errorMessage) {
            fields.append(.readOnly(FormReadOnlyField(key: "error", label: "Error")))
            values["error"] = .string(error)
        }
        fields.append(.readOnly(FormReadOnlyField(key: "body", label: "Body")))
        fields.append(.readOnly(FormReadOnlyField(key: "sent", label: "Sent")))
        let spec = FormSpec(sections: [FormSection(fields: fields)])
        return .detail(FormDetails.form(
            id: "messaging-log-entry:\(entry.id)", title: HubText.nonBlank(entry.subject) ?? "Message",
            spec: spec, values: values
        ))
    }
}
