import Testing
import Foundation
@testable import AgenticToolkitCore

/// Records every `apply`/`withdraw` call it receives, for assertions.
@MainActor
private final class RecordingContributionPoint: ContributionPoint {
    let contributionKey = "recording"

    /// What is contributed *right now* — `withdraw` removes, the way a real
    /// point uninstalls what it installed. This is the property that catches
    /// a double-apply: an append-only log cannot tell "installed twice" apart
    /// from "installed, withdrawn, installed again".
    private(set) var appliedIdentifiers: [String] = []
    /// Every `apply` call in order, repeats included.
    private(set) var applyCalls: [String] = []
    private(set) var withdrawnIdentifiers: [String] = []

    func apply(
        _ contributions: ExtensionManifest.Contributions,
        from manifest: ExtensionManifest,
        at directory: URL
    ) throws {
        applyCalls.append(manifest.identifier)
        appliedIdentifiers.append(manifest.identifier)
    }

    func withdraw(extensionIdentifier: String) {
        withdrawnIdentifiers.append(extensionIdentifier)
        appliedIdentifiers.removeAll { $0 == extensionIdentifier }
    }
}

/// Refuses every `apply`, so the registry's handling of a contribution point
/// that says no is observable.
@MainActor
private final class ThrowingContributionPoint: ContributionPoint {
    struct Refused: Error {}

    let contributionKey = "throwing"
    private(set) var withdrawnIdentifiers: [String] = []

    func apply(
        _ contributions: ExtensionManifest.Contributions,
        from manifest: ExtensionManifest,
        at directory: URL
    ) throws {
        throw Refused()
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

    /// `/var` is a symlink to `/private/var` on macOS, and
    /// `contentsOfDirectory` hands back the resolved form — so a path the
    /// registry stored and a path a test built from `temporaryDirectory`
    /// differ by that prefix alone. `resolvingSymlinksInPath()` strips a
    /// leading `/private`, so putting both sides through it is what makes
    /// them comparable.
    private func normalizedPath(_ url: URL?) -> String? {
        url?.resolvingSymlinksInPath().path
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

    @Test("the same identifier in two search paths: the first path wins and the second is a duplicate failure")
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

            // Counts alone would pass if the *second* path won, which is the
            // opposite of the specified behavior — so name the winner.
            let winner = firstRoot.appendingPathComponent("dup-ext")
            let loser = secondRoot.appendingPathComponent("dup-ext")

            #expect(registry.extensions.count == 1)
            #expect(normalizedPath(registry.extensions.first?.directory) == normalizedPath(winner))
            #expect(registry.failures.count == 1)
            #expect(normalizedPath(registry.failures.first?.directory) == normalizedPath(loser))
            if case .duplicateIdentifier(let existing) = registry.failures.first?.reason {
                #expect(normalizedPath(URL(fileURLWithPath: existing)) == normalizedPath(winner))
            } else {
                let reason = String(describing: registry.failures.first?.reason)
                Issue.record("expected duplicateIdentifier, got \(reason)")
            }
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
            #expect(point.applyCalls == ["acme.toggle", "acme.toggle"])
            #expect(point.appliedIdentifiers == ["acme.toggle"])
            #expect(registry.isEnabled("acme.toggle"))
        }
    }

    @Test("setEnabled with the state it already has does nothing")
    func redundantSetEnabledIsANoOp() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            try writeManifest(manifestJSON(name: "toggle"), named: "toggle-ext", in: root)

            let point = RecordingContributionPoint()
            let registry = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
            registry.register(point)
            registry.loadAll()
            #expect(point.applyCalls == ["acme.toggle"])

            registry.setEnabled(true, for: "acme.toggle")
            #expect(point.applyCalls == ["acme.toggle"])
            #expect(point.withdrawnIdentifiers.isEmpty)

            registry.setEnabled(false, for: "acme.toggle")
            registry.setEnabled(false, for: "acme.toggle")
            #expect(point.withdrawnIdentifiers == ["acme.toggle"])
        }
    }

    @Test("loadAll is re-runnable: a second call leaves the contributions applied once")
    func loadAllTwiceAppliesContributionsOnce() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            try writeManifest(manifestJSON(name: "good"), named: "good-ext", in: root)

            let point = RecordingContributionPoint()
            let registry = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
            registry.register(point)
            registry.loadAll()
            registry.loadAll()

            #expect(registry.extensions.count == 1)
            #expect(point.appliedIdentifiers.count == 1)
            #expect(point.withdrawnIdentifiers == ["acme.good"])
        }
    }

    @Test("a contribution point that refuses is recorded in failures and the extension stays loaded")
    func refusedContributionIsRecorded() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            try writeManifest(manifestJSON(name: "refused"), named: "refused-ext", in: root)

            let throwing = ThrowingContributionPoint()
            let recording = RecordingContributionPoint()
            let registry = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
            registry.register(throwing)
            registry.register(recording)
            registry.loadAll()

            #expect(registry.extensions.count == 1)
            #expect(registry.extensions.first?.identifier == "acme.refused")
            // The refusal does not abort loading: the next point still runs.
            #expect(recording.appliedIdentifiers == ["acme.refused"])

            #expect(registry.failures.count == 1)
            if case .contributionPointFailed(let key, let message) = registry.failures.first?.reason {
                #expect(key == "throwing")
                #expect(!message.isEmpty)
            } else {
                let reason = String(describing: registry.failures.first?.reason)
                Issue.record("expected contributionPointFailed, got \(reason)")
            }
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

    @Test("a failed uninstall leaves the extension entirely intact")
    func failedUninstallChangesNothing() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: root.path
                )
                try? FileManager.default.removeItem(at: root)
            }

            try writeManifest(manifestJSON(name: "stuck"), named: "stuck-ext", in: root)
            let extensionDirectory = root.appendingPathComponent("stuck-ext")

            let point = RecordingContributionPoint()
            let registry = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
            registry.register(point)
            registry.loadAll()

            // Unlinking a directory entry needs write permission on its
            // *parent*, so a read-only search path is the honest way to make
            // the delete fail without mocking `FileManager`.
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o500],
                ofItemAtPath: root.path
            )

            #expect(throws: (any Error).self) {
                try registry.uninstall("acme.stuck")
            }

            #expect(registry.extensions.count == 1)
            #expect(point.appliedIdentifiers == ["acme.stuck"])
            #expect(point.withdrawnIdentifiers.isEmpty)
            #expect(FileManager.default.fileExists(atPath: extensionDirectory.path))
        }
    }

    @Test("uninstall clears the identifier from the disabled set")
    func uninstallClearsTheDisabledTombstone() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            try writeManifest(manifestJSON(name: "gone"), named: "gone-ext", in: root)

            let registry = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
            registry.loadAll()

            registry.setEnabled(false, for: "acme.gone")
            #expect(UserSettings.disabledExtensionIdentifiers.value.contains("acme.gone"))

            try registry.uninstall("acme.gone")

            // Otherwise a later reinstall comes back disabled with nothing
            // anywhere to explain why.
            #expect(!UserSettings.disabledExtensionIdentifiers.value.contains("acme.gone"))
            #expect(registry.isEnabled("acme.gone"))
        }
    }
}
