import AgenticToolkitHTDV
import XCTest
@testable import AgenticToolkitHub

// MARK: Fakes

final class FakeAuthSettingsDataSource: AuthSettingsDataSource, @unchecked Sendable {
    var settings = AuthSettings(signupMode: .inviteOnly, loginEnabled: true, allowedProviders: nil)
    var updates: [AuthSettingsUpdate] = []
    var failure: Error?
    func get(ecosystemID: String) async throws -> AuthSettings { if let failure { throw failure }; return settings }
    func update(ecosystemID: String, _ patch: AuthSettingsUpdate) async throws -> AuthSettings {
        if let failure { throw failure }
        updates.append(patch)
        if let mode = patch.signupMode { settings.signupMode = mode }
        if let login = patch.loginEnabled { settings.loginEnabled = login }
        return settings
    }
}

final class FakeSigninAppsDataSource: SigninAppsDataSource, @unchecked Sendable {
    var apps: [SigninApp]
    var creates: [SigninAppCreate] = []
    var updates: [(id: String, body: SigninAppUpdate)] = []
    var deleted: [String] = []
    var failure: Error?
    init(apps: [SigninApp] = []) { self.apps = apps }
    func list(ecosystemID: String) async throws -> [SigninApp] { if let failure { throw failure }; return apps }
    func create(ecosystemID: String, _ body: SigninAppCreate) async throws -> SigninApp {
        if let failure { throw failure }
        creates.append(body)
        let app = SigninApp(
            id: "app-\(body.slug)", slug: "shop.\(body.slug)", name: body.name,
            allowedReturnOrigins: body.allowedReturnOrigins,
            defaultEcosystemId: ecosystemID, githubEnabled: body.enableGithub)
        apps.append(app)
        return app
    }
    func update(ecosystemID: String, id: String, _ body: SigninAppUpdate) async throws -> SigninApp {
        if let failure { throw failure }
        updates.append((id, body))
        guard var app = apps.first(where: { $0.id == id }) else { throw HubError.notFound }
        if let name = body.name { app.name = name }
        if let origins = body.allowedReturnOrigins { app.allowedReturnOrigins = origins }
        if let github = body.githubEnabled { app.githubEnabled = github }
        return app
    }
    func delete(ecosystemID: String, id: String) async throws {
        if let failure { throw failure }
        deleted.append(id)
        apps.removeAll { $0.id == id }
    }
}

final class FakeFeatureFlagsDataSource: FeatureFlagsDataSource, @unchecked Sendable {
    var flags: [FeatureFlag]
    var creates: [FeatureFlagCreate] = []
    var updates: [(key: String, body: FeatureFlagUpdate)] = []
    var deleted: [String] = []
    var failure: Error?
    init(flags: [FeatureFlag] = []) { self.flags = flags }
    func list(ecosystemID: String) async throws -> [FeatureFlag] { if let failure { throw failure }; return flags }
    func create(ecosystemID: String, _ body: FeatureFlagCreate) async throws -> FeatureFlag {
        if let failure { throw failure }
        creates.append(body)
        let flag = FeatureFlag(key: body.key, enabled: body.enabled, description: body.description)
        flags.append(flag)
        return flag
    }
    func update(ecosystemID: String, key: String, _ body: FeatureFlagUpdate) async throws -> FeatureFlag {
        if let failure { throw failure }
        updates.append((key, body))
        guard var flag = flags.first(where: { $0.key == key }) else { throw HubError.notFound }
        if let enabled = body.enabled { flag.enabled = enabled }
        if let description = body.description { flag.description = description }
        return flag
    }
    func delete(ecosystemID: String, key: String) async throws {
        if let failure { throw failure }
        deleted.append(key)
        flags.removeAll { $0.key == key }
    }
}

