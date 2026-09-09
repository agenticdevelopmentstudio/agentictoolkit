//
//  SemanticVersion.swift
//  AgenticToolkit
//

import Foundation

/// A parsed `major.minor.patch` version number.
///
/// This is not `Core/Extensions/` because a version number is not a VS Code
/// concept — it is general enough that Stage 7's Open VSX installer compares
/// extension versions with it too. The subset implemented here (no
/// prerelease, no build metadata) is deliberately small: nothing in this
/// toolkit currently needs to order `1.0.0-rc.1` against `1.0.0`, and half a
/// precedence table is worse than an honest `nil`.
public struct SemanticVersion: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses `"1.74.0"`, `"1.74"` and `"1"` (missing components are zero).
    /// A leading `v` is accepted. Anything else — a prerelease suffix, build
    /// metadata, a non-numeric component — returns `nil` rather than guessing
    /// at precedence rules this type does not implement.
    public init?(_ string: String) {
        var remainder = Substring(string)
        if remainder.first == "v" {
            remainder = remainder.dropFirst()
        }

        let components = remainder.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(components.count) else { return nil }

        var parsed: [Int] = []
        for component in components {
            guard let value = Int(component), value >= 0 else { return nil }
            parsed.append(value)
        }
        while parsed.count < 3 {
            parsed.append(0)
        }

        self.init(major: parsed[0], minor: parsed[1], patch: parsed[2])
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }
}
