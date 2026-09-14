import XCTest
@testable import AgenticToolkitHub
import AgenticToolkitHTDV

final class FakeCustomersDataSource: CustomersDataSource, @unchecked Sendable {
    var customers: [Customer]
    var creates: [CustomerInput] = []
    var updates: [(id: String, input: CustomerInput)] = []
    var deletes: [String] = []
    var failure: HubError?
    var createFailure: HubError?

    init(customers: [Customer]) { self.customers = customers }

    func list(ecosystemID: String) async throws -> [Customer] {
        try check()
        return customers.filter { $0.ecosystemId == ecosystemID }
    }
    func get(id: String) async throws -> Customer {
        try check()
        guard let customer = customers.first(where: { $0.id == id }) else { throw HubError.notFound }
        return customer
    }
    func create(_ input: CustomerInput) async throws -> Customer {
        try check()
        if let createFailure { throw createFailure }
        creates.append(input)
        let customer = Customer(
            id: "c-\(customers.count + 1)", ecosystemId: input.ecosystemId, email: input.email,
            displayName: input.displayName
        )
        customers.append(customer); return customer
    }
    func update(id: String, _ input: CustomerInput) async throws -> Customer {
        try check(); updates.append((id, input))
        guard var customer = customers.first(where: { $0.id == id }) else { throw HubError.notFound }
        customer.email = input.email; customer.displayName = input.displayName
        customer.externalId = input.externalId
        customer.slug = input.slug; customer.avatarUrl = input.avatarUrl
        return customer
    }
    func delete(id: String) async throws { try check(); deletes.append(id); customers.removeAll { $0.id == id } }
    private func check() throws { if let failure { throw failure } }
}

extension Customer {
    static func fixture(
        id: String = "c-jane", email: String? = "jane@example.com", displayName: String? = "Jane Doe",
        externalId: String? = nil
    ) -> Customer {
        Customer(
            id: id, ecosystemId: "org.acme.shop", email: email, displayName: displayName, externalId: externalId,
            slug: "jane", avatarUrl: nil,
            createdAt: "2026-09-04T10:00:00.000Z", updatedAt: "2026-09-04T10:00:00.000Z"
        )
    }
}

@MainActor
final class CustomersTopicTests: XCTestCase {
    private func makeRail(_ source: FakeCustomersDataSource) -> SingleTopicRail {
        SingleTopicRail(topic: CustomersTopic(dataSource: source))
    }

