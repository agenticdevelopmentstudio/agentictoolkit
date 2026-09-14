import Foundation

public protocol ApplicationsDataSource: AnyObject, Sendable {
    func list(ecosystemID: String) async throws -> [Application]
    func get(id: String) async throws -> Application
    func create(_ input: ApplicationCreate) async throws -> Application
    func update(id: String, _ input: ApplicationUpdate) async throws -> Application
    func delete(id: String) async throws
    /// `PATCH /registry/identifiers/{current}` with `{rdid: next}`; throws `HubError.conflict` when taken.
    func renameIdentifier(_ current: String, to next: String) async throws
    func schemaGrants(applicationID: String) async throws -> [SchemaGrant]
    func setSchemaGrants(applicationID: String, _ grants: [SchemaGrant]) async throws
    func tokens(applicationID: String) async throws -> [ApplicationToken]
    func createToken(applicationID: String, name: String) async throws -> ApplicationTokenCreated
    func revokeToken(applicationID: String, tokenID: String) async throws
}