final class FakeServerBagsDataSource: ServerBagsDataSource, @unchecked Sendable {
    var bags: [ServerBag]
    var creates: [ServerBagCreate] = []
    var updates: [(key: String, body: ServerBagUpdate)] = []
    var deleted: [String] = []
    var failure: Error?
    init(bags: [ServerBag] = []) { self.bags = bags }
    func list(ecosystemID: String) async throws -> [ServerBag] { if let failure { throw failure }; return bags }
    func create(ecosystemID: String, _ body: ServerBagCreate) async throws -> ServerBag {
        if let failure { throw failure }
        creates.append(body)
        let bag = ServerBag(key: body.key, value: body.value, description: body.description)
        bags.append(bag)
        return bag
    }
    func update(ecosystemID: String, key: String, _ body: ServerBagUpdate) async throws -> ServerBag {
        if let failure { throw failure }
        updates.append((key, body))
        guard var bag = bags.first(where: { $0.key == key }) else { throw HubError.notFound }
        if let value = body.value { bag.value = value }
        if let description = body.description { bag.description = description }
        return bag
    }
    func delete(ecosystemID: String, key: String) async throws {
        if let failure { throw failure }
        deleted.append(key)
        bags.removeAll { $0.key == key }
    }
}

final class FakeStorageTokensDataSource: StorageTokensDataSource, @unchecked Sendable {
    var tokens: [StorageToken]
    var creates: [(ecosystemID: String?, body: StorageTokenCreate)] = []
    var revoked: [(ecosystemID: String?, id: String)] = []
    var listedEcosystems: [String?] = []
    var failure: Error?
    init(tokens: [StorageToken] = []) { self.tokens = tokens }
    func list(ecosystemID: String?) async throws -> [StorageToken] {
        if let failure { throw failure }
        listedEcosystems.append(ecosystemID)
        return tokens
    }
    func create(ecosystemID: String?, _ body: StorageTokenCreate) async throws -> StorageTokenCreated {
        if let failure { throw failure }
        creates.append((ecosystemID, body))
        let created = StorageTokenCreated(
            id: "tok-\(body.name)", rdid: "token.acme.\(body.name)", slug: body.name,
            description: body.description ?? "",
            prefix: "adh_ab12", bucketRdid: "storage.acme.\(body.name)", token: "adh_ab12cd34ef56")
        tokens.append(StorageToken(
            id: created.id, slug: created.slug, description: created.description,
            prefix: created.prefix, rdid: created.rdid,
            bucketRdid: created.bucketRdid, expiresAt: body.expiresAt, createdAt: "2026-09-04T00:00:00.000Z"))
        return created
    }
    func revoke(ecosystemID: String?, id: String) async throws {
        if let failure { throw failure }
        revoked.append((ecosystemID, id))
        tokens.removeAll { $0.id == id }
    }
}

extension SigninApp {
    static func fixture(
        id: String = "app-1", leaf: String = "shop-web", name: String = "Shop web",
        origins: [String] = ["https://shop.acme.test"], github: Bool = true
    ) -> SigninApp {
        SigninApp(id: id, slug: "shop.\(leaf)", name: name, allowedReturnOrigins: origins,
                  defaultEcosystemId: "org.acme.shop", githubEnabled: github)
    }
}

extension StorageToken {
    static func fixture(
        id: String = "tok-1", slug: String = "ci-sync", lastUsedAt: String? = nil, expiresAt: String? = nil
    ) -> StorageToken {
        StorageToken(id: id, slug: slug, description: "Deploy sync", prefix: "adh_ab12",
                     rdid: "token.acme.\(slug)", bucketRdid: "storage.acme.\(slug)",
                     expiresAt: expiresAt, lastUsedAt: lastUsedAt, createdAt: "2026-09-01T00:00:00.000Z")
    }
}

// MARK: User Auth

@MainActor
final class AuthSettingsTopicTests: XCTestCase {
    private var data = FakeAuthSettingsDataSource()
    private lazy var rail = SingleTopicRail(topic: AuthSettingsTopic(dataSource: data))

    func testEntry() {
        XCTAssertEqual(AuthSettingsTopic.entry.id, "auth")
        XCTAssertEqual(AuthSettingsTopic.entry.label, "User Auth")
        XCTAssertEqual(AuthSettingsTopic.entry.leadsTo, .detail)
    }

