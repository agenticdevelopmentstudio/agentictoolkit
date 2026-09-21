import Foundation
import Testing
@testable import AgenticToolkitCore

/// The three escape shapes a `.vsix` can carry, and the budget that bounds one
/// that never finishes.
///
/// `VSIXArchive.expand`'s own documentation states all three outcomes as fact —
/// "both were checked against a purpose-built archive rather than assumed" —
/// and no such archive was in the repo. A claim about a directory traversal in
/// the path that takes third-party archives off the internet is exactly the
/// claim that has to be re-checked by a machine: `ditto` is a platform binary
/// this code does not own, its behaviour is a dependency like any other, and a
/// macOS release is free to change it. These tests are what turns the comment
/// into something a build can disprove.
///
/// The archives come from `HostileZip` rather than `VSIXFixtures`, because no
/// archiver on this machine will write the names that matter — see that file.
@Suite
struct VSIXArchiveContainmentTests {

    // MARK: - Names that point out of the destination

    /// `../escaped.txt` is the classic zip-slip entry. What makes the test
    /// non-vacuous is the second assertion: if `ditto` had simply *skipped* the
    /// entry, nothing would be outside either, and the test would pass while
    /// proving nothing. The file has to land — flattened into the destination —
    /// for the refusal to be a refusal rather than an omission.
    @Test("an entry named ../escaped.txt is flattened into the destination")
    func aRelativeTraversalIsFlattened() throws {
        let scratch = try VSIXFixtures.makeTemporaryDirectory("traversal")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let archive = try HostileZip.write([
            .file("extension/package.json", "{}"),
            .file("../escaped.txt")
        ], into: scratch, named: "traversal.vsix")
        let destination = scratch.appendingPathComponent("expanded", isDirectory: true)

        try VSIXArchive.expand(archive, to: destination)

        #expect(!exists(scratch.appendingPathComponent("escaped.txt")))
        #expect(exists(destination.appendingPathComponent("escaped.txt")))
        #expect(exists(destination.appendingPathComponent("extension/package.json")))
    }

    /// An absolute entry name is the same attack spelled the other way, and it
    /// is the more dangerous half: `../` only reaches the parent, while `/etc`
    /// names anywhere. The leading slash is dropped and the whole path is
    /// re-rooted at the destination, so the entry lands at a deep nested path
    /// *inside* it.
    ///
    /// The absolute path aimed at is inside this test's own scratch directory
    /// rather than somewhere real: a test that proved containment by trying to
    /// write to `/tmp` would be a test that damages the machine on the day it
    /// starts failing.
    @Test("an entry with an absolute name is re-rooted inside the destination")
    func anAbsoluteNameIsReRooted() throws {
        let scratch = try VSIXFixtures.makeTemporaryDirectory("absolute")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let aimedAt = scratch.appendingPathComponent("planted.txt")
        let archive = try HostileZip.write([
            .file("extension/package.json", "{}"),
            .file(aimedAt.path)
        ], into: scratch, named: "absolute.vsix")
        let destination = scratch.appendingPathComponent("expanded", isDirectory: true)

        try VSIXArchive.expand(archive, to: destination)

        #expect(!exists(aimedAt))
        // Where the leading slash having been dropped puts it: the whole
        // absolute path, minus its root, underneath the destination.
        let reRooted = destination.appendingPathComponent(String(aimedAt.path.dropFirst()))
        #expect(exists(reRooted))
    }

    /// The shape a flattening rule alone does not stop. Every entry name here
    /// is innocent — `link` and `link/evil.txt` are both inside the
    /// destination — and the escape is that `link` is a *symlink* to somewhere
    /// else, so writing the second entry writes through it.
    ///
    /// The whole extraction fails rather than the one entry being skipped, and
    /// `expand` then removes the destination, so the planted symlink does not
    /// survive either. Both halves matter: a partial tree left behind is a
    /// half-installed extension, and the symlink in it is the escape still
    /// sitting there for whatever walks the directory next.
    @Test("a symlink written through fails the whole expansion and plants nothing")
    func aSymlinkWrittenThroughFailsTheExpansion() throws {
        let scratch = try VSIXFixtures.makeTemporaryDirectory("symlink")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let outside = scratch.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let archive = try HostileZip.write([
            .file("extension/package.json", "{}"),
            .symlink("link", to: outside.path),
            .file("link/evil.txt")
        ], into: scratch, named: "symlink.vsix")
        let destination = scratch.appendingPathComponent("expanded", isDirectory: true)

        var thrown: (any Error)?
        do { try VSIXArchive.expand(archive, to: destination) } catch { thrown = error }

        let failure = try #require(thrown as? VSIXArchiveError)
        guard case .expansionFailed(let status, let message) = failure else {
            Issue.record("expected .expansionFailed, got \(failure)")
            return
        }
        #expect(status != 0)
        // `ditto` says why on standard error, and the message is the only thing
        // that tells a user reading a log which entry was the problem.
        #expect(!message.isEmpty)
        #expect(!exists(outside.appendingPathComponent("evil.txt")))
        #expect(!exists(destination))
    }

    // MARK: - An expansion that does not end

    /// The budget's own path, which nothing reached before: an archive that
    /// expands forever is a real shape, and until this test the code that gives
    /// up on one had never run.
    ///
    /// A millisecond is not a realistic budget — it is the smallest one that
    /// makes the test about the giving-up rather than about how fast this
    /// machine is. `ditto` cannot be spawned, let alone finish, inside it, so
    /// the outcome does not depend on the archive being slow.
    @Test("an expansion that outlasts its budget is stopped, and leaves nothing")
    func anExpansionThatOutlastsItsBudgetIsStopped() throws {
        let scratch = try VSIXFixtures.makeTemporaryDirectory("timeout")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let archive = try HostileZip.write([
            .file("extension/package.json", "{}")
        ], into: scratch, named: "slow.vsix")
        let destination = scratch.appendingPathComponent("expanded", isDirectory: true)

        #expect(throws: VSIXArchiveError.expansionTimedOut(seconds: 0.001)) {
            try VSIXArchive.expand(archive, to: destination, timeout: 0.001)
        }

        // The half-written tree is gone, so the retry hits the archive again
        // rather than `destinationExists`.
        #expect(!exists(destination))
    }

    /// The default is what production uses, and a budget that only applied when
    /// a caller remembered to pass one would be no budget at all.
    @Test("the default budget is the published one")
    func theDefaultBudgetIsThePublishedOne() {
        #expect(VSIXArchive.expansionTimeout == 120)
    }

    // MARK: - The fixture is a real zip

    /// `HostileZip` writes the format by hand, so the traversal tests above are
    /// only worth anything if what it writes is an archive the platform agrees
    /// is an archive. An ordinary entry, expanded by the same `ditto` call, is
    /// the check — a malformed archive would fail here rather than quietly
    /// making every containment test pass by never extracting anything.
    @Test("a hand-built archive expands like any other")
    func theHandBuiltArchiveIsValid() throws {
        let scratch = try VSIXFixtures.makeTemporaryDirectory("valid")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let archive = try HostileZip.write([
            .file("extension/package.json", "{\"name\": \"widget\"}")
        ], into: scratch, named: "ordinary.vsix")
        let destination = scratch.appendingPathComponent("expanded", isDirectory: true)

        try VSIXArchive.expand(archive, to: destination)

        let manifest = VSIXArchive.payloadDirectory(in: destination)
            .appendingPathComponent("package.json")
        #expect(try String(contentsOf: manifest, encoding: .utf8) == "{\"name\": \"widget\"}")
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}
