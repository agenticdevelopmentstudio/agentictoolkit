import AgenticToolkitHub
import Foundation
import HTTPTypes

/// `/auth/tokens` — the caller's personal API tokens.
@MainActor
public final class ApiTokensAdapter: ApiTokensDataSource {
    private struct ScopeCatalogue: Decodable { let prefixes: [String] }

    private let api: HubAPI
    private let workspace: HubWorkspace

    public init(environment: HubEnvironment, workspace: HubWorkspace) {
        api = HubAPI(environment: environment)
        self.workspace = workspace
    }

    public func list() async throws -> [ApiToken] {
        try await api.get("/auth/tokens", query: workspace.query, as: [ApiToken].self)
    }

    public func scopes() async throws -> [String] {
        try await api.get("/auth/tokens/scopes", query: workspace.query, as: ScopeCatalogue.self).prefixes
    }

    public func create(_ body: ApiTokenCreate) async throws -> ApiTokenCreated {
        try await api.send(.post, "/auth/tokens", query: workspace.query, body: body, as: ApiTokenCreated.self)
    }

    public func revoke(id: String) async throws {
        try await api.send(.delete, "/auth/tokens/\(id)", query: workspace.query)
    }
}