    func testDetailShowsPolicy() async throws {
        let (detail, form) = try await rail.form([])
        XCTAssertEqual(detail.id, "auth-settings:org.acme.shop")
        XCTAssertEqual(detail.title, "User Auth")
        XCTAssertEqual(form.state.spec.fields.map(\.key), ["signupMode", "signupHelp", "loginEnabled"])
        XCTAssertEqual(form.state.value(for: "signupMode"), .string("invite_only"))
        XCTAssertEqual(
            form.state.value(for: "signupHelp"),
            .string("Only people you've invited can create an account."))
        XCTAssertEqual(form.state.value(for: "loginEnabled"), .bool(true))
        guard case .select(let mode) = form.state.spec.fields[0] else { return XCTFail("expected select") }
        XCTAssertEqual(mode.options.map(\.title), ["Open", "Invite only", "Closed"])
        XCTAssertNil(form.state.spec.actions.delete)
    }

    func testSaveSendsBothValues() async throws {
        let (_, form) = try await rail.form([])
        form.state.set(.string("closed"), for: "signupMode")
        form.state.set(.bool(false), for: "loginEnabled")
        let saved = await form.state.save()
        XCTAssertTrue(saved)
        XCTAssertEqual(data.updates, [AuthSettingsUpdate(signupMode: .closed, loginEnabled: false)])
    }

    func testUnknownPathIsEmpty() async throws {
        guard case .empty = try await rail.child(["x"]) else { return XCTFail("expected .empty") }
    }
}

// MARK: Sign-in apps

@MainActor
final class SigninAppsTopicTests: XCTestCase {
    private var data = FakeSigninAppsDataSource(apps: [
        .fixture(), .fixture(id: "app-2", leaf: "admin", name: "Admin console", origins: [], github: false)
    ])
    private lazy var topic = SigninAppsTopic(dataSource: data)
    private lazy var rail = SingleTopicRail(topic: topic)

    func testListSortedByName() async throws {
        let level = try await rail.level([])
        XCTAssertEqual(level.id, "signin-apps:org.acme.shop")
        XCTAssertEqual(level.title, "Sign-in apps")
        XCTAssertEqual(level.items.map(\.label), ["Admin console", "Shop web"])
        XCTAssertEqual(level.items[1].sublabel, "shop.shop-web")
        XCTAssertEqual(level.items[0].systemImage, "door.left.hand.open")
        XCTAssertEqual(level.emptyMessage, "No sign-in apps yet.")
        XCTAssertEqual(level.createAction?.title, "New sign-in app")
    }

    func testOriginValidation() {
        XCTAssertNil(SigninAppsTopic.validateOrigin("https://myapp.com"))
        XCTAssertNil(SigninAppsTopic.validateOrigin("http://localhost:3000"))
        XCTAssertEqual(SigninAppsTopic.validateOrigin("not a url"), "Return origin \"not a url\" is not a valid URL.")
        XCTAssertEqual(
            SigninAppsTopic.validateOrigin("ftp://files.example.com"),
            "Return origin \"ftp://files.example.com\" must be http(s).")
        XCTAssertEqual(
            SigninAppsTopic.validateOrigin("https://user:pw@example.com"),
            "Return origin \"https://user:pw@example.com\" must not include credentials.")
        XCTAssertEqual(
            SigninAppsTopic.validateOrigin("https://example.com/callback"),
            "Return origin \"https://example.com/callback\" must be just a scheme + host (no path).")
        XCTAssertEqual(SigninAppsTopic.canonicalOrigin("HTTPS://Example.com:8443/"), "https://example.com:8443")
        XCTAssertEqual(SigninAppsTopic.canonicalOrigin("https://example.com"), "https://example.com")
    }

