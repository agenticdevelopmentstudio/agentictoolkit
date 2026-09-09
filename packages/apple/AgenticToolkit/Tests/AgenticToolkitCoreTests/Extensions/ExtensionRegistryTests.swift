import Testing
import Foundation
@testable import AgenticToolkitCore

/// Records every `apply`/`withdraw` call it receives, for assertions.
@MainActor
private final class RecordingContributionPoint: ContributionPoint {
    let contributionKey = "recording"
    private(set) var appliedIdentifiers: [String] = []
    private(set) var withdrawnIdentifiers: [String] = []

    func apply(
        _ contributions: ExtensionManifest.Contributions,
        from manifest: ExtensionManifest,
        at directory: URL
    ) throws {
        appliedIdentifiers.append(manifest.identifier)
    }

    func withdraw(extensionIdentifier: String) {
        withdrawnIdentifiers.append(extensionIdentifier)
    }
}

@MainActor
@Suite(.serialized)
struct ExtensionRegistryTests {

    private static let hostVersion = SemanticVersion(major: 1, minor: 95, patch: 0)

    private func writeManifest(
        _ json: String,
        named extensionDirectoryName: String,
        in searchPath: URL
    ) throws {
        let directory = searchPath.appendingPathComponent(extensionDirectoryName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try json.write(
            to: directory.appendingPathComponent("package.json"),
            atomically: true,
            encoding: .utf8
        )
    }

    /// `contributes` is present (even if only `commands`) rather than
    /// omitted, so tests that assert `apply`/`withdraw` behavior exercise
    /// the same path a real extension takes — an extension manifest with no
    /// `contributes` key at all has nothing to apply in the first place.
    private func manifestJSON(name: String, publisher: String = "acme", engine: String = "^1.74.0") -> String {
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

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExtensionRegistryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func withInMemorySettings<Result>(_ body: () throws -> Result) rethrows -> Result {
        let previous = UserSettings.shared
        UserSettings.shared = UserSettings(with: InMemorySettingsStorageProvider())
        defer { UserSettings.shared = previous }
        return try body()
    }

    @Test("a good extension loads")
    func goodExtensionLoads() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            try writeManifest(manifestJSON(name: "good"), named: "good-ext", in: root)

            let registry = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
            registry.loadAll()

            #expect(registry.extensions.count == 1)
            #expect(registry.extensions.first?.identifier == "acme.good")
            #expect(registry.failures.isEmpty)
        }
    }

    @Test("a directory with no package.json is skipped without a failure entry")
    func missingManifestIsSkippedSilently() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            let noManifest = root.appendingPathComponent("no-manifest")
            try FileManager.default.createDirectory(at: noManifest, withIntermediateDirectories: true)

            let registry = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
            registry.loadAll()

