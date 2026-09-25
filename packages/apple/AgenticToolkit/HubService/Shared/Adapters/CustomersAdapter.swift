import AgenticToolkitHub
import Foundation
import HTTPTypes

@MainActor
public final class CustomersAdapter: CustomersDataSource {
    private let api: HubAPI
    private let workspace: HubWorkspace

    public init(environment: HubEnvironment, workspace: HubWorkspace) {
        self.api = HubAPI(environment: environment)
        self.workspace = workspace
    }

    public func list(ecosystemID: String) async throws -> [Customer] {
        try await api.get("/customer/customers", query: workspace.query, as: [Customer].self)
            .filter { $0.ecosystemId == ecosystemID }
    }

    public func get(id: String) async throws -> Customer {
        try await api.get("/customer/customers/\(id)", query: workspace.query, as: Customer.self)
    }

    public func create(_ input: CustomerInput) async throws -> Customer {
        try await api.send(.post, "/customer/customers", query: workspace.query, body: input, as: Customer.self)
    }

    public func update(id: String, _ input: CustomerInput) async throws -> Customer {
        try await api.send(.put, "/customer/customers/\(id)", query: workspace.query, body: input, as: Customer.self)
    }

    public func delete(id: String) async throws {
        try await api.send(.delete, "/customer/customers/\(id)", query: workspace.query)
    }
}
