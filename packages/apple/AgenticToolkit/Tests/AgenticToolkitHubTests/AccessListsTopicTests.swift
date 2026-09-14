import AgenticToolkitHTDV
import XCTest
@testable import AgenticToolkitHub

final class FakeBucketAccessDataSource: BucketAccessDataSource, @unchecked Sendable {
    var groups: [AccessGroup]
    var members: [String: [AccessGroupMember]]
    var grants: [String: [AccessGrant]]
    var creates: [(bucketID: String, body: AccessGroupCreate)] = []
    var updates: [(id: String, body: AccessGroupUpdate)] = []
    var deleted: [String] = []
    var memberAdds: [(groupID: String, body: AccessMemberAdd)] = []
    var memberRemovals: [(groupID: String, rowID: String)] = []
    var grantUpserts: [(groupID: String, body: AccessGrantUpsert)] = []
    var grantRemovals: [(groupID: String, grantID: String)] = []
    var failure: Error?

    init(groups: [AccessGroup], members: [String: [AccessGroupMember]] = [:], grants: [String: [AccessGrant]] = [:]) {
        self.groups = groups; self.members = members; self.grants = grants
    }
    private func check() throws { if let failure { throw failure } }

    func groups() async throws -> [AccessGroup] { try check(); return groups }
    func detail(id: String) async throws -> AccessGroupDetail {
        try check()
        guard let group = groups.first(where: { $0.id == id }) else { throw HubError.notFound }
        return AccessGroupDetail(group: group, members: members[id] ?? [], grants: grants[id] ?? [])
    }
    func create(bucketID: String, _ body: AccessGroupCreate) async throws -> AccessGroup {
        try check(); creates.append((bucketID, body))
        let group = AccessGroup(
            id: "g-\(groups.count + 1)", ecosystemId: "org.acme.shop", bucketId: bucketID,
            name: body.name, description: body.description ?? ""
        )
        groups.append(group); return group
    }
    func update(id: String, _ body: AccessGroupUpdate) async throws -> AccessGroup {
        try check(); updates.append((id, body))
        guard var group = groups.first(where: { $0.id == id }) else { throw HubError.notFound }
        if let name = body.name { group.name = name }
        if let description = body.description { group.description = description }
        return group
    }
    func delete(id: String) async throws { try check(); deleted.append(id); groups.removeAll { $0.id == id } }
    func addMember(groupID: String, _ body: AccessMemberAdd) async throws -> AccessGroupMember {
        try check(); memberAdds.append((groupID, body))
        let member = AccessGroupMember(
            id: "m-\(memberAdds.count)", ecosystemId: "org.acme.shop", accessGroupId: groupID,
            memberType: body.memberType.rawValue, memberId: body.memberId
        )
        members[groupID, default: []].append(member); return member
    }
    func removeMember(groupID: String, memberRowID: String) async throws {
        try check(); memberRemovals.append((groupID, memberRowID)); members[groupID]?.removeAll { $0.id == memberRowID }
    }
    func upsertGrant(groupID: String, _ body: AccessGrantUpsert) async throws -> AccessGrant {
        try check(); grantUpserts.append((groupID, body))
        let grant = AccessGrant(
            id: "gr-\(grantUpserts.count)", ecosystemId: "org.acme.shop", accessGroupId: groupID,
            targetType: body.targetType.rawValue, targetId: body.targetId, crud: body.crud
        )
        grants[groupID, default: []].append(grant); return grant
    }
    func removeGrant(groupID: String, grantID: String) async throws {
        try check(); grantRemovals.append((groupID, grantID)); grants[groupID]?.removeAll { $0.id == grantID }
    }
}

@MainActor
final class AccessListsTopicTests: XCTestCase {
    private let everyone = AccessGroup(
        id: "g-everyone", ecosystemId: "org.acme.shop", bucketId: "b-profile", name: "everyone", kind: "everyone"
    )
    private let editors = AccessGroup(
        id: "g-editors", ecosystemId: "org.acme.shop", bucketId: "b-profile", name: "Editors",
        description: "Can edit profiles"
    )
    private let auditors = AccessGroup(
        id: "g-auditors", ecosystemId: "org.acme.shop", bucketId: "b-audit", name: "Auditors"
    )
    private let foreign = AccessGroup(
        id: "g-foreign", ecosystemId: "org.other", bucketId: "b-other", name: "Other"
    )

