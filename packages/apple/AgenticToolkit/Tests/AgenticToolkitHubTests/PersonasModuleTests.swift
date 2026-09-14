import AgenticToolkitHTDV
import Foundation
import XCTest
@testable import AgenticToolkitHub

/// In-memory data source: records calls, serves fixtures.
final class FakePersonasDataSource: PersonasDataSource, @unchecked Sendable {
    var personas: [Persona]
    var services: [PersonaService]
    var updates: [(id: String, body: PersonaBody)] = []
    var creates: [PersonaBody] = []
    var deletes: [String] = []
    var failure: HubError?

    init(personas: [Persona], services: [PersonaService] = []) {
        self.personas = personas
        self.services = services
    }

    func list() async throws -> [Persona] { try check(); return personas }
    func get(id: String) async throws -> Persona {
        try check()
        guard let persona = personas.first(where: { $0.id == id }) else { throw HubError.notFound }
        return persona
    }
    func create(_ body: PersonaBody) async throws -> Persona {
        try check()
        creates.append(body)
        let persona = Persona.fixture(id: "persona.me.\(body.slug)", slug: body.slug, name: body.name)
        personas.append(persona)
        return persona
    }
    func update(id: String, _ body: PersonaBody) async throws -> Persona {
        try check()
        updates.append((id, body))
        guard var persona = personas.first(where: { $0.id == id }) else { throw HubError.notFound }
        persona.name = body.name
        persona.slug = body.slug
        persona.description = body.description
        persona.modelPrompt = body.modelPrompt
        return persona
    }
    func delete(id: String) async throws { try check(); deletes.append(id); personas.removeAll { $0.id == id } }
    func listServices() async throws -> [PersonaService] { try check(); return services }
    private func check() throws { if let failure { throw failure } }
}

extension Persona {
    static func fixture(id: String = "persona.me.ada", slug: String = "ada", name: String = "Ada") -> Persona {
        Persona(
            id: id, slug: slug, name: name, description: "Math tutor", visibility: "private",
            model: "gpt-x", serviceId: "svc1", appId: nil, avatarAttachmentId: nil,
            modelPrompt: "You are Ada.", voice: "Warm", character: nil, examples: nil,
            cannedChat: .object(["mode": .string("script")]), chatStatus: nil,
            createdAt: "2026-09-01T00:00:00.000Z", updatedAt: "2026-09-02T00:00:00.000Z",
            ownedEcosystemId: nil, corpusEcosystemId: nil
        )
    }
}

@MainActor
final class PersonasModuleTests: XCTestCase {
    private let service = PersonaService(
        id: "svc1", name: "OpenAI", providerKind: "openai", baseUrl: "https://api.openai.com",
        connectStatus: "connected",
        models: [
            PersonaServiceModel(id: "gpt-x", displayName: "GPT X"), PersonaServiceModel(id: "gpt-y", displayName: nil)
        ]
    )

    func testRootLevelListsPersonas() async throws {
        let source = FakePersonasDataSource(
            personas: [.fixture(), .fixture(id: "persona.me.bob", slug: "bob", name: "Bob")]
        )
        let module = PersonasModule(dataSource: source)
        let level = try await module.rootLevel()
        XCTAssertEqual(level.id, "personas")
        XCTAssertEqual(level.title, "Personas")
        XCTAssertEqual(level.items.map(\.label), ["Ada", "Bob"])
        XCTAssertEqual(level.items.map(\.sublabel), ["ada", "bob"])
        XCTAssertEqual(level.items.first?.systemImage, "person.crop.circle")
        XCTAssertEqual(level.emptyMessage, "No personas yet.")
        XCTAssertEqual(level.createAction?.title, "New Persona")
    }

    func testPersonaChildIsFacetRail() async throws {
        let source = FakePersonasDataSource(personas: [.fixture()])
        let module = PersonasModule(dataSource: source)
        let root = try await module.rootLevel()
        guard case .level(let topics) = try await module.child(for: [root.items[0]]) else {
            return XCTFail("expected level")
        }
        XCTAssertEqual(topics.id, "persona-topics")
        XCTAssertEqual(topics.title, "Ada")
        XCTAssertEqual(topics.items.map(\.id), [
            "identity", "description", "personality", "purpose", "project", "knowledge", "memory",
            "abilities", "permissions", "access", "demo", "chatStatus", "llm"
        ])
        XCTAssertEqual(topics.items.map(\.label), [
            "Identity", "Description", "Personality", "Purpose", "Project", "Knowledge", "Memory",
            "Abilities", "Permissions", "Access", "Demo Chat", "Chat Status", "LLM Settings"
        ])
        XCTAssertTrue(topics.items.allSatisfy { $0.leadsTo == .detail })
    }

