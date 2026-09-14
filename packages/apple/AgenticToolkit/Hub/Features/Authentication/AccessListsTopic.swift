import AgenticToolkitHTDV
import Foundation

/// Product rail topic "Access": bucket access lists (groups), their members and their grants, as nested levels.
///
/// Paths are topic-relative: `[]` → all lists in this ecosystem; `[group]` → the group's sections;
/// `[group, settings]` → the settings form; `[group, members]` / `[group, members, row]`;
/// `[group, grants]` / `[group, grants, grant]`.
@MainActor
public final class AccessListsTopic: EcosystemTopicProvider {
    public static let entry = EcosystemTopicEntry(
        id: "access", label: "Access", systemImage: "lock.shield",
        description: "Who can read and write each bucket: access lists, their members and their grants.")

    public static let everyoneMembersMessage =
        "Applies to everyone — every principal in this ecosystem. Choose what they can do with grants below."
    public static let everyoneNameHelp =
        "The built-in \"everyone\" list applies to every principal and can't be renamed."
    public static let everyoneDeleteBlocked = "The \"everyone\" list is built in and can't be deleted."
    public static let grantHint = "Grants narrow downward: bucket ≥ type ≥ row."
    public static let grantCreateValues: [String: FormValue] = ["target": .string("row"), "read": .bool(true)]

    public let entry: EcosystemTopicEntry = AccessListsTopic.entry
    private let dataSource: BucketAccessDataSource
    private let buckets: BucketsDataSource

    public init(dataSource: BucketAccessDataSource, buckets: BucketsDataSource) {
        self.dataSource = dataSource
        self.buckets = buckets
    }

    public func child(for ecosystem: Ecosystem, path: [HTDVItem], rail _: EcosystemRail) async throws -> HTDVChild {
        let bucketList = try await HubError.wrap { try await self.buckets.list(ecosystemID: ecosystem.id) }
        let allGroups = try await HubError.wrap { try await self.dataSource.groups() }
        let groups = allGroups.filter { $0.ecosystemId == ecosystem.id }
        guard !path.isEmpty else { return .level(listLevel(ecosystem: ecosystem, groups: groups, buckets: bucketList)) }

        guard let group = groups.first(where: { $0.id == path[0].id }) else { return .empty }
        let bucket = bucketList.first { $0.id == group.bucketId }
        let detail = try await HubError.wrap { try await self.dataSource.detail(id: group.id) }
        let allTables = try await HubError.wrap { try await self.buckets.tables(ecosystemID: ecosystem.id) }
        let tables = allTables.filter { $0.bucketId == group.bucketId }

        let rest = path.dropFirst().map(\.id)
        switch (rest.first, rest.dropFirst().first, rest.count) {
        case (nil, _, _):
            return .level(groupLevel(detail: detail))
        case ("settings", nil, 1):
            return .detail(settingsDetail(group: detail.group, bucketName: bucket?.name ?? group.bucketId))
        case ("members", nil, 1):
            if detail.group.isEveryone {
                return .detail(FormDetails.notice(
                    id: "access-members:\(group.id)", title: "Members",
                    message: AccessListsTopic.everyoneMembersMessage
                ))
            }
            return .level(membersLevel(detail: detail))
        case ("members", let rowID?, 2):
            guard let member = detail.members.first(where: { $0.id == rowID }) else { return .empty }
            return .detail(memberDetail(member, groupID: group.id))
        case ("grants", nil, 1):
            return .level(grantsLevel(detail: detail, tables: tables))
        case ("grants", let grantID?, 2):
            guard let grant = detail.grants.first(where: { $0.id == grantID }) else { return .empty }
            return .detail(grantDetail(grant, groupID: group.id, tables: tables))
        default:
            return .empty
        }
    }

    // MARK: - Access lists

