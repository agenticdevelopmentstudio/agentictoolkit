import Foundation
import AgenticToolkitHTDV

/// One entry in a product's topics rail.
public struct EcosystemTopicEntry: Hashable, Sendable {
    public var id: String
    public var label: String
    public var systemImage: String
    public var description: String?
    public var leadsTo: HTDVLeadsTo
    public var dividerAfter: Bool

    public init(
        id: String, label: String, systemImage: String, description: String? = nil,
        leadsTo: HTDVLeadsTo = .list, dividerAfter: Bool = false
    ) {
        self.id = id; self.label = label; self.systemImage = systemImage
        self.description = description; self.leadsTo = leadsTo; self.dividerAfter = dividerAfter
    }

    public func item() -> HTDVItem {
        HTDVItem(
            id: id, label: label, sublabel: description, systemImage: systemImage,
            dividerAfter: dividerAfter, leadsTo: leadsTo
        )
    }
}

/// Resolves paths beneath a product's topics rail. `EcosystemsModule` is the implementation; a provider that
/// navigates into another ecosystem (child ecosystems) calls back through it so the child gets the same rail.
@MainActor
public protocol EcosystemRail: AnyObject {
    func child(for ecosystem: Ecosystem, path: [HTDVItem]) async throws -> HTDVChild
}

/// A topic of the product rail. `path` is relative to the topic: `[]` asks for the topic's own child
/// (a level or a detail); deeper paths descend into it.
@MainActor
public protocol EcosystemTopicProvider: AnyObject {
    var entry: EcosystemTopicEntry { get }
    func child(for ecosystem: Ecosystem, path: [HTDVItem], rail: any EcosystemRail) async throws -> HTDVChild
}

/// A topic that opens a level of sub-topics (the hub's "Storage", "Users", "Authentication" groups).
@MainActor
public final class EcosystemTopicGroup: EcosystemTopicProvider {
    public let entry: EcosystemTopicEntry
    public let children: [any EcosystemTopicProvider]

    public init(
        id: String, label: String, systemImage: String, dividerAfter: Bool = false,
        children: [any EcosystemTopicProvider]
    ) {
        self.entry = EcosystemTopicEntry(
            id: id, label: label, systemImage: systemImage, leadsTo: .list, dividerAfter: dividerAfter
        )
        self.children = children
    }

    public func child(for ecosystem: Ecosystem, path: [HTDVItem], rail: any EcosystemRail) async throws -> HTDVChild {
        guard let childID = RailPath.id(at: 0, in: path) else {
            let items = children.map { $0.entry.item() }
            return .level(HTDVLevel(id: "ecosystem-group:\(entry.id)", title: entry.label, items: items))
        }
        guard let provider = children.first(where: { $0.entry.id == childID }) else { return .empty }
        return try await provider.child(for: ecosystem, path: Array(path.dropFirst()), rail: rail)
    }
}

/// A topic whose only content is a read-only message (used for web panes that are not in this version).
@MainActor
public final class EcosystemNoticeTopic: EcosystemTopicProvider {
    public let entry: EcosystemTopicEntry
    public let message: String

    public init(entry: EcosystemTopicEntry, message: String) {
        self.entry = entry
        self.message = message
    }

    public func child(for ecosystem: Ecosystem, path: [HTDVItem], rail: any EcosystemRail) async throws -> HTDVChild {
        .detail(FormDetails.notice(id: "ecosystem:\(ecosystem.id):\(entry.id)", title: entry.label, message: message))
    }
}
