import AgenticDeveloperHubClient
import Foundation

/// The app-facing user. Deliberately narrower than the generated schema:
/// the shell needs an identity, a label and an avatar — nothing else.
public struct HubUser: Sendable, Equatable, Codable {
    public let id: String
    public let email: String
    public let name: String
    public let slug: String?
    public let avatarURL: URL?

    public init(id: String, email: String, name: String, slug: String?, avatarURL: URL?) {
        self.id = id
        self.email = email
        self.name = name
        self.slug = slug
        self.avatarURL = avatarURL
    }

    public init(_ user: Components.Schemas.User) {
        let trimmed = user.avatarUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            id: user.id,
            email: user.email,
            name: user.name,
            slug: user.slug,
            avatarURL: trimmed.isEmpty ? nil : URL(string: trimmed)
        )
    }

    /// Spec §5.5: the name, or the email when the name is blank.
    public var displayLabel: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? email : trimmed
    }

    /// Spec §5.5 avatar fallback: up to two initials from the name's first
    /// two words, else the first letter of the email.
    public var initials: String {
        let words = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        let letters = words.compactMap { $0.first.map { String($0).uppercased() } }
        if !letters.isEmpty { return letters.joined() }
        return email.first.map { String($0).uppercased() } ?? "?"
    }
}