    private lazy var access = FakeBucketAccessDataSource(
        groups: [editors, foreign, auditors, everyone],
        members: ["g-editors": [
            AccessGroupMember(
                id: "m-1", ecosystemId: "org.acme.shop", accessGroupId: "g-editors",
                memberType: "user", memberId: "user.ada"
            )
        ]],
        grants: ["g-editors": [
            AccessGrant(
                id: "gr-1", ecosystemId: "org.acme.shop", accessGroupId: "g-editors",
                targetType: "bucket", targetId: "b-profile", crud: "R"
            ),
            AccessGrant(
                id: "gr-2", ecosystemId: "org.acme.shop", accessGroupId: "g-editors",
                targetType: "bucket_type", targetId: "t-1", crud: "C,R,U"
            )
        ]])
    private lazy var buckets = FakeBucketsDataSource(
        buckets: [.fixture(id: "b-profile", name: "Profile Basics"), .fixture(id: "b-audit", name: "Audit Log")],
        tables: [BucketTable(id: "t-1", bucketId: "b-profile", sqlTableName: "names", name: "Names"),
                 BucketTable(id: "t-2", bucketId: "b-profile", sqlTableName: "avatars", name: "Avatars")])
    private lazy var topic = AccessListsTopic(dataSource: access, buckets: buckets)
    private lazy var rail = SingleTopicRail(topic: topic)

    func testEntry() {
        XCTAssertEqual(AccessListsTopic.entry.id, "access")
        XCTAssertEqual(AccessListsTopic.entry.label, "Access")
        XCTAssertEqual(AccessListsTopic.entry.leadsTo, .list)
    }

    func testListFiltersAndSorts() async throws {
        let level = try await rail.level([])
        XCTAssertEqual(level.id, "access-list:org.acme.shop")
        XCTAssertEqual(level.title, "Access lists")
        XCTAssertEqual(level.items.map(\.id), ["g-auditors", "g-everyone", "g-editors"])
        XCTAssertEqual(level.items.map(\.label), ["Auditors", "Everyone", "Editors"])
        XCTAssertEqual(level.items.map(\.sublabel), ["Audit Log", "Profile Basics", "Profile Basics"])
        XCTAssertEqual(level.items[0].systemImage, "key")
        XCTAssertEqual(level.items[0].leadsTo, .list)
        XCTAssertEqual(level.emptyMessage, "No access lists yet.")
        XCTAssertEqual(level.createAction?.title, "New access list")
    }

    func testCreateSpecValidation() async throws {
        let spec = topic.createSpec(for: .fixture(), buckets: buckets.buckets, existing: access.groups)
        let state = FormState(spec: spec)
        XCTAssertEqual(state.spec.fields.map(\.key), ["bucketId", "name", "description"])
        guard case .select(let bucket) = state.spec.fields[0] else { return XCTFail("expected select") }
        XCTAssertEqual(bucket.options.map(\.title), ["Audit Log", "Profile Basics"])
        state.set(.string("Reviewers"), for: "name")
        let missingBucketSaved = await state.save()
        XCTAssertFalse(missingBucketSaved)
        XCTAssertEqual(state.saveError, "Choose a bucket.")
        state.set(.string("b-profile"), for: "bucketId")
        state.set(.string("editors"), for: "name")
        let duplicateSaved = await state.save()
        XCTAssertFalse(duplicateSaved)
        XCTAssertEqual(state.saveError, "An access list named \"editors\" already exists in that bucket.")
        state.set(.string("Reviewers"), for: "name")
        state.set(.string("Second pair of eyes"), for: "description")
        let validSaved = await state.save()
        XCTAssertTrue(validSaved)
        XCTAssertEqual(access.creates.last?.bucketID, "b-profile")
        XCTAssertEqual(
            access.creates.last?.body,
            AccessGroupCreate(name: "Reviewers", description: "Second pair of eyes")
        )
    }

    func testCreateConflictMessage() async throws {
        access.failure = HubError.conflict("dup")
        let state = FormState(spec: topic.createSpec(for: .fixture(), buckets: buckets.buckets, existing: []))
        state.set(.string("b-profile"), for: "bucketId")
        state.set(.string("Editors"), for: "name")
        let saved = await state.save()
        XCTAssertFalse(saved)
        XCTAssertEqual(state.saveError, "An access list named \"Editors\" already exists.")
    }

    func testGroupLevel() async throws {
        let level = try await rail.level(["g-editors"])
        XCTAssertEqual(level.id, "access-group:g-editors")
        XCTAssertEqual(level.title, "Editors")
        XCTAssertEqual(level.items.map(\.id), ["settings", "members", "grants"])
        XCTAssertEqual(level.items.map(\.leadsTo), [.detail, .list, .list])
        XCTAssertEqual(level.items[1].sublabel, "1 member")
        XCTAssertEqual(level.items[2].sublabel, "2 grants")

        let everyoneLevel = try await rail.level(["g-everyone"])
        XCTAssertEqual(everyoneLevel.title, "Everyone")
        XCTAssertEqual(everyoneLevel.items[1].sublabel, "Applies to everyone")
    }

