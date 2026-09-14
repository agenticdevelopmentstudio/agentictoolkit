import Foundation

/// I/O for ecosystems. The app's adapter (Task 6) implements it over `HubAPI`; tests use an in-memory fake.
public protocol EcosystemsDataSource: AnyObject, Sendable {
    /// The workspace's own ecosystems, default rows included (the module hides `isDefault`).
    func list() async throws -> [Ecosystem]
    func children(of parentID: String) async throws -> [Ecosystem]
    func get(id: String) async throws -> Ecosystem
    /// Identifier of the workspace's infrastructure ecosystem, the prefix for new top-level products.
    func infrastructureID() async throws -> String
    func identifierExists(_ identifier: String) async throws -> Bool
    func create(_ input: EcosystemCreate, parentID: String?) async throws -> Ecosystem
    func update(id: String, _ input: EcosystemUpdate) async throws -> Ecosystem
    func delete(id: String) async throws
}
