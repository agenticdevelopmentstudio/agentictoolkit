import XCTest
@testable import AgenticToolkitHub
import AgenticToolkitHTDV

final class FakeEcosystemsDataSource: EcosystemsDataSource, @unchecked Sendable {
    var ecosystems: [Ecosystem]
    var infrastructure = "org.acme"
    var existing: Set<String> = []
    var creates: [(input: EcosystemCreate, parentID: String?)] = []
    var updates: [(id: String, input: EcosystemUpdate)] = []
    var deletes: [String] = []
    var failure: HubError?
    var createFailure: HubError?
    var updateFailure: HubError?

    init(ecosystems: [Ecosystem]) { self.ecosystems = ecosystems }

    func list() async throws -> [Ecosystem] { try check(); return ecosystems.filter { $0.parentId == nil } }
    func children(of parentID: String) async throws -> [Ecosystem] {
        try check()
        return ecosystems.filter { $0.parentId == parentID }
    }
    func get(id: String) async throws -> Ecosystem {
        try check()
        guard let ecosystem = ecosystems.first(where: { $0.id == id }) else { throw HubError.notFound }
        return ecosystem
    }
    func infrastructureID() async throws -> String { try check(); return infrastructure }
    func identifierExists(_ identifier: String) async throws -> Bool {
        try check()
        return existing.contains(identifier)
    }
    func create(_ input: EcosystemCreate, parentID: String?) async throws -> Ecosystem {
        try check()
        if let createFailure { throw createFailure }
        creates.append((input, parentID))
        let ecosystem = Ecosystem.fixture(id: input.id, slug: input.slug, name: input.name, parentId: parentID)
        ecosystems.append(ecosystem)
        return ecosystem
    }
    func update(id: String, _ input: EcosystemUpdate) async throws -> Ecosystem {
        try check()
        if let updateFailure { throw updateFailure }
        updates.append((id, input))
        guard var ecosystem = ecosystems.first(where: { $0.id == id }) else { throw HubError.notFound }
        if let slug = input.slug { ecosystem.slug = slug; ecosystem.id = ecosystem.identifierPrefix + slug }
        if let name = input.name { ecosystem.name = name }
        if let description = input.description { ecosystem.description = description }
        return ecosystem
    }
    func delete(id: String) async throws { try check(); deletes.append(id); ecosystems.removeAll { $0.id == id } }
    private func check() throws { if let failure { throw failure } }
}

extension Ecosystem {
    static func fixture(
        id: String = "org.acme.shop", slug: String = "shop", name: String = "Shop", isDefault: Bool = false,
        parentId: String? = nil, canManage: Bool? = true
    ) -> Ecosystem {
        Ecosystem(
            id: id, slug: slug, name: name, description: "Storefront", region: nil, primaryDomain: nil,
            createdAt: "2026-09-04T10:00:00.000Z", updatedAt: "2026-09-04T10:00:00.000Z",
            isDefault: isDefault, isInfrastructure: nil, parentId: parentId, canManage: canManage
        )
    }
}

@MainActor
final class EcosystemsModuleTests: XCTestCase {
    private func makeModule(
        _ source: FakeEcosystemsDataSource, extra: [any EcosystemTopicProvider] = []
    ) -> EcosystemsModule {
        EcosystemsModule(dataSource: source, topics: [
            EcosystemTopicGroup(
                id: "storage", label: "Storage", systemImage: "internaldrive", dividerAfter: true,
                children: [
                    EcosystemNoticeTopic(
                        entry: EcosystemTopicEntry(
                            id: "all-data", label: "All Data", systemImage: "tablecells",
                            description: "Browse and edit the raw rows behind every bucket.", leadsTo: .detail
                        ),
                        message: FormDetails.unavailableMessage
                    )
                ]
            )
        ] + extra + [
            ChildEcosystemsTopic(dataSource: source),
            EcosystemSettingsTopic(dataSource: source)
        ])
    }

    func testDecodesEcosystemWithMissingIsDefault() throws {
        let json = #"{"id":"org.acme.shop","slug":"shop","name":"Shop","createdAt":"2026-09-04T10:00:00.000Z","#
            + #""updatedAt":"2026-09-04T10:00:00.000Z"}"#
        let ecosystem = try JSONDecoder().decode(Ecosystem.self, from: Data(json.utf8))
        XCTAssertFalse(ecosystem.isDefault)
        XCTAssertTrue(ecosystem.isManageable)
        XCTAssertEqual(ecosystem.identifierPrefix, "org.acme.")
        XCTAssertEqual(Ecosystem.fixture(id: "shop").identifierPrefix, "")
    }

