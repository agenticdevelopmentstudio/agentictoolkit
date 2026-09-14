import Foundation
import AgenticToolkitHTDV

/// The product's own record: name, slug, identifier, description, region, and the Danger Zone delete.
@MainActor
public final class EcosystemSettingsTopic: EcosystemTopicProvider {
    public static let deleteWarning =
        "Deleting a product deletes all the data associated with the product, including applications, " +
        "buckets, and users. Do you wish to proceed?"

    public let entry = EcosystemTopicEntry(
        id: "settings", label: "Settings", systemImage: "gearshape",
        description: "The ecosystem's own record — name, identifier, and description.", leadsTo: .detail
    )
    private let dataSource: any EcosystemsDataSource

    public init(dataSource: any EcosystemsDataSource) {
        self.dataSource = dataSource
    }

    public func child(for ecosystem: Ecosystem, path: [HTDVItem], rail: any EcosystemRail) async throws -> HTDVChild {
        .detail(FormDetails.form(
            id: "ecosystem:\(ecosystem.id):settings", title: entry.label,
            spec: spec(for: ecosystem), values: values(for: ecosystem)
        ))
    }

    public func spec(for ecosystem: Ecosystem) -> FormSpec {
        let dataSource = dataSource
        return FormSpec(
            sections: [FormSection(fields: [
                .text(FormTextField(key: "name", label: "Display Name", placeholder: "My Product", isRequired: true)),
                .text(FormTextField(
                    key: "slug", label: "Slug", placeholder: "my-product", isRequired: true,
                    pattern: Slug.pattern, patternMessage: Slug.patternMessage
                )),
                .readOnly(FormReadOnlyField(key: "id", label: "Identifier", isMonospaced: true)),
                .textArea(FormTextAreaField(
                    key: "description", label: "Description", placeholder: "What this product is for.",
                    isRequired: false, minLines: 3
                )),
                .readOnly(FormReadOnlyField(key: "region", label: "Geographic Region"))
            ])],
            actions: FormActions(
                save: FormAction(id: "save", title: "Save") { values in
                    let slug = (values["slug"]?.stringValue ?? "").lowercased()
                    let identifier = ecosystem.identifierPrefix + slug
                    guard Slug.isValid(slug) else {
                        throw HubError.validation(
                            "\"\(identifier)\" is not a valid identifier — lowercase letters, digits, " +
                            "and interior hyphens only."
                        )
                    }
                    let update = EcosystemUpdate(
                        slug: slug,
                        name: values["name"]?.stringValue,
                        description: values["description"]?.stringValue
                    )
                    do {
                        _ = try await dataSource.update(id: ecosystem.id, update)
                    } catch HubError.conflict {
                        throw HubError.validation("Identifier \"\(identifier)\" is already in use.")
                    } catch {
                        throw HubError.wrap(error)
                    }
                },
                delete: FormDeleteAction(title: "Delete Product", confirmationText: Self.deleteWarning) {
                    do { try await dataSource.delete(id: ecosystem.id) } catch { throw HubError.wrap(error) }
                }
            )
        )
    }

    public func values(for ecosystem: Ecosystem) -> [String: FormValue] {
        [
            "name": .string(ecosystem.name),
            "slug": .string(ecosystem.slug),
            "id": .string(ecosystem.id),
            "description": .string(ecosystem.description ?? ""),
            "region": .string("coming soon")
        ]
    }
}

/// The ecosystems this product owns. Picking one re-enters the product rail for the child.
@MainActor
public final class ChildEcosystemsTopic: EcosystemTopicProvider {
    public let entry = EcosystemTopicEntry(
        id: "child-ecosystems", label: "Child Ecosystems", systemImage: "square.stack.3d.down.right",
        description: "The ecosystems this one owns."
    )
    private let dataSource: any EcosystemsDataSource

    public init(dataSource: any EcosystemsDataSource) {
        self.dataSource = dataSource
    }

    public func child(for ecosystem: Ecosystem, path: [HTDVItem], rail: any EcosystemRail) async throws -> HTDVChild {
        guard let childID = RailPath.id(at: 0, in: path) else {
            let children: [Ecosystem]
            do { children = try await dataSource.children(of: ecosystem.id) } catch { throw HubError.wrap(error) }
            let items = children.map { EcosystemsModule.item(for: $0) }
            let spec = EcosystemCreateForm(dataSource: dataSource, parent: ecosystem).spec()
            let action = HTDVCreateAction(title: "New Ecosystem") { presenter in
                _ = await FormSheet.present(title: "New Ecosystem", spec: spec, from: presenter)
            }
            return .level(HTDVLevel(
                id: "child-ecosystems-list", title: entry.label, items: items,
                emptyMessage: "No child ecosystems yet.", createAction: action
            ))
        }
        let child: Ecosystem
        do {
            child = try await dataSource.get(id: childID)
        } catch HubError.notFound {
            return .empty
        } catch {
            throw HubError.wrap(error)
        }
        return try await rail.child(for: child, path: Array(path.dropFirst()))
    }
}
