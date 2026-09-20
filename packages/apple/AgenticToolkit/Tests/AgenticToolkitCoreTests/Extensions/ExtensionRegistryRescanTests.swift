import Testing
import Foundation
@testable import AgenticToolkitCore

/// Records what it was handed, so a rescan's effect on contributions is
/// observable.
@MainActor
private final class RecordingPoint: ContributionPoint {
    let contributionKey = "recording"
    private(set) var applied: [String] = []
    private(set) var withdrawn: [String] = []

    func apply(
        _ contributions: ExtensionManifest.Contributions,
        from manifest: ExtensionManifest,
        at directory: URL
    ) throws {
        applied.append(manifest.identifier)
    }

    func withdraw(extensionIdentifier: String) {
        withdrawn.append(extensionIdentifier)
        applied.removeAll { $0 == extensionIdentifier }
    }
}

/// Reloading the registry after the user installs something, without stopping
/// the window.
///
/// `loadAll()` is synchronous on the main actor and the class doc says why —
/// but the reason it gives is scoped to startup: it runs once during feature
/// construction, before any window is on screen. An install runs from a button
/// in a live settings window, and what happens there is a directory
/// enumeration, a read and a JSONC decode per installed extension, and then
/// every contribution point withdrawn and re-applied — with the run loop
/// stopped for all of it.
///
/// So the reading of disk is separated from the applying of what was read: the
/// first is a pure function of the search paths and can run anywhere, the
/// second is the registry's own state and stays where it belongs.
@MainActor
@Suite(.serialized)
struct ExtensionRegistryRescanTests {

    private static let hostVersion = SemanticVersion(major: 1, minor: 95, patch: 0)

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExtensionRegistryRescanTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeManifest(
        _ json: String, named directoryName: String, in searchPath: URL
    ) throws {
        let directory = searchPath.appendingPathComponent(directoryName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try json.write(
            to: directory.appendingPathComponent("package.json"),
            atomically: true,
            encoding: .utf8)
    }

    private func manifestJSON(
        name: String, publisher: String = "acme", engine: String = "^1.74.0"
    ) -> String {
        """
        {
            "name": "\(name)",
            "publisher": "\(publisher)",
            "version": "1.0.0",
            "engines": { "vscode": "\(engine)" },
            "contributes": {
                "commands": [ { "command": "\(publisher).\(name).run", "title": "Run" } ]
            }
        }
        """
    }

    /// The part that costs: enumerating directories, reading a file each and
    /// decoding it, plus the engine gate that needs nothing but the manifest
    /// and the host's version. Run here from a detached task, which is the
    /// assertion — a function that touched the registry's state could not be
    /// called from one at all.
    @Test("the scan reads and gates manifests away from the main actor")
    func theScanRunsOffTheMainActor() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeManifest(manifestJSON(name: "good"), named: "good-ext", in: root)
        try writeManifest(
            manifestJSON(name: "demanding", engine: "^2.0.0"), named: "demanding-ext", in: root)
        try writeManifest("{ not json", named: "broken-ext", in: root)

        let version = Self.hostVersion
        let scan = await Task.detached {
            ExtensionRegistry.scan(searchPaths: [root], hostVersion: version)
        }.value

        #expect(scan.readEverything)
        #expect(scan.directories.count == 3)

        var manifests: [String] = []
        var failures: [String?] = []
        for directory in scan.directories {
            switch directory.outcome {
            case .manifest(let manifest): manifests.append(manifest.identifier)
            case .failed(_, let identifier): failures.append(identifier)
            }
        }
        #expect(manifests == ["acme.good"])
        // The demanding one is named, because its manifest decoded before the
        // engine gate refused it; the broken one is not, because nothing in it
        // parsed.
        #expect(failures == [nil, "acme.demanding"])
    }

    /// A search path that exists and will not open is the one thing a scan must
    /// carry forward, because everything downstream treats "not seen" as "gone"
    /// unless told the scan was partial.
    @Test("a search path that cannot be read makes the scan incomplete")
    func anUnreadablePathIsCarried() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("not-a-directory")
        try Data().write(to: file)

        let version = Self.hostVersion
        let scan = await Task.detached {
            ExtensionRegistry.scan(searchPaths: [file], hostVersion: version)
        }.value

        #expect(!scan.readEverything)
    }

    /// And the asynchronous reload is the synchronous one in every respect a
    /// caller can see.
    @Test("an off-main-thread reload loads what loadAll would have")
    func reloadMatchesLoadAll() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeManifest(manifestJSON(name: "good"), named: "good-ext", in: root)
        try writeManifest(
            manifestJSON(name: "demanding", engine: "^2.0.0"), named: "demanding-ext", in: root)

        let previous = UserSettings.shared
        UserSettings.shared = UserSettings(with: InMemorySettingsStorageProvider())
        defer { UserSettings.shared = previous }

        let synchronous = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
        synchronous.loadAll()

        let asynchronous = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
        await asynchronous.reload()

        #expect(asynchronous.extensions.map(\.identifier)
            == synchronous.extensions.map(\.identifier))
        #expect(asynchronous.failures.map(\.identifier)
            == synchronous.failures.map(\.identifier))
        #expect(asynchronous.establishedIdentifiers == synchronous.establishedIdentifiers)
    }

    /// The reason the rescan is a whole rescan: an install can supersede a
    /// directory, so what the previous load applied has to be withdrawn. Twice
    /// through, the count still has to be one — an extension applied twice with
    /// one withdrawal on a later disable leaves a copy behind.
    @Test("a reload withdraws what the last load applied")
    func reloadWithdrawsTheLastLoad() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeManifest(manifestJSON(name: "good"), named: "good-ext", in: root)

        let previous = UserSettings.shared
        UserSettings.shared = UserSettings(with: InMemorySettingsStorageProvider())
        defer { UserSettings.shared = previous }

        let point = RecordingPoint()
        let registry = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
        registry.register(point)

        registry.loadAll()
        #expect(point.applied == ["acme.good"])

        var changes = 0
        registry.addContributionsObserver { changes += 1 }
        await registry.reload()

        #expect(point.withdrawn == ["acme.good"])
        #expect(point.applied == ["acme.good"])
        #expect(changes == 1)
    }

    /// A new extension appearing between the two loads is the case an install
    /// actually is.
    @Test("a reload picks up what was installed since")
    func reloadSeesANewExtension() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeManifest(manifestJSON(name: "first"), named: "first-ext", in: root)

        let previous = UserSettings.shared
        UserSettings.shared = UserSettings(with: InMemorySettingsStorageProvider())
        defer { UserSettings.shared = previous }

        let point = RecordingPoint()
        let registry = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
        registry.register(point)
        registry.loadAll()

        try writeManifest(manifestJSON(name: "second"), named: "second-ext", in: root)
        await registry.reload()

        #expect(registry.extensions.map(\.identifier) == ["acme.first", "acme.second"])
        #expect(point.applied == ["acme.first", "acme.second"])
    }
}
