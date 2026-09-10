import Foundation
import Testing
@testable import AgenticToolkitCore

@Suite("GitBranch.parse")
struct GitBranchParserTests {
    @Test("parses name, current marker and upstream")
    func parsesFields() {
        let output = "main\t*\torigin/main\nfeature\t\t\ntabs\t\torigin/tabs\n"
        let branches = GitBranch.parse(forEachRef: output)
        #expect(branches == [
            GitBranch(name: "main", isCurrent: true, upstream: "origin/main"),
            GitBranch(name: "feature", isCurrent: false, upstream: nil),
            GitBranch(name: "tabs", isCurrent: false, upstream: "origin/tabs")
        ])
    }

    @Test("ignores blank lines")
    func ignoresBlankLines() {
        #expect(GitBranch.parse(forEachRef: "\n\n").isEmpty)
    }

    @Test("a non-current branch's HEAD field is a single space, not empty")
    func realisticNonCurrentHeadField() {
        let output = "main\t \torigin/main\nfeature\t \t\n"
        let branches = GitBranch.parse(forEachRef: output)
        #expect(branches == [
            GitBranch(name: "main", isCurrent: false, upstream: "origin/main"),
            GitBranch(name: "feature", isCurrent: false, upstream: nil)
        ])
    }
}
