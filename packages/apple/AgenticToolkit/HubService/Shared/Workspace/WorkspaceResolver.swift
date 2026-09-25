import AgenticToolkitHub

public enum WorkspaceResolution: Equatable, Sendable {
    case workspace(HubWorkspace)
    case notFound(String)
    case none
}

/// Spec §5.3, copied from the web app's resolver: an explicit slug wins
/// (unknown → `.notFound`), then the server preference when it names a
/// known workspace, then the first workspace in server order
/// (individual → organization → team), else `.none`.
public enum WorkspaceResolver {
    public static func resolve(
        workspaces: [HubWorkspace],
        requestedSlug: String?,
        serverPrefSlug: String?
    ) -> WorkspaceResolution {
        if let requested = requestedSlug?.trimmingCharacters(in: .whitespaces), !requested.isEmpty {
            if let match = workspaces.first(where: { $0.slug == requested }) {
                return .workspace(match)
            }
            return .notFound(requested)
        }
        if let pref = serverPrefSlug, let match = workspaces.first(where: { $0.slug == pref }) {
            return .workspace(match)
        }
        if let first = workspaces.first {
            return .workspace(first)
        }
        return .none
    }

    /// Only explicit picks persist, and never a team (the web's `canPersist`).
    public static func shouldPersist(_ workspace: HubWorkspace) -> Bool {
        workspace.type != .team
    }
}
