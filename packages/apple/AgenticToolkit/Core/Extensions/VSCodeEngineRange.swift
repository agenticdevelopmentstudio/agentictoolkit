//
//  VSCodeEngineRange.swift
//  AgenticToolkit
//

import Foundation

/// A parsed `engines.vscode` value from an extension manifest.
///
/// This is a port of VS Code's own `extensionValidator.ts` — `isValidVersionStr`,
/// `parseVersion`, `normalizeVersion` and `isValidVersion` — pinned at the commit
/// recorded in `docs/planning/vsc-extensions-upstream-pin-manifest.md`. It is
/// deliberately a port rather than an interpretation: `engines.vscode` *looks*
/// like an npm semver range and is not one, and the difference is not academic.
/// Against the 198 web extensions among the 600 most-downloaded on Open VSX
/// (`Scripts/openvsx_engine_survey.py`), an npm reading rejects 48 of them —
/// nearly a quarter — that VS Code itself runs.
///
/// The grammar is `(^|>=)?(\d+|x).(\d+|x).(\d+|x)(-.*)?`, plus the bare `*`.
/// Every other shape npm defines — `~`, `>`, `<`, `||`, hyphen ranges, a
/// two-component `1.74` — VS Code never implemented, so neither does this: an
/// unevaluable range is a load failure naming the raw string, never a silent
/// pass or a silent reject.
///
/// Two of upstream's behaviours are surprising enough to name here, because
/// both are load-bearing and neither is what npm would do:
///
///   * A requirement is not a floor-and-ceiling pair. It is three bases, each
///     with a *must-equal* flag, and an operator's only job is to clear flags:
///     `^` clears the patch flag (and the minor flag too, unless the major is
///     0), `x` clears its own component's. Once cleared, the component is
///     simply unconstrained upward — which is why `^1.74.0` admits 1.999.0 but
///     not 2.0.0, without a ceiling ever being computed.
///   * *Anything below 1.0.0 is compatible with 1.x, except exact matches.* A
///     `^0.10.5` extension therefore runs here, because the caret left slack;
///     a bare `0.10.0` does not, because it left none. npm's caret would cap
///     the first at 0.11.0 and never run it at all.
public struct VSCodeEngineRange: Sendable, Hashable, CustomStringConvertible {
    /// The raw string as it appeared in the manifest.
    public let rawValue: String

    private let requirement: Requirement

    /// Upstream's `INormalizedVersion`, less `notBefore`.
    ///
    /// A `-YYYYMMDD` pre-release suffix is the one part of the suffix upstream
    /// gives meaning to, and only when it is handed a product *build date* to
    /// compare against — both `notBefore` tests in `isValidVersion` are guarded
    /// by `productTs`. This host publishes no build date, so those branches
    /// could never fire and the field would be dead weight carried through
    /// every comparison. The suffix is still parsed, because the grammar has a
    /// production for it and a manifest that uses one must load.
    private struct Requirement: Sendable, Hashable {
        var majorBase: Int
        var majorMustEqual: Bool
        var minorBase: Int
        var minorMustEqual: Bool
        var patchBase: Int
        var patchMustEqual: Bool
        /// `>=`, which upstream evaluates by a wholly separate path.
        var isMinimum: Bool
    }

