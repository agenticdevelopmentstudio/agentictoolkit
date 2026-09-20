import Foundation
import Testing
@testable import AgenticToolkitCore

/// Putting an extension on disk, and taking the previous one away.
///
/// The failure this type is built around is invisible: `ExtensionRegistry`
/// silently skips a directory whose `package.json` has not landed yet, calls
/// the scan complete, and `pruneOrphans` then deletes that extension's themes
/// — including the one the user is looking at. So the assertions here are as
/// much about what is *not* on disk at each moment as about what is.
///
/// Every test installs into its own temporary directory. `installDirectory` is
/// the injected seam precisely so a test never touches a real user's
/// extensions folder.
@Suite
struct VSIXInstallerTests {

    private static let host = SemanticVersion(major: 1, minor: 138, patch: 0)

    // MARK: - Fixtures

    // The archive fixtures live in `VSIXFixtures`, which
    // `VSIXRegistryInstallTests` shares. Forwarded rather than called through
    // directly so that moving them did not have to rewrite every call site in
    // this file, which would have buried the change that mattered.

    private func makeTemporaryDirectory(_ name: String) throws -> URL {
        try VSIXFixtures.makeTemporaryDirectory(name)
    }

    private func manifestJSON(
        name: String = "widget",
        publisher: String = "acme",
        version: String = "1.0.0",
        engine: String = "^1.74.0",
        entryPoint: String? = nil
    ) -> String {
        VSIXFixtures.manifestJSON(
            name: name,
            publisher: publisher,
            version: version,
            engine: engine,
            entryPoint: entryPoint)
    }

    private func makeVSIX(
        manifest: String?,
        in scratch: URL,
        extraFile: String? = nil
    ) throws -> Data {
        try VSIXFixtures.makeVSIX(manifest: manifest, in: scratch, extraFile: extraFile)
    }

    /// What the local-file path hands the installer: nothing was published to
    /// check against, because there is no registry in that flow at all.
    private let unsigned = VSIXVerification(
        sha256: "abc", digest: .notPublished, signature: .notPublished)

    private func installedDirectoryNames(in directory: URL) -> [String] {
        VSIXFixtures.installedDirectoryNames(in: directory)
    }

    // MARK: - The happy path

