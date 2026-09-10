import Testing
@testable import AgenticToolkitCore

@Suite
struct SemanticVersionTests {

    @Test("parses major.minor.patch, major.minor, and major alone")
    func parsesShortForms() {
        #expect(SemanticVersion("1.74.0") == SemanticVersion(major: 1, minor: 74, patch: 0))
        #expect(SemanticVersion("1.74") == SemanticVersion(major: 1, minor: 74, patch: 0))
        #expect(SemanticVersion("1") == SemanticVersion(major: 1, minor: 0, patch: 0))
    }

    @Test("tolerates a leading v")
    func parsesLeadingV() {
        #expect(SemanticVersion("v1.74.0") == SemanticVersion(major: 1, minor: 74, patch: 0))
    }

    @Test(
        "rejects prerelease, build metadata, and non-numeric input",
        arguments: ["1.74.0-rc.1", "1.74.0+build", "abc", "", "1.x.0"]
    )
    func rejectsInvalid(_ input: String) {
        #expect(SemanticVersion(input) == nil)
    }

    @Test("orders across all three components, including the string-comparison trap")
    func ordering() {
        #expect(SemanticVersion(major: 1, minor: 0, patch: 0) < SemanticVersion(major: 2, minor: 0, patch: 0))
        #expect(SemanticVersion(major: 1, minor: 9, patch: 0) < SemanticVersion(major: 1, minor: 10, patch: 0))
        #expect(SemanticVersion(major: 1, minor: 74, patch: 0) < SemanticVersion(major: 1, minor: 74, patch: 1))
        #expect(!(SemanticVersion(major: 1, minor: 74, patch: 0) < SemanticVersion(major: 1, minor: 74, patch: 0)))
    }

    @Test("description round-trips through init")
    func descriptionRoundTrips() throws {
        let version = try #require(SemanticVersion("1.74.2"))
        #expect(version.description == "1.74.2")
        #expect(SemanticVersion(version.description) == version)
    }

    /// A version component is arithmetic, not just a label: `VSCodeEngineRange`
    /// computes a caret ceiling as `major + 1`, and on `Int` that is a
    /// *trapping* add. The guard belongs here rather than at each caller, so
    /// every consumer of this type inherits it.
    ///
    /// What this catches: a third-party `package.json` spelling
    /// `"engines": {"vscode": "^9223372036854775807"}`. Before the ceiling
    /// existed this parsed, and the trap fired inside `Features.init()` —
    /// before the app had any UI to disable the offending extension from.
    @Test(
        "rejects a component too large to do arithmetic on",
        arguments: [
            "\(Int.max)",
            "1.\(Int.max)",
            "1.74.\(Int.max)",
            "2147483648",
            "v2147483648.0.0"
        ]
    )
    func rejectsImplausiblyLargeComponents(_ input: String) {
        #expect(SemanticVersion(input) == nil)
    }

    /// The ceiling is inclusive, and the boundary is pinned so a later
    /// tightening cannot pass silently.
    @Test("accepts the largest component it promises to accept")
    func acceptsTheCeilingItself() {
        #expect(
            SemanticVersion("2147483647.2147483647.2147483647")
                == SemanticVersion(major: 2_147_483_647, minor: 2_147_483_647, patch: 2_147_483_647)
        )
        #expect(SemanticVersion("2147483648") == nil)
    }
}
