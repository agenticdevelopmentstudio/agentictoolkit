import AgenticToolkitHub
import Foundation
import HTTPTypes

/// `FeatureFlagsDataSource` over `/ecosystem/feature-flags/{id}`. The list response is wrapped as `{ "flags": [...] }`.
@MainActor
public final class FeatureFlagsAdapter: FeatureFlagsDataSource {
    private struct FlagsEnvelope: Decodable { let flags: [FeatureFlag] }

    private let api: HubAPI
    private let workspace: HubWorkspace

    public init(environment: HubEnvironment, workspace: HubWorkspace) {
        self.api = HubAPI(environment: environment)
        self.workspace = workspace
    }

    private func path(_ ecosystemID: String, _ key: String? = nil) -> String {
        key.map { "/ecosystem/feature-flags/\(ecosystemID)/\($0)" } ?? "/ecosystem/feature-flags/\(ecosystemID)"
    }

    public func list(ecosystemID: String) async throws -> [FeatureFlag] {
        try await api.get(path(ecosystemID), query: workspace.query, as: FlagsEnvelope.self).flags
    }

    public func create(ecosystemID: String, _ body: FeatureFlagCreate) async throws -> FeatureFlag {
        try await api.send(.post, path(ecosystemID), query: workspace.query, body: body, as: FeatureFlag.self)
    }

    public func update(ecosystemID: String, key: String, _ body: FeatureFlagUpdate) async throws -> FeatureFlag {
        try await api.send(.put, path(ecosystemID, key), query: workspace.query, body: body, as: FeatureFlag.self)
    }

    public func delete(ecosystemID: String, key: String) async throws {
        try await api.send(.delete, path(ecosystemID, key), query: workspace.query)
    }
}
