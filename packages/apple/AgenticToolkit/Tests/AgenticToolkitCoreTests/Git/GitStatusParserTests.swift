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

    @Test("a work-tree rename consumes its origin field instead of desynchronising")
    func workTreeRenameConsumesItsOriginField() {
        // `git mv a b` followed by `git add -N b` leaves " R" — renamed in
        // the work tree, with the index column blank. The origin field is
        // written for that shape too, so a parser that only recognised a
        // rename in the index column read `App/Sources/Bar.swift` as the next
        // status record: the rename vanished and a phantom `.added` entry
        // appeared under `/Sources/Bar.swift`, three characters in.
        let status = GitStatus.parse(
            porcelain: " R App/Sources/Foo.swift\u{0}App/Sources/Bar.swift\u{0} M README.md\u{0}"
        )
        #expect(status.files["App/Sources/Foo.swift"] == .renamed)
        #expect(status.files["App/Sources/Bar.swift"] == nil)
        #expect(status.files["/Sources/Bar.swift"] == nil)
        #expect(status.files["README.md"] == .modified)
        #expect(status.files.count == 2)
    }

    @Test("a non-ASCII path is keyed exactly, with no C-quoting")
    func nonASCIIPathIsKeyedExactly() {
        // Without `-z`, `core.quotePath` would C-quote this as
        // `"caf\303\251.txt"` and that string, quotes included, would become
        // the dictionary key. `-z` disables the quoting entirely.
        let status = GitStatus.parse(porcelain: " M café.txt\u{0}")
        #expect(status.files["café.txt"] == .modified)
    }

    @Test("a path beginning with a combining mark keeps every byte")
    func pathBeginningWithACombiningMarkIsNotTruncated() {
        // U+0301 COMBINING ACUTE ACCENT is a legal leading byte sequence for a
        // filename, and it clusters with whatever precedes it — here the space
        // that separates the status columns from the path. Counted and sliced
        // in `Character`s, the four-byte record `" M" + " " + "\u{301}"` has a
        // `count` of 3 and `dropFirst(3)` consumed the accent along with the
        // separator, leaving an empty path. That empty path then reached the
        // directory roll-up, where `removeLast()` on no components trapped the
        // process — a `git status` refresh in the file browser taking the app
        // down.
        let status = GitStatus.parse(porcelain: " M \u{301}.txt\u{0}")
        #expect(status.files["\u{301}.txt"] == .modified)
        #expect(status.files[""] == nil)
    }

    @Test("a record with nothing but a status and a separator is skipped")
    func recordWithNoPathIsSkipped() {
        // Malformed, and therefore exactly what must not cost more than the
        // one record: `split` drops empty components, so an empty path yields
        // no components at all and the roll-up's `removeLast()` would trap.
        let status = GitStatus.parse(porcelain: " M \u{0} M kept.txt\u{0}")
        #expect(status.files["kept.txt"] == .modified)
        #expect(status.files[""] == nil)
    }

    @Test("a path that is only separators is skipped rather than trapping")
    func pathOfSeparatorsOnlyIsSkipped() {
        let status = GitStatus.parse(porcelain: " M ///\u{0}")
        #expect(status.directories.isEmpty)
    }
}