    func testCreateSpecValidatesLeafAndDuplicates() async throws {
        let ecosystem = Ecosystem.fixture()
        let state = FormState(spec: topic.createSpec(for: ecosystem, existing: data.apps))
        XCTAssertEqual(state.spec.fields.map(\.key), ["name", "clientId"])
        state.set(.string("Kiosk"), for: "name")
        state.set(.string("Bad.Id"), for: "clientId")
        let firstSave = await state.save()
        XCTAssertFalse(firstSave)
        XCTAssertEqual(state.errors["clientId"], SigninAppsTopic.leafMessage)
        state.set(.string("shop-web"), for: "clientId")
        let secondSave = await state.save()
        XCTAssertFalse(secondSave)
        XCTAssertEqual(state.saveError, "App id \"shop-web\" is already in use.")
        state.set(.string("kiosk"), for: "clientId")
        let thirdSave = await state.save()
        XCTAssertTrue(thirdSave)
        XCTAssertEqual(
            data.creates,
            [SigninAppCreate(slug: "kiosk", name: "Kiosk", allowedReturnOrigins: [], enableGithub: false)])
    }

    func testCreateConflictMessage() async throws {
        data.failure = HubError.conflict("dup")
        let state = FormState(spec: topic.createSpec(for: .fixture(), existing: []))
        state.set(.string("Kiosk"), for: "name")
        state.set(.string("kiosk"), for: "clientId")
        let saved = await state.save()
        XCTAssertFalse(saved)
        XCTAssertEqual(state.saveError, "A sign-in app \"kiosk\" already exists in this ecosystem.")
    }

    func testDetailAndSave() async throws {
        let (detail, form) = try await rail.form(["app-1"])
        XCTAssertEqual(detail.id, "signin-app:app-1")
        XCTAssertEqual(detail.title, "Sign-in app")
        XCTAssertEqual(
            form.state.spec.fields.map(\.key), ["name", "slug", "githubEnabled", "allowedReturnOrigins", "startURL"])
        XCTAssertEqual(form.state.value(for: "slug"), .string("shop.shop-web"))
        XCTAssertEqual(form.state.value(for: "allowedReturnOrigins"), .stringSet(["https://shop.acme.test"]))
        XCTAssertEqual(form.state.value(for: "startURL"), .string(SigninAppsTopic.startURL(clientID: "shop.shop-web")))

        form.state.set(.stringSet(["https://Shop.acme.test/", "bogus"]), for: "allowedReturnOrigins")
        let firstSave = await form.state.save()
        XCTAssertFalse(firstSave)
        XCTAssertEqual(form.state.saveError, "Return origin \"bogus\" is not a valid URL.")
        form.state.set(.stringSet(["https://Shop.acme.test/", "https://kiosk.acme.test"]), for: "allowedReturnOrigins")
        form.state.set(.bool(false), for: "githubEnabled")
        let secondSave = await form.state.save()
        XCTAssertTrue(secondSave)
        XCTAssertEqual(data.updates.last?.id, "app-1")
        XCTAssertEqual(
            data.updates.last?.body,
            SigninAppUpdate(
                name: "Shop web",
                allowedReturnOrigins: ["https://shop.acme.test", "https://kiosk.acme.test"],
                githubEnabled: false))
    }

    func testDeleteConfirmation() async throws {
        let (_, form) = try await rail.form(["app-1"])
        XCTAssertEqual(form.state.spec.actions.delete?.title, "Delete sign-in app")
        XCTAssertEqual(
            form.state.spec.actions.delete?.confirmationText,
            "Delete sign-in app \"Shop web\"? Apps using it will stop signing in.")
        try await form.state.spec.actions.delete?.perform()
        XCTAssertEqual(data.deleted, ["app-1"])
    }

    func testUnknownAppIsEmpty() async throws {
        guard case .empty = try await rail.child(["nope"]) else { return XCTFail("expected .empty") }
    }
}

// MARK: Feature flags

