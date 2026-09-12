import Foundation

/// One of git's porcelain status letters, in the toolkit's vocabulary.
public enum GitFileStatus: String, Codable, CaseIterable, Sendable {
    case modified = "M"
    case added = "A"
    case deleted = "D"
    case renamed = "R"
    case copied = "C"
    case untracked = "?"
    case conflicted = "U"
    case ignored = "!"

    public var displayCharacter: String { rawValue }

    /// Higher wins when statuses are merged for a directory.
    public var priority: Int {
        switch self {
        case .conflicted: 7
        case .modified: 6
        case .added: 5
        case .deleted: 4
        case .renamed: 3
        case .copied: 2
        case .untracked: 1
        case .ignored: 0
        }
    }

    public static func merge(_ statuses: [GitFileStatus]) -> GitFileStatus? {
        statuses.max(by: { $0.priority < $1.priority })
    }
}
