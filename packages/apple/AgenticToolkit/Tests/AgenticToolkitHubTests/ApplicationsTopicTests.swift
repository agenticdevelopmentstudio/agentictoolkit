import XCTest
@testable import AgenticToolkitHub
import AgenticToolkitHTDV

final class FakeApplicationsDataSource: ApplicationsDataSource, @unchecked Sendable {
    var applications: [Application]
    var grants: [String: [SchemaGrant]] = [:]
    var tokens: [String: [ApplicationToken]] = [:]
    var creates: [ApplicationCreate] = []
    var updates: [(id: String, input: ApplicationUpdate)] = []
    var deletes: [String] = []
    var renames: [(current: String, next: String)] = []
    var grantWrites: [(id: String, grants: [SchemaGrant])] = []
    var tokenCreates: [(id: String, name: String)] = []
    var tokenRevokes: [(id: String, tokenID: String)] = []
    var failure: HubError?
    var createFailure: HubError?
    var renameFailure: HubError?
    /// Index into `grantWrites` at which `setSchemaGrants` throws instead of persisting.
    var grantWriteFailureIndex: Int?

    init(applications: [Application]) { self.applications = applications }

    func list(ecosystemID: String) async throws -> [Application] {
        try check(); return applications.filter { $0.ecosystemId == ecosystemID }
    }
    func get(id: String) async throws -> Application {
        try check()
        guard let app = applications.first(where: { $0.id == id }) else { throw HubError.notFound }
        return app
    }
    func create(_ input: ApplicationCreate) async throws -> Application {
        try check()
        if let createFailure { throw createFailure }
        creates.append(input)
        let app = Application(
            id: "app.acme.shop.\(input.slug)", ecosystemId: input.ecosystemId, slug: input.slug,
            displayName: input.displayName, consumerKind: input.consumerKind
        )
        applications.append(app); return app
    }
    func update(id: String, _ input: ApplicationUpdate) async throws -> Application {
        try check(); updates.append((id, input))
        guard let index = applications.firstIndex(where: { $0.id == id }) else { throw HubError.notFound }
        var app = applications[index]
        if let slug = input.slug { app.slug = slug }
        if let displayName = input.displayName { app.displayName = displayName }
        if let kind = input.consumerKind { app.consumerKind = kind }
        // Write the mutation back: the brief's original draft mutated a local copy of `app` and never
        // persisted it into `applications`, so a later `get(id:)` (as the settings-form rename test does)
        // would see the pre-update slug forever. Persisting here is what a real backend's update does.
        applications[index] = app
        return app
    }
    func delete(id: String) async throws { try check(); deletes.append(id); applications.removeAll { $0.id == id } }
    func renameIdentifier(_ current: String, to next: String) async throws {
        try check()
        if let renameFailure { throw renameFailure }
        renames.append((current, next))
        if let index = applications.firstIndex(where: { $0.id == current }) { applications[index].id = next }
        // Deliberately does NOT auto-migrate `grants` here: the real backend's rename endpoint only
        // renames the identifier, and `ApplicationsTopic.settingsDetail`'s save action explicitly
        // re-homes schema grants itself afterward ("as the web does"). Auto-migrating here as well
        // would double-move the grants and starve the topic's own re-home read.
    }
    func schemaGrants(applicationID: String) async throws -> [SchemaGrant] {
        try check(); return grants[applicationID] ?? []
    }
    func setSchemaGrants(applicationID: String, _ newGrants: [SchemaGrant]) async throws {
        try check()
        if grantWrites.count == grantWriteFailureIndex { throw HubError.transport("grant write failed") }
        grantWrites.append((applicationID, newGrants)); grants[applicationID] = newGrants
    }
    func tokens(applicationID: String) async throws -> [ApplicationToken] {
        try check(); return tokens[applicationID] ?? []
    }
    func createToken(applicationID: String, name: String) async throws -> ApplicationTokenCreated {
        try check(); tokenCreates.append((applicationID, name))
        let created = ApplicationTokenCreated(
            id: "tok-\(tokenCreates.count)", name: name, prefix: "apk_ab12", token: "apk_ab12cd34ef56",
            createdAt: "2026-09-04T10:00:00.000Z"
        )
        tokens[applicationID, default: []].append(ApplicationToken(
            id: created.id, name: created.name, prefix: created.prefix, createdAt: created.createdAt
        ))
        return created
    }
    func revokeToken(applicationID: String, tokenID: String) async throws {
        try check(); tokenRevokes.append((applicationID, tokenID))
        tokens[applicationID]?.removeAll { $0.id == tokenID }
    }
    private func check() throws { if let failure { throw failure } }
}