    func testSettingsDetailSaveAndDelete() async throws {
        let (detail, form) = try await rail.form(["g-editors", "settings"])
        XCTAssertEqual(detail.id, "access-group-settings:g-editors")
        XCTAssertEqual(detail.title, "Access list")
        XCTAssertEqual(form.state.spec.fields.map(\.key), ["bucket", "name", "description"])
        XCTAssertEqual(form.state.value(for: "bucket"), .string("Profile Basics"))
        form.state.set(.string("Profile editors"), for: "name")
        let saved = await form.state.save()
        XCTAssertTrue(saved)
        XCTAssertEqual(access.updates.last?.id, "g-editors")
        XCTAssertEqual(
            access.updates.last?.body,
            AccessGroupUpdate(name: "Profile editors", description: "Can edit profiles")
        )
        XCTAssertEqual(form.state.spec.actions.delete?.title, "Delete access list")
        XCTAssertEqual(
            form.state.spec.actions.delete?.confirmationText,
            "Delete access list \"Editors\"? Its members and grants will be removed."
        )
        try await form.state.spec.actions.delete?.perform()
        XCTAssertEqual(access.deleted, ["g-editors"])
    }

    func testEveryoneSettingsAreProtected() async throws {
        let (_, form) = try await rail.form(["g-everyone", "settings"])
        XCTAssertEqual(form.state.spec.fields.map(\.key), ["bucket", "name", "nameHelp", "description", "deleteNote"])
        XCTAssertFalse(form.state.spec.fields[1].isEditable)
        XCTAssertEqual(form.state.value(for: "nameHelp"), .string(AccessListsTopic.everyoneNameHelp))
        XCTAssertEqual(form.state.value(for: "deleteNote"), .string(AccessListsTopic.everyoneDeleteBlocked))
        XCTAssertNil(form.state.spec.actions.delete)
        form.state.set(.string("Applies to all"), for: "description")
        let saved = await form.state.save()
        XCTAssertTrue(saved)
        XCTAssertEqual(access.updates.last?.body, AccessGroupUpdate(name: nil, description: "Applies to all"))
    }

    func testMembersLevelAddAndRemove() async throws {
        let level = try await rail.level(["g-editors", "members"])
        XCTAssertEqual(level.id, "access-members:g-editors")
        XCTAssertEqual(level.items.map(\.label), ["user.ada"])
        XCTAssertEqual(level.items[0].sublabel, "User")
        XCTAssertEqual(level.items[0].systemImage, "person")
        XCTAssertEqual(level.emptyMessage, "No members yet.")
        XCTAssertEqual(level.createAction?.title, "Add member")

        let state = FormState(spec: topic.memberSpec(groupID: "g-editors"))
        XCTAssertEqual(state.spec.fields.map(\.key), ["memberType", "memberId"])
        state.set(.string("persona"), for: "memberType")
        state.set(.string("persona.me.ada"), for: "memberId")
        let addSaved = await state.save()
        XCTAssertTrue(addSaved)
        XCTAssertEqual(access.memberAdds.last?.body, AccessMemberAdd(memberType: .persona, memberId: "persona.me.ada"))

        access.failure = HubError.conflict("dup")
        let conflictSaved = await state.save()
        XCTAssertFalse(conflictSaved)
        XCTAssertEqual(state.saveError, "That member is already in this access list.")
        access.failure = nil

        let (detail, form) = try await rail.form(["g-editors", "members", "m-1"])
        XCTAssertEqual(detail.id, "access-member:m-1")
        XCTAssertEqual(detail.title, "user.ada")
        XCTAssertEqual(form.state.value(for: "type"), .string("User"))
        XCTAssertEqual(form.state.spec.actions.delete?.title, "Remove member")
        XCTAssertEqual(
            form.state.spec.actions.delete?.confirmationText,
            "Remove User \"user.ada\" from this access list?"
        )
        try await form.state.spec.actions.delete?.perform()
        XCTAssertEqual(access.memberRemovals.last?.rowID, "m-1")
    }

    func testEveryoneMembersIsNotice() async throws {
        let (detail, form) = try await rail.form(["g-everyone", "members"])
        XCTAssertEqual(detail.id, "access-members:g-everyone")
        XCTAssertEqual(form.state.value(for: "notice"), .string(AccessListsTopic.everyoneMembersMessage))
    }

