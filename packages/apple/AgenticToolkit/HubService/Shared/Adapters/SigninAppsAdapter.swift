import AgenticToolkitHub
import Foundation
import HTTPTypes

/// `SigninAppsDataSource` over `/ecosystem/signin-apps/{id}`.
@MainActor
public final class SigninAppsAdapter: SigninAppsDataSource {
    private let api: HubAPI
    private let workspace: HubWorkspace

    public init(environment: HubEnvironment, workspace: HubWorkspace) {
        self.api = HubAPI(environment: environment)
        self.workspace = workspace
    }

    private func path(_ ecosystemID: String, _ id: String? = nil) -> String {
        id.map { "/ecosystem/signin-apps/\(ecosystemID)/\($0)" } ?? "/ecosystem/signin-apps/\(ecosystemID)"
    }

    public func list(ecosystemID: String) async throws -> [SigninApp] {
        try await api.get(path(ecosystemID), query: workspace.query, as: [SigninApp].self)
    }

    public func create(ecosystemID: String, _ body: SigninAppCreate) async throws -> SigninApp {
        try await api.send(.post, path(ecosystemID), query: workspace.query, body: body, as: SigninApp.self)
    }

    public func update(ecosystemID: String, id: String, _ body: SigninAppUpdate) async throws -> SigninApp {
        try await api.send(.patch, path(ecosystemID, id), query: workspace.query, body: body, as: SigninApp.self)
    }

    public func delete(ecosystemID: String, id: String) async throws {
        try await api.send(.delete, path(ecosystemID, id), query: workspace.query)
    }
}
