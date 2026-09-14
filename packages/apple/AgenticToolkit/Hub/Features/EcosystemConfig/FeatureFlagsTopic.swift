import AgenticToolkitHTDV
import Foundation

/// Product rail topic "Feature flags": named on/off toggles this product's apps can read.
@MainActor
public final class FeatureFlagsTopic: EcosystemTopicProvider {
    public static let entry = EcosystemTopicEntry(
        id: "feature-flags", label: "Feature flags", systemImage: "flag",
        description: "Named on/off toggles this product's apps can read.")
    public static let removalMessage = "will be removed. Anything reading it falls back to its default."

    public var entry: EcosystemTopicEntry { Self.entry }
    private let dataSource: any FeatureFlagsDataSource

    public init(dataSource: any FeatureFlagsDataSource) { self.dataSource = dataSource }

    public func child(for ecosystem: Ecosystem, path: [HTDVItem], rail: any EcosystemRail) async throws -> HTDVChild {
        let flags = try await HubError.wrap { try await self.dataSource.list(ecosystemID: ecosystem.id) }
        switch path.count {
        case 0:
            return .level(level(for: ecosystem, flags: flags))
        case 1:
            guard let flag = flags.first(where: { $0.key == path[0].id }) else { return .empty }
            return .detail(detail(for: ecosystem, flag: flag))
        default:
            return .empty
        }
    }

    private func level(for ecosystem: Ecosystem, flags: [FeatureFlag]) -> HTDVLevel {
        let items = flags.sorted { $0.key < $1.key }.map { flag -> HTDVItem in
            var sublabel = flag.enabled ? "On" : "Off"
            if !flag.description.isEmpty { sublabel += " · \(flag.description)" }
            let systemImage = flag.enabled ? "flag.fill" : "flag"
            return HTDVItem(id: flag.key, label: flag.key, sublabel: sublabel,
                            systemImage: systemImage, leadsTo: .detail)
        }
        let spec = createSpec(for: ecosystem, existing: flags)
        return HTDVLevel(
            id: "feature-flags:\(ecosystem.id)", title: "Feature flags", items: items,
            emptyMessage: "No feature flags yet.",
            createAction: HTDVCreateAction(title: "New flag") { presenter in
                _ = await FormSheet.present(title: "New flag", spec: spec, from: presenter)
            })
    }

    /// Create form. The key is fixed once created, so it is only editable here.
    public func createSpec(for ecosystem: Ecosystem, existing: [FeatureFlag]) -> FormSpec {
        let takenKeys = Set(existing.map(\.key))
        return FormSpec(
            sections: [FormSection(fields: [
                .text(FormTextField(key: "key", label: "Key", placeholder: "e.g. dark_mode", isRequired: true)),
                .textArea(FormTextAreaField(key: "description", label: "Description",
                                            placeholder: "What does this flag gate? (optional)", minLines: 2)),
                .toggle(FormToggleField(key: "enabled", label: "Enabled"))
            ])],
            actions: FormActions(save: FormAction(id: "create", title: "Create") { [dataSource] values in
                let key = values["key"]?.stringValue?.trimmingCharacters(in: .whitespaces) ?? ""
                if takenKeys.contains(key) {
                    throw HubError.validation("A flag named \"\(key)\" already exists.")
                }
                let enabled = values["enabled"]?.boolValue ?? false
                let description = values["description"]?.stringValue ?? ""
                do {
                    let body = FeatureFlagCreate(key: key, enabled: enabled, description: description)
                    _ = try await dataSource.create(ecosystemID: ecosystem.id, body)
                } catch HubError.conflict {
                    throw HubError.validation("A flag named \"\(key)\" already exists.")
                } catch {
                    throw HubError.wrap(error)
                }
            }))
    }

    private func detail(for ecosystem: Ecosystem, flag: FeatureFlag) -> HTDVDetail {
        let spec = FormSpec(
            sections: [FormSection(fields: [
                .readOnly(FormReadOnlyField(key: "key", label: "Key", isMonospaced: true)),
                .toggle(FormToggleField(key: "enabled", label: "Enabled")),
                .textArea(FormTextAreaField(key: "description", label: "Description",
                                            placeholder: "What does this flag gate? (optional)", minLines: 2))
            ])],
            actions: FormActions(
                save: FormAction(id: "save", title: "Save") { [dataSource] values in
                    let enabled = values["enabled"]?.boolValue ?? flag.enabled
                    let description = values["description"]?.stringValue ?? flag.description
                    _ = try await HubError.wrap {
                        try await dataSource.update(ecosystemID: ecosystem.id, key: flag.key,
                                                    FeatureFlagUpdate(enabled: enabled, description: description))
                    }
                },
                delete: FormDeleteAction(
                    title: "Delete flag",
                    confirmationText: "\"\(flag.key)\" \(FeatureFlagsTopic.removalMessage)"
                ) { [dataSource] in
                    try await HubError.wrap { try await dataSource.delete(ecosystemID: ecosystem.id, key: flag.key) }
                }))
        return FormDetails.form(id: "feature-flag:\(ecosystem.id):\(flag.key)", title: flag.key, spec: spec, values: [
            "key": .string(flag.key),
            "enabled": .bool(flag.enabled),
            "description": .string(flag.description)
        ])
    }
}
