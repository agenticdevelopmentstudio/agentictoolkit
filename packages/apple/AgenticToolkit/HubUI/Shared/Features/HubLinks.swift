import AgenticToolkitHubService
import AgenticToolkitHub
import Foundation

/// Web URLs for the rows v1 does not implement natively (spec §5.4: Messages).
public enum HubLinks {
    public static let webBase: URL = {
        guard let url = URL(string: "https://agenticdeveloperhub.com") else { preconditionFailure("static URL") }
        return url
    }()

    public static func url(path: String) -> URL {
        webBase.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    public static func workspaceURL(_ workspace: HubWorkspace, path: String) -> URL {
        url(path: "\(workspace.slug)/\(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))")
    }
}