    func testRootLevelListsProductsWithoutDefaultRows() async throws {
        let source = FakeEcosystemsDataSource(ecosystems: [
            .fixture(id: "org.acme", slug: "acme", name: "Acme", isDefault: true),
            .fixture(),
            .fixture(id: "org.acme.blog", slug: "blog", name: "Blog")
        ])
        let level = try await makeModule(source).rootLevel()
        XCTAssertEqual(level.id, "ecosystems")
        XCTAssertEqual(level.title, "Products")
        XCTAssertEqual(level.items.map(\.id), ["org.acme.shop", "org.acme.blog"])
        XCTAssertEqual(level.items.map(\.label), ["Shop", "Blog"])
        XCTAssertEqual(level.items.map(\.sublabel), ["org.acme.shop", "org.acme.blog"])
        XCTAssertEqual(level.items.first?.systemImage, "shippingbox")
        XCTAssertEqual(level.emptyMessage, "No products yet.")
        XCTAssertEqual(level.createAction?.title, "New Product")
    }

    func testProductChildIsTopicsRailInProviderOrder() async throws {
        let source = FakeEcosystemsDataSource(ecosystems: [.fixture()])
        let module = makeModule(source)
        let root = try await module.rootLevel()
        guard case .level(let topics) = try await module.child(for: [root.items[0]]) else {
            return XCTFail("expected level")
        }
        XCTAssertEqual(topics.id, "ecosystem-topics")
        XCTAssertEqual(topics.title, "Shop")
        XCTAssertEqual(topics.items.map(\.id), ["storage", "child-ecosystems", "settings"])
        XCTAssertEqual(topics.items.map(\.label), ["Storage", "Child Ecosystems", "Settings"])
        XCTAssertEqual(topics.items.map(\.dividerAfter), [true, false, false])
        XCTAssertEqual(topics.items.map(\.leadsTo), [.list, .list, .detail])
        XCTAssertEqual(topics.items[2].sublabel, "The ecosystem's own record — name, identifier, and description.")
    }

    func testNotManageableProductShowsNotice() async throws {
        let source = FakeEcosystemsDataSource(ecosystems: [.fixture(canManage: false)])
        let module = makeModule(source)
        let root = try await module.rootLevel()
        guard case .detail(let detail) = try await module.child(for: [root.items[0]]) else {
            return XCTFail("expected detail")
        }
        XCTAssertEqual(detail.id, "ecosystem:org.acme.shop:not-manageable")
        XCTAssertEqual(detail.title, "You don't have admin access to this ecosystem")
        // swiftlint:disable:next force_cast
        let form = detail.make() as! FormViewController
        XCTAssertEqual(
            form.state.value(for: "notice").stringValue,
            "Viewing an ecosystem's contents needs organization admin access — ask one of the organization's admins."
        )
    }

    func testGroupTopicListsItsChildrenAndDelegates() async throws {
        let source = FakeEcosystemsDataSource(ecosystems: [.fixture()])
        let module = makeModule(source)
        let root = try await module.rootLevel()
        guard case .level(let topics) = try await module.child(for: [root.items[0]]) else {
            return XCTFail("expected level")
        }
        guard case .level(let storage) = try await module.child(for: [root.items[0], topics.items[0]]) else {
            return XCTFail("expected group level")
        }
        XCTAssertEqual(storage.id, "ecosystem-group:storage")
        XCTAssertEqual(storage.title, "Storage")
        XCTAssertEqual(storage.items.map(\.id), ["all-data"])
        XCTAssertEqual(storage.items[0].sublabel, "Browse and edit the raw rows behind every bucket.")
        guard case .detail(let notice) = try await module.child(
            for: [root.items[0], topics.items[0], storage.items[0]]
        ) else {
            return XCTFail("expected notice")
        }
        XCTAssertEqual(notice.id, "ecosystem:org.acme.shop:all-data")
        XCTAssertEqual(notice.title, "All Data")
        guard case .empty = try await module.child(
            for: [root.items[0], topics.items[0], HTDVItem(id: "nope", label: "?")]
        ) else {
            return XCTFail("expected empty")
        }
    }

    func testUnknownProductOrTopicIsEmpty() async throws {
        let source = FakeEcosystemsDataSource(ecosystems: [.fixture()])
        let module = makeModule(source)
        guard case .empty = try await module.child(for: [HTDVItem(id: "gone", label: "Gone")]) else {
            return XCTFail("expected empty")
        }
        let root = try await module.rootLevel()
        guard case .empty = try await module.child(for: [root.items[0], HTDVItem(id: "nope", label: "?")]) else {
            return XCTFail("expected empty")
        }
    }

