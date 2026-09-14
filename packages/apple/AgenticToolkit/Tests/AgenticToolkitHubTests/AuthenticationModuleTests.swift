import AgenticToolkitHTDV
import XCTest
@testable import AgenticToolkitHub

final class FakeApiTokensDataSource: ApiTokensDataSource, @unchecked Sendable {
    var tokens: [ApiToken]
    var catalogue: [String]? = ["research", "notebook"]
    var creates: [ApiTokenCreate] = []
    var revoked: [String] = []
    var failure: Error?
    init(tokens: [ApiToken] = []) { self.tokens = tokens }
    func list() async throws -> [ApiToken] { if let failure { throw failure }; return tokens }
    func scopes() async throws -> [String] {
        if let failure { throw failure }
        guard let catalogue else { throw HubError.transport("HTTP 503") }
        return catalogue
    }
    func create(_ body: ApiTokenCreate) async throws -> ApiTokenCreated {
        if let failure { throw failure }
        let newID = "api-\(tokens.count + 1)"
        creates.append(body)
        let created = ApiTokenCreated(
            id: newID, name: body.name, prefix: "tmp_ab12", createdAt: "2026-09-04T00:00:00.000Z",
            expiresAt: body.expiresAt, scope: body.scope, token: "tmp_ab12cd34ef56"
        )
        tokens.append(ApiToken(
            id: created.id, name: created.name, prefix: created.prefix, createdAt: created.createdAt,
            expiresAt: created.expiresAt, scope: created.scope
        ))
        return created
    }
    func revoke(id: String) async throws {
        if let failure { throw failure }
        revoked.append(id)
        tokens.removeAll { $0.id == id }
    }
}

@MainActor
final class AuthenticationModuleTests: XCTestCase {
    private var api = FakeApiTokensDataSource(tokens: [
        ApiToken(
            id: "api-1", name: "research-agent", prefix: "tmp_ab12", createdAt: "2026-09-01T00:00:00.000Z",
            scope: ["research", "notebook:read"]
        ),
        ApiToken(
            id: "api-2", name: "legacy-cli", prefix: "tmp_cd34", createdAt: "2026-08-01T00:00:00.000Z",
            expiresAt: "2027-01-01T00:00:00.000Z", lastUsedAt: "2026-09-02T00:00:00.000Z"
        )
    ])
    private var storage = FakeStorageTokensDataSource(tokens: [.fixture()])
    private lazy var module = AuthenticationModule(apiTokens: api, storageTokens: storage)

    private func item(_ id: String) -> HTDVItem { HTDVItem(id: id, label: id) }

    func testRootLevel() async throws {
        let root = try await module.rootLevel()
        XCTAssertEqual(root.id, "token-sections")
        XCTAssertEqual(root.title, "Tokens")
        XCTAssertEqual(root.items.map(\.id), ["api", "storage", "about"])
        XCTAssertEqual(root.items.map(\.leadsTo), [.list, .list, .detail])
        XCTAssertTrue(root.items[1].dividerAfter)
        XCTAssertNil(root.createAction)
    }

    func testAboutNotice() async throws {
        guard case .detail(let detail) = try await module.child(for: [item("about")]) else {
            return XCTFail("expected detail")
        }
        XCTAssertEqual(detail.id, "tokens-about")
        // swiftlint:disable:next force_cast
        let form = detail.make() as! FormViewController
        XCTAssertEqual(form.state.value(for: "notice"), .string(AuthenticationModule.overviewMessage))
    }

    func testApiTokensLevel() async throws {
        guard case .level(let level) = try await module.child(for: [item("api")]) else {
            return XCTFail("expected level")
        }
        XCTAssertEqual(level.id, "api-tokens-list")
        XCTAssertEqual(level.title, "API tokens")
        XCTAssertEqual(level.items.map(\.label), ["legacy-cli", "research-agent"])
        XCTAssertEqual(level.items[0].sublabel, "tmp_cd34… · legacy")
        XCTAssertEqual(level.items[1].sublabel, "tmp_ab12… · research, notebook:read")
        XCTAssertEqual(level.items[0].systemImage, "key")
        XCTAssertEqual(level.emptyMessage, "No API tokens yet.")
        XCTAssertEqual(level.createAction?.title, "New API token")
    }

    func testApiTokenCreateSpecBuildsScopeAndReveals() async throws {
        let state = FormState(
            spec: module.apiTokens.createSpec(scopes: ["research", "notebook"]),
            values: ["scopeHelp": .string(ApiTokensRail.scopeHelp)]
        )
        XCTAssertEqual(
            state.spec.fields.map(\.key),
            ["name", "scopeHelp", "scope:research", "scope:notebook", "readOnly", "expiresAt"]
        )
        XCTAssertEqual(state.value(for: "scopeHelp"), .string(ApiTokensRail.scopeHelp))
        let missingNameSaved = await state.save()
        XCTAssertFalse(missingNameSaved)
        XCTAssertEqual(state.errors["name"], "Name is required")
        state.set(.string("nightly"), for: "name")
        // Read-only with no scope ticked used to mint an unscoped LEGACY token — the broadest of all —
        // while the admin believed they had minted the narrowest.
        state.set(.bool(true), for: "readOnly")
        let noScopeSaved = await state.save()
        XCTAssertFalse(noScopeSaved)
        XCTAssertEqual(state.saveError, ApiTokensRail.noScopeSelectedMessage)
        XCTAssertTrue(api.creates.isEmpty)
        state.set(.bool(true), for: "scope:research")
        let validSaved = await state.save()
        XCTAssertTrue(validSaved)
        XCTAssertEqual(api.creates.last, ApiTokenCreate(name: "nightly", expiresAt: nil, scope: ["research:read"]))
        XCTAssertEqual(module.apiTokens.revealedSecrets["api-1"], nil)
        XCTAssertEqual(module.apiTokens.revealedSecrets["api-3"], "tmp_ab12cd34ef56")

        guard case .detail(let detail) = try await module.child(for: [item("api"), item("api-3")]) else {
            return XCTFail("expected detail")
        }
        // swiftlint:disable:next force_cast
        let form = detail.make() as! FormViewController
        XCTAssertEqual(
            form.state.spec.fields.map(\.key),
            ["name", "prefix", "scope", "created", "lastUsed", "expires", "token", "notice"]
        )
        XCTAssertEqual(form.state.value(for: "token"), .string("tmp_ab12cd34ef56"))
        XCTAssertEqual(form.state.value(for: "notice"), .string(ApplicationsTopic.revealMessage))

        // The reveal is one-shot: going back to the list drops the secret, so the notice
        // ("you won't be able to see it again") is true rather than aspirational.
        _ = try await module.child(for: [item("api")])
        XCTAssertNil(module.apiTokens.revealedSecrets["api-3"])
        guard case .detail(let again) = try await module.child(for: [item("api"), item("api-3")]) else {
            return XCTFail("expected detail")
        }
        // swiftlint:disable:next force_cast
        let reopened = again.make() as! FormViewController
        XCTAssertEqual(
            reopened.state.spec.fields.map(\.key),
            ["name", "prefix", "scope", "created", "lastUsed", "expires"]
        )
        XCTAssertEqual(reopened.state.value(for: "token"), .null)
    }

