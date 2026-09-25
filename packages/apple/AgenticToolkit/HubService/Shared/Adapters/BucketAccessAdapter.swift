import AgenticToolkitHub
import Foundation
import HTTPTypes

/// `/bucket/access-groups` — access lists, their members and their grants.
@MainActor
public final class BucketAccessAdapter: BucketAccessDataSource {
    private struct GroupList: Decodable { let accessGroups: [AccessGroup] }

    private let api: HubAPI
    private let workspace: HubWorkspace

    public init(environment: HubEnvironment, workspace: HubWorkspace) {
        api = HubAPI(environment: environment)
        self.workspace = workspace
    }

    public func groups() async throws -> [AccessGroup] {
        try await api.get("/bucket/access-groups", query: workspace.query, as: GroupList.self).accessGroups
    }

    public func detail(id: String) async throws -> AccessGroupDetail {
        try await api.get("/bucket/access-groups/\(id)", query: workspace.query, as: AccessGroupDetail.self)
    }

    public func create(bucketID: String, _ body: AccessGroupCreate) async throws -> AccessGroup {
        try await api.send(
            .post, "/bucket/buckets/\(bucketID)/access-groups", query: workspace.query, body: body, as: AccessGroup.self
        )
    }

    public func update(id: String, _ body: AccessGroupUpdate) async throws -> AccessGroup {
        try await api.send(
            .patch, "/bucket/access-groups/\(id)", query: workspace.query, body: body, as: AccessGroup.self
        )
    }

    public func delete(id: String) async throws {
        try await api.send(.delete, "/bucket/access-groups/\(id)", query: workspace.query)
    }

    public func addMember(groupID: String, _ body: AccessMemberAdd) async throws -> AccessGroupMember {
        try await api.send(
            .post, "/bucket/access-groups/\(groupID)/members",
            query: workspace.query, body: body, as: AccessGroupMember.self
        )
    }

    public func removeMember(groupID: String, memberRowID: String) async throws {
        try await api.send(.delete, "/bucket/access-groups/\(groupID)/members/\(memberRowID)", query: workspace.query)
    }

    public func upsertGrant(groupID: String, _ body: AccessGrantUpsert) async throws -> AccessGrant {
        try await api.send(
            .put, "/bucket/access-groups/\(groupID)/grants", query: workspace.query, body: body, as: AccessGrant.self
        )
    }

    public func removeGrant(groupID: String, grantID: String) async throws {
        try await api.send(.delete, "/bucket/access-groups/\(groupID)/grants/\(grantID)", query: workspace.query)
    }
}
