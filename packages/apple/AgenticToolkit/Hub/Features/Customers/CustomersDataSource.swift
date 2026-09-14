import Foundation

public protocol CustomersDataSource: AnyObject, Sendable {
    func list(ecosystemID: String) async throws -> [Customer]
    func get(id: String) async throws -> Customer
    func create(_ input: CustomerInput) async throws -> Customer
    func update(id: String, _ input: CustomerInput) async throws -> Customer
    func delete(id: String) async throws
}