    private func listLevel(ecosystem: Ecosystem, groups: [AccessGroup], buckets: [Bucket]) -> HTDVLevel {
        let names = Dictionary(uniqueKeysWithValues: buckets.map { ($0.id, $0.name) })
        let sorted = groups.sorted { lhsGroup, rhsGroup in
            let lhsName = names[lhsGroup.bucketId] ?? lhsGroup.bucketId
            let rhsName = names[rhsGroup.bucketId] ?? rhsGroup.bucketId
            if lhsName != rhsName { return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending }
            if lhsGroup.isEveryone != rhsGroup.isEveryone { return lhsGroup.isEveryone }
            return lhsGroup.name.localizedCaseInsensitiveCompare(rhsGroup.name) == .orderedAscending
        }
        let items = sorted.map { group in
            HTDVItem(id: group.id, label: group.displayName, sublabel: names[group.bucketId] ?? group.bucketId,
                     systemImage: "key", leadsTo: .list)
        }
        let spec = createSpec(for: ecosystem, buckets: buckets, existing: groups)
        return HTDVLevel(id: "access-list:\(ecosystem.id)", title: "Access lists", items: items,
                         emptyMessage: "No access lists yet.",
                         createAction: HTDVCreateAction(title: "New access list") { presenter in
                             _ = await FormSheet.present(title: "New access list", spec: spec, from: presenter)
                         })
    }

    /// Create form: bucket (select), name, description. Duplicate names are rejected per bucket, case-insensitively.
    public func createSpec(for ecosystem: Ecosystem, buckets: [Bucket], existing: [AccessGroup]) -> FormSpec {
        let options = buckets.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { FormSelectOption(value: $0.id, title: $0.name) }
        return FormSpec(
            sections: [FormSection(fields: [
                .select(FormSelectField(key: "bucketId", label: "Bucket", options: options)),
                .text(FormTextField(key: "name", label: "Name", placeholder: "Editors", isRequired: true)),
                .textArea(FormTextAreaField(
                    key: "description", label: "Description", placeholder: "What this access list is for.",
                    minLines: 2
                ))
            ])],
            actions: FormActions(save: FormAction(id: "create", title: "Create") { [dataSource] values in
                guard let bucketID = HubText.nonBlank(values["bucketId"]?.stringValue) else {
                    throw HubError.validation("Choose a bucket.")
                }
                let name = values["name"]?.stringValue?.trimmingCharacters(in: .whitespaces) ?? ""
                let nameTaken = existing.contains {
                    $0.bucketId == bucketID && $0.name.caseInsensitiveCompare(name) == .orderedSame
                }
                if nameTaken {
                    throw HubError.validation("An access list named \"\(name)\" already exists in that bucket.")
                }
                do {
                    let body = AccessGroupCreate(
                        name: name, description: HubText.nonBlank(values["description"]?.stringValue)
                    )
                    _ = try await dataSource.create(bucketID: bucketID, body)
                } catch HubError.conflict {
                    throw HubError.validation("An access list named \"\(name)\" already exists.")
                } catch {
                    throw HubError.wrap(error)
                }
            }))
    }

    private func groupLevel(detail: AccessGroupDetail) -> HTDVLevel {
        let group = detail.group
        let memberCount = detail.members.count
        let items = [
            HTDVItem(id: "settings", label: "Access list", sublabel: "Name and description",
                     systemImage: "slider.horizontal.3", leadsTo: .detail),
            HTDVItem(id: "members", label: "Members",
                     sublabel: group.isEveryone
                        ? "Applies to everyone" : "\(memberCount) member\(memberCount == 1 ? "" : "s")",
                     systemImage: "person.2", leadsTo: .list),
            HTDVItem(id: "grants", label: "Grants",
                     sublabel: "\(detail.grants.count) grant\(detail.grants.count == 1 ? "" : "s")",
                     systemImage: "checkmark.shield", leadsTo: .list)
        ]
        return HTDVLevel(id: "access-group:\(group.id)", title: group.displayName, items: items,
                         emptyMessage: "", createAction: nil)
    }

