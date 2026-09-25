import AgenticToolkitHub
import Foundation
import HTTPTypes

/// `ServerBagsDataSource` over `/ecosystem/server-bag/{id}`. The list response is wrapped as `{ "bags": [...] }`.
@MainActor
public final class ServerBagsAdapter: ServerBagsDataSource {
    private struct BagsEnvelope: Decodable { let bags: [ServerBag] }

    private let api: HubAPI
    private let workspace: HubWorkspace

    public init(environment: HubEnvironment, workspace: HubWorkspace) {
        self.api = HubAPI(environment: environment)
        self.workspace = workspace
    }

    private func path(_ ecosystemID: String, _ key: String? = nil) -> String {
        key.map { "/ecosystem/server-bag/\(ecosystemID)/\($0)" } ?? "/ecosystem/server-bag/\(ecosystemID)"
    }

    public func list(ecosystemID: String) async throws -> [ServerBag] {
        try await api.get(path(ecosystemID), query: workspace.query, as: BagsEnvelope.self).bags
    }

    public func create(ecosystemID: String, _ body: ServerBagCreate) async throws -> ServerBag {
        try await api.send(.post, path(ecosystemID), query: workspace.query, body: body, as: ServerBag.self)
    }

    public func update(ecosystemID: String, key: String, _ body: ServerBagUpdate) async throws -> ServerBag {
        try await api.send(.put, path(ecosystemID, key), query: workspace.query, body: body, as: ServerBag.self)
    }

    public func delete(ecosystemID: String, key: String) async throws {
        try await api.send(.delete, path(ecosystemID, key), query: workspace.query)
    }
}
