import AgenticToolkitHTDV
import Foundation

/// The caller's personal API tokens (`tmp_`): list, mint with a scope, reveal once, revoke.
/// Paths are relative to the "API tokens" entry: `[]` → the list, `[token]` → its detail.
@MainActor
public final class ApiTokensRail {
    public static let catalogueUnavailableMessage =
        "Couldn't load the scope catalogue. Token creation is disabled until it loads — " +
        "otherwise an empty selection would silently mint a broad legacy token instead of " +
        "the scoped one you intended."
    public static let scopeHelp = "Scope (leave empty for legacy curated-only access)"
    public static let scopePrefix = "scope:"

    public private(set) var revealedSecrets: [String: String] = [:]
    private let dataSource: ApiTokensDataSource

    public init(dataSource: ApiTokensDataSource) { self.dataSource = dataSource }

    public func child(path: [HTDVItem]) async throws -> HTDVChild {
        let tokens = try await HubError.wrap { try await self.dataSource.list() }
        switch path.count {
        case 0:
            return .level(level(tokens: tokens))
        case 1:
            guard let token = tokens.first(where: { $0.id == path[0].id }) else { return .empty }
            return .detail(detail(for: token))
        default:
            return .empty
        }
    }

    private func level(tokens: [ApiToken]) -> HTDVLevel {
        let sorted = tokens.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let items = sorted.map { token in
            HTDVItem(id: token.id, label: token.name, sublabel: "\(token.prefix)… · \(token.scopeLine)",
                     systemImage: "key", leadsTo: .detail)
        }
        return HTDVLevel(id: "api-tokens-list", title: "API tokens", items: items, emptyMessage: "No API tokens yet.",
                         createAction: HTDVCreateAction(title: "New API token") { [dataSource] presenter in
                             // The catalogue is fetched when the sheet opens so a stale or failed load
                             // never mints a legacy token by accident.
                             let scopes = try? await dataSource.scopes()
                             let spec = self.createSpec(scopes: scopes)
                             let values: [String: FormValue] = scopes == nil
                                 ? ["notice": .string(ApiTokensRail.catalogueUnavailableMessage)]
                                 : ["scopeHelp": .string(ApiTokensRail.scopeHelp)]
                             _ = await FormSheet.present(
                                 title: "New API token", spec: spec, values: values, from: presenter
                             )
                         })
    }

    /// `scopes == nil` means the catalogue failed to load: the form is a notice with no save action.
    public func createSpec(scopes: [String]?) -> FormSpec {
        guard let scopes else {
            return FormSpec(
                sections: [FormSection(fields: [
                    .readOnly(FormReadOnlyField(key: "notice", label: "Scope catalogue"))
                ])],
                actions: FormActions()
            )
        }
        var fields: [FormField] = [
            .text(FormTextField(key: "name", label: "Name", placeholder: "e.g. research-agent", isRequired: true)),
            .readOnly(FormReadOnlyField(key: "scopeHelp", label: "Scope"))
        ]
        fields += scopes.map { .toggle(FormToggleField(key: ApiTokensRail.scopePrefix + $0, label: $0)) }
        fields.append(.toggle(FormToggleField(
            key: "readOnly", label: "Read-only (GET/HEAD only)", help: "Every selected scope is limited to reads."
        )))
        fields.append(.date(FormDateField(key: "expiresAt", label: "Expires")))
        return FormSpec(
            sections: [FormSection(fields: fields)],
            actions: FormActions(save: FormAction(id: "create", title: "Create") { [weak self, dataSource] values in
                let body = ApiTokenCreate(
                    name: values["name"]?.stringValue?.trimmingCharacters(in: .whitespaces) ?? "",
                    expiresAt: values["expiresAt"]?.dateValue.map(HubDates.iso),
                    scope: await ApiTokensRail.scope(from: values, prefixes: scopes))
                let created = try await HubError.wrap { try await dataSource.create(body) }
                await MainActor.run { self?.revealedSecrets[created.id] = created.token }
            }))
    }

    /// Selected prefixes in catalogue order, each suffixed `:read` when the read-only toggle is
    /// on; `nil` when none are selected (legacy token).
    public static func scope(from values: [String: FormValue], prefixes: [String]) -> [String]? {
        let readOnly = values["readOnly"]?.boolValue ?? false
        let selected = prefixes
            .filter { values[scopePrefix + $0]?.boolValue == true }
            .map { readOnly ? "\($0):read" : $0 }
        return selected.isEmpty ? nil : selected
    }

    private func detail(for token: ApiToken) -> HTDVDetail {
        var fields: [FormField] = [
            .readOnly(FormReadOnlyField(key: "name", label: "Name")),
            .readOnly(FormReadOnlyField(key: "prefix", label: "Prefix", isMonospaced: true)),
            .readOnly(FormReadOnlyField(key: "scope", label: "Scope", isMonospaced: true)),
            .readOnly(FormReadOnlyField(key: "created", label: "Created")),
            .readOnly(FormReadOnlyField(key: "lastUsed", label: "Last used")),
            .readOnly(FormReadOnlyField(key: "expires", label: "Expires"))
        ]
        var values: [String: FormValue] = [
            "name": .string(token.name),
            "prefix": .string("\(token.prefix)…"),
            "scope": .string(
                (token.scope?.isEmpty == false) ? token.scope!.joined(separator: "\n") : "legacy (curated-only)"
            ),
            "created": .string(HubDates.display(token.createdAt)),
            "lastUsed": .string(token.lastUsedAt.map { HubDates.display($0) } ?? "never used"),
            "expires": .string(token.expiresAt.map { HubDates.display($0) } ?? "never")
        ]
        if let secret = revealedSecrets[token.id] {
            fields.append(.readOnly(FormReadOnlyField(key: "token", label: "Token", isMonospaced: true)))
            fields.append(.readOnly(FormReadOnlyField(key: "notice", label: "")))
            values["token"] = .string(secret)
            values["notice"] = .string(ApplicationsTopic.revealMessage)
        }
        let spec = FormSpec(
            sections: [FormSection(fields: fields)],
            actions: FormActions(delete: FormDeleteAction(
                title: "Revoke token",
                confirmationText: "Revoke API token \"\(token.name)\"? Anything using it will stop working."
            ) { [weak self, dataSource] in
                try await HubError.wrap { try await dataSource.revoke(id: token.id) }
                await MainActor.run { self?.revealedSecrets[token.id] = nil }
            }))
        return FormDetails.form(id: "api-token:\(token.id)", title: token.name, spec: spec, values: values)
    }
}
