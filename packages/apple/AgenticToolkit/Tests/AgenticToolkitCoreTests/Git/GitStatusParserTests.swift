import Foundation
import Testing
@testable import AgenticToolkitCore

@Suite("GitStatus.parse")
struct GitStatusParserTests {
    @Test("empty output yields no statuses")
    func emptyOutput() {
        let status = GitStatus.parse(porcelain: "")
        #expect(status == .empty)
    }

    @Test("a modified file is marked modified")
    func modifiedFile() {
        let status = GitStatus.parse(porcelain: " M foo.txt\n")
        #expect(status.files["foo.txt"] == .modified)
    }

    @Test("an untracked file is marked untracked")
    func untrackedFile() {
        let status = GitStatus.parse(porcelain: "?? untracked/new.txt\n")
        #expect(status.files["untracked/new.txt"] == .untracked)
        #expect(status.directories["untracked"] == .untracked)
    }

    @Test("a status propagates to every parent directory")
    func directoryPropagation() {
        let status = GitStatus.parse(porcelain: " M a/b/c.txt\n")
        #expect(status.directories["a"] == .modified)
        #expect(status.directories["a/b"] == .modified)
    }

    @Test("a rename is recorded under the new path")
    func renamedFileUsesNewPath() {
        let status = GitStatus.parse(porcelain: "R  old.txt -> new.txt\n")
        #expect(status.files["new.txt"] == .renamed)
        #expect(status.files["old.txt"] == nil)
    }
}
