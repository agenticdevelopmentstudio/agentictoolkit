import AgenticToolkitHTDV
import Foundation

/// Product rail topic "Sign-in apps": OAuth clients that may sign users in to this ecosystem.
@MainActor
public final class SigninAppsTopic: EcosystemTopicProvider {
    public static let entry = EcosystemTopicEntry(
        id: "signin-apps", label: "Sign-in apps", systemImage: "door.left.hand.open",
        description: "Apps allowed to sign users in, and where they may return to.")
    public static let leafPattern = Slug.pattern
    public static let leafMessage = "App id must be a lowercase token, e.g. my-app."
    public static let originPlaceholder = "https://myapp.com"
    public static let authHostPlaceholder = "<your-adh-auth-host>"

    public var entry: EcosystemTopicEntry { Self.entry }
    private let dataSource: any SigninAppsDataSource

    public init(dataSource: any SigninAppsDataSource) { self.dataSource = dataSource }

    // MARK: Origins

    /// Returns nil when `raw` is an acceptable return origin, else the web's message for the first violated rule.
    /// `nonisolated`: called from `canonicalOrigins`, which itself must be `nonisolated` to run inside a
    /// `FormAction.perform` closure — those closures are not `@MainActor` (`FormSpec.swift`).
    public nonisolated static func validateOrigin(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              let host = url.host, !host.isEmpty else {
            return "Return origin \"\(raw)\" is not a valid URL."
        }
        guard scheme == "http" || scheme == "https" else { return "Return origin \"\(raw)\" must be http(s)." }
        if url.user != nil || url.password != nil { return "Return origin \"\(raw)\" must not include credentials." }
        let path = url.path
        if !(path.isEmpty || path == "/") || url.query != nil || url.fragment != nil {
            return "Return origin \"\(raw)\" must be just a scheme + host (no path)."
        }
        return nil
    }

    /// Lower-cases scheme and host and drops a trailing slash:
    /// `HTTPS://Example.com:8443/` → `https://example.com:8443`.
    public nonisolated static func canonicalOrigin(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased() else { return trimmed }
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }

    /// The "Connect your app" start URL the web shows, with the auth host left as a placeholder.
    public static func startURL(clientID: String) -> String {
        "\(authHostPlaceholder)/oauth/signin/start?clientId=\(clientID)&providerId=github"
            + "&return=<your-app-origin>/auth/callback"
    }

    private nonisolated static func canonicalOrigins(_ value: FormValue?) throws -> [String] {
        let raw = value?.stringSetValue ?? []
        var seen = Set<String>()
        var result: [String] = []
        for origin in raw {
            if let message = validateOrigin(origin) { throw HubError.validation(message) }
            let canonical = canonicalOrigin(origin)
            if seen.insert(canonical).inserted { result.append(canonical) }
        }
        return result
    }

    // MARK: Rail

    public func child(for ecosystem: Ecosystem, path: [HTDVItem], rail: any EcosystemRail) async throws -> HTDVChild {
        let apps = try await HubError.wrap { try await self.dataSource.list(ecosystemID: ecosystem.id) }
        switch path.count {
        case 0:
            return .level(level(for: ecosystem, apps: apps))
        case 1:
            guard let app = apps.first(where: { $0.id == path[0].id }) else { return .empty }
            return .detail(detail(for: ecosystem, app: app))
        default:
            return .empty
        }
    }

    private func level(for ecosystem: Ecosystem, apps: [SigninApp]) -> HTDVLevel {
        let sorted = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let items = sorted.map {
            HTDVItem(id: $0.id, label: $0.name, sublabel: $0.slug, systemImage: "door.left.hand.open", leadsTo: .detail)
        }
        let spec = createSpec(for: ecosystem, existing: apps)
        return HTDVLevel(
            id: "signin-apps:\(ecosystem.id)", title: "Sign-in apps", items: items,
            emptyMessage: "No sign-in apps yet.",
            createAction: HTDVCreateAction(title: "New sign-in app") { presenter in
                _ = await FormSheet.present(title: "New sign-in app", spec: spec, from: presenter)
            })
    }

