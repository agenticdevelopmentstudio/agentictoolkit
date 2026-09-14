import AgenticToolkitHTDV
import Foundation

/// Storage tokens list + create + detail, parameterised by an optional ecosystem.
/// Holds the raw secret of every token minted in this session so the detail can reveal it once.
@MainActor
public final class StorageTokensRail {
    /// `nonisolated`: read inside the create form's save action, which runs in a `FormAction.perform`
    /// closure — those closures are not `@MainActor` (`FormSpec.swift`).
    public nonisolated static let nameTakenMessage =
        "That name is already in use. Token names stay reserved even after revoke — pick a different one."
    public nonisolated static let createFailedMessage = "Couldn't create the token. Please try again."
    public static let aboutWithEcosystem =
        "A storage principal scoped to your account; its own empty bucket lives in this product's ecosystem."
    public static let aboutWithoutEcosystem =
        "A storage principal scoped to your account; it gets its own empty bucket."

    public private(set) var revealedSecrets: [String: String] = [:]
    private let dataSource: any StorageTokensDataSource

    public init(dataSource: any StorageTokensDataSource) { self.dataSource = dataSource }

    /// `path` is relative to the level: `[]` → the list, `[token]` → its detail.
    public func child(
        path: [HTDVItem], ecosystemID: String?, levelID: String, title: String
    ) async throws -> HTDVChild {
        let tokens = try await HubError.wrap { try await self.dataSource.list(ecosystemID: ecosystemID) }
        switch path.count {
        case 0:
            return .level(level(tokens: tokens, ecosystemID: ecosystemID, levelID: levelID, title: title))
        case 1:
            guard let token = tokens.first(where: { $0.id == path[0].id }) else { return .empty }
            return .detail(detail(for: token, ecosystemID: ecosystemID))
        default:
            return .empty
        }
    }

    private func level(tokens: [StorageToken], ecosystemID: String?, levelID: String, title: String) -> HTDVLevel {
        let items = tokens.sorted { $0.slug < $1.slug }.map { token -> HTDVItem in
            let sublabel = "\(token.prefix)… · \(token.bucketRdid ?? "no bucket")"
            return HTDVItem(id: token.id, label: token.rdid ?? token.slug, sublabel: sublabel,
                            systemImage: "externaldrive", leadsTo: .detail)
        }
        let spec = createSpec(ecosystemID: ecosystemID)
        let values: [String: FormValue] = ["about": .string(StorageTokensRail.aboutText(ecosystemID: ecosystemID))]
        return HTDVLevel(
            id: levelID, title: title, items: items, emptyMessage: "No tokens yet.",
            createAction: HTDVCreateAction(title: "New storage token") { presenter in
                _ = await FormSheet.present(title: "New storage token", spec: spec, values: values, from: presenter)
            })
    }

    /// The explanatory line shown above the create form; supplied as the `about` value when the sheet opens.
    public static func aboutText(ecosystemID: String?) -> String {
        ecosystemID == nil ? aboutWithoutEcosystem : aboutWithEcosystem
    }

    /// Create form: name (slug), description, optional expiry. On success the raw secret is kept in `revealedSecrets`.
    public func createSpec(ecosystemID: String?) -> FormSpec {
        FormSpec(
            sections: [FormSection(fields: [
                .readOnly(FormReadOnlyField(key: "about", label: "About")),
                .text(FormTextField(key: "name", label: "Name", placeholder: "ci-sync", isRequired: true,
                                    pattern: Slug.pattern, patternMessage: Slug.patternMessage)),
                .text(FormTextField(key: "description", label: "Description", placeholder: "What this token is for")),
                .date(FormDateField(key: "expiresAt", label: "Expires"))
            ])],
            actions: FormActions(save: FormAction(id: "create", title: "Create") { [weak self, dataSource] values in
                let body = StorageTokenCreate(
                    name: values["name"]?.stringValue?.trimmingCharacters(in: .whitespaces) ?? "",
                    description: HubText.nonBlank(values["description"]?.stringValue),
                    expiresAt: values["expiresAt"]?.dateValue.map(HubDates.iso),
                    ecosystemId: nil)
                let created: StorageTokenCreated
                do {
                    created = try await dataSource.create(ecosystemID: ecosystemID, body)
                } catch HubError.conflict {
                    throw HubError.validation(StorageTokensRail.nameTakenMessage)
                } catch let error as HubError {
                    throw error
                } catch {
                    throw HubError.unexpected(StorageTokensRail.createFailedMessage)
                }
                await MainActor.run { self?.revealedSecrets[created.id] = created.token }
            }))
    }

    private func detail(for token: StorageToken, ecosystemID: String?) -> HTDVDetail {
        var fields: [FormField] = [
            .readOnly(FormReadOnlyField(key: "name", label: "Name", isMonospaced: true)),
            .readOnly(FormReadOnlyField(key: "identifier", label: "Identifier", isMonospaced: true)),
            .readOnly(FormReadOnlyField(key: "prefix", label: "Prefix", isMonospaced: true)),
            .readOnly(FormReadOnlyField(key: "bucket", label: "Bucket", isMonospaced: true)),
            .readOnly(FormReadOnlyField(key: "description", label: "Description")),
            .readOnly(FormReadOnlyField(key: "created", label: "Created")),
            .readOnly(FormReadOnlyField(key: "lastUsed", label: "Last used")),
            .readOnly(FormReadOnlyField(key: "expires", label: "Expires"))
        ]
        var values: [String: FormValue] = [
            "name": .string(token.slug),
            "identifier": .string(token.rdid ?? "—"),
            "prefix": .string("\(token.prefix)…"),
            "bucket": .string(token.bucketRdid ?? "no bucket"),
            "description": .string(token.description.isEmpty ? "—" : token.description),
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
                confirmationText: "Revoke storage token \"\(token.slug)\"? "
                    + "Anything using it will lose access to its bucket."
            ) { [weak self, dataSource] in
                try await HubError.wrap { try await dataSource.revoke(ecosystemID: ecosystemID, id: token.id) }
                await MainActor.run { self?.revealedSecrets[token.id] = nil }
            }))
        return FormDetails.form(id: "storage-token:\(token.id)", title: token.slug, spec: spec, values: values)
    }
}