extension Application {
    static func fixture(
        id: String = "app.acme.shop.web", slug: String = "web", displayName: String = "Web Storefront",
        consumerKind: ConsumerKind = .customer
    ) -> Application {
        Application(
            id: id, ecosystemId: "org.acme.shop", slug: slug, displayName: displayName, consumerKind: consumerKind,
            createdAt: "2026-09-04T10:00:00.000Z", updatedAt: "2026-09-04T10:00:00.000Z"
        )
    }
}

@MainActor
final class ApplicationsTopicTests: XCTestCase {
    private var apps = FakeApplicationsDataSource(applications: [.fixture()])
    private var buckets = FakeBucketsDataSource(
        buckets: [.fixture(), .fixture(id: "b-orders", name: "Orders")],
        tables: [BucketTable(id: "t1", bucketId: "b-profile", sqlTableName: "contacts", name: "Contacts"),
                 BucketTable(id: "t2", bucketId: "b-profile", sqlTableName: "avatars", name: "Avatars")]
    )
    private lazy var topic = ApplicationsTopic(dataSource: apps, buckets: buckets)
    private lazy var rail = SingleTopicRail(topic: topic)

    func testCrudPermissionsRoundTrip() {
        XCTAssertEqual(CrudPermissions(wire: "R, D,C").wire, "C,R,D")
        XCTAssertEqual(CrudPermissions(wire: "").summary, "No access")
        XCTAssertTrue(CrudPermissions(wire: "").isEmpty)
        XCTAssertEqual(CrudPermissions(wire: "C,R,U,D").summary, "Create, Read, Update, Delete")
        XCTAssertEqual(CrudPermissions.readOnly.wire, "R")
        XCTAssertEqual(Application.fixture().identifierPrefix, "app.acme.shop.")
        XCTAssertEqual(ConsumerKind.staff.title, "Staff")
    }

    /// `SchemaGrant`/`TableGrant` are deliberately NOT `Codable` — the wire shape
    /// (`{schemaId, crud, tables: [{tableId, crud}]}`) lives in the app's adapter, so this test no
    /// longer decodes a grant straight from JSON. It only covers the token row, which IS a wire type.
    func testDecodesTokens() throws {
        let tokenJson = #"{"id":"t","name":"CI","prefix":"apk_1","token":"apk_1secret","#
            + #""createdAt":"2026-09-04T10:00:00.000Z"}"#
        let created = try JSONDecoder().decode(ApplicationTokenCreated.self, from: Data(tokenJson.utf8))
        XCTAssertEqual(created.token, "apk_1secret")
    }

