import Foundation
import Testing
@testable import AgenticToolkitCore

/// What the installer does when the file system says no partway through.
///
/// Separate from `VSIXInstallerTests`, which refuses bad input before anything
/// is written — every refusal there happens with the install directory
/// untouched, which is the easy half. These are the cases where the writing
/// has already started: one move of two has landed, or the new version is in
/// place and the old one will not go away. Neither can be staged with real
/// directories, because no arrangement of them makes `rename(2)` fail on the
/// second of two calls or `unlink(2)` fail on a directory the test itself
/// created — which is what the `fileManager` seam is for.
@Suite
struct VSIXInstallerFileSystemFailureTests {

    private static let host = SemanticVersion(major: 1, minor: 138, patch: 0)

    private let unsigned = VSIXVerification(
        sha256: "abc", digest: .notPublished, signature: .notPublished)

    /// Installs 1.0.0 into a fresh scratch directory and hands back both paths.
    /// Every test here needs a previous version to endanger.
    private func installFirstVersion(
        _ label: String
    ) throws -> (scratch: URL, installDirectory: URL) {
        let scratch = try VSIXFixtures.makeTemporaryDirectory(label)
        let installDirectory = scratch.appendingPathComponent("Extensions", isDirectory: true)
        let installer = VSIXInstaller(
            installDirectory: installDirectory, hostVersion: Self.host)

        _ = try installer.install(
            archive: try VSIXFixtures.makeVSIX(
                manifest: VSIXFixtures.manifestJSON(version: "1.0.0"),
                in: scratch,
                extraFile: "theme.json"),
            verification: unsigned,
            source: .localFile(scratch))

        return (scratch, installDirectory)
    }

    private func archive(version: String, in scratch: URL) throws -> Data {
        try VSIXFixtures.makeVSIX(
            manifest: VSIXFixtures.manifestJSON(version: version), in: scratch)
    }

    // MARK: - The move that fails after the old one is out of the way

    /// The outcome that would make an update button unsafe to press. The
    /// previous install is moved aside rather than deleted precisely so this
    /// can be undone, and until now nothing had ever run the undo: every test
    /// of a refused install refused *before* the first move.
    ///
    /// **The version reinstalled is the same one, and that is the whole
    /// point.** `moveIntoPlace` only moves anything aside when the
    /// *destination directory* already exists, and the destination is
    /// `<identifier>-<version>` — so installing 2.0.0 over 1.0.0 never touches
    /// 1.0.0 at all, and a test written that way watches the previous version
    /// survive a move that was never aimed at it. It passes with the rollback
    /// deleted; a mutation run is what said so. Reinstalling the same version
    /// is the case that reaches the undo, and the installer documents it as a
    /// supported, idempotent replace rather than a conflict.
    @Test("a move that fails puts the previous version back, whole")
    func aFailedMoveRestoresThePreviousVersion() throws {
        let (scratch, installDirectory) = try installFirstVersion("rollback-move")
        defer { try? FileManager.default.removeItem(at: scratch) }

        let manager = RefusingFileManager(refuseMovesInto: "acme.widget-1.0.0")
        let installer = VSIXInstaller(
            installDirectory: installDirectory,
            hostVersion: Self.host,
            fileManager: { manager })

        #expect(throws: VSIXInstallError.self) {
            try installer.install(
                archive: try self.archive(version: "1.0.0", in: scratch),
                verification: self.unsigned,
                source: .localFile(scratch))
        }

