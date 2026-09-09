//
//  VSCodeEngineRange.swift
//  AgenticToolkit
//

import Foundation

/// A parsed `engines.vscode` value from an extension manifest.
///
/// VS Code's own range grammar (`~`, `||`, hyphen ranges, `>`/`<`) is much
/// larger than this. Only the three forms extensions actually publish in
/// practice — `^x.y.z`, `>=x.y.z`, and an exact `x.y.z` — are implemented.
/// Anything else, including the `"*"` the manifest reference explicitly
/// forbids, fails to parse: a range this type cannot evaluate must be a load
/// failure that names the raw string, never a silent pass or a silent reject.
public struct VSCodeEngineRange: Sendable, Hashable, CustomStringConvertible {
    /// The raw string as it appeared in the manifest.
    public let rawValue: String

    private let requirement: Requirement

    private enum Requirement: Sendable, Hashable {
        case caret(SemanticVersion)
        case atLeast(SemanticVersion)
        case exact(SemanticVersion)
    }

    /// Parses the subset VS Code extensions actually use:
    ///   "^1.74.0"   — >= 1.74.0 and < 2.0.0
    ///   ">=1.74.0"  — >= 1.74.0
    ///   "1.74.0"    — exactly 1.74.0
    /// Returns `nil` for anything else, including `"*"`, which the manifest
    /// reference forbids. Whitespace around the operator is tolerated.
    public init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("^") {
            let versionPart = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
            guard let version = SemanticVersion(versionPart) else { return nil }
            self.requirement = .caret(version)
        } else if trimmed.hasPrefix(">=") {
            let versionPart = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
            guard let version = SemanticVersion(versionPart) else { return nil }
            self.requirement = .atLeast(version)
        } else {
            guard let version = SemanticVersion(trimmed) else { return nil }
            self.requirement = .exact(version)
        }

        self.rawValue = string
    }

    public func accepts(_ version: SemanticVersion) -> Bool {
        switch requirement {
        case .caret(let floor):
            let ceiling = SemanticVersion(major: floor.major + 1, minor: 0, patch: 0)
            return version >= floor && version < ceiling
        case .atLeast(let floor):
            return version >= floor
        case .exact(let exact):
            return version == exact
        }
    }

    public var description: String { rawValue }
}
