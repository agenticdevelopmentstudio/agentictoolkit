import AgenticToolkitHTDV
import Foundation

/// Product rail topic "User Auth": one detail form editing sign-up mode and sign-in.
@MainActor
public final class AuthSettingsTopic: EcosystemTopicProvider {
    public static let entry = EcosystemTopicEntry(
        id: "auth", label: "User Auth", systemImage: "person.badge.key",
        description: "Who can create an account and whether anyone can sign in.", leadsTo: .detail)

    public var entry: EcosystemTopicEntry { Self.entry }
    private let dataSource: any AuthSettingsDataSource

    public init(dataSource: any AuthSettingsDataSource) { self.dataSource = dataSource }

    public func child(for ecosystem: Ecosystem, path: [HTDVItem], rail: any EcosystemRail) async throws -> HTDVChild {
        guard path.isEmpty else { return .empty }
        let settings = try await HubError.wrap { try await self.dataSource.get(ecosystemID: ecosystem.id) }
        return .detail(detail(for: ecosystem, settings: settings))
    }

    private func detail(for ecosystem: Ecosystem, settings: AuthSettings) -> HTDVDetail {
        let signupOptions = SignupMode.allCases.map { FormSelectOption(value: $0.rawValue, title: $0.title) }
        let signupField = FormSelectField(key: "signupMode", label: "Sign-up", options: signupOptions)
        let signinHelp = "When off, no one can sign in to this ecosystem."
        let spec = FormSpec(
            sections: [
                FormSection(title: "Sign-up", fields: [
                    .select(signupField),
                    .readOnly(FormReadOnlyField(key: "signupHelp", label: ""))
                ]),
                FormSection(title: "Sign-in", fields: [
                    .toggle(FormToggleField(key: "loginEnabled", label: "Allow sign-in", help: signinHelp))
                ])
            ],
            actions: FormActions(save: FormAction(id: "save", title: "Save") { [dataSource] values in
                let mode = SignupMode(rawValue: values["signupMode"]?.stringValue ?? "") ?? .inviteOnly
                let loginEnabled = values["loginEnabled"]?.boolValue ?? false
                _ = try await HubError.wrap {
                    try await dataSource.update(ecosystemID: ecosystem.id,
                                                 AuthSettingsUpdate(signupMode: mode, loginEnabled: loginEnabled))
                }
            }))
        return FormDetails.form(id: "auth-settings:\(ecosystem.id)", title: "User Auth", spec: spec, values: [
            "signupMode": .string(settings.signupMode.rawValue),
            "signupHelp": .string(settings.signupMode.help),
            "loginEnabled": .bool(settings.loginEnabled)
        ])
    }
}
