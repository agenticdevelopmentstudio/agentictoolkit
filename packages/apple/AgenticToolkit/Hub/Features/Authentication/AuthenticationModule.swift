import AgenticToolkitHTDV
import Foundation

/// Root feature "Authentication": the caller's API tokens and storage tokens, plus an explainer.
@MainActor
public final class AuthenticationModule: HTDVDataSource {
    public static let overviewMessage =
        "An API token (tmp_) is personal — it acts as YOU across the REST paths you scope it to. " +
        "A storage token (adh_) is a principal of its own, reaching the one isolated bucket minted " +
        "with it and nothing else."

    public let apiTokens: ApiTokensRail
    public let storageTokens: StorageTokensRail

    public init(apiTokens: ApiTokensDataSource, storageTokens: StorageTokensDataSource) {
        self.apiTokens = ApiTokensRail(dataSource: apiTokens)
        self.storageTokens = StorageTokensRail(dataSource: storageTokens)
    }

    public func rootLevel() async throws -> HTDVLevel {
        HTDVLevel(id: "token-sections", title: "Tokens", items: [
            HTDVItem(id: "api", label: "API tokens", sublabel: "Personal tokens (tmp_) that act as you.",
                     systemImage: "key", leadsTo: .list),
            HTDVItem(id: "storage", label: "Storage tokens",
                     sublabel: "Principals of their own (adh_) with one isolated bucket.",
                     systemImage: "externaldrive", dividerAfter: true, leadsTo: .list),
            HTDVItem(id: "about", label: "About tokens", systemImage: "info.circle", leadsTo: .detail)
        ], emptyMessage: "", createAction: nil)
    }

    public func child(for path: [HTDVItem]) async throws -> HTDVChild {
        guard let first = path.first else { return .level(try await rootLevel()) }
        let rest = Array(path.dropFirst())
        switch first.id {
        case "api":
            return try await apiTokens.child(path: rest)
        case "storage":
            return try await storageTokens.child(
                path: rest, ecosystemID: nil, levelID: "storage-tokens-list", title: "Storage tokens"
            )
        case "about" where rest.isEmpty:
            return .detail(FormDetails.notice(
                id: "tokens-about", title: "About tokens", message: AuthenticationModule.overviewMessage
            ))
        default:
            return .empty
        }
    }
}
