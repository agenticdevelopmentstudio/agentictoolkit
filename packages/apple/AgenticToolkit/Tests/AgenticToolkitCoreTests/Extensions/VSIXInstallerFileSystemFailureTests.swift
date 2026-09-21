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

    init(refuseMovesInto: String? = nil, refuseRemovalsOf: String? = nil) {
        self.refusedMoveDestination = refuseMovesInto
        self.refusedRemoval = refuseRemovalsOf
        super.init()
    }

    override func moveItem(at source: URL, to destination: URL) throws {
        if let refusedMoveDestination,
           destination.lastPathComponent == refusedMoveDestination,
           !source.lastPathComponent.hasPrefix(".") {
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
