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

    private func makeTemporaryDirectory(_ name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VSIXInstallerTests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func manifestJSON(
        name: String = "widget",
        publisher: String = "acme",
        version: String = "1.0.0",
        engine: String = "^1.74.0",
        entryPoint: String? = nil
    ) -> String {
        var fields = [
            "\"name\": \"\(name)\"",
            "\"publisher\": \"\(publisher)\"",
            "\"version\": \"\(version)\"",
            "\"displayName\": \"The \(name)\"",
            "\"engines\": { \"vscode\": \"\(engine)\" }"
        ]
        if let entryPoint {
            fields.append("\"\(entryPoint)\": \"./out/extension.js\"")
        }
        return "{ \(fields.joined(separator: ", ")) }"
    }

    /// Builds a real `.vsix`: a zip whose top-level entry is `extension/`.
    /// Real rather than faked because the installer's whole local path runs
    /// through `ditto`, and a fixture that skipped the archive would test none
    /// of it.
    private func makeVSIX(manifest: String?, in scratch: URL, extraFile: String? = nil) throws -> Data {
        let staging = scratch.appendingPathComponent("vsix-\(UUID().uuidString)", isDirectory: true)
        let payload = staging.appendingPathComponent(
            VSIXArchive.payloadDirectoryName, isDirectory: true)
        if let manifest {
            try FileManager.default.createDirectory(
                at: payload, withIntermediateDirectories: true)
            try Data(manifest.utf8).write(to: payload.appendingPathComponent("package.json"))
            if let extraFile {
                try Data("marker".utf8).write(to: payload.appendingPathComponent(extraFile))
            }
        } else {
            // A zip that is not a `.vsix`: no `extension/` at all.
            try FileManager.default.createDirectory(
                at: staging, withIntermediateDirectories: true)
            try Data("not an extension".utf8)
                .write(to: staging.appendingPathComponent("readme.txt"))
        }

        let archive = scratch.appendingPathComponent("\(UUID().uuidString).vsix")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", staging.path, archive.path]
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
        return try Data(contentsOf: archive)
    }

    private let unsigned = VSIXVerification(sha256: "abc", signature: .notPublished)

    private func installedDirectoryNames(in directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
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
}
