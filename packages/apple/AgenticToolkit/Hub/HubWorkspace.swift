import Foundation

/// The kind of workspace a slug names. Raw values match the API's `Workspace.type` strings.
public enum HubWorkspaceType: String, Sendable, Codable, CaseIterable {
    case individual
    case organization
    case team
}

/// A workspace the signed-in user belongs to. This is the shared, generated-code-free shape feature modules
/// receive as their context; the app maps the OpenAPI `Workspace` schema into it.
public struct HubWorkspace: Sendable, Equatable, Hashable, Identifiable, Codable {
    public let slug: String
    public let name: String
    public let type: HubWorkspaceType

    public var id: String { slug }

    /// "Name (slug)" — the label the workspace chooser shows.
    public var listLabel: String { "\(name) (\(slug))" }

    public init(slug: String, name: String, type: HubWorkspaceType) {
        self.slug = slug
        self.name = name
        self.type = type
    }
}
