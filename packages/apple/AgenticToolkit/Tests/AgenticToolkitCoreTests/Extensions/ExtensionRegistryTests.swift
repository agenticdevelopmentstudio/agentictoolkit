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
    /// What the most recent `apply` was handed. A point cannot reconcile
    /// against a declaration it was never shown, so *what* arrives is as much
    /// the registry's contract as *whether* it arrives.
    private(set) var lastContributions: ExtensionManifest.Contributions?
    private(set) var withdrawnIdentifiers: [String] = []

    func apply(
        _ contributions: ExtensionManifest.Contributions,
        from manifest: ExtensionManifest,
        at directory: URL
    ) throws {
        applyCalls.append(manifest.identifier)
        appliedIdentifiers.append(manifest.identifier)
        lastContributions = contributions
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
    /// Deliberately a bare `Error` with an associated value and no
    /// `LocalizedError` conformance — the shape every first-party contribution
    /// point is likely to throw. Its `localizedDescription` is Foundation's
    /// "The operation couldn't be completed…" boilerplate, so the recorded
    /// message below is only readable if the registry uses
    /// `String(describing:)`.
    enum Refused: Error {
        case pointSaidNo(String)
    }

    let contributionKey = "throwing"
    private(set) var withdrawnIdentifiers: [String] = []

    func apply(
        _ contributions: ExtensionManifest.Contributions,
        from manifest: ExtensionManifest,
        at directory: URL
    ) throws {
        throw Refused.pointSaidNo(manifest.identifier)
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

    @Test("an extension with no contributes key still reaches every point, with an empty block")
    func manifestWithoutContributesStillApplies() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            try writeManifest(
                """
                {
                    "name": "quiet",
                    "publisher": "acme",
                    "version": "1.0.0",
                    "engines": { "vscode": "^1.74.0" }
                }
                """,
                named: "quiet-ext",
                in: root
            )

            let point = RecordingContributionPoint()
            let registry = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
            registry.register(point)
            registry.loadAll()

            // Absent and empty are the same statement. Skipping the points for
            // an absent key means an update that *drops* `contributes` is never
            // announced, so a point holding persisted state — themes — can
            // never reconcile it away: the previous version's contributions
            // outlive the declaration that justified them, permanently, because
            // the extension is still installed and so still off-limits to
            // `pruneOrphans`.
            #expect(point.appliedIdentifiers == ["acme.quiet"])
            let contributions = try #require(point.lastContributions)
            #expect(contributions == ExtensionManifest.Contributions.empty)
            // Nil cannot also mean "failed to decode" — `decodeIfPresent`
            // throws on any shape but absent-or-null, and a manifest that
            // throws never reaches a contribution point at all. That is the
            // fact this whole path rests on; the case below is the proof.
            #expect(contributions.decodingFailures.isEmpty)
        }
    }

    @Test("a contributes key of the wrong shape sinks the manifest rather than reading as empty")
    func malformedContributesIsNotAnEmptyDeclaration() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            // `contributes` is a list, not an object. `decodeIfPresent` throws
            // rather than answering nil, so this is `manifestMalformed` and no
            // point hears about it — which is the only reason handing points an
            // empty block for an absent key is safe. Were it to arrive as
            // "declares nothing", an unparseable file would delete the user's
            // themes.
            try writeManifest(
                """
                {
                    "name": "broken",
                    "publisher": "acme",
                    "version": "1.0.0",
                    "engines": { "vscode": "^1.74.0" },
                    "contributes": []
                }
                """,
                named: "broken-ext",
                in: root
            )

            let point = RecordingContributionPoint()
            let registry = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
            registry.register(point)
            registry.loadAll()

            #expect(point.applyCalls.isEmpty)
            #expect(registry.extensions.isEmpty)
            guard case .manifestMalformed = registry.failures.first?.reason else {
                let reason = String(describing: registry.failures.first?.reason)
                Issue.record("expected manifestMalformed, got \(reason)")
                return
            }
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
                // Exactly, not merely non-empty: the boilerplate
                // `localizedDescription` is also non-empty, and pinning the
                // payload is the only thing that keeps the message useful.
                #expect(message == "pointSaidNo(\"acme.refused\")")
            } else {
                let reason = String(describing: registry.failures.first?.reason)
                Issue.record("expected contributionPointFailed, got \(reason)")
            }
        }
    }

    @Test("re-enabling an extension re-derives its contribution failures rather than duplicating them")
    func togglingDoesNotAccumulateContributionFailures() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            try writeManifest(manifestJSON(name: "refused"), named: "refused-ext", in: root)

            let throwing = ThrowingContributionPoint()
            let registry = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
            registry.register(throwing)
            registry.loadAll()

            #expect(registry.failures.count == 1)

            // Disabled: nothing is contributed, so nothing is refused.
            registry.setEnabled(false, for: "acme.refused")
            #expect(registry.failures.isEmpty)

            // Re-enabled: refused again, and recorded once — not twice.
            registry.setEnabled(true, for: "acme.refused")
            #expect(registry.failures.count == 1)

            registry.setEnabled(false, for: "acme.refused")
            registry.setEnabled(true, for: "acme.refused")
            #expect(registry.failures.count == 1)
        }
    }

    @Test("uninstall drops the contribution failures naming the directory it removed")
    func uninstallDropsContributionFailures() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            try writeManifest(manifestJSON(name: "refused"), named: "refused-ext", in: root)

            let throwing = ThrowingContributionPoint()
            let registry = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
            registry.register(throwing)
            registry.loadAll()

            #expect(registry.failures.count == 1)

            try registry.uninstall("acme.refused")

            #expect(registry.extensions.isEmpty)
            #expect(registry.failures.isEmpty)
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

    // MARK: - Which failures know whose extension they were

    @Test("a manifest that did not parse leaves the scan unable to name that directory")
    func aMalformedManifestMakesTheWholeScanUnnameable() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            try writeManifest("{ not valid json", named: "broken-ext", in: root)
            try writeManifest(manifestJSON(name: "good"), named: "good-ext", in: root)

            let registry = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
            registry.loadAll()

            #expect(registry.failures.count == 1)
            // The identifier lives inside the file that would not parse, and
            // the folder name is not it: "broken-ext" is not "acme.broken",
            // and no rule says it has to be.
            #expect(registry.failures.first?.identifier == nil)
            // So the answer for the whole scan is "I do not know", even
            // though the other extension loaded perfectly: nothing here can
            // tell "acme.broken was uninstalled" from "acme.broken is the
            // folder that would not parse".
            #expect(registry.establishedIdentifiers == nil)
        }
    }

    @Test("an extension this host cannot run is still an extension it can name")
    func engineFailuresStillReportTheirIdentifiers() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            try writeManifest(manifestJSON(name: "too-new", engine: "^2.0.0"), named: "too-new-ext", in: root)
            try writeManifest(manifestJSON(name: "weird", engine: "~1.74.0"), named: "weird-ext", in: root)
            try writeManifest(manifestJSON(name: "good"), named: "good-ext", in: root)

            let registry = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
            registry.loadAll()

            // Both engine cases decode the manifest first, so both know whose
            // extension they are — and neither is an error about the
            // extension at all: it is installed, intact, and simply not
            // applicable to this host. Dropping the identifier here is what
            // made a host downgrade delete a live extension's themes.
            #expect(registry.failures.count == 2)
            #expect(Set(registry.failures.compactMap(\.identifier)) == ["acme.too-new", "acme.weird"])
            #expect(registry.establishedIdentifiers == ["acme.good", "acme.too-new", "acme.weird"])
        }
    }

    @Test("a refused contribution does not make the scan unnameable")
    func aRefusedContributionKeepsTheScanComplete() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            try writeManifest(manifestJSON(name: "good"), named: "good-ext", in: root)

            let registry = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
            registry.register(ThrowingContributionPoint())
            registry.loadAll()

            // This extension loaded and is in `extensions`; only one of its
            // contributions was refused. A nil identifier here would be the
            // widest hole of all — `everyThemeFailed` is an ordinary entry,
            // and it would switch the prune off for every other extension
            // for as long as one theme file stayed broken.
            #expect(registry.extensions.count == 1)
            #expect(registry.failures.count == 1)
            #expect(registry.failures.first?.identifier == "acme.good")
            #expect(registry.establishedIdentifiers == ["acme.good"])
        }
    }

    // MARK: - Which directories the scan never got far enough to name

    @Test("a search path that exists and cannot be listed prunes nothing")
    func anUnreadableSearchPathMakesTheWholeScanUnnameable() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            let locked = root.appendingPathComponent("locked")
            try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
            // An extension really is in there. That is what makes this test
            // self-checking: if the chmod below failed to bite, this loads and
            // the answer stops being nil.
            try writeManifest(manifestJSON(name: "hidden"), named: "hidden-ext", in: locked)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o000], ofItemAtPath: locked.path)
            defer {
                // Runs *before* the removeItem above — defers unwind
                // last-in-first-out — because a 000 directory cannot be
                // emptied, so the cleanup would silently leave the fixture
                // behind in the shared temp root.
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: locked.path)
            }

            let registry = ExtensionRegistry(searchPaths: [locked], hostVersion: Self.hostVersion)
            registry.loadAll()

            // Nothing loaded and nothing failed: this exit is above the line
            // that records failures, so the two arrays say "an empty search
            // path" just as loudly as a genuinely empty one would.
            #expect(registry.extensions.isEmpty)
            #expect(registry.failures.isEmpty)
            // Which is why the answer cannot be computed from them alone. An
            // empty set here is the instruction to delete every contributed
            // theme in the store, for extensions this scan never even saw.
            #expect(registry.establishedIdentifiers == nil)
        }
    }

    @Test("a search path that does not exist still prunes normally")
    func anAbsentSearchPathLeavesTheScanComplete() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            let missing = root.appendingPathComponent("no-such-folder")

            // The ordinary case, and the one that must not be marked
            // incomplete: bringing the feature up deliberately does not create
            // the extensions folder, so almost every user has one of these.
            // Answering nil here would switch pruning off permanently for all
            // of them — a worse bug than the one the flag exists to fix.
            let empty = ExtensionRegistry(searchPaths: [missing], hostVersion: Self.hostVersion)
            empty.loadAll()
            #expect(empty.establishedIdentifiers == [])

            // And an absent path alongside a real one must not poison the real
            // one's answer either.
            try writeManifest(manifestJSON(name: "good"), named: "good-ext", in: root)
            let registry = ExtensionRegistry(
                searchPaths: [missing, root], hostVersion: Self.hostVersion)
            registry.loadAll()
            #expect(registry.establishedIdentifiers == ["acme.good"])
        }
    }

    @Test("a registry that has never scanned knows nothing rather than nothing being installed")
    func anUnscannedRegistryAnswersUnknown() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            try writeManifest(manifestJSON(name: "good"), named: "good-ext", in: root)

            // Two empty arrays, and an extension sitting on disk that nobody
            // has looked for yet. No caller reaches this today, which is the
            // only reason it is not a live bug — the arrays alone would answer
            // "nothing is installed" with total confidence.
            let registry = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
            #expect(registry.establishedIdentifiers == nil)

            registry.loadAll()
            #expect(registry.establishedIdentifiers == ["acme.good"])
        }
    }

    // MARK: - F33 — the manifest is JSONC, the dialect VS Code writes

    @Test("a manifest with comments, a trailing comma and a BOM loads")
    func jsoncManifestLoads() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            let jsonc = """
            \u{FEFF}{
                // The extension's identity.
                "name": "jsonc",
                "publisher": "acme",
                "version": "1.0.0",
                /* block comments too */
                "engines": { "vscode": "^1.74.0" },
                "contributes": {
                    "commands": [ { "command": "acme.jsonc.run", "title": "Run" }, ]
                },
            }
            """
            try writeManifest(jsonc, named: "jsonc-ext", in: root)

            let registry = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
            registry.loadAll()

            #expect(registry.failures.isEmpty)
            #expect(registry.extensions.first?.identifier == "acme.jsonc")
            #expect(registry.extensions.first?.manifest.contributes?.commands.count == 1)
        }
    }

    // MARK: - F40 — directory enumeration is ordered, so the answer is reproducible

    @Test("extensions load in sorted directory order, not in readdir order")
    func directoriesAreEnumeratedInSortedOrder() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            // Twenty directories: whatever order the filesystem hands back, it
            // is not going to be lexicographic by accident twenty entries deep.
            let names = (0..<20).map { String(format: "e%02d", $0) }
            for name in names {
                try writeManifest(manifestJSON(name: name), named: "\(name)-ext", in: root)
            }

            let registry = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
            registry.loadAll()

            #expect(registry.extensions.map(\.identifier) == names.map { "acme.\($0)" })
        }
    }

    @Test("the lexicographically first directory wins a contested identifier")
    func duplicateResolutionIsDeterministic() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            try writeManifest(manifestJSON(name: "tool"), named: "acme.tool-1.1.0", in: root)
            try writeManifest(manifestJSON(name: "tool"), named: "acme.tool-1.0.0", in: root)

            let registry = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
            registry.loadAll()

            #expect(registry.extensions.count == 1)
            #expect(
                normalizedPath(registry.extensions.first?.directory)
                    == normalizedPath(root.appendingPathComponent("acme.tool-1.0.0")))
            #expect(registry.failures.count == 1)
            #expect(
                normalizedPath(registry.failures.first?.directory)
                    == normalizedPath(root.appendingPathComponent("acme.tool-1.1.0")))
        }
    }

    // MARK: - F09 — a manifest that will not decode is still nameable

    @Test("a malformed manifest whose name survives keeps the scan complete")
    func malformedManifestStillNamesItsExtension() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            // `version` is required and is the wrong JSON type, so the strict
            // decode fails — but `name` and `publisher` are right there.
            try writeManifest("""
            {
                "name": "broken",
                "publisher": "acme",
                "version": 3,
                "engines": { "vscode": "^1.74.0" }
            }
            """, named: "broken-ext", in: root)
            try writeManifest(manifestJSON(name: "good"), named: "good-ext", in: root)

            let registry = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
            registry.loadAll()

            #expect(registry.failures.count == 1)
            #expect(registry.failures.first?.identifier == "acme.broken")
            // The whole point: one unparseable manifest must not switch
            // orphan pruning off for every other extension.
            #expect(registry.establishedIdentifiers == ["acme.broken", "acme.good"])
        }
    }

    @Test("a manifest with no readable name still leaves the scan incomplete")
    func namelessMalformedManifestStillBlocksPruning() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            try writeManifest("{ not valid json", named: "broken-ext", in: root)

            let registry = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
            registry.loadAll()

            #expect(registry.failures.first?.identifier == nil)
            #expect(registry.establishedIdentifiers == nil)
        }
    }

    // MARK: - F39 — one extension in two spellings is one extension

    @Test("two casings of one identifier are one identity, and either spelling disables it")
    func caseVariantsAreOneExtension() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            try writeManifest(
                manifestJSON(name: "Foo", publisher: "MS-vscode"), named: "A-ext", in: root)
            try writeManifest(
                manifestJSON(name: "foo", publisher: "ms-vscode"), named: "b-ext", in: root)

            let point = RecordingContributionPoint()
            let registry = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
            registry.register(point)
            registry.loadAll()

            #expect(registry.extensions.count == 1)
            #expect(registry.extensions.first?.identifier == "ms-vscode.foo")
            #expect(point.applyCalls == ["ms-vscode.foo"])
            #expect(registry.failures.count == 1)

            // The user turns it off by the marketplace spelling.
            registry.setEnabled(false, for: "ms-vscode.foo")
            #expect(!registry.isEnabled("MS-vscode.Foo"))
            #expect(point.appliedIdentifiers.isEmpty)
        }
    }

    @Test("a disabled identifier persisted in another casing still disables")
    func persistedDisabledIdentifierMigratesCase() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            UserSettings.disabledExtensionIdentifiers.value = ["MS-vscode.Foo"]
            try writeManifest(
                manifestJSON(name: "foo", publisher: "ms-vscode"), named: "b-ext", in: root)

            let point = RecordingContributionPoint()
            let registry = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
            registry.register(point)
            registry.loadAll()

            #expect(registry.extensions.count == 1)
            #expect(!registry.isEnabled("ms-vscode.foo"))
            #expect(point.applyCalls.isEmpty)
        }
    }
    // MARK: - F52 — the load path is synchronous, so its cost is the launch's

    @Test("a hundred fat manifests all load, in order, on one synchronous pass")
    func aHundredExtensionsLoadInSortedOrder() throws {
        try withInMemorySettings {
            let root = try makeTempDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            // Sized like real manifests rather than like the two-line fixtures
            // above — four themes, a dozen commands, twenty configuration
            // properties — because `loadAll()` runs synchronously on the main
            // actor at launch (Ruling FN) and what it costs is decided by what
            // it decodes. This is the fixture F52 was measured on; the numbers
            // are in the D7 report, and the reason there is no timing
            // assertion here is that a wall-clock threshold on a shared
            // machine fails for reasons that have nothing to do with this code.
            func fat(_ index: Int) -> String {
                let themes = (0..<4).map {
                    "{ \"label\": \"T\($0)\", \"uiTheme\": \"vs-dark\", \"path\": \"./t\($0).json\" }"
                }.joined(separator: ",")
                let commands = (0..<12).map {
                    "{ \"command\": \"acme.e\(index).c\($0)\", \"title\": \"Command \($0)\" }"
                }.joined(separator: ",")
                let properties = (0..<20).map {
                    // swiftlint:disable:next line_length
                    "\"acme.e\(index).p\($0)\": { \"type\": \"string\", \"default\": \"v\($0)\", \"description\": \"A setting number \($0).\" }"
                }.joined(separator: ",")
                return """
                {
                    "name": "e\(index)", "publisher": "acme", "version": "1.0.0",
                    "displayName": "Extension \(index)",
                    "description": "A synthetic extension for the load benchmark.",
                    "engines": { "vscode": "^1.74.0" },
                    "activationEvents": ["onLanguage:swift", "onCommand:acme.e\(index).c0"],
                    "contributes": {
                        "themes": [\(themes)],
                        "commands": [\(commands)],
                        "configuration": { "title": "Extension \(index)", "properties": { \(properties) } }
                    }
                }
                """
            }

            let count = 100
            for index in 0..<count {
                try writeManifest(fat(index), named: String(format: "ext-%03d", index), in: root)
            }

            let registry = ExtensionRegistry(searchPaths: [root], hostVersion: Self.hostVersion)
            let point = RecordingContributionPoint()
            registry.register(point)
            registry.loadAll()

            #expect(registry.failures.isEmpty)
            #expect(registry.extensions.count == count)
            // Directory order, which `contentsOfDirectory` does not give (F40).
            #expect(registry.extensions.map(\.identifier) == (0..<count).map { "acme.e\($0)" })
            #expect(point.applyCalls.count == count)
            // Every fat manifest decoded whole — the strict-first shortcut in
            // `LenientDecoding` must not quietly drop what the slow path kept.
            #expect(registry.extensions.allSatisfy { $0.manifest.contributes?.commands.count == 12 })
            #expect(registry.extensions.allSatisfy { $0.manifest.contributes?.themes.count == 4 })
        }
    }

}
