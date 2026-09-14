import Foundation
import AgenticToolkitHTDV

/// Product ▸ Users: list of the ecosystem's end users → one form per user.
@MainActor
public final class CustomersTopic: EcosystemTopicProvider {
    public static let entry = EcosystemTopicEntry(
        id: "users", label: "Users", systemImage: "person.2",
        description: "The people who sign in to this product."
    )
    public static let emailPattern = "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$"
    public static let emailMessage = "Enter a valid email address."

    public var entry: EcosystemTopicEntry { Self.entry }
    private let dataSource: any CustomersDataSource

    public init(dataSource: any CustomersDataSource) {
        self.dataSource = dataSource
    }

    public func child(for ecosystem: Ecosystem, path: [HTDVItem], rail: any EcosystemRail) async throws -> HTDVChild {
        guard let customerID = RailPath.id(at: 0, in: path) else {
            return .level(try await listLevel(for: ecosystem))
        }
        let customer: Customer
        do {
            customer = try await dataSource.get(id: customerID)
        } catch HubError.notFound {
            return .empty
        } catch {
            throw HubError.wrap(error)
        }
        return .detail(detail(for: customer))
    }

    private func listLevel(for ecosystem: Ecosystem) async throws -> HTDVLevel {
        let customers: [Customer]
        do {
            customers = try await dataSource.list(ecosystemID: ecosystem.id)
        } catch {
            throw HubError.wrap(error)
        }
        let items = customers.map {
            HTDVItem(id: $0.id, label: $0.label, sublabel: $0.sublabel, systemImage: "person", leadsTo: .detail)
        }
        let spec = createSpec(for: ecosystem)
        let action = HTDVCreateAction(title: "New user") { presenter in
            _ = await FormSheet.present(title: "New user", spec: spec, from: presenter)
        }
        return HTDVLevel(
            id: "users-list", title: "Users", items: items, emptyMessage: "No users yet.", createAction: action
        )
    }

    /// The five user fields. `isRequiredEmail` is always true today; the parameter keeps the create and detail
    /// specs literally shared.
    public static func fieldSpec(isRequiredEmail: Bool) -> [FormField] {
        [
            .text(FormTextField(
                key: "email", label: "Email", placeholder: "person@example.com", isRequired: isRequiredEmail,
                pattern: emailPattern, patternMessage: emailMessage
            )),
            .text(FormTextField(key: "displayName", label: "Display name", placeholder: "Jane Doe")),
            .text(FormTextField(key: "externalId", label: "External ID", placeholder: "auth0|abc123")),
            .text(FormTextField(key: "slug", label: "Handle", placeholder: "jane")),
            .text(FormTextField(key: "avatarUrl", label: "Avatar URL", placeholder: "https://…"))
        ]
    }

    private nonisolated static func input(from values: [String: FormValue], ecosystemID: String) -> CustomerInput {
        func optional(_ key: String) -> String? {
            Customer.nonBlank(values[key]?.stringValue)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return CustomerInput(
            ecosystemId: ecosystemID,
            email: values["email"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            displayName: optional("displayName"), externalId: optional("externalId"),
            slug: optional("slug"), avatarUrl: optional("avatarUrl")
        )
    }

    /// "New user" dialog: Email + Display name. Rejects an email already used in the ecosystem (case-insensitive).
    public func createSpec(for ecosystem: Ecosystem) -> FormSpec {
        let dataSource = self.dataSource
        let save = FormAction(id: "create", title: "Create") { values in
            let input = Self.input(from: values, ecosystemID: ecosystem.id)
            let existing: [Customer]
            do {
                existing = try await dataSource.list(ecosystemID: ecosystem.id)
            } catch {
                throw HubError.wrap(error)
            }
            if existing.contains(where: { ($0.email ?? "").caseInsensitiveCompare(input.email) == .orderedSame }) {
                throw HubError.validation("A user with email \"\(input.email)\" already exists.")
            }
            do {
                _ = try await dataSource.create(input)
            } catch HubError.conflict {
                throw HubError.validation("A user with email \"\(input.email)\" already exists.")
            } catch {
                throw HubError.wrap(error)
            }
        }
        let fields = Array(Self.fieldSpec(isRequiredEmail: true).prefix(2))
        return FormSpec(sections: [FormSection(fields: fields)], actions: FormActions(save: save))
    }

    private func detail(for customer: Customer) -> HTDVDetail {
        let dataSource = self.dataSource
        let save = FormAction(id: "save", title: "Save") { values in
            let input = Self.input(from: values, ecosystemID: customer.ecosystemId)
            do {
                _ = try await dataSource.update(id: customer.id, input)
            } catch HubError.conflict {
                throw HubError.validation("A user with email \"\(input.email)\" already exists.")
            } catch {
                throw HubError.wrap(error)
            }
        }
        let delete = FormDeleteAction(
            title: "Delete user",
            confirmationText: "Delete user \"\(customer.label)\"? This cannot be undone."
        ) {
            do { try await dataSource.delete(id: customer.id) } catch { throw HubError.wrap(error) }
        }
        let spec = FormSpec(
            sections: [FormSection(fields: Self.fieldSpec(isRequiredEmail: true))],
            actions: FormActions(save: save, delete: delete)
        )
        return FormDetails.form(id: "customer:\(customer.id)", title: "User", spec: spec, values: [
            "email": .string(customer.email ?? ""),
            "displayName": .string(customer.displayName ?? ""),
            "externalId": .string(customer.externalId ?? ""),
            "slug": .string(customer.slug ?? ""),
            "avatarUrl": .string(customer.avatarUrl ?? "")
        ])
    }
}
