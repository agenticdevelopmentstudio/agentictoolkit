import AgenticToolkitHubService
import Foundation

/// Spec §5.5: avatar label precedence and the account menu.
public struct AccountMenuModel: Equatable, Sendable {
    public enum Item: String, CaseIterable, Sendable {
        case home, profile, settings, logOut

        public var label: String {
            switch self {
            case .home: "Home"
            case .profile: "Profile"
            case .settings: "Settings"
            case .logOut: "Log out"
            }
        }
    }

    public let avatarLabel: String
    public let initials: String
    public let items: [Item]

    public init(user: HubUser) {
        avatarLabel = Self.avatarLabel(name: user.name, slug: user.slug, email: user.email)
        initials = user.initials
        items = Item.allCases
    }

    public static func avatarLabel(name: String, slug: String?, email: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty { return trimmedName }
        if let slug, !slug.isEmpty { return slug }
        return String(email.split(separator: "@", maxSplits: 1).first ?? Substring(email))
    }
}