    func testScopeHelperTreatsEmptyAsLegacy() {
        XCTAssertNil(ApiTokensRail.scope(from: [:], prefixes: ["research"]))
        XCTAssertEqual(
            ApiTokensRail.scope(
                from: ["scope:research": .bool(true), "scope:notebook": .bool(true)],
                prefixes: ["research", "notebook"]
            ),
            ["research", "notebook"]
        )
        XCTAssertEqual(
            ApiTokensRail.scope(
                from: ["scope:notebook": .bool(true), "readOnly": .bool(true)],
                prefixes: ["research", "notebook"]
            ),
            ["notebook:read"]
        )
    }

    func testCatalogueUnavailableDisablesCreate() async throws {
        api.catalogue = nil
        guard case .level(let level) = try await module.child(for: [item("api")]) else {
            return XCTFail("expected level")
        }
        XCTAssertEqual(level.createAction?.title, "New API token")
        let spec = module.apiTokens.createSpec(scopes: nil)
        XCTAssertEqual(spec.fields.map(\.key), ["notice"])
        XCTAssertNil(spec.actions.save)
        let state = FormState(spec: spec, values: ["notice": .string(ApiTokensRail.catalogueUnavailableMessage)])
        XCTAssertFalse(state.canSave)
    }

    func testApiTokenDetailAndRevoke() async throws {
        guard case .detail(let detail) = try await module.child(for: [item("api"), item("api-2")]) else {
            return XCTFail("expected detail")
        }
        XCTAssertEqual(detail.id, "api-token:api-2")
        XCTAssertEqual(detail.title, "legacy-cli")
        // swiftlint:disable:next force_cast
        let form = detail.make() as! FormViewController
        XCTAssertEqual(
            form.state.spec.fields.map(\.key), ["name", "prefix", "scope", "created", "lastUsed", "expires"]
        )
        XCTAssertEqual(form.state.value(for: "scope"), .string("legacy (curated-only)"))
        XCTAssertEqual(form.state.value(for: "lastUsed"), .string(HubDates.display("2026-09-02T00:00:00.000Z")))
        XCTAssertEqual(form.state.value(for: "expires"), .string(HubDates.display("2027-01-01T00:00:00.000Z")))
        XCTAssertNil(form.state.spec.actions.save)
        XCTAssertEqual(form.state.spec.actions.delete?.title, "Revoke token")
        XCTAssertEqual(
            form.state.spec.actions.delete?.confirmationText,
            "Revoke API token \"legacy-cli\"? Anything using it will stop working."
        )
        try await form.state.spec.actions.delete?.perform()
        XCTAssertEqual(api.revoked, ["api-2"])

        guard case .detail(let scoped) = try await module.child(for: [item("api"), item("api-1")]) else {
            return XCTFail("expected detail")
        }
        // swiftlint:disable:next force_cast
        let scopedForm = scoped.make() as! FormViewController
        XCTAssertEqual(scopedForm.state.value(for: "scope"), .string("research\nnotebook:read"))
        XCTAssertEqual(scopedForm.state.value(for: "lastUsed"), .string("never used"))
        XCTAssertEqual(scopedForm.state.value(for: "expires"), .string("never"))
    }

    func testStorageSectionUsesSharedRail() async throws {
        guard case .level(let level) = try await module.child(for: [item("storage")]) else {
            return XCTFail("expected level")
        }
        XCTAssertEqual(level.id, "storage-tokens-list")
        XCTAssertEqual(level.title, "Storage tokens")
        XCTAssertEqual(level.items.map(\.id), ["tok-1"])
        XCTAssertEqual(storage.listedEcosystems, [nil])
        guard case .detail(let detail) = try await module.child(for: [item("storage"), item("tok-1")]) else {
            return XCTFail("expected detail")
        }
        XCTAssertEqual(detail.id, "storage-token:tok-1")
    }

    func testUnknownPathsAreEmpty() async throws {
        guard case .empty = try await module.child(for: [item("nope")]) else {
            return XCTFail("expected .empty")
        }
        guard case .empty = try await module.child(for: [item("api"), item("api-404")]) else {
            return XCTFail("expected .empty")
        }
        guard case .empty = try await module.child(for: [item("about"), item("x")]) else {
            return XCTFail("expected .empty")
        }
    }
}
