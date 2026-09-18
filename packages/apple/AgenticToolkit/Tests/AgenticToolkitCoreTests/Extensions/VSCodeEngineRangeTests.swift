import Testing
@testable import AgenticToolkitCore

@Suite
struct VSCodeEngineRangeTests {

    /// The host version the survey cases below are judged against — high
    /// enough that nothing in the registry floors above it, so every case
    /// here isolates the *grammar* rather than the floor comparison.
    private let host = SemanticVersion(major: 1, minor: 138, patch: 0)

    @Test("caret range accepts the floor and anything below the next major")
    func caretAccepts() throws {
        let range = try #require(VSCodeEngineRange("^1.74.0"))
        #expect(range.accepts(SemanticVersion(major: 1, minor: 74, patch: 0)))
        #expect(range.accepts(SemanticVersion(major: 1, minor: 95, patch: 0)))
        #expect(range.accepts(SemanticVersion(major: 1, minor: 74, patch: 1)))
    }

    @Test("caret range rejects below the floor and at/above the next major")
    func caretRejects() throws {
        let range = try #require(VSCodeEngineRange("^1.74.0"))
        #expect(!range.accepts(SemanticVersion(major: 1, minor: 73, patch: 9)))
        #expect(!range.accepts(SemanticVersion(major: 2, minor: 0, patch: 0)))
    }

    @Test(">= range accepts anything at or above the floor")
    func atLeastAccepts() throws {
        let range = try #require(VSCodeEngineRange(">=1.74.0"))
        #expect(range.accepts(SemanticVersion(major: 2, minor: 0, patch: 0)))
    }

    @Test("exact range accepts only the exact version")
    func exactAcceptsOnlyItself() throws {
        let range = try #require(VSCodeEngineRange("1.74.0"))
        #expect(range.accepts(SemanticVersion(major: 1, minor: 74, patch: 0)))
        #expect(!range.accepts(SemanticVersion(major: 1, minor: 74, patch: 1)))
    }

    // MARK: - The grammar VS Code actually defines

    /// `*` is the single most common `engines.vscode` value on Open VSX — 45
    /// of the 198 web extensions in the 600-most-downloaded sample
    /// (`Scripts/openvsx_engine_survey.py`), more than any other string. It
    /// was rejected here on the strength of a doc comment claiming the
    /// manifest reference forbids it. Upstream is unambiguous the other way:
    /// `isValidVersionStr` at `extensionValidator.ts:39-42` returns true for
    /// `*` before it ever consults the regexp, and `parseVersion` :51-63
    /// gives it every `mustEqual` false, which is "any version".
    @Test("a star engine accepts every version")
    func starAcceptsEverything() throws {
        let range = try #require(VSCodeEngineRange("*"))
        #expect(range.accepts(host))
        #expect(range.accepts(SemanticVersion(major: 0, minor: 0, patch: 1)))
        #expect(range.accepts(SemanticVersion(major: 42, minor: 0, patch: 0)))
    }

    /// A `*` engine must not pick up the implicit command activation VS Code
    /// grants from 1.74, because upstream's parse floors it at 0.0.0 rather
    /// than at the current version. `ActivationEventMatcher` reads
    /// `minimumVersion` for exactly that decision, so the floor is the seam
    /// this has to hold at.
    @Test("a star engine floors at zero, so it earns no implicit command activation")
    func starFloorsAtZero() throws {
        let range = try #require(VSCodeEngineRange("*"))
        #expect(range.minimumVersion == SemanticVersion(major: 0, minor: 0, patch: 0))
    }

    /// `x` in any component is upstream's wildcard: `VERSION_REGEXP` at
    /// `extensionValidator.ts:36` admits `(\d+)|x` per component, and
    /// `parseVersion` :70-78 turns an `x` into base 0 with its `mustEqual`
    /// false — i.e. "this component is unconstrained".
    @Test(
        "an x wildcard leaves its component unconstrained",
        arguments: [
            ("1.x.x", true),
            ("1.138.x", true),
            ("x.x.x", true),
            ("2.x.x", false),
            ("1.139.x", false)
        ]
    )
    func wildcardComponents(_ input: String, _ expected: Bool) throws {
        let range = try #require(VSCodeEngineRange(input))
        #expect(range.accepts(host) == expected)
    }

    /// A pre-release suffix is part of the grammar (`(\-.*)?` at
    /// `extensionValidator.ts:36`), not a parse failure. Two of the sample's
    /// web extensions declare `-insider` suffixes. Upstream only ever
    /// *uses* the suffix when it is a `-YYYYMMDD` date and a product build
    /// date is supplied (`isValidVersion` :180-182, guarded by `productTs`);
    /// with no product date the suffix cannot reject anything, which is the
    /// position this host is in.
    @Test(
        "a pre-release suffix parses and does not narrow the range",
        arguments: ["^1.89.0-insider", "^1.79.0-insider", "^1.89.0-20240101"]
    )
    func preReleaseSuffixIsAccepted(_ input: String) throws {
        let range = try #require(VSCodeEngineRange(input))
        #expect(range.accepts(host))
    }

    /// Upstream's one genuinely surprising rule, at `isValidVersion`
    /// :187-195: *"Anything < 1.0.0 is compatible with >= 1.0.0, except exact
    /// matches."* A `^0.10.x` extension therefore runs on 1.138.0, because
    /// the caret cleared a `mustEqual` and the whole requirement is rewritten
    /// to 1.0.0. This is **not** npm's caret rule, which holds the leftmost
    /// non-zero component fixed and would cap `^0.10.5` at 0.11.0 — modelling
    /// it as npm's is what made this wrong.
    @Test(
        "a sub-1.0.0 requirement with any slack is satisfied by a 1.x host",
        arguments: ["^0.10.5", "^0.10.x", "0.10.x", "^0.0.1"]
    )
    func subOneRequirementsWithSlackAccept1x(_ input: String) throws {
        let range = try #require(VSCodeEngineRange(input))
        #expect(range.accepts(host))
    }