    func testIdentityFormValuesAndSave() async throws {
        let source = FakePersonasDataSource(personas: [.fixture()], services: [service])
        let module = PersonasModule(dataSource: source)
        let root = try await module.rootLevel()
        guard case .level(let topics) = try await module.child(for: [root.items[0]]) else {
            return XCTFail("expected level")
        }
        guard case .detail(let detail) = try await module.child(for: [root.items[0], topics.items[0]]) else {
            return XCTFail("expected detail")
        }
        XCTAssertEqual(detail.id, "persona:persona.me.ada:identity")
        XCTAssertEqual(detail.title, "Identity")
        // swiftlint:disable:next force_cast
        let form = detail.make() as! FormViewController
        XCTAssertEqual(form.state.spec.fields.map(\.key), ["name", "slug", "visibility"])
        XCTAssertEqual(form.state.value(for: "name"), .string("Ada"))
        XCTAssertEqual(form.state.value(for: "slug"), .string("ada"))
        XCTAssertEqual(form.state.value(for: "visibility"), .string("private"))
        form.state.set(.string("Ada Lovelace"), for: "name")
        form.state.set(.string("hub"), for: "visibility")
        let saved = await form.state.save()
        XCTAssertTrue(saved)
        XCTAssertEqual(source.updates.count, 1)
        XCTAssertEqual(source.updates[0].id, "persona.me.ada")
        XCTAssertEqual(source.updates[0].body.name, "Ada Lovelace")
        XCTAssertEqual(source.updates[0].body.visibility, "hub")
        XCTAssertEqual(source.updates[0].body.modelPrompt, "You are Ada.", "untouched fields ride along")
        XCTAssertEqual(source.updates[0].body.cannedChat, .object(["mode": .string("script")]))
    }

    func testIdentityFormValidatesSlug() async throws {
        let source = FakePersonasDataSource(personas: [.fixture()])
        let module = PersonasModule(dataSource: source)
        let (spec, _) = module.facetSpec("identity", persona: .fixture(), services: [])!
        guard case .text(let slug) = spec.fields[1] else { return XCTFail("expected text field") }
        XCTAssertEqual(slug.pattern, Slug.pattern)
        XCTAssertTrue(slug.isRequired)
        XCTAssertEqual(FormValidator.validate(field: spec.fields[1], value: .string("Bad Slug")), Slug.patternMessage)
    }

    func testIdentityDeleteAction() async throws {
        let source = FakePersonasDataSource(personas: [.fixture()])
        let module = PersonasModule(dataSource: source)
        let (spec, _) = module.facetSpec("identity", persona: .fixture(), services: [])!
        XCTAssertEqual(spec.actions.delete?.title, "Delete persona")
        XCTAssertEqual(spec.actions.delete?.confirmationText, "Delete persona \"Ada\"? This cannot be undone.")
        try await spec.actions.delete?.perform()
        XCTAssertEqual(source.deletes, ["persona.me.ada"])
    }

    func testDescriptionPersonalityPurposeForms() async throws {
        let module = PersonasModule(dataSource: FakePersonasDataSource(personas: [.fixture()]))
        let persona = Persona.fixture()
        let description = module.facetSpec("description", persona: persona, services: [])!
        XCTAssertEqual(description.spec.fields.map(\.key), ["description"])
        XCTAssertEqual(description.values["description"], .string("Math tutor"))
        let personality = module.facetSpec("personality", persona: persona, services: [])!
        XCTAssertEqual(personality.spec.fields.map(\.key), ["character", "voice", "examples"])
        XCTAssertEqual(personality.spec.fields.map(\.label), ["Character", "Voice", "Examples"])
        XCTAssertEqual(personality.values["voice"], .string("Warm"))
        XCTAssertEqual(personality.values["character"], .string(""))
        let purpose = module.facetSpec("purpose", persona: persona, services: [])!
        XCTAssertEqual(purpose.spec.fields.map(\.key), ["modelPrompt"])
        guard case .markdown(let prompt) = purpose.spec.fields[0] else { return XCTFail("expected markdown field") }
        XCTAssertEqual(prompt.label, "Purpose")
        XCTAssertFalse(prompt.isRequired)
    }

    func testBlankTextBecomesNilOnSave() async throws {
        let source = FakePersonasDataSource(personas: [.fixture()])
        let module = PersonasModule(dataSource: source)
        let (spec, values) = module.facetSpec("personality", persona: .fixture(), services: [])!
        var edited = values
        edited["voice"] = .string("   ")
        edited["character"] = .string("Curious")
        try await spec.actions.save?.perform(edited)
        XCTAssertEqual(source.updates[0].body.voice, nil)
        XCTAssertEqual(source.updates[0].body.character, "Curious")
    }