    private func settingsDetail(group: AccessGroup, bucketName: String) -> HTDVDetail {
        var fields: [FormField] = [.readOnly(FormReadOnlyField(key: "bucket", label: "Bucket"))]
        var values: [String: FormValue] = [
            "bucket": .string(bucketName), "name": .string(group.name), "description": .string(group.description)
        ]
        if group.isEveryone {
            fields.append(.readOnly(FormReadOnlyField(key: "name", label: "Name")))
            fields.append(.readOnly(FormReadOnlyField(key: "nameHelp", label: "")))
            values["nameHelp"] = .string(AccessListsTopic.everyoneNameHelp)
        } else {
            fields.append(.text(FormTextField(key: "name", label: "Name", placeholder: "Editors", isRequired: true)))
        }
        fields.append(.textArea(FormTextAreaField(
            key: "description", label: "Description", placeholder: "What this access list is for.", minLines: 2
        )))
        if group.isEveryone {
            fields.append(.readOnly(FormReadOnlyField(key: "deleteNote", label: "")))
            values["deleteNote"] = .string(AccessListsTopic.everyoneDeleteBlocked)
        }
        let save = FormAction(id: "save", title: "Save") { [dataSource] values in
            let body = AccessGroupUpdate(
                name: group.isEveryone ? nil : values["name"]?.stringValue?.trimmingCharacters(in: .whitespaces),
                description: values["description"]?.stringValue ?? "")
            _ = try await HubError.wrap { try await dataSource.update(id: group.id, body) }
        }
        let delete: FormDeleteAction? = group.isEveryone ? nil : FormDeleteAction(
            title: "Delete access list",
            confirmationText: "Delete access list \"\(group.name)\"? Its members and grants will be removed."
        ) { [dataSource] in
            try await HubError.wrap { try await dataSource.delete(id: group.id) }
        }
        let spec = FormSpec(sections: [FormSection(fields: fields)], actions: FormActions(save: save, delete: delete))
        return FormDetails.form(
            id: "access-group-settings:\(group.id)", title: "Access list", spec: spec, values: values
        )
    }

    // MARK: - Members

    private func membersLevel(detail: AccessGroupDetail) -> HTDVLevel {
        let items = detail.members.map { member in
            HTDVItem(id: member.id, label: member.memberId, sublabel: member.typeTitle,
                     systemImage: member.type?.systemImage ?? "questionmark.circle", leadsTo: .detail)
        }
        let spec = memberSpec(groupID: detail.group.id)
        return HTDVLevel(id: "access-members:\(detail.group.id)", title: "Members", items: items,
                         emptyMessage: "No members yet.",
                         createAction: HTDVCreateAction(title: "Add member") { presenter in
                             _ = await FormSheet.present(title: "Add member", spec: spec, from: presenter)
                         })
    }

    /// Add-member form: type (select) + principal id (text).
    public func memberSpec(groupID: String) -> FormSpec {
        FormSpec(
            sections: [FormSection(fields: [
                .select(FormSelectField(
                    key: "memberType", label: "Type",
                    options: AccessMemberType.allCases.map { FormSelectOption(value: $0.rawValue, title: $0.title) },
                    isRequired: true
                )),
                .text(FormTextField(key: "memberId", label: "Id", placeholder: "user.ada", isRequired: true))
            ])],
            actions: FormActions(save: FormAction(id: "add", title: "Add") { [dataSource] values in
                guard let type = AccessMemberType(rawValue: values["memberType"]?.stringValue ?? "") else {
                    throw HubError.validation("Choose a type.")
                }
                let id = values["memberId"]?.stringValue?.trimmingCharacters(in: .whitespaces) ?? ""
                do {
                    let body = AccessMemberAdd(memberType: type, memberId: id)
                    _ = try await dataSource.addMember(groupID: groupID, body)
                } catch HubError.conflict {
                    throw HubError.validation("That member is already in this access list.")
                } catch {
                    throw HubError.wrap(error)
                }
            }))
    }