        // Nothing left under the `.replacing-` alias either: a rollback that
        // copied instead of moving would satisfy every assertion below and
        // leave the previous version duplicated in a hidden directory, which
        // `ExtensionRegistry` does not scan and nothing ever cleans up.
        #expect(try FileManager.default
            .contentsOfDirectory(atPath: installDirectory.path)
            .filter { $0.hasPrefix(".") } == [])

        // Back in its own name, not left under the `.replacing-` alias.
        #expect(VSIXFixtures.installedDirectoryNames(in: installDirectory)
            == ["acme.widget-1.0.0"])
        // And whole: a directory that exists but lost its payload is the same
        // failure wearing a different face, because `ExtensionRegistry` skips
        // an extension whose `package.json` is missing and `pruneOrphans`
        // then deletes the themes that extension owned.
        for file in ["package.json", "theme.json"] {
            #expect(FileManager.default.fileExists(
                atPath: installDirectory
                    .appendingPathComponent("acme.widget-1.0.0")
                    .appendingPathComponent(file).path))
        }
    }

    /// The error a caller is given has to say installing is what failed. The
    /// underlying `NSError` is a `Cocoa` file error whose text names neither
    /// the extension nor the operation, and the browse panel renders this
    /// case as a sentence.
    @Test("a move that fails is reported as a failure to install")
    func aFailedMoveIsReportedAsSuch() throws {
        let (scratch, installDirectory) = try installFirstVersion("rollback-error")
        defer { try? FileManager.default.removeItem(at: scratch) }

        let manager = RefusingFileManager(refuseMovesInto: "acme.widget-1.0.0")
        let installer = VSIXInstaller(
            installDirectory: installDirectory,
            hostVersion: Self.host,
            fileManager: { manager })

        do {
            _ = try installer.install(
                archive: try archive(version: "1.0.0", in: scratch),
                verification: unsigned,
                source: .localFile(scratch))
            Issue.record("a refused move was reported as a successful install")
        } catch let error as VSIXInstallError {
            guard case .couldNotInstall(let reason) = error else {
                Issue.record("wrong case: \(error)")
                return
            }
            #expect(!reason.isEmpty)
        }
    }

    /// The same failure with nothing to restore. There is no previous version,
    /// so the rollback branch is skipped entirely — and the thing to assert is
    /// that skipping it leaves no half-named wreckage behind either.
    @Test("a first install that fails to move leaves nothing behind")
    func aFailedFirstInstallLeavesNothing() throws {
        let scratch = try VSIXFixtures.makeTemporaryDirectory("rollback-first")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let installDirectory = scratch.appendingPathComponent("Extensions", isDirectory: true)

        let manager = RefusingFileManager(refuseMovesInto: "acme.widget-1.0.0")
        let installer = VSIXInstaller(
            installDirectory: installDirectory,
            hostVersion: Self.host,
            fileManager: { manager })

        #expect(throws: VSIXInstallError.self) {
            try installer.install(
                archive: try self.archive(version: "1.0.0", in: scratch),
                verification: self.unsigned,
                source: .localFile(scratch))
        }

        #expect(VSIXFixtures.installedDirectoryNames(in: installDirectory).isEmpty)
        // Nothing hidden, either: the aside name begins with a dot, so a
        // listing that filters dotfiles would call a littered directory clean.
        let everything = try FileManager.default.contentsOfDirectory(
            atPath: installDirectory.path)
        #expect(everything.isEmpty)
    }

    // MARK: - The old copy that will not go away

    /// Not fatal, and the reason is worth keeping: the new version is already
    /// in place and loadable by the time this runs. Throwing here would report
    /// an install that actually succeeded as having failed, and the user's
    /// recourse — press Install again — would do nothing, because it already
    /// worked.
    @Test("a superseded copy that cannot be removed does not fail the install")
    func anUnremovableSupersededCopyStillInstalls() throws {
        let (scratch, installDirectory) = try installFirstVersion("stale-removal")
        defer { try? FileManager.default.removeItem(at: scratch) }

        let manager = RefusingFileManager(refuseRemovalsOf: "acme.widget-1.0.0")
        let installer = VSIXInstaller(
            installDirectory: installDirectory,
            hostVersion: Self.host,
            fileManager: { manager })

        let installed = try installer.install(
            archive: try archive(version: "2.0.0", in: scratch),
            verification: unsigned,
            source: .localFile(scratch))

        #expect(installed.version == "2.0.0")
        // The failure is reported in the one place that survives: the
        // installation names the directory it could not clean up, which is
        // what turns this into a visible `duplicateIdentifier` row rather
        // than silence.
        #expect(installed.supersededDirectories.map(\.lastPathComponent)
            == ["acme.widget-1.0.0"])
        #expect(VSIXFixtures.installedDirectoryNames(in: installDirectory)
            == ["acme.widget-1.0.0", "acme.widget-2.0.0"])
        #expect(FileManager.default.fileExists(
            atPath: installDirectory
                .appendingPathComponent("acme.widget-2.0.0")
                .appendingPathComponent("package.json").path))
    }

    /// And with a cooperative file system it really is removed, which is the
    /// assertion that stops "never remove anything" from passing the one
    /// above.
    @Test("a superseded copy is removed when it can be")
    func aSupersededCopyIsRemovedWhenItCanBe() throws {
        let (scratch, installDirectory) = try installFirstVersion("stale-removed")
        defer { try? FileManager.default.removeItem(at: scratch) }

        let installer = VSIXInstaller(
            installDirectory: installDirectory, hostVersion: Self.host)

        _ = try installer.install(
            archive: try archive(version: "2.0.0", in: scratch),
            verification: unsigned,
            source: .localFile(scratch))

        #expect(VSIXFixtures.installedDirectoryNames(in: installDirectory)
            == ["acme.widget-2.0.0"])
    }

    // MARK: - A crash between the two renames

    /// **The window the aside name exists to close.** Replacing an install is
    /// two renames: the previous version out of the way, the new one in. Lose
    /// power between them and the extension is present on disk under a hidden
    /// name that `ExtensionRegistry` does not scan — so the extension is
    /// simply gone, and nothing in the app ever looks at that name again.
    ///
    /// Staged by hand rather than by killing a process, because there is no
    /// way to stop this one between two lines. What is staged is exactly what
    /// the crash leaves: the aside, and no destination.
    @Test("an aside left by a crash is put back under its own name")
    func anInterruptedReplacementIsPutBack() throws {
        let (scratch, installDirectory) = try installFirstVersion("recover-restore")
        defer { try? FileManager.default.removeItem(at: scratch) }

        let live = installDirectory.appendingPathComponent(
            "acme.widget-1.0.0", isDirectory: true)
        let aside = installDirectory.appendingPathComponent(
            ".acme.widget-1.0.0.replacing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.moveItem(at: live, to: aside)

        let installer = VSIXInstaller(
            installDirectory: installDirectory, hostVersion: Self.host)
        let recovered = installer.recoverInterruptedInstalls()

        #expect(recovered.map(\.lastPathComponent) == ["acme.widget-1.0.0"])
        #expect(VSIXFixtures.installedDirectoryNames(in: installDirectory)
            == ["acme.widget-1.0.0"])
        // Whole, not an empty directory wearing the right name.
        for file in ["package.json", "theme.json"] {
            #expect(FileManager.default.fileExists(
                atPath: live.appendingPathComponent(file).path))
        }
        #expect(!FileManager.default.fileExists(atPath: aside.path))
    }

    /// The other side of the same window, and the one that must *not* restore:
    /// the crash came after the second rename, so the new version is already
    /// in place and the aside is the superseded copy. Putting it back would
    /// undo a completed install.
    @Test("an aside whose destination is occupied is discarded, not restored")
    func aSupersededAsideIsDiscarded() throws {
        let (scratch, installDirectory) = try installFirstVersion("recover-discard")
        defer { try? FileManager.default.removeItem(at: scratch) }

        let live = installDirectory.appendingPathComponent(
            "acme.widget-1.0.0", isDirectory: true)
        let aside = installDirectory.appendingPathComponent(
            ".acme.widget-1.0.0.replacing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: live, to: aside)
        // The mark of the *new* copy, so a restore that overwrote it would be
        // visible rather than a directory comparing equal to itself.
        try Data("new".utf8).write(to: live.appendingPathComponent("marker.txt"))

        let installer = VSIXInstaller(
            installDirectory: installDirectory, hostVersion: Self.host)
        _ = installer.recoverInterruptedInstalls()

        #expect(!FileManager.default.fileExists(atPath: aside.path))
        #expect(FileManager.default.fileExists(
            atPath: live.appendingPathComponent("marker.txt").path))
    }

    /// Recovery runs on every install, so it has to leave an ordinary
    /// directory alone — including one whose name merely begins with a dot.
    /// A sweep that read any hidden entry as an aside would move a
    /// `.DS_Store` to `DS_Store`.
    @Test("a hidden entry that is not an aside is left where it is")
    func anUnrelatedHiddenEntryIsLeftAlone() throws {
        let (scratch, installDirectory) = try installFirstVersion("recover-unrelated")
        defer { try? FileManager.default.removeItem(at: scratch) }

        let stray = installDirectory.appendingPathComponent(".DS_Store")
        try Data("x".utf8).write(to: stray)

        let installer = VSIXInstaller(
            installDirectory: installDirectory, hostVersion: Self.host)
        let recovered = installer.recoverInterruptedInstalls()

        #expect(recovered.isEmpty)
        #expect(FileManager.default.fileExists(atPath: stray.path))
        #expect(!FileManager.default.fileExists(
            atPath: installDirectory.appendingPathComponent("DS_Store").path))
    }

    /// And the sweep is wired into `install`, not only exposed for a caller to
    /// remember: an install that follows a crash has to see the extension it
    /// is replacing, or `otherInstallDirectories` cannot find the stranded
    /// copy and the install leaves two of them.
    @Test("installing after a crash recovers the stranded copy first")
    func installingRunsTheRecoverySweep() throws {
        let (scratch, installDirectory) = try installFirstVersion("recover-on-install")
        defer { try? FileManager.default.removeItem(at: scratch) }

        let live = installDirectory.appendingPathComponent(
            "acme.widget-1.0.0", isDirectory: true)
        let aside = installDirectory.appendingPathComponent(
            ".acme.widget-1.0.0.replacing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.moveItem(at: live, to: aside)

        let installer = VSIXInstaller(
            installDirectory: installDirectory, hostVersion: Self.host)
        let installed = try installer.install(
            archive: try archive(version: "2.0.0", in: scratch),
            verification: unsigned,
            source: .localFile(scratch))

        #expect(installed.version == "2.0.0")
        // 1.0.0 was restored and then superseded by the install, so exactly one
        // directory is left — not 2.0.0 beside a hidden 1.0.0 nobody scans.
        #expect(VSIXFixtures.installedDirectoryNames(in: installDirectory)
            == ["acme.widget-2.0.0"])
        let everything = try FileManager.default.contentsOfDirectory(
            atPath: installDirectory.path)
        #expect(everything.filter { $0.hasPrefix(".") } == [])
    }

    // MARK: - When the rollback itself fails

    /// The worst case, and the one the message has to be honest about: the new
    /// version would not move in, and the previous version would not move
    /// back. The only copy of the extension is now under a hidden name, and a
    /// message that said only "could not install" would leave the user
    /// believing their previous version is still there.
    @Test("a rollback that fails names where the previous version was left")
    func aFailedRollbackSaysWhereTheCopyIs() throws {
        let (scratch, installDirectory) = try installFirstVersion("rollback-failed")
        defer { try? FileManager.default.removeItem(at: scratch) }

        // Refuses *every* move into the destination name, so the rollback —
        // which has the same destination and comes from a dotfile — fails too.
        let manager = RefusingFileManager(
            refuseMovesInto: "acme.widget-1.0.0", refusingAsides: true)
        let installer = VSIXInstaller(
            installDirectory: installDirectory,
            hostVersion: Self.host,
            fileManager: { manager })

        do {
            _ = try installer.install(
                archive: try archive(version: "1.0.0", in: scratch),
                verification: unsigned,
                source: .localFile(scratch))
            Issue.record("a refused move was reported as a successful install")
        } catch let error as VSIXInstallError {
            guard case .couldNotInstall(let reason) = error else {
                Issue.record("wrong case: \(error)")
                return
            }
            #expect(reason.contains("could not be put back"))
            // And it names the directory, because that is the only way anyone
            // gets the extension back by hand.
            #expect(reason.contains(".acme.widget-1.0.0.replacing-"))
        }

        // Still on disk under the aside name — not deleted to tidy up. It is
        // the only copy there is.
        let hidden = try FileManager.default
            .contentsOfDirectory(atPath: installDirectory.path)
            .filter { $0.hasPrefix(".") }
        #expect(hidden.count == 1)
    }
}

