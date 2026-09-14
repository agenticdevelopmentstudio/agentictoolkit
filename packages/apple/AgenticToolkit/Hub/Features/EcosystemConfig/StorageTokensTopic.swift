import AgenticToolkitHTDV
import Foundation

/// Product rail topic "Storage Access Tokens": the caller's storage tokens whose bucket lives in this ecosystem.
@MainActor
public final class StorageTokensTopic: EcosystemTopicProvider {
    public static let entry = EcosystemTopicEntry(
        id: "tokens", label: "Storage Access Tokens", systemImage: "externaldrive.badge.person.crop",
        description: "Storage principals whose own bucket lives in this product's ecosystem.")

    public var entry: EcosystemTopicEntry { Self.entry }
    public let rail: StorageTokensRail

    public init(dataSource: any StorageTokensDataSource) { rail = StorageTokensRail(dataSource: dataSource) }

    public func child(
        for ecosystem: Ecosystem, path: [HTDVItem], rail _: any EcosystemRail
    ) async throws -> HTDVChild {
        try await rail.child(
            path: path, ecosystemID: ecosystem.id,
            levelID: "storage-tokens:\(ecosystem.id)", title: "Storage Access Tokens")
    }
}