    func testGrantsLevelLabels() async throws {
        let level = try await rail.level(["g-editors", "grants"])
        XCTAssertEqual(level.id, "access-grants:g-editors")
        XCTAssertEqual(level.items.map(\.label), ["Whole bucket", "Names"])
        XCTAssertEqual(level.items.map(\.sublabel), ["Read", "Create · Read · Update"])
        XCTAssertEqual(level.emptyMessage, "No grants yet.")
        XCTAssertEqual(level.createAction?.title, "Add grant")
    }

    func testGrantSpecOffersOnlyUngrantedTargets() async throws {
        let existing = access.grants["g-editors"] ?? []
        let spec = topic.grantSpec(group: editors, tables: buckets.tables, existing: existing)
        XCTAssertEqual(
            spec.fields.map(\.key),
            ["hint", "target", "bucketType", "rowId", "create", "read", "update", "delete"]
        )
        guard case .select(let target) = spec.fields[1], case .select(let type) = spec.fields[2] else {
            return XCTFail("expected selects")
        }
        XCTAssertEqual(target.options.map(\.value), ["bucket_type", "row"])
        XCTAssertEqual(type.options.map(\.title), ["Avatars"])
        XCTAssertEqual(AccessListsTopic.grantCreateValues, ["target": .string("row"), "read": .bool(true)])

        let state = FormState(spec: spec, values: AccessListsTopic.grantCreateValues)
        state.set(.string("bucket_type"), for: "target")
        let missingTypeSaved = await state.save()
        XCTAssertFalse(missingTypeSaved)
        XCTAssertEqual(state.saveError, "Choose a bucket type.")
        state.set(.string("row"), for: "target")
        let missingRowSaved = await state.save()
        XCTAssertFalse(missingRowSaved)
        XCTAssertEqual(state.saveError, "Enter a row id.")
        state.set(.string(String(repeating: "x", count: 37)), for: "rowId")
        let longRowSaved = await state.save()
        XCTAssertFalse(longRowSaved)
        XCTAssertEqual(state.saveError, "Row id must be 36 characters or fewer.")
        state.set(.string("row-9"), for: "rowId")
        state.set(.bool(false), for: "read")
        let noPermissionSaved = await state.save()
        XCTAssertFalse(noPermissionSaved)
        XCTAssertEqual(state.saveError, "Choose at least one permission.")
        state.set(.bool(true), for: "read")
        state.set(.bool(true), for: "update")
        let validSaved = await state.save()
        XCTAssertTrue(validSaved)
        XCTAssertEqual(
            access.grantUpserts.last?.body, AccessGrantUpsert(targetType: .row, targetId: "row-9", crud: "R,U")
        )
    }

    func testGrantDetailToggleAndRemove() async throws {
        let (detail, form) = try await rail.form(["g-editors", "grants", "gr-2"])
        XCTAssertEqual(detail.id, "access-grant:gr-2")
        XCTAssertEqual(detail.title, "Names")
        XCTAssertEqual(form.state.spec.fields.map(\.key), ["target", "create", "read", "update", "delete"])
        XCTAssertEqual(form.state.value(for: "target"), .string("Bucket type · Names"))
        XCTAssertEqual(form.state.value(for: "create"), .bool(true))
        XCTAssertEqual(form.state.value(for: "delete"), .bool(false))
        form.state.set(.bool(true), for: "delete")
        let toggleSaved = await form.state.save()
        XCTAssertTrue(toggleSaved)
        XCTAssertEqual(
            access.grantUpserts.last?.body,
            AccessGrantUpsert(targetType: .bucketType, targetId: "t-1", crud: "C,R,U,D")
        )

        form.state.set(.bool(false), for: "create"); form.state.set(.bool(false), for: "read")
        form.state.set(.bool(false), for: "update"); form.state.set(.bool(false), for: "delete")
        let removeSaved = await form.state.save()
        XCTAssertTrue(removeSaved)
        XCTAssertEqual(access.grantRemovals.last?.grantID, "gr-2")

        XCTAssertEqual(form.state.spec.actions.delete?.title, "Remove grant")
        XCTAssertEqual(form.state.spec.actions.delete?.confirmationText, "Remove the grant for Names?")
    }

    func testUnknownPathsAreEmpty() async throws {
        guard case .empty = try await rail.child(["nope"]) else { return XCTFail("expected .empty") }
        guard case .empty = try await rail.child(["g-editors", "other"]) else { return XCTFail("expected .empty") }
        guard case .empty = try await rail.child(["g-editors", "members", "m-404"]) else {
            return XCTFail("expected .empty")
        }
    }
}
