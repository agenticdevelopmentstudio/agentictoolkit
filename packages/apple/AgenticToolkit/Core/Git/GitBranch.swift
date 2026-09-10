import Foundation

/// A local branch as `git for-each-ref` reports it.
public struct GitBranch: Sendable, Equatable, Hashable {
    public let name: String
    public let isCurrent: Bool
    public let upstream: String?

    public init(name: String, isCurrent: Bool, upstream: String?) {
        self.name = name
        self.isCurrent = isCurrent
        self.upstream = upstream
    }

    /// Format string this parser expects (tab-separated): `%(refname:short)%09%(HEAD)%09%(upstream:short)`.
    ///
    /// Real `git for-each-ref` fills the `%(HEAD)` field with `*` for the checked-out
    /// branch and a single space (not an empty string) for every other one, so the
    /// current-branch check below only ever compares against `"*"` and never assumes
    /// the non-current case is empty.
    public static let forEachRefFormat = "%(refname:short)%09%(HEAD)%09%(upstream:short)"

    /// Parses tab-separated `for-each-ref` lines into branches.
    ///
    /// A branch name can never contain a tab (`git check-ref-format` forbids control
    /// characters in refs), so splitting on `\t` cannot be confused by field content.
    public static func parse(forEachRef output: String) -> [GitBranch] {
        output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard let name = fields.first, !name.isEmpty else { return nil }
            let isCurrent = fields.count > 1 && fields[1] == "*"
            let upstream = fields.count > 2 && !fields[2].isEmpty ? fields[2] : nil
            return GitBranch(name: name, isCurrent: isCurrent, upstream: upstream)
        }
    }
}
