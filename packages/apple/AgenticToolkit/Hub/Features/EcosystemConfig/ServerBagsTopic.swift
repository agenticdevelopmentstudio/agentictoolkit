import AgenticToolkitHTDV
import Foundation

/// Product rail topic "Server bags": key → JSON config values this product's backend reads at runtime.
@MainActor
public final class ServerBagsTopic: EcosystemTopicProvider {
    public static let entry = EcosystemTopicEntry(
        id: "server-bags", label: "Server bags", systemImage: "shippingbox",
        description: "Key → JSON config values this product's backend reads at runtime.")
    /// `nonisolated`: read by `parsedValue`, which must itself be `nonisolated` to run inside a
    /// `FormAction.perform` closure — those closures are not `@MainActor` (`FormSpec.swift`).
    public nonisolated static let invalidJSONMessage =
        "Value must be valid JSON — e.g. true, 42, \"text\", or {\"a\": 1}."

    public var entry: EcosystemTopicEntry { Self.entry }
    private let dataSource: any ServerBagsDataSource

    public init(dataSource: any ServerBagsDataSource) { self.dataSource = dataSource }

    public func child(for ecosystem: Ecosystem, path: [HTDVItem], rail: any EcosystemRail) async throws -> HTDVChild {
        let bags = try await HubError.wrap { try await self.dataSource.list(ecosystemID: ecosystem.id) }
        switch path.count {
        case 0:
            return .level(level(for: ecosystem, bags: bags))
        case 1:
            guard let bag = bags.first(where: { $0.key == path[0].id }) else { return .empty }
            return .detail(detail(for: ecosystem, bag: bag))
        default:
            return .empty
        }
    }

    private func level(for ecosystem: Ecosystem, bags: [ServerBag]) -> HTDVLevel {
        let items = bags.sorted { $0.key < $1.key }.map {
            HTDVItem(id: $0.key, label: $0.key, sublabel: $0.preview, systemImage: "shippingbox", leadsTo: .detail)
        }
        let spec = createSpec(for: ecosystem, existing: bags)
        return HTDVLevel(
            id: "server-bags:\(ecosystem.id)", title: "Server bags", items: items,
            emptyMessage: "No server bags yet.",
            createAction: HTDVCreateAction(title: "New bag") { presenter in
                _ = await FormSheet.present(title: "New bag", spec: spec, from: presenter)
            })
    }

    /// Parses the `value` field; the JSON field's own validator has already rejected unparsable text.
    private nonisolated static func parsedValue(_ value: FormValue?) throws -> JSONValue {
        let text = value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        do { return try JSONValue.parse(text) } catch { throw HubError.validation(invalidJSONMessage) }
    }

    public func createSpec(for ecosystem: Ecosystem, existing: [ServerBag]) -> FormSpec {
        let takenKeys = Set(existing.map(\.key))
        return FormSpec(
            sections: [FormSection(fields: [
                .text(FormTextField(key: "key", label: "Key", placeholder: "e.g. onboarding_config", isRequired: true)),
                .json(FormJSONField(key: "value", label: "Value", isRequired: true)),
                .textArea(FormTextAreaField(key: "description", label: "Description",
                                            placeholder: "What does this configure? (optional)", minLines: 2))
            ])],
            actions: FormActions(save: FormAction(id: "create", title: "Create") { [dataSource] values in
                let key = values["key"]?.stringValue?.trimmingCharacters(in: .whitespaces) ?? ""
                let value = try ServerBagsTopic.parsedValue(values["value"])
                if takenKeys.contains(key) {
                    throw HubError.validation("A bag named \"\(key)\" already exists.")
                }
                let description = values["description"]?.stringValue ?? ""
                do {
                    let body = ServerBagCreate(key: key, value: value, description: description)
                    _ = try await dataSource.create(ecosystemID: ecosystem.id, body)
                } catch HubError.conflict {
                    throw HubError.validation("A bag named \"\(key)\" already exists.")
                } catch {
                    throw HubError.wrap(error)
                }
            }))
    }

    private func detail(for ecosystem: Ecosystem, bag: ServerBag) -> HTDVDetail {
        let spec = FormSpec(
            sections: [FormSection(fields: [
                .readOnly(FormReadOnlyField(key: "key", label: "Key", isMonospaced: true)),
                .json(FormJSONField(key: "value", label: "Value", isRequired: true)),
                .textArea(FormTextAreaField(key: "description", label: "Description",
                                            placeholder: "What does this configure? (optional)", minLines: 2))
            ])],
            actions: FormActions(
                save: FormAction(id: "save", title: "Save") { [dataSource] values in
                    let value = try ServerBagsTopic.parsedValue(values["value"])
                    let description = values["description"]?.stringValue ?? bag.description
                    _ = try await HubError.wrap {
                        try await dataSource.update(ecosystemID: ecosystem.id, key: bag.key,
                                                    ServerBagUpdate(value: value, description: description))
                    }
                },
                delete: FormDeleteAction(
                    title: "Delete bag",
                    confirmationText: "\"\(bag.key)\" \(FeatureFlagsTopic.removalMessage)"
                ) { [dataSource] in
                    try await HubError.wrap { try await dataSource.delete(ecosystemID: ecosystem.id, key: bag.key) }
                }))
        return FormDetails.form(id: "server-bag:\(ecosystem.id):\(bag.key)", title: bag.key, spec: spec, values: [
            "key": .string(bag.key),
            "value": .string(bag.value.prettyText),
            "description": .string(bag.description)
        ])
    }
}
