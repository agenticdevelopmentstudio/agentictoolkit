import AgenticDeveloperHubClient
import AgenticToolkitPermissions

/// The grants the hub service itself needs — one Keychain entry, where the
/// session lives. A host lists these in its permissions panel and walkthrough
/// instead of the toolkit's default set, which names grants the hub never
/// asks for. macOS only: `AgenticToolkitPermissions` is a macOS framework.
public enum HubPermissions {
    public static let required: [AgenticToolkitPermissions.Permission] = [
        .keychain(service: KeychainHelper.service)
    ]
}
