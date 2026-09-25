import AgenticDeveloperHubClient
import AgenticToolkitHub
import Foundation
import HTTPTypes
import XCTest
@testable import AgenticToolkitHubService

@MainActor
final class AuthenticationAdaptersTests: XCTestCase {
    private var stub: StubClientTransport!
    private var environment: HubEnvironment!
    private let workspace = HubWorkspace(slug: "acme", name: "Acme", type: .organization)

    override func setUp() async throws {
        try await super.setUp()
        stub = StubClientTransport()
        let store = InMemorySessionStore(Session(credentials: Credentials(token: "jwt", kind: .jwt), refreshToken: "r"))
        environment = HubEnvironment(
            sessionStore: store,
            transportSource: StaticTransportSource(.direct(transport: stub)),
            initialTransport: .direct(transport: stub)
        )
    }

    // MARK: - API tokens

    func testListTokensDecodesBareArray() async throws {
        stub.on(
            .get, "/auth/tokens",
            json: #"""
            [{"id":"api-1","name":"research-agent","prefix":"tmp_ab12",
              "createdAt":"2026-09-01T00:00:00.000Z","scope":["research"]}]
            """#
        )
        let tokens = try await ApiTokensAdapter(environment: environment, workspace: workspace).list()
        XCTAssertEqual(tokens.map(\.name), ["research-agent"])
        XCTAssertEqual(tokens[0].scope, ["research"])
        XCTAssertEqual(stub.lastRequest(.get, "/auth/tokens")?.path, "/auth/tokens?workspace=acme")
    }

    func testScopesUnwrapsPrefixes() async throws {
        stub.on(.get, "/auth/tokens/scopes", json: #"{"prefixes":["research","notebook"]}"#)
        let scopes = try await ApiTokensAdapter(environment: environment, workspace: workspace).scopes()
        XCTAssertEqual(scopes, ["research", "notebook"])
        XCTAssertEqual(stub.lastRequest(.get, "/auth/tokens/scopes")?.path, "/auth/tokens/scopes?workspace=acme")
    }

    func testCreateTokenPostsBodyAndDecodesSecret() async throws {
        stub.on(
            .post, "/auth/tokens", status: 201,
            json: #"""
            {"id":"api-9","name":"nightly","prefix":"tmp_zz99","createdAt":"2026-09-04T00:00:00.000Z",
             "scope":["research:read"],"token":"tmp_zz99secret"}
            """#
        )
        let created = try await ApiTokensAdapter(environment: environment, workspace: workspace)
            .create(ApiTokenCreate(name: "nightly", scope: ["research:read"]))
        XCTAssertEqual(created.token, "tmp_zz99secret")
        let sent = try XCTUnwrap(stub.lastBody(.post, "/auth/tokens"))
        XCTAssertEqual(sent["name"] as? String, "nightly")
        XCTAssertEqual(sent["scope"] as? [String], ["research:read"])
        XCTAssertNil(sent["expiresAt"])
        XCTAssertEqual(stub.lastRequest(.post, "/auth/tokens")?.path, "/auth/tokens?workspace=acme")
    }

    func testRevokeTokenDeletes() async throws {
        stub.on(.delete, "/auth/tokens/api-1", status: 204, json: "")
        try await ApiTokensAdapter(environment: environment, workspace: workspace).revoke(id: "api-1")
        XCTAssertEqual(stub.lastRequest(.delete, "/auth/tokens/api-1")?.path, "/auth/tokens/api-1?workspace=acme")
    }

    // MARK: - Bucket access

    func testGroupsUnwrapsAccessGroups() async throws {
        stub.on(
            .get, "/bucket/access-groups",
            json: #"""
            {"accessGroups":[{"id":"g-1","ecosystemId":"org.acme.shop","bucketId":"b-profile",
             "name":"everyone","description":"","kind":"everyone"}]}
            """#
        )
        let groups = try await BucketAccessAdapter(environment: environment, workspace: workspace).groups()
        XCTAssertEqual(groups.map(\.id), ["g-1"])
        XCTAssertTrue(groups[0].isEveryone)
        XCTAssertEqual(stub.lastRequest(.get, "/bucket/access-groups")?.path, "/bucket/access-groups?workspace=acme")
    }

    func testDetailDecodesMembersAndGrants() async throws {
        stub.on(.get, "/bucket/access-groups/g-1", json: #"""
        {"id":"g-1","ecosystemId":"org.acme.shop","bucketId":"b-profile","name":"Editors",
         "description":"","kind":"custom",
         "members":[{"id":"m-1","ecosystemId":"org.acme.shop","accessGroupId":"g-1",
                     "memberType":"user","memberId":"user.ada"}],
         "grants":[{"id":"gr-1","ecosystemId":"org.acme.shop","accessGroupId":"g-1",
                    "targetType":"bucket","targetId":"b-profile","crud":"R"}]}
        """#)
        let detail = try await BucketAccessAdapter(environment: environment, workspace: workspace).detail(id: "g-1")
        XCTAssertEqual(detail.group.name, "Editors")
        XCTAssertEqual(detail.members.map(\.memberId), ["user.ada"])
        XCTAssertEqual(detail.grants.map(\.crud), ["R"])
        XCTAssertEqual(
            stub.lastRequest(.get, "/bucket/access-groups/g-1")?.path,
            "/bucket/access-groups/g-1?workspace=acme"
        )
    }

    func testCreateUpdateDeleteGroup() async throws {
        let adapter = BucketAccessAdapter(environment: environment, workspace: workspace)
        stub.on(
            .post, "/bucket/buckets/b-profile/access-groups", status: 201,
            json: #"""
            {"id":"g-2","ecosystemId":"org.acme.shop","bucketId":"b-profile","name":"Editors",
             "description":"","kind":"custom"}
            """#
        )
        let created = try await adapter.create(
            bucketID: "b-profile", AccessGroupCreate(name: "Editors", description: "Can edit")
        )
        XCTAssertEqual(created.id, "g-2")
        let sent = try XCTUnwrap(stub.lastBody(.post, "/bucket/buckets/b-profile/access-groups"))
        XCTAssertEqual(sent["name"] as? String, "Editors")
        XCTAssertEqual(sent["description"] as? String, "Can edit")
        XCTAssertEqual(
            stub.lastRequest(.post, "/bucket/buckets/b-profile/access-groups")?.path,
            "/bucket/buckets/b-profile/access-groups?workspace=acme"
        )

        stub.on(
            .patch, "/bucket/access-groups/g-2",
            json: #"""
            {"id":"g-2","ecosystemId":"org.acme.shop","bucketId":"b-profile","name":"Reviewers",
             "description":"","kind":"custom"}
            """#
        )
        let updated = try await adapter.update(id: "g-2", AccessGroupUpdate(name: "Reviewers"))
        XCTAssertEqual(updated.name, "Reviewers")
        let patch = try XCTUnwrap(stub.lastBody(.patch, "/bucket/access-groups/g-2"))
        XCTAssertEqual(patch["name"] as? String, "Reviewers")
        XCTAssertNil(patch["description"])
        XCTAssertEqual(
            stub.lastRequest(.patch, "/bucket/access-groups/g-2")?.path,
            "/bucket/access-groups/g-2?workspace=acme"
        )

        stub.on(.delete, "/bucket/access-groups/g-2", status: 204, json: "")
        try await adapter.delete(id: "g-2")
        XCTAssertEqual(
            stub.lastRequest(.delete, "/bucket/access-groups/g-2")?.path,
            "/bucket/access-groups/g-2?workspace=acme"
        )
    }

    func testMembersAddAndRemove() async throws {
        let adapter = BucketAccessAdapter(environment: environment, workspace: workspace)
        stub.on(
            .post, "/bucket/access-groups/g-1/members", status: 201,
            json: #"""
            {"id":"m-2","ecosystemId":"org.acme.shop","accessGroupId":"g-1",
             "memberType":"persona","memberId":"persona.me.ada"}
            """#
        )
        let member = try await adapter.addMember(
            groupID: "g-1", AccessMemberAdd(memberType: .persona, memberId: "persona.me.ada")
        )
        XCTAssertEqual(member.type, .persona)
        let sent = try XCTUnwrap(stub.lastBody(.post, "/bucket/access-groups/g-1/members"))
        XCTAssertEqual(sent["memberType"] as? String, "persona")
        XCTAssertEqual(sent["memberId"] as? String, "persona.me.ada")
        XCTAssertEqual(
            stub.lastRequest(.post, "/bucket/access-groups/g-1/members")?.path,
            "/bucket/access-groups/g-1/members?workspace=acme"
        )

        stub.on(.delete, "/bucket/access-groups/g-1/members/m-2", status: 204, json: "")
        try await adapter.removeMember(groupID: "g-1", memberRowID: "m-2")
        XCTAssertEqual(
            stub.lastRequest(.delete, "/bucket/access-groups/g-1/members/m-2")?.path,
            "/bucket/access-groups/g-1/members/m-2?workspace=acme"
        )
    }

    func testGrantsUpsertAndRemove() async throws {
        let adapter = BucketAccessAdapter(environment: environment, workspace: workspace)
        stub.on(
            .put, "/bucket/access-groups/g-1/grants",
            json: #"""
            {"id":"gr-2","ecosystemId":"org.acme.shop","accessGroupId":"g-1",
             "targetType":"bucket_type","targetId":"t-1","crud":"C,R"}
            """#
        )
        let grant = try await adapter.upsertGrant(
            groupID: "g-1", AccessGrantUpsert(targetType: .bucketType, targetId: "t-1", crud: "C,R")
        )
        XCTAssertEqual(grant.target, .bucketType)
        let sent = try XCTUnwrap(stub.lastBody(.put, "/bucket/access-groups/g-1/grants"))
        XCTAssertEqual(sent["targetType"] as? String, "bucket_type")
        XCTAssertEqual(sent["crud"] as? String, "C,R")
        XCTAssertEqual(
            stub.lastRequest(.put, "/bucket/access-groups/g-1/grants")?.path,
            "/bucket/access-groups/g-1/grants?workspace=acme"
        )

        stub.on(.delete, "/bucket/access-groups/g-1/grants/gr-2", status: 204, json: "")
        try await adapter.removeGrant(groupID: "g-1", grantID: "gr-2")
        XCTAssertEqual(
            stub.lastRequest(.delete, "/bucket/access-groups/g-1/grants/gr-2")?.path,
            "/bucket/access-groups/g-1/grants/gr-2?workspace=acme"
        )
    }

    func testConflictBecomesHubConflict() async throws {
        stub.on(.post, "/bucket/access-groups/g-1/members", status: 409, json: #"{"error":"already a member"}"#)
        do {
            _ = try await BucketAccessAdapter(environment: environment, workspace: workspace)
                .addMember(groupID: "g-1", AccessMemberAdd(memberType: .user, memberId: "user.ada"))
            XCTFail("expected conflict")
        } catch HubError.conflict {
            // expected
        }
        XCTAssertEqual(
            stub.lastRequest(.post, "/bucket/access-groups/g-1/members")?.path,
            "/bucket/access-groups/g-1/members?workspace=acme"
        )
    }
}