            #expect(registry.extensions.isEmpty)
            #expect(registry.failures.isEmpty)
        }
    }

    @Test("malformed JSON produces manifestMalformed and does not stop the other extension from loading")
    func malformedJSONIsIsolated() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            try writeManifest("{ not valid json", named: "broken-ext", in: root)
            try writeManifest(manifestJSON(name: "good"), named: "good-ext", in: root)

            let registry = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
            registry.loadAll()

            #expect(registry.extensions.count == 1)
            #expect(registry.extensions.first?.identifier == "acme.good")
            #expect(registry.failures.count == 1)
            if case .manifestMalformed = registry.failures.first?.reason {
                // expected
            } else {
                Issue.record("expected manifestMalformed, got \(String(describing: registry.failures.first?.reason))")
            }
        }
    }

    @Test("an engines.vscode of ^2.0.0 produces engineIncompatible")
    func incompatibleEngineFails() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            try writeManifest(manifestJSON(name: "too-new", engine: "^2.0.0"), named: "too-new-ext", in: root)

            let registry = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
            registry.loadAll()

            #expect(registry.extensions.isEmpty)
            #expect(registry.failures.count == 1)
            if case .engineIncompatible(let required, let host) = registry.failures.first?.reason {
                #expect(required == "^2.0.0")
                #expect(host == "1.95.0")
            } else {
                Issue.record("expected engineIncompatible, got \(String(describing: registry.failures.first?.reason))")
            }
        }
    }

    @Test("an unparsable engine range produces engineRangeUnparsable")
    func unparsableEngineRangeFails() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            try writeManifest(manifestJSON(name: "weird", engine: "~1.74.0"), named: "weird-ext", in: root)

            let registry = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
            registry.loadAll()

            #expect(registry.extensions.isEmpty)
            #expect(registry.failures.count == 1)
            if case .engineRangeUnparsable(let raw) = registry.failures.first?.reason {
                #expect(raw == "~1.74.0")
            } else {
                let reason = String(describing: registry.failures.first?.reason)
                Issue.record("expected engineRangeUnparsable, got \(reason)")
            }
        }
    }

    @Test("the same identifier in two search paths loads once and records one failure")
    func duplicateIdentifierAcrossSearchPathsLoadsOnce() throws {
        try withInMemorySettings {
            let firstRoot = try makeTempDirectory()
            let secondRoot = try makeTempDirectory()
            defer {
                try? FileManager.default.removeItem(at: firstRoot)
                try? FileManager.default.removeItem(at: secondRoot)
            }

            try writeManifest(manifestJSON(name: "dup"), named: "dup-ext", in: firstRoot)
            try writeManifest(manifestJSON(name: "dup"), named: "dup-ext", in: secondRoot)

            let registry = ExtensionRegistry(searchPaths: [firstRoot, secondRoot], hostVersion: Self.hostVersion)
            registry.loadAll()

            #expect(registry.extensions.count == 1)
            #expect(registry.failures.count == 1)
        }
    }

    @Test("a registered contribution point receives apply for an enabled extension and not for a disabled one")
    func contributionPointRespectsEnablement() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            try writeManifest(manifestJSON(name: "enabled"), named: "enabled-ext", in: root)
            try writeManifest(manifestJSON(name: "disabled"), named: "disabled-ext", in: root)

            UserSettings.disabledExtensionIdentifiers.value = ["acme.disabled"]

            let point = RecordingContributionPoint()
            let registry = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
            registry.register(point)
            registry.loadAll()

            #expect(point.appliedIdentifiers == ["acme.enabled"])
        }
    }

    @Test("setEnabled(false) withdraws; setEnabled(true) applies")
    func setEnabledDrivesContributionPoint() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            try writeManifest(manifestJSON(name: "toggle"), named: "toggle-ext", in: root)

            let point = RecordingContributionPoint()
            let registry = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
            registry.register(point)
            registry.loadAll()
            #expect(point.appliedIdentifiers == ["acme.toggle"])

            registry.setEnabled(false, for: "acme.toggle")
            #expect(point.withdrawnIdentifiers == ["acme.toggle"])
            #expect(!registry.isEnabled("acme.toggle"))

            registry.setEnabled(true, for: "acme.toggle")
            #expect(point.appliedIdentifiers == ["acme.toggle", "acme.toggle"])
            #expect(registry.isEnabled("acme.toggle"))
        }
    }

    @Test("uninstall withdraws and removes the directory")
    func uninstallWithdrawsAndRemoves() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            try writeManifest(manifestJSON(name: "gone"), named: "gone-ext", in: root)
            let extensionDirectory = root.appendingPathComponent("gone-ext")

            let point = RecordingContributionPoint()
            let registry = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
            registry.register(point)
            registry.loadAll()

            try registry.uninstall("acme.gone")

            #expect(point.withdrawnIdentifiers == ["acme.gone"])
            #expect(!FileManager.default.fileExists(atPath: extensionDirectory.path))
            #expect(registry.extensions.isEmpty)
        }
    }
}