    @Test("an extension lands under publisher.name-version, whole")
    func installsUnderTheConventionalName() throws {
        let scratch = try makeTemporaryDirectory("happy")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let installDirectory = scratch.appendingPathComponent("Extensions", isDirectory: true)
        let installer = VSIXInstaller(installDirectory: installDirectory, hostVersion: Self.host)

        let archive = try makeVSIX(manifest: manifestJSON(), in: scratch, extraFile: "theme.json")
        let installation = try installer.install(
            archive: archive,
            verification: unsigned,
            expectedIdentifier: "acme.widget",
            source: .registry("acme/widget", version: "1.0.0"))

        #expect(installation.identifier == "acme.widget")
        #expect(installation.version == "1.0.0")
        #expect(installation.displayName == "The widget")
        #expect(installation.directory.lastPathComponent == "acme.widget-1.0.0")
        #expect(installation.supersededDirectories.isEmpty)
        #expect(installedDirectoryNames(in: installDirectory) == ["acme.widget-1.0.0"])
        // The payload's contents, not just the manifest: an install that
        // dropped everything but `package.json` would still pass every
        // assertion above.
        #expect(FileManager.default.fileExists(
            atPath: installation.directory.appendingPathComponent("theme.json").path))
    }

    /// The layout the Marketplace installer writes, so someone comparing this
    /// app's extensions directory against VS Code's sees the same names.
    @Test("the directory name is identifier-version")
    func directoryNameIsConventional() {
        #expect(
            VSIXInstaller.directoryName(identifier: "acme.widget", version: "1.2.3")
                == "acme.widget-1.2.3")
    }

    /// The install directory does not have to exist yet — a first install into
    /// a fresh home is the common case, not an edge one.
    @Test("a missing install directory is created")
    func createsTheInstallDirectory() throws {
        let scratch = try makeTemporaryDirectory("fresh")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let installDirectory = scratch
            .appendingPathComponent("does", isDirectory: true)
            .appendingPathComponent("not/exist", isDirectory: true)
        let installer = VSIXInstaller(installDirectory: installDirectory, hostVersion: Self.host)

        let archive = try makeVSIX(manifest: manifestJSON(), in: scratch)
        _ = try installer.install(
            archive: archive, verification: unsigned, source: .localFile(scratch))

        #expect(installedDirectoryNames(in: installDirectory) == ["acme.widget-1.0.0"])
    }

    // MARK: - What the manifest decides

    /// `runnableHere` cannot be known from the registry's metadata — only the
    /// archive's manifest says it — which is why it is reported rather than
    /// checked as a precondition.
    @Test("runnableHere follows the manifest's entry point, and is not a failure")
    func runnableHereFollowsTheEntryPoint() throws {
        let scratch = try makeTemporaryDirectory("runnable")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let installer = VSIXInstaller(
            installDirectory: scratch.appendingPathComponent("Extensions", isDirectory: true),
            hostVersion: Self.host)

        // A web extension: declares `browser`, so its code runs here.
        let web = try installer.install(
            archive: try makeVSIX(
                manifest: manifestJSON(name: "web", entryPoint: "browser"), in: scratch),
            verification: unsigned,
            source: .localFile(scratch))
        #expect(web.runnableHere)

        // A theme or snippet pack: no entry point at all, nothing to run, and
        // its declarative contributions work perfectly.
        let declarative = try installer.install(
            archive: try makeVSIX(manifest: manifestJSON(name: "theme"), in: scratch),
            verification: unsigned,
            source: .localFile(scratch))
        #expect(declarative.runnableHere)

        // A Node extension: `main` and no `browser`. Installed — its themes
        // and commands still contribute — but its code will not run here.
        let node = try installer.install(
            archive: try makeVSIX(
                manifest: manifestJSON(name: "node", entryPoint: "main"), in: scratch),
            verification: unsigned,
            source: .localFile(scratch))
        #expect(!node.runnableHere)
        #expect(FileManager.default.fileExists(atPath: node.directory.path))
    }

    /// The registry said one thing and the archive contains another: a
    /// substitution, and installing it would put an extension on disk under a
    /// name nothing in the UI expects.
    @Test("an archive whose identity does not match the claim is refused")
    func identityMismatchIsRefused() throws {
        let scratch = try makeTemporaryDirectory("identity")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let installDirectory = scratch.appendingPathComponent("Extensions", isDirectory: true)
        let installer = VSIXInstaller(installDirectory: installDirectory, hostVersion: Self.host)

        let archive = try makeVSIX(manifest: manifestJSON(name: "widget"), in: scratch)
        #expect(throws: VSIXInstallError.identityMismatch(
            claimed: "acme.something-else", found: "acme.widget")) {
            try installer.install(
                archive: archive,
                verification: unsigned,
                expectedIdentifier: "acme.something-else",
                source: .registry("acme/something-else", version: "1.0.0"))
        }
        // Refused before anything was written.
        #expect(installedDirectoryNames(in: installDirectory).isEmpty)
    }

    /// The registry's metadata and the archive's own manifest can disagree,
    /// and the manifest is the one the registry will be loaded by — so it is
    /// checked too, here, rather than becoming a failure row later.
    @Test("an engine range the host falls outside is refused after the download")
    func engineIncompatibleIsRefused() throws {
        let scratch = try makeTemporaryDirectory("engine")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let installDirectory = scratch.appendingPathComponent("Extensions", isDirectory: true)
        let installer = VSIXInstaller(installDirectory: installDirectory, hostVersion: Self.host)

        let archive = try makeVSIX(manifest: manifestJSON(engine: "^1.200.0"), in: scratch)
        #expect(throws: VSIXInstallError.engineIncompatible(
            "^1.200.0", host: Self.host.description)) {
            try installer.install(
                archive: archive, verification: unsigned, source: .localFile(scratch))
        }
        #expect(installedDirectoryNames(in: installDirectory).isEmpty)
    }

    @Test("an engine range nothing here can read is refused, and kept distinct")
    func engineRangeUnreadableIsRefused() throws {
        let scratch = try makeTemporaryDirectory("unreadable")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let installer = VSIXInstaller(
            installDirectory: scratch.appendingPathComponent("Extensions", isDirectory: true),
            hostVersion: Self.host)

        let archive = try makeVSIX(manifest: manifestJSON(engine: ">= 1.74.0"), in: scratch)
        #expect(throws: VSIXInstallError.engineRangeUnreadable(">= 1.74.0")) {
            try installer.install(
                archive: archive, verification: unsigned, source: .localFile(scratch))
        }
    }

    @Test("a zip that is not a .vsix is refused by name")
    func noPayloadDirectory() throws {
        let scratch = try makeTemporaryDirectory("nopayload")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let installer = VSIXInstaller(
            installDirectory: scratch.appendingPathComponent("Extensions", isDirectory: true),
            hostVersion: Self.host)

        let archive = try makeVSIX(manifest: nil, in: scratch)
        #expect(throws: VSIXInstallError.noPayloadDirectory) {
            try installer.install(
                archive: archive, verification: unsigned, source: .localFile(scratch))
        }
    }

    @Test("a payload with no readable manifest is refused")
    func manifestUnreadable() throws {
        let scratch = try makeTemporaryDirectory("nomanifest")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let installer = VSIXInstaller(
            installDirectory: scratch.appendingPathComponent("Extensions", isDirectory: true),
            hostVersion: Self.host)

        // An `extension/` directory holding everything but `package.json`.
        let staging = scratch.appendingPathComponent("staging", isDirectory: true)
        let payload = staging.appendingPathComponent(
            VSIXArchive.payloadDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: payload.appendingPathComponent("README.md"))
        let archiveURL = scratch.appendingPathComponent("no-manifest.vsix")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", staging.path, archiveURL.path]
        try process.run()
        process.waitUntilExit()

        #expect(throws: VSIXInstallError.manifestUnreadable) {
            try installer.install(
                archive: try Data(contentsOf: archiveURL),
                verification: unsigned,
                source: .localFile(scratch))
        }
    }

    @Test("a malformed manifest is refused with the decoder's reason")
    func manifestMalformed() throws {
        let scratch = try makeTemporaryDirectory("malformed")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let installer = VSIXInstaller(
            installDirectory: scratch.appendingPathComponent("Extensions", isDirectory: true),
            hostVersion: Self.host)

        let archive = try makeVSIX(manifest: "{ not json at all", in: scratch)
        var thrown: VSIXInstallError?
        do {
            _ = try installer.install(
                archive: archive, verification: unsigned, source: .localFile(scratch))
        } catch let error as VSIXInstallError {
            thrown = error
        }
        guard case .manifestMalformed(let reason) = thrown else {
            Issue.record("expected .manifestMalformed, got \(String(describing: thrown))")
            return
        }
        #expect(!reason.isEmpty)
    }

    // MARK: - Replacing what was there

    /// Re-installing the same version is what an interrupted download, a
    /// retry, or a double-click all look like from here, and none of them
    /// wants an error *(idempotency)*.
    @Test("installing the same version twice succeeds and leaves one directory")
    func reinstallIsIdempotent() throws {
        let scratch = try makeTemporaryDirectory("idempotent")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let installDirectory = scratch.appendingPathComponent("Extensions", isDirectory: true)
        let installer = VSIXInstaller(installDirectory: installDirectory, hostVersion: Self.host)

        let archive = try makeVSIX(manifest: manifestJSON(), in: scratch, extraFile: "theme.json")
        let first = try installer.install(
            archive: archive, verification: unsigned, source: .localFile(scratch))
        let second = try installer.install(
            archive: archive, verification: unsigned, source: .localFile(scratch))

        #expect(first.directory.standardizedFileURL == second.directory.standardizedFileURL)
        #expect(second.supersededDirectories.isEmpty)
        #expect(installedDirectoryNames(in: installDirectory) == ["acme.widget-1.0.0"])
        #expect(FileManager.default.fileExists(
            atPath: second.directory.appendingPathComponent("theme.json").path))
    }

    /// The reason the old copy is removed rather than left: the registry
    /// resolves two directories claiming one identifier by *sorted name*, and
    /// `…-1.10.0` sorts before `…-1.9.0`. An update that only added a folder
    /// could leave the old version winning.
    @Test("an older version is removed, even when its name sorts later")
    func supersedesTheOlderVersion() throws {
        let scratch = try makeTemporaryDirectory("supersede")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let installDirectory = scratch.appendingPathComponent("Extensions", isDirectory: true)
        let installer = VSIXInstaller(installDirectory: installDirectory, hostVersion: Self.host)

        _ = try installer.install(
            archive: try makeVSIX(manifest: manifestJSON(version: "1.9.0"), in: scratch),
            verification: unsigned,
            source: .localFile(scratch))
        #expect(installedDirectoryNames(in: installDirectory) == ["acme.widget-1.9.0"])

        let updated = try installer.install(
            archive: try makeVSIX(manifest: manifestJSON(version: "1.10.0"), in: scratch),
            verification: unsigned,
            source: .localFile(scratch))

        #expect(updated.supersededDirectories.count == 1)
        #expect(updated.supersededDirectories[0].lastPathComponent == "acme.widget-1.9.0")
        #expect(installedDirectoryNames(in: installDirectory) == ["acme.widget-1.10.0"])
    }

    /// The old copies are found by reading each manifest, not by matching the
    /// folder name — a hand-unpacked extension or a dev checkout is named
    /// whatever its author named it, and those are exactly the ones whose
    /// survival would shadow the extension just installed.
    @Test("a hand-named directory claiming the same identifier is superseded too")
    func supersedesAHandNamedDirectory() throws {
        let scratch = try makeTemporaryDirectory("handnamed")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let installDirectory = scratch.appendingPathComponent("Extensions", isDirectory: true)
        try FileManager.default.createDirectory(
            at: installDirectory, withIntermediateDirectories: true)

        let byHand = installDirectory.appendingPathComponent("my-widget-checkout", isDirectory: true)
        try FileManager.default.createDirectory(at: byHand, withIntermediateDirectories: true)
        try Data(manifestJSON(version: "0.0.1").utf8)
            .write(to: byHand.appendingPathComponent("package.json"))

        // An unrelated extension, which must survive untouched.
        let other = installDirectory.appendingPathComponent("other.thing-1.0.0", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try Data(manifestJSON(name: "thing", publisher: "other").utf8)
            .write(to: other.appendingPathComponent("package.json"))

        let installer = VSIXInstaller(installDirectory: installDirectory, hostVersion: Self.host)
        let installed = try installer.install(
            archive: try makeVSIX(manifest: manifestJSON(version: "2.0.0"), in: scratch),
            verification: unsigned,
            source: .localFile(scratch))

        #expect(installed.supersededDirectories.map(\.lastPathComponent) == ["my-widget-checkout"])
        #expect(
            installedDirectoryNames(in: installDirectory)
                == ["acme.widget-2.0.0", "other.thing-1.0.0"])
    }

    /// A refusal must not take the working copy with it. The existing install
    /// is moved aside rather than deleted precisely so a failure can put it
    /// back, and a user left with neither version is the outcome that would
    /// make an update button unsafe to press.
    @Test("a refused install leaves the previous version in place")
    func afailedInstallLeavesTheOldOneAlone() throws {
        let scratch = try makeTemporaryDirectory("rollback")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let installDirectory = scratch.appendingPathComponent("Extensions", isDirectory: true)
        let installer = VSIXInstaller(installDirectory: installDirectory, hostVersion: Self.host)

        _ = try installer.install(
            archive: try makeVSIX(
                manifest: manifestJSON(version: "1.0.0"), in: scratch, extraFile: "theme.json"),
            verification: unsigned,
            source: .localFile(scratch))

        // An update the host cannot run — refused after the bytes are in hand
        // and before anything is moved.
        #expect(throws: (any Error).self) {
            try installer.install(
                archive: try self.makeVSIX(
                    manifest: self.manifestJSON(version: "2.0.0", engine: "^1.200.0"),
                    in: scratch),
                verification: self.unsigned,
                source: .localFile(scratch))
        }

        #expect(installedDirectoryNames(in: installDirectory) == ["acme.widget-1.0.0"])
        #expect(FileManager.default.fileExists(
            atPath: installDirectory
                .appendingPathComponent("acme.widget-1.0.0")
                .appendingPathComponent("theme.json").path))
    }

    // MARK: - Hostile identities

    /// The manifest is the attacker's document on every path, and three of its
    /// fields reach a directory name. `expectedIdentifier` guards only one of
    /// them, only on the registry path — `version` is never compared with
    /// anything, anywhere.
    ///
    /// What it catches: `directoryName(identifier:version:)` interpolating
    /// straight into a path component, and `moveIntoPlace` finishing the job
    /// with `rename(2)`, which resolves `..` in the kernel. A `version` of
    /// `../../../../Library/LaunchAgents/evil` put the expanded payload
    /// wherever the archive asked — a LaunchAgent plist there is code
    /// execution at next login.
    @Test("a version that climbs out of the install directory is refused")
    func hostileVersionIsRefused() throws {
        let scratch = try makeTemporaryDirectory("hostile-version")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let root = scratch.appendingPathComponent("root", isDirectory: true)
        let installDirectory = root.appendingPathComponent("Extensions", isDirectory: true)
        let installer = VSIXInstaller(installDirectory: installDirectory, hostVersion: Self.host)

        #expect(throws: VSIXInstallError.unsafeIdentity(
            field: "version", value: "../../escaped").self) {
            try installer.install(
                archive: try self.makeVSIX(
                    manifest: self.manifestJSON(version: "../../escaped"), in: scratch),
                verification: self.unsigned,
                expectedIdentifier: "acme.widget",
                source: .registry("acme/widget", version: "1.0.0"))
        }

        // The refusal is worth nothing if the bytes went anywhere. `root` is
        // where a two-step climb out of `Extensions` lands.
        #expect(installedDirectoryNames(in: root) == [])
    }

    /// The same hole through `name`, which reaches the path via `identifier`.
    /// On the local-file path there is no `expectedIdentifier` to stop it, and
    /// on the registry path a hostile registry supplies both sides of that
    /// comparison anyway.
    @Test("a name that climbs out of the install directory is refused")
    func hostileNameIsRefused() throws {
        let scratch = try makeTemporaryDirectory("hostile-name")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let root = scratch.appendingPathComponent("root", isDirectory: true)
        let installDirectory = root.appendingPathComponent("Extensions", isDirectory: true)
        let installer = VSIXInstaller(installDirectory: installDirectory, hostVersion: Self.host)

        #expect(throws: VSIXInstallError.unsafeIdentity(
            field: "identifier", value: "acme.../../escaped").self) {
            try installer.install(
                archive: try self.makeVSIX(
                    manifest: self.manifestJSON(name: "../../escaped"), in: scratch),
                verification: self.unsigned,
                source: .localFile(scratch))
        }

        #expect(installedDirectoryNames(in: root) == [])
    }

    /// An absolute path is the other shape of the same attack, and it does not
    /// contain `..` at all — which is why the check is containment of the
    /// resolved destination rather than a scan for a substring.
    @Test("an identity that names an absolute path is refused")
    func absolutePathIdentityIsRefused() throws {
        let scratch = try makeTemporaryDirectory("hostile-absolute")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let installDirectory = scratch.appendingPathComponent("Extensions", isDirectory: true)
        let installer = VSIXInstaller(installDirectory: installDirectory, hostVersion: Self.host)

        #expect(throws: (any Error).self) {
            try installer.install(
                archive: try self.makeVSIX(
                    manifest: self.manifestJSON(version: "/tmp/absolute"), in: scratch),
                verification: self.unsigned,
                source: .localFile(scratch))
        }

        #expect(installedDirectoryNames(in: installDirectory) == [])
    }

    /// A `.`-leading component is hidden from every directory listing this app
    /// makes (`skipsHiddenFiles` in `otherInstallDirectories`), so an
    /// extension installed under one is invisible to the supersede sweep and
    /// to anyone looking at the folder — while still being loaded.
    @Test("an identity that hides the directory is refused")
    func hiddenDirectoryIdentityIsRefused() throws {
        let scratch = try makeTemporaryDirectory("hostile-hidden")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let installDirectory = scratch.appendingPathComponent("Extensions", isDirectory: true)
        let installer = VSIXInstaller(installDirectory: installDirectory, hostVersion: Self.host)

        #expect(throws: (any Error).self) {
            try installer.install(
                archive: try self.makeVSIX(
                    manifest: self.manifestJSON(publisher: ".hidden"), in: scratch),
                verification: self.unsigned,
                source: .localFile(scratch))
        }

        #expect(installedDirectoryNames(in: installDirectory) == [])
    }

    /// The guard has to be narrow enough to leave real extensions alone. A
    /// pre-release build number is ordinary semver and a legitimate directory
    /// name, and a guard that refused it would break installing any nightly.
    @Test("an unusual but safe version still installs")
    func prereleaseVersionStillInstalls() throws {
        let scratch = try makeTemporaryDirectory("prerelease")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let installDirectory = scratch.appendingPathComponent("Extensions", isDirectory: true)
        let installer = VSIXInstaller(installDirectory: installDirectory, hostVersion: Self.host)

        let installation = try installer.install(
            archive: try makeVSIX(
                manifest: manifestJSON(version: "1.0.0-beta.1+build.7"), in: scratch),
            verification: unsigned,
            source: .localFile(scratch))

        #expect(installation.directory.lastPathComponent == "acme.widget-1.0.0-beta.1+build.7")
        #expect(installedDirectoryNames(in: installDirectory)
            == ["acme.widget-1.0.0-beta.1+build.7"])
    }

    /// **The containment guard used to refuse an ordinary install whenever the
    /// extensions folder was reached through `/private`.**
    ///
    /// `resolvingSymlinksInPath()` drops a leading `/private` — but only when
    /// what is left still names something that exists. The install directory
    /// exists, so it canonicalized to `/tmp/…`; the destination is the
    /// directory about to be *created*, so it kept `/private/tmp/…`, and
    /// comparing the two said the destination was outside its own parent. The
    /// install failed with `unsafeIdentity` naming a perfectly ordinary
    /// `<publisher>.<name>-<version>`.
    ///
    /// Nothing about it was hostile and nothing about it was hypothetical: it
    /// is what a macOS temporary directory, a home on another volume, or any
    /// `/private`-rooted path does. The fix is to canonicalize the parent —
    /// which exists — and append to that, rather than canonicalizing a path
    /// that does not exist yet.
    @Test("an extensions folder reached through /private still installs")
    func aPrivateRootedInstallDirectoryStillInstalls() throws {
        let scratch = try makeTemporaryDirectory("private-rooted")
        defer { try? FileManager.default.removeItem(at: scratch) }

        // `/var/folders/…` → `/private/var/folders/…`: the same directory,
        // named the way the guard could not cope with.
        let installDirectory = scratch
            .resolvingSymlinksInPath()
            .appendingPathComponent("Extensions", isDirectory: true)
        try #require(installDirectory.path.hasPrefix("/private/"))
        try FileManager.default.createDirectory(
            at: installDirectory, withIntermediateDirectories: true)

        let installer = VSIXInstaller(installDirectory: installDirectory, hostVersion: Self.host)

        let installation = try installer.install(
            archive: try makeVSIX(manifest: manifestJSON(), in: scratch),
            verification: unsigned,
            source: .localFile(scratch))

        #expect(installation.directory.lastPathComponent == "acme.widget-1.0.0")
        #expect(installedDirectoryNames(in: installDirectory) == ["acme.widget-1.0.0"])
    }

    /// The guard is still a guard. Canonicalizing the parent rather than the
    /// whole path must not be a way of turning the check off: a directory name
    /// that climbs out is still refused, and from a `/private` root too.
    @Test("a name that climbs out of a /private-rooted folder is still refused")
    func aClimbingNameIsStillRefusedFromAPrivateRoot() throws {
        let scratch = try makeTemporaryDirectory("private-rooted-hostile")
        defer { try? FileManager.default.removeItem(at: scratch) }

        let installDirectory = scratch
            .resolvingSymlinksInPath()
            .appendingPathComponent("Extensions", isDirectory: true)
        try FileManager.default.createDirectory(
            at: installDirectory, withIntermediateDirectories: true)

        let installer = VSIXInstaller(installDirectory: installDirectory, hostVersion: Self.host)

        #expect(throws: (any Error).self) {
            try installer.install(
                archive: try self.makeVSIX(
                    manifest: self.manifestJSON(name: "escape", publisher: ".."), in: scratch),
                verification: self.unsigned,
                source: .localFile(scratch))
        }

        #expect(installedDirectoryNames(in: installDirectory) == [])
    }
}
