import Foundation
import AgenticToolkitHTDV

/// Products rail: workspace products → one product's topics → each topic's provider.
@MainActor
public final class EcosystemsModule: HTDVDataSource, EcosystemRail {
    public static let notManageableTitle = "You don't have admin access to this ecosystem"
    public static let notManageableMessage =
        "Viewing an ecosystem's contents needs organization admin access — ask one of the organization's admins."

    private let dataSource: any EcosystemsDataSource
    private let topics: [any EcosystemTopicProvider]

    public init(dataSource: any EcosystemsDataSource, topics: [any EcosystemTopicProvider]) {
        self.dataSource = dataSource
        self.topics = topics
    }

    // MARK: HTDVDataSource

    public func rootLevel() async throws -> HTDVLevel {
        let ecosystems: [Ecosystem]
        do { ecosystems = try await dataSource.list() } catch { throw HubError.wrap(error) }
        let items = ecosystems.filter { !$0.isDefault }.map { Self.item(for: $0) }
        let spec = EcosystemCreateForm(dataSource: dataSource, parent: nil).spec()
        let action = HTDVCreateAction(title: "New Product") { presenter in
            _ = await FormSheet.present(title: "New Product", spec: spec, from: presenter)
        }
        return HTDVLevel(
            id: "ecosystems", title: "Products", items: items, emptyMessage: "No products yet.", createAction: action
        )
    }

    public func child(for path: [HTDVItem]) async throws -> HTDVChild {
        guard let ecosystemID = RailPath.id(at: 0, in: path) else { return .empty }
        let ecosystem: Ecosystem
        do {
            ecosystem = try await dataSource.get(id: ecosystemID)
        } catch HubError.notFound {
            return .empty
        } catch {
            throw HubError.wrap(error)
        }
        return try await child(for: ecosystem, path: Array(path.dropFirst()))
    }

    // MARK: EcosystemRail

    public func child(for ecosystem: Ecosystem, path: [HTDVItem]) async throws -> HTDVChild {
        guard ecosystem.isManageable else {
            return .detail(FormDetails.notice(
                id: "ecosystem:\(ecosystem.id):not-manageable",
                title: Self.notManageableTitle, message: Self.notManageableMessage
            ))
        }
        guard let topicID = RailPath.id(at: 0, in: path) else { return .level(topicsLevel(for: ecosystem)) }
        guard let provider = topics.first(where: { $0.entry.id == topicID }) else { return .empty }
        return try await provider.child(for: ecosystem, path: Array(path.dropFirst()), rail: self)
    }

    public func topicsLevel(for ecosystem: Ecosystem) -> HTDVLevel {
        HTDVLevel(id: "ecosystem-topics", title: ecosystem.name, items: topics.map { $0.entry.item() })
    }

    static func item(for ecosystem: Ecosystem) -> HTDVItem {
        HTDVItem(id: ecosystem.id, label: ecosystem.name, sublabel: ecosystem.id, systemImage: "shippingbox")
    }
}

/// The "New Product" / "New Ecosystem" create form. The identifier is derived from the parent
/// (the workspace's infrastructure ecosystem for top-level products) plus the slug, probed for
/// availability before the create request.
public struct EcosystemCreateForm: Sendable {
    public static let slugTooLongMessage = "Slug must be 64 characters or fewer."
    public static let slugMaxLength = 64

    private let dataSource: any EcosystemsDataSource
    private let parent: Ecosystem?

    public init(dataSource: any EcosystemsDataSource, parent: Ecosystem?) {
        self.dataSource = dataSource
        self.parent = parent
    }

    public func spec() -> FormSpec {
        let dataSource = dataSource
        let parentID = parent?.id
        return FormSpec(
            sections: [FormSection(fields: [
                .text(FormTextField(key: "name", label: "Display Name", placeholder: "My Product", isRequired: true)),
                .text(FormTextField(
                    key: "slug", label: "Slug", placeholder: "my-product", isRequired: true,
                    pattern: Slug.pattern, patternMessage: Slug.patternMessage
                )),
                .textArea(FormTextAreaField(
                    key: "description", label: "Description", placeholder: "What this product is for.",
                    isRequired: false, minLines: 3
                ))
            ])],
            actions: FormActions(save: FormAction(id: "create", title: "Create") { values in
                let slug = (values["slug"]?.stringValue ?? "").lowercased()
                guard slug.count <= Self.slugMaxLength else { throw HubError.validation(Self.slugTooLongMessage) }
                let prefix: String
                if let parentID {
                    prefix = parentID
                } else {
                    do { prefix = try await dataSource.infrastructureID() } catch { throw HubError.wrap(error) }
                }
                let identifier = "\(prefix).\(slug)"
                let exists: Bool
                do { exists = try await dataSource.identifierExists(identifier) } catch { throw HubError.wrap(error) }
                if exists { throw HubError.validation("Identifier \"\(identifier)\" is already in use.") }
                let input = EcosystemCreate(
                    id: identifier, slug: slug,
                    name: values["name"]?.stringValue ?? "",
                    description: values["description"]?.stringValue ?? ""
                )
                do {
                    _ = try await dataSource.create(input, parentID: parentID)
                } catch HubError.conflict {
                    throw HubError.validation("An ecosystem with identifier \"\(identifier)\" already exists.")
                } catch {
                    throw HubError.wrap(error)
                }
            })
        )
    }
}