@MainActor
final class FeatureFlagsTopicTests: XCTestCase {
    private var data = FakeFeatureFlagsDataSource(flags: [
        FeatureFlag(key: "new_checkout", enabled: true, description: "New checkout flow"),
        FeatureFlag(key: "dark_mode", enabled: false)
    ])
    private lazy var topic = FeatureFlagsTopic(dataSource: data)
    private lazy var rail = SingleTopicRail(topic: topic)

    func testListSortedByKey() async throws {
        let level = try await rail.level([])
        XCTAssertEqual(level.id, "feature-flags:org.acme.shop")
        XCTAssertEqual(level.items.map(\.id), ["dark_mode", "new_checkout"])
        XCTAssertEqual(level.items[0].sublabel, "Off")
        XCTAssertEqual(level.items[0].systemImage, "flag")
        XCTAssertEqual(level.items[1].sublabel, "On · New checkout flow")
        XCTAssertEqual(level.items[1].systemImage, "flag.fill")
        XCTAssertEqual(level.emptyMessage, "No feature flags yet.")
        XCTAssertEqual(level.createAction?.title, "New flag")
    }

    func testCreateSpec() async throws {
        let state = FormState(spec: topic.createSpec(for: .fixture(), existing: data.flags))
        XCTAssertEqual(state.spec.fields.map(\.key), ["key", "description", "enabled"])
        let firstSave = await state.save()
        XCTAssertFalse(firstSave)
        XCTAssertEqual(state.errors["key"], "Key is required")
        state.set(.string("dark_mode"), for: "key")
        let secondSave = await state.save()
        XCTAssertFalse(secondSave)
        XCTAssertEqual(state.saveError, "A flag named \"dark_mode\" already exists.")
        state.set(.string("beta_search"), for: "key")
        state.set(.bool(true), for: "enabled")
        let thirdSave = await state.save()
        XCTAssertTrue(thirdSave)
        XCTAssertEqual(data.creates, [FeatureFlagCreate(key: "beta_search", enabled: true, description: "")])
    }

    func testDetailSaveAndDelete() async throws {
        let (detail, form) = try await rail.form(["new_checkout"])
        XCTAssertEqual(detail.id, "feature-flag:org.acme.shop:new_checkout")
        XCTAssertEqual(detail.title, "new_checkout")
        XCTAssertEqual(form.state.spec.fields.map(\.key), ["key", "enabled", "description"])
        form.state.set(.bool(false), for: "enabled")
        let saved = await form.state.save()
        XCTAssertTrue(saved)
        XCTAssertEqual(data.updates.last?.key, "new_checkout")
        XCTAssertEqual(data.updates.last?.body, FeatureFlagUpdate(enabled: false, description: "New checkout flow"))

        XCTAssertEqual(form.state.spec.actions.delete?.title, "Delete flag")
        XCTAssertEqual(
            form.state.spec.actions.delete?.confirmationText,
            "\"new_checkout\" will be removed. Anything reading it falls back to its default.")
        try await form.state.spec.actions.delete?.perform()
        XCTAssertEqual(data.deleted, ["new_checkout"])
    }
}

// MARK: Server bags

@MainActor
final class ServerBagsTopicTests: XCTestCase {
    private var data = FakeServerBagsDataSource(bags: [
        ServerBag(key: "onboarding", value: .object(["maxItems": .number(20)]), description: "Onboarding limits")
    ])
    private lazy var topic = ServerBagsTopic(dataSource: data)
    private lazy var rail = SingleTopicRail(topic: topic)

    func testListShowsPreview() async throws {
        let level = try await rail.level([])
        XCTAssertEqual(level.id, "server-bags:org.acme.shop")
        XCTAssertEqual(level.items.map(\.label), ["onboarding"])
        XCTAssertEqual(level.items[0].sublabel, "{ \"maxItems\" : 20 }")
        XCTAssertEqual(level.items[0].systemImage, "shippingbox")
        XCTAssertEqual(level.createAction?.title, "New bag")
    }

