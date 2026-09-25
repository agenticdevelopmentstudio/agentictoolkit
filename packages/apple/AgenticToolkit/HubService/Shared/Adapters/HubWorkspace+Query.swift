import AgenticToolkitHub
import Foundation

extension HubWorkspace {
    /// The `?workspace=<slug>` pair the web sends on workspace-scoped endpoints.
    public var query: [String: String] { ["workspace": slug] }
}