    func testDecodesCustomerWithNullFields() throws {
        let json = #"""
        {"id":"c1","ecosystemId":"org.acme.shop","email":null,"displayName":null,"externalId":"auth0|abc",
        "slug":null,"avatarUrl":null,"createdAt":"2026-09-04T10:00:00.000Z","updatedAt":"2026-09-04T10:00:00.000Z"}
        """#
        let customer = try JSONDecoder().decode(Customer.self, from: Data(json.utf8))
        XCTAssertNil(customer.email)
        XCTAssertEqual(customer.label, "—")
        XCTAssertEqual(customer.sublabel, "auth0|abc")
    }

    func testLabelsPreferDisplayNameThenEmail() {
        XCTAssertEqual(Customer.fixture().label, "Jane Doe")
        XCTAssertEqual(Customer.fixture().sublabel, "jane@example.com")
        XCTAssertEqual(Customer.fixture(displayName: "").label, "jane@example.com")
        XCTAssertEqual(Customer.fixture(email: nil, displayName: nil).label, "—")
        XCTAssertEqual(Customer.fixture(email: nil, displayName: nil).sublabel, "—")
        // A newline is whitespace too: `HubText.nonBlank` trims `.whitespacesAndNewlines`, so a
        // newline-only display name is missing, not a label made of padding.
        XCTAssertEqual(Customer.fixture(displayName: "\n").label, "jane@example.com")
        XCTAssertEqual(Customer.fixture(displayName: "  Jane  ").label, "Jane")
    }

    /// A field holding only a newline must OMIT the key, not encode an empty string. The local
    /// `Customer.nonBlank` trimmed `.whitespaces` (newlines excluded) and returned the value
    /// untrimmed, so `"\n"` survived as non-nil and the call site re-trimmed it to `""`.
    func testNewlineOnlyOptionalFieldIsOmittedNotEmptied() async throws {
        let source = FakeCustomersDataSource(customers: [.fixture()])
        let (_, form) = try await makeRail(source).form(["c-jane"])
        form.state.set(.string("\n"), for: "slug")
        form.state.set(.string("\n \n"), for: "externalId")
        let saved = await form.state.save()
        XCTAssertTrue(saved)
        XCTAssertNil(source.updates[0].input.slug)
        XCTAssertNil(source.updates[0].input.externalId)
    }

    func testListShowsUsers() async throws {
        let source = FakeCustomersDataSource(customers: [
            .fixture(), .fixture(id: "c-bob", email: "bob@example.com", displayName: nil),
            Customer(id: "x", ecosystemId: "org.other")
        ])
        let level = try await makeRail(source).level([])
        XCTAssertEqual(level.id, "users-list")
        XCTAssertEqual(level.title, "Users")
        XCTAssertEqual(level.items.map(\.label), ["Jane Doe", "bob@example.com"])
        XCTAssertEqual(level.items.map(\.sublabel), ["jane@example.com", "bob@example.com"])
        XCTAssertEqual(level.items.map(\.leadsTo), [.detail, .detail])
        XCTAssertEqual(level.emptyMessage, "No users yet.")
        XCTAssertEqual(level.createAction?.title, "New user")
    }

    func testCreateFormValidatesEmailAndDuplicates() async throws {
        let source = FakeCustomersDataSource(customers: [.fixture()])
        let spec = CustomersTopic(dataSource: source).createSpec(for: .fixture())
        XCTAssertEqual(spec.fields.map(\.key), ["email", "displayName"])

        let bad = FormState(spec: spec)
        bad.set(.string("not-an-email"), for: "email")
        let badSaved = await bad.save()
        XCTAssertFalse(badSaved)
        XCTAssertEqual(bad.errors["email"], "Enter a valid email address.")

        let missing = FormState(spec: spec)
        let missingSaved = await missing.save()
        XCTAssertFalse(missingSaved)
        XCTAssertEqual(missing.errors["email"], "Email is required")

        let duplicate = FormState(spec: spec)
        duplicate.set(.string("Jane@Example.com"), for: "email")
        let duplicateSaved = await duplicate.save()
        XCTAssertFalse(duplicateSaved)
        XCTAssertEqual(duplicate.saveError, "A user with email \"Jane@Example.com\" already exists.")

        let fresh = FormState(spec: spec)
        fresh.set(.string("bob@example.com"), for: "email")
        fresh.set(.string("Bob"), for: "displayName")
        let freshSaved = await fresh.save()
        XCTAssertTrue(freshSaved)
        XCTAssertEqual(source.creates, [
            CustomerInput(ecosystemId: "org.acme.shop", email: "bob@example.com", displayName: "Bob")
        ])

        source.createFailure = .conflict("dup")
        let conflict = FormState(spec: spec)
        conflict.set(.string("carol@example.com"), for: "email")
        let conflictSaved = await conflict.save()
        XCTAssertFalse(conflictSaved)
        XCTAssertEqual(conflict.saveError, "A user with email \"carol@example.com\" already exists.")
    }

    func testDetailFormShowsAllFieldsAndSaves() async throws {
        let source = FakeCustomersDataSource(customers: [.fixture()])
        let (detail, form) = try await makeRail(source).form(["c-jane"])
        XCTAssertEqual(detail.id, "customer:c-jane")
        XCTAssertEqual(detail.title, "User")
        XCTAssertEqual(
            form.state.spec.fields.map(\.key), ["email", "displayName", "externalId", "slug", "avatarUrl"]
        )
        XCTAssertEqual(
            form.state.spec.fields.map(\.label),
            ["Email", "Display name", "External ID", "Handle", "Avatar URL"]
        )
        XCTAssertEqual(form.state.value(for: "email"), .string("jane@example.com"))
        XCTAssertEqual(form.state.value(for: "slug"), .string("jane"))
        XCTAssertEqual(form.state.value(for: "externalId"), .string(""))
        form.state.set(.string("auth0|abc123"), for: "externalId")
        form.state.set(.string(""), for: "slug")
        let saved = await form.state.save()
        XCTAssertTrue(saved)
        XCTAssertEqual(source.updates.map(\.id), ["c-jane"])
        XCTAssertEqual(source.updates[0].input, CustomerInput(
            ecosystemId: "org.acme.shop", email: "jane@example.com", displayName: "Jane Doe",
            externalId: "auth0|abc123", slug: nil, avatarUrl: nil
        ))
    }

    func testDetailDeleteConfirmsWithLabel() async throws {
        let source = FakeCustomersDataSource(customers: [.fixture(displayName: nil)])
        let (_, form) = try await makeRail(source).form(["c-jane"])
        let delete = try XCTUnwrap(form.state.spec.actions.delete)
        XCTAssertEqual(delete.title, "Delete user")
        XCTAssertEqual(delete.confirmationText, "Delete user \"jane@example.com\"? This cannot be undone.")
        try await delete.perform()
        XCTAssertEqual(source.deletes, ["c-jane"])
    }

    func testUnknownUserIsEmpty() async throws {
        guard case .empty = try await makeRail(FakeCustomersDataSource(customers: [])).child(["nope"]) else {
            return XCTFail("expected empty")
        }
    }

    func testFailuresSurfaceAsHubError() async throws {
        let source = FakeCustomersDataSource(customers: [])
        source.failure = .forbidden
        do {
            _ = try await makeRail(source).child([])
            XCTFail("expected throw")
        } catch let error as HubError {
            XCTAssertEqual(error, .forbidden)
        }
    }
}
