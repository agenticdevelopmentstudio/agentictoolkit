import AgenticToolkitHub
import Foundation
import HTTPTypes

/// `AuthSettingsDataSource` over `/ecosystem/auth-settings/{id}`.
@MainActor
public final class AuthSettingsAdapter: AuthSettingsDataSource {
    private let api: HubAPI
    private let workspace: HubWorkspace

    public init(environment: HubEnvironment, workspace: HubWorkspace) {
        self.api = HubAPI(environment: environment)
        self.workspace = workspace
    }

    public func get(ecosystemID: String) async throws -> AuthSettings {
        try await api.get("/ecosystem/auth-settings/\(ecosystemID)", query: workspace.query, as: AuthSettings.self)
    }

    public func update(ecosystemID: String, _ patch: AuthSettingsUpdate) async throws -> AuthSettings {
        try await api.send(
            .put, "/ecosystem/auth-settings/\(ecosystemID)", query: workspace.query, body: patch, as: AuthSettings.self
        )
    }
}