    private func memberDetail(_ member: AccessGroupMember, groupID: String) -> HTDVDetail {
        let spec = FormSpec(
            sections: [FormSection(fields: [
                .readOnly(FormReadOnlyField(key: "type", label: "Type")),
                .readOnly(FormReadOnlyField(key: "id", label: "Id", isMonospaced: true)),
                .readOnly(FormReadOnlyField(key: "added", label: "Added"))
            ])],
            actions: FormActions(delete: FormDeleteAction(
                title: "Remove member",
                confirmationText: "Remove \(member.typeTitle) \"\(member.memberId)\" from this access list?"
            ) { [dataSource] in
                try await HubError.wrap { try await dataSource.removeMember(groupID: groupID, memberRowID: member.id) }
            }))
        let values: [String: FormValue] = [
            "type": .string(member.typeTitle), "id": .string(member.memberId),
            "added": .string(HubDates.display(member.createdAt))
        ]
        return FormDetails.form(id: "access-member:\(member.id)", title: member.memberId, spec: spec, values: values)
    }

    // MARK: - Grants

    /// "Whole bucket", the bucket type's name (or its id when unknown), or `Row <id>`.
    public static func targetLabel(_ grant: AccessGrant, tables: [BucketTable]) -> String {
        switch grant.target {
        case .bucket: return "Whole bucket"
        case .bucketType: return tables.first { $0.id == grant.targetId }?.name ?? grant.targetId
        case .row: return "Row \(grant.targetId)"
        case nil: return grant.targetId
        }
    }

    private func grantsLevel(detail: AccessGroupDetail, tables: [BucketTable]) -> HTDVLevel {
        let items = detail.grants.map { grant in
            HTDVItem(id: grant.id, label: AccessListsTopic.targetLabel(grant, tables: tables),
                     sublabel: grant.permissions.summary, systemImage: "key", leadsTo: .detail)
        }
        let spec = grantSpec(group: detail.group, tables: tables, existing: detail.grants)
        return HTDVLevel(id: "access-grants:\(detail.group.id)", title: "Grants", items: items,
                         emptyMessage: "No grants yet.",
                         createAction: HTDVCreateAction(title: "Add grant") { presenter in
                             _ = await FormSheet.present(
                                 title: "Add grant", spec: spec, values: AccessListsTopic.grantCreateValues,
                                 from: presenter
                             )
                         })
    }