/// A `FileManager` that refuses one named operation and does everything else
/// for real.
///
/// Subclassed rather than protocol-extracted because the installer uses eight
/// different `FileManager` methods and only two of them are interesting here;
/// a protocol would be six passthroughs written twice, and every one of them
/// is a chance for the double to diverge from the real thing in a way no test
/// would notice.
///
/// The refusals are matched on the *last path component* rather than on a
/// whole path, because the paths involved are inside a temporary directory
/// whose name the test never sees, and because the interesting move has a
/// different source each run (`UUID` in the aside name).
private final class RefusingFileManager: FileManager, @unchecked Sendable {

    /// Fail a move whose destination ends in this — but only the one coming
    /// *from* the expanded payload.
    ///
    /// The rollback move has the very same destination, so a rule written on
    /// the destination alone refuses the undo as well and the test asserts
    /// about a rollback that never ran. What separates them is where they
    /// come from: the payload is in a scratch directory, and the copy set
    /// aside is a dotfile beside the install itself.
    private let refusedMoveDestination: String?

    /// Fail the removal of anything ending in this.
    private let refusedRemoval: String?

    /// Drop the "not from an aside" exemption, so the rollback move is
    /// refused as well. That is the double failure — nothing moved in, and the
    /// previous version could not be moved back — and it is the only way to
    /// reach the message that says so.
    private let refusingAsides: Bool

    init(
        refuseMovesInto: String? = nil,
        refuseRemovalsOf: String? = nil,
        refusingAsides: Bool = false
    ) {
        self.refusedMoveDestination = refuseMovesInto
        self.refusedRemoval = refuseRemovalsOf
        self.refusingAsides = refusingAsides
        super.init()
    }

    override func moveItem(at source: URL, to destination: URL) throws {
        if let refusedMoveDestination,
           destination.lastPathComponent == refusedMoveDestination,
           refusingAsides || !source.lastPathComponent.hasPrefix(".") {
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.moveItem(at: source, to: destination)
    }

    override func removeItem(at url: URL) throws {
        if let refusedRemoval, url.lastPathComponent == refusedRemoval {
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.removeItem(at: url)
    }
}
