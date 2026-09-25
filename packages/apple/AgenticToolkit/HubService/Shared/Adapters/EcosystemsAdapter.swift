import AgenticToolkitHub
import Foundation
import HTTPTypes

@MainActor
public final class EcosystemsAdapter: EcosystemsDataSource {
    private struct ExistsResponse: Decodable { let exists: Bool }

    private let api: HubAPI
    private let workspace: HubWorkspace

    public init(environment: HubEnvironment, workspace: HubWorkspace) {
        self.api = HubAPI(environment: environment)
        self.workspace = workspace
    }

    public func list() async throws -> [Ecosystem] {
        try await api.get("/ecosystem/ecosystems", query: workspace.query, as: [Ecosystem].self)
    }

    /// `parent=` ALONE, matching the web reference implementation
    /// (`packages/web/packages/data/src/ecosystems/ecosystems.ts`: "Scoped server-side (`?parent=`, which
    /// also excludes the structural defaults)"). The two scopes select by different owners — a child is
    /// owned by its parent ecosystem, not by the workspace principal — so sending both AND'd them together
    /// and the child list read empty for a product that has children. Every other call here keeps
    /// `workspace`; this is the one endpoint the web deliberately does not send it on.
    public func children(of parentID: String) async throws -> [Ecosystem] {
        try await api.get("/ecosystem/ecosystems", query: ["parent": parentID], as: [Ecosystem].self)
    }

    public func get(id: String) async throws -> Ecosystem {
        try await api.get("/ecosystem/ecosystems/\(id)", query: workspace.query, as: Ecosystem.self)
    }

    public func infrastructureID() async throws -> String {
        let rows = try await api.get(
            "/ecosystem/ecosystems", query: query(["infrastructure": "true"]), as: [Ecosystem].self
        )
        guard let first = rows.first else {
            throw HubError.unexpected("No infrastructure ecosystem for workspace \(workspace.slug)")
        }
        return first.id
    }

    public func identifierExists(_ identifier: String) async throws -> Bool {
        try await api.get("/registry/identifiers/\(identifier)/exists", as: ExistsResponse.self).exists
    }

    public func create(_ input: EcosystemCreate, parentID: String?) async throws -> Ecosystem {
        try await api.send(
            .post, "/ecosystem/ecosystems", query: query(["parent": parentID]), body: input, as: Ecosystem.self
        )
    }

    public func update(id: String, _ input: EcosystemUpdate) async throws -> Ecosystem {
        try await api.send(.put, "/ecosystem/ecosystems/\(id)", query: workspace.query, body: input, as: Ecosystem.self)
    }

    public func delete(id: String) async throws {
        try await api.send(.delete, "/ecosystem/ecosystems/\(id)", query: workspace.query)
    }

    /// The workspace query plus extra pairs; nil values are dropped.
    private func query(_ extra: [String: String?]) -> [String: String] {
        workspace.query.merging(HubAPI.query(extra)) { _, new in new }
    }
}
