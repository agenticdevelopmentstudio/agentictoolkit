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

    /// The largest component `init?(String)` will parse.
    ///
    /// A version component is *arithmetic*, not just a label: `VSCodeEngineRange`
    /// derives a caret range's ceiling as `floor.major + 1`, and `+` on `Int`
    /// traps on overflow rather than wrapping. The numbers come straight out of
    /// a third-party `package.json`, so without a bound a manifest reading
    /// `"engines": {"vscode": "^9223372036854775807"}` parses cleanly and then
    /// kills the process the first time anything compares against it — inside
    /// `Features.init()`, before the app has any UI the user could disable the
    /// offending extension from.
    ///
    /// The guard lives *here*, at the one place a version is admitted from
    /// text, rather than at each caller: a caller that re-derives it is a
    /// caller that can forget to. `Int32.max` is arbitrary in the way any
    /// plausibility bound is, and deliberately far above anything real — VS
    /// Code is on 1.x, semver majors are counted by hand — while leaving every
    /// arithmetic a range evaluation performs comfortably inside `Int`.
    ///
    /// A version this rejects is not silently downgraded or clamped: `init?`
    /// returns `nil`, `VSCodeEngineRange.init?` returns `nil` with it, and
    /// `ExtensionRegistry` records `.engineRangeUnparsable` naming the raw
    /// string and skips that one extension. Every other extension still loads.
    private static let maximumComponent = Int(Int32.max)

    /// Parses `"1.74.0"`, `"1.74"` and `"1"` (missing components are zero).
    /// A leading `v` is accepted. Anything else — a prerelease suffix, build
    /// metadata, a non-numeric component, or a component above
    /// `maximumComponent` — returns `nil` rather than guessing at precedence
    /// rules this type does not implement or admitting a number that traps the
    /// arithmetic its consumers do.
    public init?(_ string: String) {
        var remainder = Substring(string)
        if remainder.first == "v" {
            remainder = remainder.dropFirst()
        }

        let components = remainder.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(components.count) else { return nil }

        var parsed: [Int] = []
        for component in components {
            guard let value = Int(component),
                  (0...Self.maximumComponent).contains(value) else { return nil }
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