    func testLLMFormOffersServicesAndModels() async throws {
        let module = PersonasModule(dataSource: FakePersonasDataSource(personas: [.fixture()], services: [service]))
        let (spec, values) = module.facetSpec("llm", persona: .fixture(), services: [service])!
        XCTAssertEqual(spec.fields.map(\.key), ["serviceId", "model"])
        guard case .select(let serviceField) = spec.fields[0], case .select(let modelField) = spec.fields[1] else {
            return XCTFail("expected detail")
        }
        XCTAssertEqual(serviceField.options.map(\.title), ["No service", "OpenAI"])
        XCTAssertEqual(serviceField.options.map(\.value), ["", "svc1"])
        XCTAssertEqual(modelField.options.map(\.title), ["No model selected", "GPT X", "gpt-y"])
        XCTAssertEqual(values["serviceId"], .string("svc1"))
        XCTAssertEqual(values["model"], .string("gpt-x"))
    }

    func testLLMSaveClearsModelWhenServiceHasNoSuchModel() async throws {
        let source = FakePersonasDataSource(personas: [.fixture()], services: [service])
        let module = PersonasModule(dataSource: source)
        let (spec, values) = module.facetSpec("llm", persona: .fixture(), services: [service])!
        var edited = values
        edited["serviceId"] = .string("")
        try await spec.actions.save?.perform(edited)
        XCTAssertNil(source.updates[0].body.serviceId)
        XCTAssertNil(source.updates[0].body.model)
    }

    func testUnsupportedFacetsShowNotice() async throws {
        let source = FakePersonasDataSource(personas: [.fixture()])
        let module = PersonasModule(dataSource: source)
        let root = try await module.rootLevel()
        guard case .level(let topics) = try await module.child(for: [root.items[0]]) else {
            return XCTFail("expected level")
        }
        for facetID in ["project", "knowledge", "memory", "abilities", "permissions", "access", "demo", "chatStatus"] {
            let item = topics.items.first { $0.id == facetID }!
            guard case .detail(let detail) = try await module.child(for: [root.items[0], item]) else {
                return XCTFail(facetID)
            }
            // swiftlint:disable:next force_cast
            let form = detail.make() as! FormViewController
            XCTAssertEqual(form.state.value(for: "notice"), .string("Not available in this version"), facetID)
            XCTAssertNil(module.facetSpec(facetID, persona: .fixture(), services: []))
        }
    }

    func testCreateSpecAndPerform() async throws {
        let source = FakePersonasDataSource(personas: [])
        let module = PersonasModule(dataSource: source)
        let spec = module.createSpec()
        XCTAssertEqual(spec.fields.map(\.key), ["name", "slug", "description", "modelPrompt"])
        XCTAssertEqual(spec.fields.map(\.label), ["Name", "Slug", "Description", "Prompt"])
        XCTAssertEqual(spec.actions.save?.title, "Create")
        try await spec.actions.save?.perform([
            "name": .string("Bob"), "slug": .string("bob"), "description": .string(""),
            "modelPrompt": .string("You are Bob.")
        ])
        XCTAssertEqual(source.creates.count, 1)
        XCTAssertEqual(source.creates[0].name, "Bob")
        XCTAssertEqual(source.creates[0].slug, "bob")
        XCTAssertNil(source.creates[0].description)
        XCTAssertEqual(source.creates[0].modelPrompt, "You are Bob.")
        XCTAssertEqual(source.creates[0].model, "")
        XCTAssertEqual(source.creates[0].visibility, "private")
    }

    func testUnknownPathIsEmpty() async throws {
        let module = PersonasModule(dataSource: FakePersonasDataSource(personas: [.fixture()]))
        guard case .empty = try await module.child(for: []) else { return XCTFail("expected empty") }
        guard case .empty = try await module.child(for: [HTDVItem(id: "nope", label: "x")]) else {
            return XCTFail("expected empty")
        }
    }

    func testErrorsAreHubErrors() async {
        let source = FakePersonasDataSource(personas: [])
        source.failure = .offline
        let module = PersonasModule(dataSource: source)
        do {
            _ = try await module.rootLevel()
            XCTFail("expected throw")
        } catch {
            XCTAssertEqual(error as? HubError, .offline)
        }
    }

    func testPersonaDecodesFromWebJSON() throws {
        let json = #"""
        {"id":"persona.me.ada","userId":"u1","ownerKind":"user","ownerId":"u1","slug":"ada","name":"Ada",
         "description":null,
         "visibility":"private","model":null,"serviceId":null,"appId":null,"avatarAttachmentId":null,
         "modelPrompt":"",
         "voice":null,"character":null,"examples":null,"createdAt":"2026-09-01T00:00:00.000Z",
         "updatedAt":"2026-09-01T00:00:00.000Z",
         "cannedChat":{"mode":"script","turns":[]},"chatStatus":null,"ownedEcosystemId":"eco1"}
        """#
        let persona = try JSONDecoder().decode(Persona.self, from: Data(json.utf8))
        XCTAssertEqual(persona.name, "Ada")
        XCTAssertEqual(persona.cannedChat, .object(["mode": .string("script"), "turns": .array([])]))
        XCTAssertEqual(persona.ownedEcosystemId, "eco1")
    }
}