    /// `consumerKind` is an open `string` on the wire. An unknown value must narrow to `.developer`
    /// rather than failing the whole array decode and blanking the Applications rail.
    func testUnknownConsumerKindNarrowsToDeveloperWithoutLosingSiblings() throws {
        let json = #"""
        [{"id":"app.acme.shop.svc","ecosystemId":"org.acme.shop","slug":"svc","displayName":"Service",
          "consumerKind":"service"},
         {"id":"app.acme.shop.web","ecosystemId":"org.acme.shop","slug":"web","displayName":"Web",
          "consumerKind":"customer"}]
        """#
        let rows = try JSONDecoder().decode([Application].self, from: Data(json.utf8))
        XCTAssertEqual(rows.map(\.id), ["app.acme.shop.svc", "app.acme.shop.web"])
        XCTAssertEqual(rows[0].consumerKind, .developer)
        XCTAssertEqual(rows[1].consumerKind, .customer)
    }

    func testListShowsApplications() async throws {
        apps.applications.append(
            .fixture(id: "app.acme.shop.ops", slug: "ops", displayName: "Ops Console", consumerKind: .staff)
        )
        let level = try await rail.level([])
        XCTAssertEqual(level.id, "applications-list")
        XCTAssertEqual(level.title, "Applications")
        XCTAssertEqual(level.items.map(\.label), ["Web Storefront", "Ops Console"])
        XCTAssertEqual(level.items.map(\.sublabel), ["app.acme.shop.web", "app.acme.shop.ops"])
        XCTAssertEqual(level.items.map(\.systemImage), ["person.2", "person.badge.key"])
        XCTAssertEqual(level.emptyMessage, "No applications yet.")
        XCTAssertEqual(level.createAction?.title, "New application")
    }

    func testCreateFormCreatesAndMapsConflict() async throws {
        let spec = topic.createSpec(for: .fixture())
        XCTAssertEqual(spec.fields.map(\.key), ["displayName", "slug", "consumerKind"])
        let state = FormState(spec: spec)
        state.set(.string("Mobile"), for: "displayName")
        state.set(.string("Mobile-App"), for: "slug")
        let slugRejected = await state.save()
        XCTAssertFalse(slugRejected)
        XCTAssertEqual(state.errors["slug"], Slug.patternMessage)
        state.set(.string("mobile"), for: "slug")
        state.set(.string("developer"), for: "consumerKind")
        let created = await state.save()
        XCTAssertTrue(created)
        XCTAssertEqual(apps.creates, [
            ApplicationCreate(
                ecosystemId: "org.acme.shop", slug: "mobile", displayName: "Mobile", consumerKind: .developer
            )
        ])

        apps.createFailure = .conflict("dup")
        let again = FormState(spec: spec)
        again.set(.string("Mobile"), for: "displayName")
        again.set(.string("mobile"), for: "slug")
        again.set(.string("developer"), for: "consumerKind")
        let conflicted = await again.save()
        XCTAssertFalse(conflicted)
        XCTAssertEqual(again.saveError, "An application with identifier \"mobile\" already exists.")
    }

    func testApplicationLevelItems() async throws {
        let level = try await rail.level(["app.acme.shop.web"])
        XCTAssertEqual(level.id, "application:app.acme.shop.web")
        XCTAssertEqual(level.title, "Web Storefront")
        XCTAssertEqual(level.items.map(\.id), ["settings", "grants", "tokens"])
        XCTAssertEqual(level.items.map(\.label), ["Settings", "Bucket permissions", "Access tokens"])
        XCTAssertEqual(level.items.map(\.leadsTo), [.detail, .list, .list])
        guard case .empty = try await rail.child(["nope"]) else { return XCTFail("expected empty") }
    }

    func testSettingsFormSavesWithoutRename() async throws {
        let (detail, form) = try await rail.form(["app.acme.shop.web", "settings"])
        XCTAssertEqual(detail.id, "application:app.acme.shop.web:settings")
        XCTAssertEqual(detail.title, "Application")
        XCTAssertEqual(form.state.spec.fields.map(\.key), ["displayName", "slug", "identifier", "consumerKind"])
        XCTAssertEqual(form.state.value(for: "identifier"), .string("app.acme.shop.web"))
        XCTAssertEqual(form.state.value(for: "consumerKind"), .string("customer"))
        form.state.set(.string("Storefront"), for: "displayName")
        let saved = await form.state.save()
        XCTAssertTrue(saved)
        XCTAssertTrue(apps.renames.isEmpty)
        XCTAssertEqual(apps.updates.map(\.id), ["app.acme.shop.web"])
        XCTAssertEqual(
            apps.updates[0].input, ApplicationUpdate(slug: "web", displayName: "Storefront", consumerKind: .customer)
        )
    }

    func testSettingsFormRenamesAndRehomesGrants() async throws {
        apps.grants["app.acme.shop.web"] = [SchemaGrant(schemaId: "b-profile", permissions: "R", tables: [:])]
        let (_, form) = try await rail.form(["app.acme.shop.web", "settings"])
        form.state.set(.string("store"), for: "slug")
        let renamed = await form.state.save()
        XCTAssertTrue(renamed)
        XCTAssertEqual(apps.renames.map(\.current), ["app.acme.shop.web"])
        XCTAssertEqual(apps.renames.map(\.next), ["app.acme.shop.store"])
        XCTAssertEqual(apps.grantWrites.map(\.id), ["app.acme.shop.store", "app.acme.shop.web"])
        XCTAssertEqual(apps.grantWrites[0].grants, [SchemaGrant(schemaId: "b-profile", permissions: "R", tables: [:])])
        XCTAssertEqual(apps.grantWrites[1].grants, [])
        XCTAssertEqual(apps.updates.map(\.id), ["app.acme.shop.store"])

        apps.renameFailure = .conflict("dup")
        let (_, second) = try await rail.form(["app.acme.shop.store", "settings"])
        second.state.set(.string("web"), for: "slug")
        let renameConflicted = await second.state.save()
        XCTAssertFalse(renameConflicted)
        XCTAssertEqual(second.state.saveError, "The identifier \"app.acme.shop.web\" is already in use.")
    }

    /// A transient failure on the SECOND grant write must not leave the application with no grants
    /// anywhere. Writing the new id first means the failing clear-the-old-id call is the harmless one.
    func testRenameKeepsGrantsWhenTheSecondGrantWriteFails() async throws {
        let grant = SchemaGrant(schemaId: "b-profile", permissions: "R", tables: [:])
        apps.grants["app.acme.shop.web"] = [grant]
        apps.grantWriteFailureIndex = 1
        let (_, form) = try await rail.form(["app.acme.shop.web", "settings"])
        form.state.set(.string("store"), for: "slug")
        let saved = await form.state.save()
        XCTAssertFalse(saved)
        XCTAssertEqual(apps.grants["app.acme.shop.store"], [grant])
        XCTAssertEqual(apps.grants["app.acme.shop.web"], [grant])
    }

    func testDeleteDropsGrantsThenDeletes() async throws {
        let (_, form) = try await rail.form(["app.acme.shop.web", "settings"])
        let delete = try XCTUnwrap(form.state.spec.actions.delete)
        XCTAssertEqual(delete.confirmationText, "Delete application \"Web Storefront\"? This cannot be undone.")
        try await delete.perform()
        XCTAssertEqual(apps.grantWrites.map(\.id), ["app.acme.shop.web"])
        XCTAssertEqual(apps.grantWrites[0].grants, [])
        XCTAssertEqual(apps.deletes, ["app.acme.shop.web"])
    }

    func testGrantsLevelAndAddSchema() async throws {
        apps.grants["app.acme.shop.web"] = [
            SchemaGrant(schemaId: "b-profile", permissions: "C,R", tables: [:]),
            SchemaGrant(schemaId: "b-gone", permissions: "R", tables: [:])
        ]
        let level = try await rail.level(["app.acme.shop.web", "grants"])
        XCTAssertEqual(level.id, "application-grants:app.acme.shop.web")
        XCTAssertEqual(level.title, "Bucket permissions")
        XCTAssertEqual(level.items.map(\.label), ["Profile Basics", "(deleted schema)"])
        XCTAssertEqual(level.items.map(\.sublabel), ["Create, Read", "Read"])
        XCTAssertEqual(level.emptyMessage, "No schemas granted.")
        XCTAssertEqual(level.createAction?.title, "Add schema")

        let spec = topic.addSchemaSpec(
            applicationID: "app.acme.shop.web", ecosystem: .fixture(),
            ungranted: [.fixture(id: "b-orders", name: "Orders")]
        )
        guard case .select(let select) = spec.fields[0] else { return XCTFail("expected select") }
        XCTAssertEqual(select.options.map(\.value), ["b-orders"])
        let state = FormState(spec: spec)
        state.set(.string("b-orders"), for: "schemaId")
        let added = await state.save()
        XCTAssertTrue(added)
        XCTAssertEqual(apps.grantWrites.last?.grants.map(\.schemaId), ["b-profile", "b-gone", "b-orders"])
        XCTAssertEqual(apps.grantWrites.last?.grants.last?.permissions, "R")

        let none = FormState(
            spec: topic.addSchemaSpec(applicationID: "app.acme.shop.web", ecosystem: .fixture(), ungranted: [])
        )
        let noneSaved = await none.save()
        XCTAssertFalse(noneSaved)
        XCTAssertEqual(none.saveError, "No schemas defined yet. Create one in the Buckets section first.")
    }

    func testGrantLevelListsSchemaAndTables() async throws {
        apps.grants["app.acme.shop.web"] = [
            SchemaGrant(
                schemaId: "b-profile", permissions: "C,R",
                tables: ["t1": TableGrant(level: "table", permissions: "R")]
            )
        ]
        let level = try await rail.level(["app.acme.shop.web", "grants", "b-profile"])
        XCTAssertEqual(level.id, "application-grant:app.acme.shop.web:b-profile")
        XCTAssertEqual(level.title, "Profile Basics")
        XCTAssertEqual(level.items.map(\.id), ["schema", "contacts", "avatars"])
        XCTAssertEqual(level.items.map(\.label), ["Schema permissions", "Contacts", "Avatars"])
        XCTAssertEqual(level.items.map(\.sublabel), ["Create, Read", "Read", "No access"])
        XCTAssertEqual(level.emptyMessage, "This schema has no tables.")
    }

    func testSchemaPermissionsFormSavesAndRemoves() async throws {
        apps.grants["app.acme.shop.web"] = [SchemaGrant(schemaId: "b-profile", permissions: "C,R", tables: [:])]
        let (detail, form) = try await rail.form(["app.acme.shop.web", "grants", "b-profile", "schema"])
        XCTAssertEqual(detail.id, "application-grant:app.acme.shop.web:b-profile:schema")
        XCTAssertEqual(form.state.spec.fields.map(\.key), ["schema", "create", "read", "update", "delete"])
        XCTAssertEqual(form.state.value(for: "create"), .bool(true))
        XCTAssertEqual(form.state.value(for: "update"), .bool(false))
        form.state.set(.bool(true), for: "delete")
        let saved = await form.state.save()
        XCTAssertTrue(saved)
        XCTAssertEqual(apps.grants["app.acme.shop.web"]?.first?.permissions, "C,R,D")
        let remove = try XCTUnwrap(form.state.spec.actions.delete)
        XCTAssertEqual(remove.title, "Remove grant")
        XCTAssertEqual(
            remove.confirmationText,
            "Remove the \"Profile Basics\" grant? This application will lose access to its tables."
        )
        try await remove.perform()
        XCTAssertEqual(apps.grants["app.acme.shop.web"], [])
    }

    func testTablePermissionsFormCapsAndRemoves() async throws {
        apps.grants["app.acme.shop.web"] = [
            SchemaGrant(
                schemaId: "b-profile", permissions: "C,R",
                tables: ["t1": TableGrant(level: "table", permissions: "R")]
            )
        ]
        let (detail, form) = try await rail.form(["app.acme.shop.web", "grants", "b-profile", "contacts"])
        XCTAssertEqual(detail.id, "application-grant:app.acme.shop.web:b-profile:contacts")
        XCTAssertEqual(detail.title, "Contacts")
        XCTAssertEqual(form.state.spec.fields.map(\.key), ["level", "create", "read", "update", "delete"])
        XCTAssertEqual(form.state.value(for: "level"), .string("table"))
        form.state.set(.bool(true), for: "update")
        let exceeded = await form.state.save()
        XCTAssertFalse(exceeded)
        XCTAssertEqual(form.state.saveError, "\"Contacts\" can't exceed the schema's permissions.")
        form.state.set(.bool(false), for: "update")
        form.state.set(.string("row"), for: "level")
        let rowRejected = await form.state.save()
        XCTAssertFalse(rowRejected)
        XCTAssertEqual(form.state.saveError, ApplicationsTopic.rowLevelMessage)
        form.state.set(.string("table"), for: "level")
        form.state.set(.bool(true), for: "create")
        let tableSaved = await form.state.save()
        XCTAssertTrue(tableSaved)
        XCTAssertEqual(
            apps.grants["app.acme.shop.web"]?.first?.tables["t1"], TableGrant(level: "table", permissions: "C,R")
        )
        form.state.set(.bool(false), for: "create")
        form.state.set(.bool(false), for: "read")
        let emptied = await form.state.save()
        XCTAssertTrue(emptied)
        XCTAssertEqual(apps.grants["app.acme.shop.web"]?.first?.tables, [:])
    }

    func testTokensLevelCreateRevealAndRevoke() async throws {
        apps.tokens["app.acme.shop.web"] = [
            ApplicationToken(id: "tok-0", name: "Deploy", prefix: "apk_zz99", createdAt: "2026-09-04T10:00:00.000Z")
        ]
        let level = try await rail.level(["app.acme.shop.web", "tokens"])
        XCTAssertEqual(level.id, "application-tokens:app.acme.shop.web")
        XCTAssertEqual(level.title, "Access tokens")
        XCTAssertEqual(level.items.map(\.label), ["Deploy"])
        XCTAssertEqual(level.items[0].sublabel, "apk_zz99… · \(HubDates.display("2026-09-04T10:00:00.000Z"))")
        XCTAssertEqual(level.emptyMessage, "No tokens yet.")
        XCTAssertEqual(level.createAction?.title, "New token")

        let spec = topic.createTokenSpec(applicationID: "app.acme.shop.web")
        XCTAssertEqual(spec.fields.map(\.key), ["name"])
        let state = FormState(spec: spec)
        state.set(.string("CI deploy"), for: "name")
        let tokenCreated = await state.save()
        XCTAssertTrue(tokenCreated)
        XCTAssertEqual(apps.tokenCreates.map(\.name), ["CI deploy"])
        XCTAssertEqual(topic.revealedSecrets["tok-1"], "apk_ab12cd34ef56")

        let (revealed, form) = try await rail.form(["app.acme.shop.web", "tokens", "tok-1"])
        XCTAssertEqual(revealed.id, "application-token:tok-1")
        XCTAssertEqual(form.state.spec.fields.map(\.key), ["name", "prefix", "created", "token", "notice"])
        XCTAssertEqual(form.state.value(for: "token"), .string("apk_ab12cd34ef56"))
        XCTAssertEqual(form.state.value(for: "notice"), .string(ApplicationsTopic.revealMessage))

        // Navigating to a sibling token is navigating away: the one-shot reveal expires, as
        // "you won't be able to see it again" promises.
        let (_, older) = try await rail.form(["app.acme.shop.web", "tokens", "tok-0"])
        XCTAssertNil(topic.revealedSecrets["tok-1"])
        let (_, backAgain) = try await rail.form(["app.acme.shop.web", "tokens", "tok-1"])
        XCTAssertEqual(backAgain.state.spec.fields.map(\.key), ["name", "prefix", "created"])
        XCTAssertEqual(backAgain.state.value(for: "token"), .null)
        XCTAssertEqual(older.state.spec.fields.map(\.key), ["name", "prefix", "created"])
        XCTAssertEqual(older.state.value(for: "prefix"), .string("apk_zz99…"))
        let revoke = try XCTUnwrap(older.state.spec.actions.delete)
        XCTAssertEqual(revoke.title, "Revoke token")
        XCTAssertEqual(revoke.confirmationText, "Revoke token \"Deploy\"? Applications using it will lose access.")
        try await revoke.perform()
        XCTAssertEqual(apps.tokenRevokes.map(\.tokenID), ["tok-0"])
    }

    func testFailuresSurfaceAsHubError() async throws {
        apps.failure = .unauthorized
        do {
            _ = try await rail.child([]); XCTFail("expected throw")
        } catch let error as HubError {
            XCTAssertEqual(error, .unauthorized)
        }
    }
}
