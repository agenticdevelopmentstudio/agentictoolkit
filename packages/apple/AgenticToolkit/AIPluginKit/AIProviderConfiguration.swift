import Foundation
import AgenticToolkitCore

/// A user's named instance of a provider template: which plugin serves it, which
/// template it was created from, and a display name. Per-configuration field
/// values, model, and secrets live in stores keyed by `id.uuidString` (see
/// `AIProviderConfigKeys`); only identity lives here so the ordered list is a small
/// plain-Codable array shared by the app and the daemon.
public struct AIProviderConfiguration: Codable, Sendable, Identifiable, Equatable, Hashable {
    public let id: UUID
    public var name: String
    public let pluginIdentifier: String
    public let templateId: String

    public init(id: UUID = UUID(), name: String, pluginIdentifier: String, templateId: String) {
        self.id = id
        self.name = name
        self.pluginIdentifier = pluginIdentifier
        self.templateId = templateId
    }

    /// A configuration name not already in `taken`, appending " 2", " 3", … until
    /// free. One source of truth for the UI (add/rename) and the migration planner.
    public static func uniqueName(_ base: String, avoiding taken: Set<String>) -> String {
        UniqueName.next(base: base, taken: taken)
    }
}