    func testSettingsFormValuesAndSave() async throws {
        let source = FakeEcosystemsDataSource(ecosystems: [.fixture()])
        let module = makeModule(source)
        let root = try await module.rootLevel()
        guard case .level(let topics) = try await module.child(for: [root.items[0]]) else {
            return XCTFail("expected level")
        }
        guard case .detail(let detail) = try await module.child(for: [root.items[0], topics.items[2]]) else {
            return XCTFail("expected settings form")
        }
        XCTAssertEqual(detail.id, "ecosystem:org.acme.shop:settings")
        XCTAssertEqual(detail.title, "Settings")
        // swiftlint:disable:next force_cast
        let form = detail.make() as! FormViewController
        XCTAssertEqual(form.state.spec.fields.map(\.key), ["name", "slug", "id", "description", "region"])
        XCTAssertEqual(
            form.state.spec.fields.map(\.label),
            ["Display Name", "Slug", "Identifier", "Description", "Geographic Region"]
        )
        XCTAssertEqual(form.state.value(for: "name").stringValue, "Shop")
        XCTAssertEqual(form.state.value(for: "slug").stringValue, "shop")
        XCTAssertEqual(form.state.value(for: "id").stringValue, "org.acme.shop")
        XCTAssertEqual(form.state.value(for: "description").stringValue, "Storefront")
        XCTAssertEqual(form.state.value(for: "region").stringValue, "coming soon")
        XCTAssertFalse(form.state.spec.fields[2].isEditable)
        XCTAssertEqual(form.state.spec.actions.delete?.title, "Delete Product")
        XCTAssertEqual(form.state.spec.actions.delete?.confirmationText, EcosystemSettingsTopic.deleteWarning)

        form.state.set(.string("Web Shop"), for: "name")
        form.state.set(.string("web-shop"), for: "slug")
        let saved = await form.state.save()
        XCTAssertTrue(saved)
        XCTAssertEqual(source.updates.count, 1)
        XCTAssertEqual(source.updates[0].id, "org.acme.shop")
        XCTAssertEqual(source.updates[0].input.slug, "web-shop")
        XCTAssertEqual(source.updates[0].input.name, "Web Shop")
        XCTAssertEqual(source.updates[0].input.description, "Storefront")
        XCTAssertNil(source.updates[0].input.region)
    }

    func testSettingsSaveConflictBecomesIdentifierInUse() async throws {
        let source = FakeEcosystemsDataSource(ecosystems: [.fixture()])
        source.updateFailure = .conflict("dup")
        let module = makeModule(source)
        let root = try await module.rootLevel()
        guard case .level(let topics) = try await module.child(for: [root.items[0]]) else {
            return XCTFail("expected level")
        }
        guard case .detail(let detail) = try await module.child(for: [root.items[0], topics.items[2]]) else {
            return XCTFail("expected detail")
        }
        // swiftlint:disable:next force_cast
        let form = detail.make() as! FormViewController
        form.state.set(.string("blog"), for: "slug")
        let saved = await form.state.save()
        XCTAssertFalse(saved)
        XCTAssertEqual(form.state.saveError, "Identifier \"org.acme.blog\" is already in use.")
    }

    func testSettingsDeleteCallsDataSource() async throws {
        let source = FakeEcosystemsDataSource(ecosystems: [.fixture()])
        let module = makeModule(source)
        let root = try await module.rootLevel()
        guard case .level(let topics) = try await module.child(for: [root.items[0]]) else {
            return XCTFail("expected level")
        }
        guard case .detail(let detail) = try await module.child(for: [root.items[0], topics.items[2]]) else {
            return XCTFail("expected detail")
        }
        // swiftlint:disable:next force_cast
        let form = detail.make() as! FormViewController
        try await form.state.spec.actions.delete!.perform()
        XCTAssertEqual(source.deletes, ["org.acme.shop"])
    }