    /// The carve-out in the same rule: a fully-pinned sub-1.0.0 requirement
    /// has no slack — all three `mustEqual` are true — so the rewrite does
    /// not fire and a 1.x host is refused. 13 of the sample's web extensions
    /// declare a bare `0.10.0`, and VS Code refuses them too. Agreeing with
    /// upstream here matters as much as agreeing with it above.
    @Test("a fully-pinned sub-1.0.0 requirement is still refused by a 1.x host")
    func exactSubOneRequirementRejects1x() throws {
        let range = try #require(VSCodeEngineRange("0.10.0"))
        #expect(!range.accepts(host))
        #expect(range.accepts(SemanticVersion(major: 0, minor: 10, patch: 0)))
    }

    /// The shapes upstream's grammar genuinely has no production for. `~`,
    /// `>`, `<` and `||` are npm range syntax VS Code never implemented, and
    /// a two-component range is outside `VERSION_REGEXP`, which requires all
    /// three. A range this type cannot evaluate is a load failure naming the
    /// raw string — `ExtensionRegistry` records `.engineRangeUnparsable` and
    /// skips that one extension — never a silent pass or a silent reject.
    @Test(
        "rejects grammar VS Code does not define",
        arguments: ["~1.74.0", ">1.74.0", "<2.0.0", "1.74.0 || 2.0.0", "1.74", "1", "", "latest", "^"]
    )
    func rejectsUnsupportedGrammar(_ input: String) {
        #expect(VSCodeEngineRange(input) == nil)
    }

    /// Upstream trims a range before matching it (`isValidVersionStr` at
    /// `extensionValidator.ts:40`) and has no production for whitespace
    /// anywhere inside it — `VERSION_REGEXP` runs the operator straight into
    /// the first component. Tolerating `">= 1.74.0"` here would run an
    /// extension this host refuses to run in VS Code, which is the wrong
    /// direction to diverge for a host strictly less capable than the one
    /// these manifests were written against.
    @Test("trims surrounding whitespace but does not admit whitespace inside the range")
    func whitespaceIsTrimmedNotTolerated() throws {
        let range = try #require(VSCodeEngineRange("  ^1.74.0  "))
        #expect(range.accepts(SemanticVersion(major: 1, minor: 74, patch: 0)))

        #expect(VSCodeEngineRange(">= 1.74.0") == nil)
        #expect(VSCodeEngineRange("^ 1.74.0") == nil)
    }

    /// Every requirement form is fed a component no `Int` arithmetic here
    /// should ever meet. All four parse their operands through
    /// `SemanticVersion.init?`, which is where the plausibility bound lives,
    /// so all four must reject the same input at the same place rather than
    /// each re-deriving it.
    @Test(
        "rejects a component above the plausibility bound",
        arguments: [
            "^\(Int.max).0.0",
            ">=\(Int.max).0.0",
            "\(Int.max).0.0",
            "^2147483648.0.0",
            "1.\(Int.max).0",
            "1.0.\(Int.max)"
        ]
    )
    func rejectsOversizedComponents(_ input: String) {
        #expect(VSCodeEngineRange(input) == nil)
    }

    @Test("minimumVersion is the floor for caret and >= ranges, and the version itself for an exact range")
    func minimumVersionIsTheFloor() throws {
        let caret = try #require(VSCodeEngineRange("^1.74.0"))
        #expect(caret.minimumVersion == SemanticVersion(major: 1, minor: 74, patch: 0))

        let atLeast = try #require(VSCodeEngineRange(">=1.80.2"))
        #expect(atLeast.minimumVersion == SemanticVersion(major: 1, minor: 80, patch: 2))

        let exact = try #require(VSCodeEngineRange("1.74.0"))
        #expect(exact.minimumVersion == SemanticVersion(major: 1, minor: 74, patch: 0))
    }

    /// The largest component this type still evaluates, exercised through
    /// `accepts` rather than parsing alone: a boundary that parses must also
    /// be safe to compare against.
    @Test("evaluates the largest component it accepts without trapping")
    func acceptsTheLargestPermittedMajor() throws {
        let range = try #require(VSCodeEngineRange("^2147483647.0.0"))
        #expect(range.accepts(SemanticVersion(major: 2_147_483_647, minor: 9, patch: 9)))
        #expect(!range.accepts(SemanticVersion(major: 1, minor: 95, patch: 0)))
    }

    // MARK: - The registry as it really is

    /// Every distinct `engines.vscode` string that more than one web
    /// extension in the survey declares, judged against the version this
    /// host declares. The point is not the individual rows: it is that the
    /// host's declared version and this type's grammar between them admit
    /// the extensions people actually install. A regression in either — a
    /// lowered `declaredVSCodeVersion`, a narrowed grammar — turns rows here
    /// red rather than silently shrinking the installable catalogue.
    @Test(
        "the declared host version admits the ranges real web extensions publish",
        arguments: [
            "*", "^1.0.0", "^1.63.0", "^1.65.0", "^1.75.0", "^1.77.0", "^1.82.0",
            "^1.83.0", "^1.88.0", "^1.89.0", "^1.90.0", "^1.95.0", "^1.97.0",
            "^1.101.0", "^1.137.0"
        ]
    )
    func declaredVersionAdmitsRealRanges(_ input: String) throws {
        let range = try #require(VSCodeEngineRange(input))
        #expect(range.accepts(ExtensionRegistry.declaredVSCodeVersion))
    }
}