    func testCreateSpecRequiresValidJSON() async throws {
        let state = FormState(spec: topic.createSpec(for: .fixture(), existing: data.bags))
        XCTAssertEqual(state.spec.fields.map(\.key), ["key", "value", "description"])
        state.set(.string("limits"), for: "key")
        state.set(.string("{oops"), for: "value")
        let firstSave = await state.save()
        XCTAssertFalse(firstSave)
        XCTAssertNotNil(state.errors["value"])
        state.set(.string("onboarding"), for: "key")
        state.set(.string("true"), for: "value")
        let secondSave = await state.save()
        XCTAssertFalse(secondSave)
        XCTAssertEqual(state.saveError, "A bag named \"onboarding\" already exists.")
        state.set(.string("limits"), for: "key")
        let thirdSave = await state.save()
        XCTAssertTrue(thirdSave)
        XCTAssertEqual(data.creates, [ServerBagCreate(key: "limits", value: .bool(true), description: "")])
    }

    func testDetailSaveAndDelete() async throws {
        let (detail, form) = try await rail.form(["onboarding"])
        XCTAssertEqual(detail.id, "server-bag:org.acme.shop:onboarding")
        XCTAssertEqual(form.state.spec.fields.map(\.key), ["key", "value", "description"])
        XCTAssertEqual(form.state.value(for: "value"), .string(JSONValue.object(["maxItems": .number(20)]).prettyText))
        form.state.set(.string(#"{"maxItems": 50}"#), for: "value")
        let saved = await form.state.save()
        XCTAssertTrue(saved)
        XCTAssertEqual(
            data.updates.last?.body,
            ServerBagUpdate(value: .object(["maxItems": .int(50)]), description: "Onboarding limits"))

        XCTAssertEqual(form.state.spec.actions.delete?.title, "Delete bag")
        XCTAssertEqual(
            form.state.spec.actions.delete?.confirmationText,
            "\"onboarding\" will be removed. Anything reading it falls back to its default.")
        try await form.state.spec.actions.delete?.perform()
        XCTAssertEqual(data.deleted, ["onboarding"])
    }
}

// MARK: Storage tokens

@MainActor
final class StorageTokensTopicTests: XCTestCase {
    private var data = FakeStorageTokensDataSource(tokens: [
        .fixture(),
        .fixture(id: "tok-2", slug: "backup",
                lastUsedAt: "2026-09-02T00:00:00.000Z", expiresAt: "2027-01-01T00:00:00.000Z")
    ])
    private lazy var topic = StorageTokensTopic(dataSource: data)
    private lazy var rail = SingleTopicRail(topic: topic)

    func testEntry() {
        XCTAssertEqual(StorageTokensTopic.entry.id, "tokens")
        XCTAssertEqual(StorageTokensTopic.entry.label, "Storage Access Tokens")
    }

    func testListScopedToEcosystem() async throws {
        let level = try await rail.level([])
        XCTAssertEqual(level.id, "storage-tokens:org.acme.shop")
        XCTAssertEqual(level.title, "Storage Access Tokens")
        XCTAssertEqual(level.items.map(\.label), ["token.acme.backup", "token.acme.ci-sync"])
        XCTAssertEqual(level.items[1].sublabel, "adh_ab12… · storage.acme.ci-sync")
        XCTAssertEqual(level.items[0].systemImage, "externaldrive")
        XCTAssertEqual(level.emptyMessage, "No tokens yet.")
        XCTAssertEqual(level.createAction?.title, "New storage token")
        XCTAssertEqual(data.listedEcosystems, ["org.acme.shop"])
    }

    func testCreateSpecMintsAndRevealsSecret() async throws {
        let state = FormState(spec: topic.rail.createSpec(ecosystemID: "org.acme.shop"))
        XCTAssertEqual(state.spec.fields.map(\.key), ["about", "name", "description", "expiresAt"])
        XCTAssertEqual(
            StorageTokensRail.aboutText(ecosystemID: "org.acme.shop"),
            "A storage principal scoped to your account; its own empty bucket lives in this product's ecosystem.")
        state.set(.string("Bad Name"), for: "name")
        let firstSave = await state.save()
        XCTAssertFalse(firstSave)
        XCTAssertEqual(state.errors["name"], Slug.patternMessage)
        state.set(.string("nightly"), for: "name")
        state.set(.string("Nightly export"), for: "description")
        state.set(.date(HubDates.parse("2027-01-01T00:00:00.000Z")!), for: "expiresAt")
        let secondSave = await state.save()
        XCTAssertTrue(secondSave)
        XCTAssertEqual(data.creates.last?.ecosystemID, "org.acme.shop")
        XCTAssertEqual(
            data.creates.last?.body,
            StorageTokenCreate(
                name: "nightly", description: "Nightly export",
                expiresAt: "2027-01-01T00:00:00.000Z", ecosystemId: nil))
        XCTAssertEqual(topic.rail.revealedSecrets["tok-nightly"], "adh_ab12cd34ef56")

        let (_, form) = try await rail.form(["tok-nightly"])
        XCTAssertEqual(
            form.state.spec.fields.map(\.key),
            ["name", "identifier", "prefix", "bucket", "description",
             "created", "lastUsed", "expires", "token", "notice"])
        XCTAssertEqual(form.state.value(for: "token"), .string("adh_ab12cd34ef56"))
        XCTAssertEqual(form.state.value(for: "notice"), .string(ApplicationsTopic.revealMessage))
    }

    func testCreateConflictMessage() async throws {
        data.failure = HubError.conflict("taken")
        let state = FormState(spec: topic.rail.createSpec(ecosystemID: "org.acme.shop"))
        state.set(.string("ci-sync"), for: "name")
        let saved = await state.save()
        XCTAssertFalse(saved)
        XCTAssertEqual(state.saveError, StorageTokensRail.nameTakenMessage)
    }

    func testDetailFactsAndRevoke() async throws {
        let (detail, form) = try await rail.form(["tok-1"])
        XCTAssertEqual(detail.id, "storage-token:tok-1")
        XCTAssertEqual(detail.title, "ci-sync")
        XCTAssertEqual(
            form.state.spec.fields.map(\.key),
            ["name", "identifier", "prefix", "bucket", "description", "created", "lastUsed", "expires"])
        XCTAssertEqual(form.state.value(for: "prefix"), .string("adh_ab12…"))
        XCTAssertEqual(form.state.value(for: "lastUsed"), .string("never used"))
        XCTAssertEqual(form.state.value(for: "expires"), .string("never"))
        XCTAssertNil(form.state.spec.actions.save)
        XCTAssertEqual(form.state.spec.actions.delete?.title, "Revoke token")
        XCTAssertEqual(
            form.state.spec.actions.delete?.confirmationText,
            "Revoke storage token \"ci-sync\"? Anything using it will lose access to its bucket.")
        try await form.state.spec.actions.delete?.perform()
        XCTAssertEqual(data.revoked.last?.ecosystemID, "org.acme.shop")
        XCTAssertEqual(data.revoked.last?.id, "tok-1")

        let (_, other) = try await rail.form(["tok-2"])
        XCTAssertEqual(other.state.value(for: "lastUsed"), .string(HubDates.display("2026-09-02T00:00:00.000Z")))
        XCTAssertEqual(other.state.value(for: "expires"), .string(HubDates.display("2027-01-01T00:00:00.000Z")))
    }

    func testRailWithoutEcosystemListsOwnTokens() async throws {
        let child = try await topic.rail.child(
            path: [], ecosystemID: nil, levelID: "storage-tokens-list", title: "Storage tokens")
        guard case .level(let level) = child else { return XCTFail("expected level") }
        XCTAssertEqual(level.id, "storage-tokens-list")
        XCTAssertEqual(level.title, "Storage tokens")
        XCTAssertEqual(data.listedEcosystems, [nil])
        XCTAssertEqual(
            StorageTokensRail.aboutText(ecosystemID: nil),
            "A storage principal scoped to your account; it gets its own empty bucket.")
    }
}
