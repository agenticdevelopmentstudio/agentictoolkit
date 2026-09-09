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
}
