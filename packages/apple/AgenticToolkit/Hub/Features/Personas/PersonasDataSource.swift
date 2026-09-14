import Foundation

/// Everything the Personas module needs from the backend. The app repo implements it over `HubAPI`.
public protocol PersonasDataSource: Sendable {
    func list() async throws -> [Persona]
    func get(id: String) async throws -> Persona
    func create(_ body: PersonaBody) async throws -> Persona
    func update(id: String, _ body: PersonaBody) async throws -> Persona
    func delete(id: String) async throws
    func listServices() async throws -> [PersonaService]
}
