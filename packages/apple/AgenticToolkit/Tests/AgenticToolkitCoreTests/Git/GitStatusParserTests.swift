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
        let status = GitStatus.parse(porcelain: " M foo.txt\u{0}")
        #expect(status.files["foo.txt"] == .modified)
    }

    @Test("an untracked file is marked untracked")
    func untrackedFile() {
        let status = GitStatus.parse(porcelain: "?? untracked/new.txt\u{0}")
        #expect(status.files["untracked/new.txt"] == .untracked)
        #expect(status.directories["untracked"] == .untracked)
    }

    @Test("a status propagates to every parent directory")
    func directoryPropagation() {
        let status = GitStatus.parse(porcelain: " M a/b/c.txt\u{0}")
        #expect(status.directories["a"] == .modified)
        #expect(status.directories["a/b"] == .modified)
    }

    @Test("a rename is recorded under the new path")
    func renamedFileUsesNewPath() {
        // With `-z`, a rename record is two NUL-terminated fields, new path
        // first, rather than one line with an arrow.
        let status = GitStatus.parse(porcelain: "R  new.txt\u{0}old.txt\u{0}")
        #expect(status.files["new.txt"] == .renamed)
        #expect(status.files["old.txt"] == nil)
    }

    @Test("a combined rename+modify (RM) is recorded as renamed under the new path")
    func renameAndModifyIsRecordedAsRenamed() {
        // The state a `git mv` followed by an edit leaves. Before the M3/M2
        // fix, the modification ladder won this race and stored
        // `files["old.txt -> new.txt"] = .modified` — invisible to any
        // lookup by real path, and poisoning the directory roll-up with a
        // phantom directory key.
        let status = GitStatus.parse(porcelain: "RM new.txt\u{0}old.txt\u{0}")
        #expect(status.files["new.txt"] == .renamed)
        #expect(status.files["old.txt"] == nil)
        #expect(status.files["old.txt -> new.txt"] == nil)
    }

    @Test("a non-ASCII path is keyed exactly, with no C-quoting")
    func nonASCIIPathIsKeyedExactly() {
        // Without `-z`, `core.quotePath` would C-quote this as
        // `"caf\303\251.txt"` and that string, quotes included, would become
        // the dictionary key. `-z` disables the quoting entirely.
        let status = GitStatus.parse(porcelain: " M café.txt\u{0}")
        #expect(status.files["café.txt"] == .modified)
    }
}
