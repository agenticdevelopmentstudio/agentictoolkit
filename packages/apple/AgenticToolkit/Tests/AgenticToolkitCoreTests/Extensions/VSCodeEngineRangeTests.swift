import Testing
@testable import AgenticToolkitCore

@Suite
struct VSCodeEngineRangeTests {

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

    @Test(
        "rejects grammar this type does not implement",
        arguments: ["*", "~1.74.0", ">1.74.0", "1.74.0 || 2.0.0"]
    )
    func rejectsUnsupportedGrammar(_ input: String) {
        #expect(VSCodeEngineRange(input) == nil)
    }

    @Test("tolerates whitespace around the operator")
    func toleratesWhitespace() throws {
        let range = try #require(VSCodeEngineRange("  ^1.74.0  "))
        #expect(range.accepts(SemanticVersion(major: 1, minor: 74, patch: 0)))

        let atLeast = try #require(VSCodeEngineRange(">= 1.74.0"))
        #expect(atLeast.accepts(SemanticVersion(major: 1, minor: 74, patch: 0)))
    }

    /// Every requirement form is fed a major a caret ceiling cannot survive.
    ///
    /// `^` is the one that does the arithmetic (`floor.major + 1`, a trapping
    /// add), but `>=` and the exact form are listed too because they share the
    /// shape: all three parse their operand with `SemanticVersion.init?`, which
    /// is where the guard lives, so all three must reject the same input. A
    /// range this type cannot evaluate is a load failure that names the raw
    /// string — `ExtensionRegistry` records `.engineRangeUnparsable` and skips
    /// the extension — not a trap inside `Features.init()`.
    @Test(
        "rejects a version whose major cannot be incremented",
        arguments: [
            "^\(Int.max)",
            ">=\(Int.max)",
            "\(Int.max)",
            "^\(Int.max).0.0",
            "^2147483648"
        ]
    )
    func rejectsOverflowingMajors(_ input: String) {
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

    /// The largest major this type still evaluates, exercised through
    /// `accepts` rather than parsing alone — the trapping add is in `accepts`,
    /// so a boundary that parses must also be safe to compare against.
    @Test("evaluates the largest major it accepts without trapping")
    func acceptsTheLargestPermittedMajor() throws {
        let range = try #require(VSCodeEngineRange("^2147483647"))
        #expect(range.accepts(SemanticVersion(major: 2_147_483_647, minor: 9, patch: 9)))
        #expect(!range.accepts(SemanticVersion(major: 1, minor: 95, patch: 0)))
    }
}
