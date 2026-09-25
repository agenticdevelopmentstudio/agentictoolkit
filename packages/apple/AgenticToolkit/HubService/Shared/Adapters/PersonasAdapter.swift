import AgenticToolkitHub
import Foundation
import HTTPTypes

@MainActor
public final class PersonasAdapter: PersonasDataSource {
    private let api: HubAPI
    private let workspace: HubWorkspace

    public init(environment: HubEnvironment, workspace: HubWorkspace) {
        self.api = HubAPI(environment: environment)
        self.workspace = workspace
    }

    public func list() async throws -> [Persona] {
        try await api.get("/persona/personas", query: workspace.query, as: [Persona].self)
    }

    public func get(id: String) async throws -> Persona {
        try await api.get("/persona/personas/\(id)", query: workspace.query, as: Persona.self)
    }

    public func create(_ body: PersonaBody) async throws -> Persona {
        try await api.send(.post, "/persona/personas", query: workspace.query, body: body, as: Persona.self)
    }

    public func update(id: String, _ body: PersonaBody) async throws -> Persona {
        try await api.send(.put, "/persona/personas/\(id)", query: workspace.query, body: body, as: Persona.self)
    }

    public func delete(id: String) async throws {
        try await api.send(.delete, "/persona/personas/\(id)", query: workspace.query)
    }

    public func listServices() async throws -> [PersonaService] {
        try await api.get("/persona/services", as: [PersonaService].self)
    }
}
