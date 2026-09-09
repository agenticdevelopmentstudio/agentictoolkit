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
}