    /// Parses an `engines.vscode` range, or returns `nil` if it is not one.
    ///
    /// Surrounding whitespace is trimmed, as upstream trims it. Whitespace
    /// *inside* the range is not tolerated: `">= 1.74.0"` is outside the
    /// grammar, and accepting it would run an extension here that VS Code
    /// refuses to run — the wrong direction for a host strictly less capable
    /// than the one these manifests were written for.
    public init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespaces)

        guard let requirement = Self.parse(trimmed) else { return nil }
        self.requirement = requirement
        self.rawValue = string
    }

    private static func parse(_ trimmed: String) -> Requirement? {
        // `*` short-circuits the grammar entirely: every base 0, every flag
        // cleared, which is "any version at all".
        if trimmed == "*" {
            return Requirement(
                majorBase: 0, majorMustEqual: false,
                minorBase: 0, minorMustEqual: false,
                patchBase: 0, patchMustEqual: false,
                isMinimum: false)
        }

        var body = Substring(trimmed)
        var hasCaret = false
        var isMinimum = false
        if body.hasPrefix("^") {
            hasCaret = true
            body = body.dropFirst()
        } else if body.hasPrefix(">=") {
            isMinimum = true
            body = body.dropFirst(2)
        }

        // The components admit only digits and `x`, so the first `-` can only
        // begin the pre-release suffix. `(-.*)?` accepts anything after it,
        // including nothing.
        if let suffix = body.firstIndex(of: "-") {
            body = body[body.startIndex..<suffix]
        }

        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }

        var bases: [Int] = []
        var mustEqual: [Bool] = []
        for part in parts {
            if part == "x" {
                bases.append(0)
                mustEqual.append(false)
            } else if !part.isEmpty, part.allSatisfy(\.isASCII), part.allSatisfy(\.isNumber) {
                // The components are bounds-checked below by handing them to
                // `SemanticVersion`, so the plausibility bound on a component
                // lives in exactly one place and every caller inherits it
                // rather than re-deriving it.
                guard let value = Int(part) else { return nil }
                bases.append(value)
                mustEqual.append(true)
            } else {
                return nil
            }
        }
        guard SemanticVersion("\(bases[0]).\(bases[1]).\(bases[2])") != nil else { return nil }

        // The operator's whole effect: clear flags. A caret on a 0.x
        // requirement clears only the patch, because below 1.0.0 a minor bump
        // is still breaking.
        if hasCaret {
            if bases[0] == 0 {
                mustEqual[2] = false
            } else {
                mustEqual[1] = false
                mustEqual[2] = false
            }
        }

        return Requirement(
            majorBase: bases[0], majorMustEqual: mustEqual[0],
            minorBase: bases[1], minorMustEqual: mustEqual[1],
            patchBase: bases[2], patchMustEqual: mustEqual[2],
            isMinimum: isMinimum)
    }

    /// Whether a host running `version` satisfies this requirement.
    ///
    /// A transcription of upstream's `isValidVersion`, with its `notBefore`
    /// comparisons omitted for the reason given on `Requirement`. No arithmetic
    /// appears anywhere in it — upstream only ever *compares* bases, never
    /// computes a ceiling — so there is nothing here to overflow.
    public func accepts(_ version: SemanticVersion) -> Bool {
        var desiredMajorBase = requirement.majorBase
        var desiredMinorBase = requirement.minorBase
        var desiredPatchBase = requirement.patchBase
        var majorMustEqual = requirement.majorMustEqual
        var minorMustEqual = requirement.minorMustEqual
        var patchMustEqual = requirement.patchMustEqual

        if requirement.isMinimum {
            if version.major > desiredMajorBase { return true }
            if version.major < desiredMajorBase { return false }
            if version.minor > desiredMinorBase { return true }
            if version.minor < desiredMinorBase { return false }
            return version.patch >= desiredPatchBase
        }

        // Anything < 1.0.0 is compatible with >= 1.0.0, except exact matches.
        if version.major == 1, desiredMajorBase == 0,
           !majorMustEqual || !minorMustEqual || !patchMustEqual {
            desiredMajorBase = 1
            desiredMinorBase = 0
            desiredPatchBase = 0
            majorMustEqual = true
            minorMustEqual = false
            patchMustEqual = false
        }

        if version.major < desiredMajorBase { return false }
        if version.major > desiredMajorBase { return !majorMustEqual }
        if version.minor < desiredMinorBase { return false }
        if version.minor > desiredMinorBase { return !minorMustEqual }
        if version.patch < desiredPatchBase { return false }
        if version.patch > desiredPatchBase { return !patchMustEqual }
        return true
    }

    /// The lowest version this range names — its three bases, which for `*` and
    /// for an all-`x` range is 0.0.0.
    ///
    /// This is the *declared* floor, not the lowest version `accepts(_:)`
    /// returns true for; the two differ for a sub-1.0.0 range, which the rule
    /// above rewrites at comparison time. The declared floor is what the one
    /// caller wants: `ActivationEventMatcher` needs to know whether a manifest
    /// asked for 1.74.0 or later — the version VS Code began treating a
    /// declared command as implicitly activating — and a manifest that asked
    /// for `*` or for `^0.10.5` plainly did not. `accepts(_:)` alone cannot
    /// answer that: probing `accepts(1.73.0)` is wrong for a range like
    /// `^1.73.5`, whose floor is below 1.74.0 yet which still rejects the
    /// literal version 1.73.0.
    public var minimumVersion: SemanticVersion {
        SemanticVersion(
            major: requirement.majorBase,
            minor: requirement.minorBase,
            patch: requirement.patchBase)
    }

    /// Whether the range declares no version requirement at all — `*`, or an
    /// all-`x` range, and nothing else.
    ///
    /// The distinction `minimumVersion` cannot draw. `*` parses to three zero
    /// bases with every flag cleared, so its declared floor reads as 0.0.0 —
    /// indistinguishable from a manifest that really did ask for 0.0.0, and
    /// below every floor a caller might compare against. But `*` is the
    /// *absence* of a version claim, not a claim about an ancient VS Code, and
    /// reading it as one makes an extension that named no engine the strictest
    /// case rather than the loosest.
    ///
    /// The flags are what separate the two: only `*` and `x` clear a base's
    /// must-equal flag while leaving the base at zero. A literal `0.0.0` sets
    /// all three, `>=0.0.0` is a minimum rather than a range, and `0.x.x`
    /// still claims a major of 0 — none of them is unconstrained.
    public var isUnconstrained: Bool {
        !requirement.isMinimum
            && requirement.majorBase == 0 && !requirement.majorMustEqual
            && requirement.minorBase == 0 && !requirement.minorMustEqual
            && requirement.patchBase == 0 && !requirement.patchMustEqual
    }

    public var description: String { rawValue }
}