    /// Create form: name + client-id leaf. Existing apps are checked for a duplicate leaf before the request.
    public func createSpec(for ecosystem: Ecosystem, existing: [SigninApp]) -> FormSpec {
        let takenLeaves = Set(existing.map { $0.leaf(in: ecosystem).lowercased() })
        return FormSpec(
            sections: [FormSection(fields: [
                .text(FormTextField(key: "name", label: "Name", placeholder: "My app", isRequired: true)),
                .text(FormTextField(key: "clientId", label: "Client id", placeholder: "my-app", isRequired: true,
                                    pattern: SigninAppsTopic.leafPattern, patternMessage: SigninAppsTopic.leafMessage))
            ])],
            actions: FormActions(save: FormAction(id: "create", title: "Create") { [dataSource] values in
                let name = values["name"]?.stringValue?.trimmingCharacters(in: .whitespaces) ?? ""
                let leaf = values["clientId"]?.stringValue?.trimmingCharacters(in: .whitespaces) ?? ""
                if takenLeaves.contains(leaf.lowercased()) {
                    throw HubError.validation("App id \"\(leaf)\" is already in use.")
                }
                do {
                    _ = try await dataSource.create(ecosystemID: ecosystem.id, SigninAppCreate(slug: leaf, name: name))
                } catch HubError.conflict {
                    throw HubError.validation("A sign-in app \"\(leaf)\" already exists in this ecosystem.")
                } catch {
                    throw HubError.wrap(error)
                }
            }))
    }

    private func detail(for ecosystem: Ecosystem, app: SigninApp) -> HTDVDetail {
        let spec = FormSpec(
            sections: [
                FormSection(fields: [
                    .text(FormTextField(key: "name", label: "Name", placeholder: "My app", isRequired: true)),
                    .readOnly(FormReadOnlyField(key: "slug", label: "Client id", isMonospaced: true))
                ]),
                FormSection(title: "Sign-in", fields: [
                    .toggle(FormToggleField(key: "githubEnabled", label: "GitHub sign-in",
                                            help: "Let customers sign in with GitHub, brokered through ADH.")),
                    .stringSet(FormStringSetField(key: "allowedReturnOrigins", label: "Allowed return origins",
                                                  placeholder: SigninAppsTopic.originPlaceholder))
                ]),
                FormSection(title: "Connect your app", fields: [
                    .readOnly(FormReadOnlyField(key: "startURL", label: "Start URL", isMonospaced: true))
                ])
            ],
            actions: FormActions(
                save: FormAction(id: "save", title: "Save") { [dataSource] values in
                    let origins = try SigninAppsTopic.canonicalOrigins(values["allowedReturnOrigins"])
                    let name = values["name"]?.stringValue?.trimmingCharacters(in: .whitespaces) ?? app.name
                    let githubEnabled = values["githubEnabled"]?.boolValue ?? app.githubEnabled
                    _ = try await HubError.wrap {
                        try await dataSource.update(ecosystemID: ecosystem.id, id: app.id,
                                                    SigninAppUpdate(name: name, allowedReturnOrigins: origins,
                                                                    githubEnabled: githubEnabled))
                    }
                },
                delete: FormDeleteAction(
                    title: "Delete sign-in app",
                    confirmationText: "Delete sign-in app \"\(app.name)\"? Apps using it will stop signing in."
                ) { [dataSource] in
                    try await HubError.wrap { try await dataSource.delete(ecosystemID: ecosystem.id, id: app.id) }
                }))
        return FormDetails.form(id: "signin-app:\(app.id)", title: "Sign-in app", spec: spec, values: [
            "name": .string(app.name),
            "slug": .string(app.slug),
            "githubEnabled": .bool(app.githubEnabled),
            "allowedReturnOrigins": .stringSet(app.allowedReturnOrigins),
            "startURL": .string(SigninAppsTopic.startURL(clientID: app.slug))
        ])
    }
}