    /// Add-grant form. Target options shrink to what is still grantable: the whole bucket only once, each
    /// bucket type only once, rows always.
    public func grantSpec(group: AccessGroup, tables: [BucketTable], existing: [AccessGrant]) -> FormSpec {
        let hasBucketGrant = existing.contains { $0.target == .bucket }
        let grantedTypes = Set(existing.filter { $0.target == .bucketType }.map(\.targetId))
        let ungrantedTables = tables.filter { !grantedTypes.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        var targets: [FormSelectOption] = []
        if !hasBucketGrant {
            targets.append(FormSelectOption(value: AccessTargetType.bucket.rawValue, title: "Whole bucket"))
        }
        if !ungrantedTables.isEmpty {
            targets.append(FormSelectOption(value: AccessTargetType.bucketType.rawValue, title: "Bucket type"))
        }
        targets.append(FormSelectOption(value: AccessTargetType.row.rawValue, title: "Row"))

        return FormSpec(
            sections: [FormSection(fields: [
                .readOnly(FormReadOnlyField(key: "hint", label: "")),
                .select(FormSelectField(key: "target", label: "Target", options: targets)),
                .select(FormSelectField(
                    key: "bucketType", label: "Bucket type",
                    options: ungrantedTables.map { FormSelectOption(value: $0.id, title: $0.name) }
                )),
                .text(FormTextField(key: "rowId", label: "Row id", placeholder: "Row id (for row grants)")),
                .toggle(FormToggleField(key: "create", label: "Create")),
                .toggle(FormToggleField(key: "read", label: "Read")),
                .toggle(FormToggleField(key: "update", label: "Update")),
                .toggle(FormToggleField(key: "delete", label: "Delete"))
            ])],
            actions: FormActions(save: FormAction(id: "add", title: "Add") { [dataSource] values in
                guard let target = AccessTargetType(rawValue: values["target"]?.stringValue ?? "") else {
                    throw HubError.validation("Choose a target.")
                }
                let targetID: String
                switch target {
                case .bucket:
                    targetID = group.bucketId
                case .bucketType:
                    guard let id = HubText.nonBlank(values["bucketType"]?.stringValue) else {
                        throw HubError.validation("Choose a bucket type.")
                    }
                    targetID = id
                case .row:
                    let rawRowID = values["rowId"]?.stringValue?.trimmingCharacters(in: .whitespaces)
                    guard let id = HubText.nonBlank(rawRowID) else {
                        throw HubError.validation("Enter a row id.")
                    }
                    guard id.count <= 36 else { throw HubError.validation("Row id must be 36 characters or fewer.") }
                    targetID = id
                }
                let crud = await AccessListsTopic.crud(from: values)
                guard !crud.isEmpty else { throw HubError.validation("Choose at least one permission.") }
                let body = AccessGrantUpsert(targetType: target, targetId: targetID, crud: crud.crud)
                _ = try await HubError.wrap { try await dataSource.upsertGrant(groupID: group.id, body) }
            }))
    }

    private static func crud(from values: [String: FormValue]) -> AccessCRUD {
        AccessCRUD(create: values["create"]?.boolValue ?? false, read: values["read"]?.boolValue ?? false,
                   update: values["update"]?.boolValue ?? false, delete: values["delete"]?.boolValue ?? false)
    }

    private func grantDetail(_ grant: AccessGrant, groupID: String, tables: [BucketTable]) -> HTDVDetail {
        let label = AccessListsTopic.targetLabel(grant, tables: tables)
        let targetLine: String
        switch grant.target {
        case .bucket: targetLine = "Whole bucket"
        case .bucketType: targetLine = "Bucket type · \(label)"
        case .row: targetLine = label
        case nil: targetLine = "\(grant.targetType) · \(grant.targetId)"
        }
        let spec = FormSpec(
            sections: [FormSection(fields: [
                .readOnly(FormReadOnlyField(key: "target", label: "Target")),
                .toggle(FormToggleField(key: "create", label: "Create")),
                .toggle(FormToggleField(key: "read", label: "Read")),
                .toggle(FormToggleField(key: "update", label: "Update")),
                .toggle(FormToggleField(key: "delete", label: "Delete"))
            ])],
            actions: FormActions(
                save: FormAction(id: "save", title: "Save") { [dataSource] values in
                    let crud = await AccessListsTopic.crud(from: values)
                    if crud.isEmpty {
                        try await HubError.wrap {
                            try await dataSource.removeGrant(groupID: groupID, grantID: grant.id)
                        }
                    } else if let target = grant.target {
                        let body = AccessGrantUpsert(targetType: target, targetId: grant.targetId, crud: crud.crud)
                        _ = try await HubError.wrap { try await dataSource.upsertGrant(groupID: groupID, body) }
                    } else {
                        throw HubError.validation("Unknown grant target \"\(grant.targetType)\".")
                    }
                },
                delete: FormDeleteAction(
                    title: "Remove grant", confirmationText: "Remove the grant for \(label)?"
                ) { [dataSource] in
                    try await HubError.wrap { try await dataSource.removeGrant(groupID: groupID, grantID: grant.id) }
                }))
        let permissions = grant.permissions
        let values: [String: FormValue] = [
            "target": .string(targetLine), "create": .bool(permissions.create), "read": .bool(permissions.read),
            "update": .bool(permissions.update), "delete": .bool(permissions.delete)
        ]
        return FormDetails.form(id: "access-grant:\(grant.id)", title: label, spec: spec, values: values)
    }
}