    func testChildEcosystemsLevelAndDescent() async throws {
        let source = FakeEcosystemsDataSource(ecosystems: [
            .fixture(), .fixture(id: "org.acme.shop.eu", slug: "eu", name: "Shop EU", parentId: "org.acme.shop")
        ])
        let module = makeModule(source)
        let root = try await module.rootLevel()
        guard case .level(let topics) = try await module.child(for: [root.items[0]]) else {
            return XCTFail("expected level")
        }
        guard case .level(let children) = try await module.child(for: [root.items[0], topics.items[1]]) else {
            return XCTFail("expected child list")
        }
        XCTAssertEqual(children.id, "child-ecosystems-list")
        XCTAssertEqual(children.title, "Child Ecosystems")
        XCTAssertEqual(children.items.map(\.label), ["Shop EU"])
        XCTAssertEqual(children.items.map(\.sublabel), ["org.acme.shop.eu"])
        XCTAssertEqual(children.emptyMessage, "No child ecosystems yet.")
        XCTAssertEqual(children.createAction?.title, "New Ecosystem")
        guard case .level(let childTopics) = try await module.child(
            for: [root.items[0], topics.items[1], children.items[0]]
        ) else {
            return XCTFail("expected child topics")
        }
        XCTAssertEqual(childTopics.id, "ecosystem-topics")
        XCTAssertEqual(childTopics.title, "Shop EU")
        guard case .detail(let settings) = try await module.child(
            for: [root.items[0], topics.items[1], children.items[0], childTopics.items[2]]
        ) else {
            return XCTFail("expected detail")
        }
        XCTAssertEqual(settings.id, "ecosystem:org.acme.shop.eu:settings")
    }

    func testCreateFormDerivesIdentifierFromInfrastructure() async throws {
        let source = FakeEcosystemsDataSource(ecosystems: [])
        let spec = EcosystemCreateForm(dataSource: source, parent: nil).spec()
        XCTAssertEqual(spec.fields.map(\.key), ["name", "slug", "description"])
        XCTAssertEqual(spec.fields.map(\.label), ["Display Name", "Slug", "Description"])
        XCTAssertEqual(spec.actions.save?.title, "Create")
        let state = FormState(spec: spec)
        state.set(.string("Shop"), for: "name")
        state.set(.string("shop"), for: "slug")
        state.set(.string("Storefront"), for: "description")
        let saved = await state.save()
        XCTAssertTrue(saved)
        XCTAssertEqual(source.creates.count, 1)
        XCTAssertEqual(source.creates[0].input.id, "org.acme.shop")
        XCTAssertEqual(source.creates[0].input.slug, "shop")
        XCTAssertEqual(source.creates[0].input.name, "Shop")
        XCTAssertEqual(source.creates[0].input.description, "Storefront")
        XCTAssertEqual(source.creates[0].input.region, "")
        XCTAssertEqual(source.creates[0].input.primaryDomain, "")
        XCTAssertNil(source.creates[0].parentID)
    }

    func testCreateFormForChildUsesParentPrefix() async throws {
        let source = FakeEcosystemsDataSource(ecosystems: [.fixture()])
        let spec = EcosystemCreateForm(dataSource: source, parent: .fixture()).spec()
        let state = FormState(spec: spec)
        state.set(.string("Shop EU"), for: "name")
        state.set(.string("eu"), for: "slug")
        let saved = await state.save()
        XCTAssertTrue(saved)
        XCTAssertEqual(source.creates[0].input.id, "org.acme.shop.eu")
        XCTAssertEqual(source.creates[0].parentID, "org.acme.shop")
    }

    func testCreateFormValidationMessages() async throws {
        let source = FakeEcosystemsDataSource(ecosystems: [])
        source.existing = ["org.acme.taken"]
        let spec = EcosystemCreateForm(dataSource: source, parent: nil).spec()

        let tooLong = FormState(spec: spec)
        tooLong.set(.string("X"), for: "name")
        tooLong.set(.string(String(repeating: "a", count: 65)), for: "slug")
        let tooLongSaved = await tooLong.save()
        XCTAssertFalse(tooLongSaved)
        XCTAssertEqual(tooLong.saveError, "Slug must be 64 characters or fewer.")

        let taken = FormState(spec: spec)
        taken.set(.string("X"), for: "name")
        taken.set(.string("taken"), for: "slug")
        let takenSaved = await taken.save()
        XCTAssertFalse(takenSaved)
        XCTAssertEqual(taken.saveError, "Identifier \"org.acme.taken\" is already in use.")

        source.createFailure = .conflict("dup")
        let conflict = FormState(spec: spec)
        conflict.set(.string("X"), for: "name")
        conflict.set(.string("fresh"), for: "slug")
        let conflictSaved = await conflict.save()
        XCTAssertFalse(conflictSaved)
        XCTAssertEqual(conflict.saveError, "An ecosystem with identifier \"org.acme.fresh\" already exists.")
        XCTAssertTrue(source.creates.isEmpty)
    }

    func testDataSourceFailuresSurfaceAsHubError() async throws {
        let source = FakeEcosystemsDataSource(ecosystems: [.fixture()])
        source.failure = .offline
        let module = makeModule(source)
        do {
            _ = try await module.rootLevel()
            XCTFail("expected throw")
        } catch let error as HubError {
            XCTAssertEqual(error, .offline)
        }
    }
}
