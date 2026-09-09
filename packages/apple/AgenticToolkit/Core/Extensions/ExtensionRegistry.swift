//
//  ExtensionRegistry.swift
//  AgenticToolkit
//

import Foundation
import OSLog

/// Discovers VS Code extensions from disk, gates them by declared VS Code
/// engine compatibility, and drives their contributions through whatever
/// `ContributionPoint`s the host has registered.
///
/// Modeled on `AIPluginManager` (`AIPluginKit/AIPluginManager.swift`):
/// discovery reads only manifests — it never opens `main`/`browser`, and
/// never `dlopen`s anything, because a VS Code extension's JavaScript is not
/// something this host runs. A bad or malicious manifest can therefore only
/// ever produce a load failure, never code execution.
///
/// Search paths are injected, not derived. `AppStorageLocation` (where the
/// app would normally answer "where do extensions live on disk") is in
/// `apple-database`, a tier this one cannot import without creating an
/// upward dependency — so the caller resolves the real paths and passes
/// them in, exactly as `AIPluginManager`'s test-only initializer does.
@MainActor
public final class ExtensionRegistry {

    // MARK: - Properties

    /// The VS Code API version this host claims to implement. Extensions
    /// whose `engines.vscode` rejects this version fail to load — see
    /// `ExtensionLoadError.engineIncompatible`.
    public static let declaredVSCodeVersion = SemanticVersion(major: 1, minor: 95, patch: 0)

    public private(set) var extensions: [LoadedExtension] = []
    public private(set) var failures: [ExtensionLoadFailure] = []

    private let searchPaths: [URL]
    private let hostVersion: SemanticVersion
    private var contributionPoints: [ContributionPoint] = []

    // MARK: - Initialization

    public init(searchPaths: [URL], hostVersion: SemanticVersion) {
        self.searchPaths = searchPaths
        self.hostVersion = hostVersion
    }

    // MARK: - Contribution points

    /// Registers a contribution point. Must happen before `loadAll()`:
    /// loading does not replay past extensions against points registered
    /// afterward, the same way `AIPluginManager`'s discovery does not
    /// retroactively notify a late caller.
    public func register(_ point: any ContributionPoint) {
        contributionPoints.append(point)
    }

    // MARK: - Loading

    /// Discovers manifests under every search path, decodes them, applies
    /// the engine gate, and applies the contributions of every enabled
    /// extension. Never throws: one bad extension does not sink the rest,
    /// it is recorded in `failures` instead.
    ///
    /// Safe to call more than once: the reset covers the contributions an
    /// earlier call applied as well as the two arrays. Clearing only the
    /// arrays would leave every contribution installed twice while the
    /// registry's own state said once, and the single `withdraw` on a later
    /// disable would leave one copy behind.
    public func loadAll() {
        for loaded in extensions {
            for point in contributionPoints {
                point.withdraw(extensionIdentifier: loaded.identifier)
            }
        }

        extensions = []
        failures = []

        let fileManager = FileManager.default
        var claimedIdentifiers: [String: URL] = [:]

        for searchPath in searchPaths {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: searchPath,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for directory in contents {
                guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                    continue
                }
                load(from: directory, claimedIdentifiers: &claimedIdentifiers)
            }
        }
    }

    /// Loads a single extension directory, recording a `LoadedExtension` on
    /// success or an `ExtensionLoadFailure` on any of: an unreadable file,
    /// malformed JSON, an unparsable engine range, or an engine range that
    /// rejects `hostVersion`.
    ///
    /// A directory with no `package.json` is not itself a failure — a
    /// search path can hold ordinary non-extension directories (`.DS_Store`
    /// siblings, a README, a partially-downloaded extension folder) and
    /// none of those are worth surfacing as a load error. `manifestMissing`
    /// stays a case on `ExtensionLoadError` for a future single-extension
    /// lookup (e.g. an install flow resolving one specific directory), just
    /// not for bulk discovery.
    private func load(from directory: URL, claimedIdentifiers: inout [String: URL]) {
        let manifestURL = directory.appendingPathComponent("package.json")

        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return
        }

        let data: Data
        do {
            data = try Data(contentsOf: manifestURL)
        } catch {
            record(.manifestUnreadable(error.localizedDescription), at: directory)
            return
        }

        let manifest: ExtensionManifest
        do {
            manifest = try JSONDecoder().decode(ExtensionManifest.self, from: data)
        } catch {
            record(.manifestMalformed(error.localizedDescription), at: directory)
            return
        }

        guard let range = VSCodeEngineRange(manifest.engines.vscode) else {
            record(.engineRangeUnparsable(manifest.engines.vscode), at: directory)
            return
        }

        guard range.accepts(hostVersion) else {
            record(
                .engineIncompatible(required: manifest.engines.vscode, host: hostVersion.description),
                at: directory
            )
            return
        }

        if let existing = claimedIdentifiers[manifest.identifier] {
            // swiftlint:disable:next line_length
            logger.warning("Skipping duplicate extension '\(manifest.identifier, privacy: .public)' at \(directory.path, privacy: .public); already loaded from \(existing.path, privacy: .public)")
            record(.duplicateIdentifier(existing: existing.path), at: directory)
            return
        }
        claimedIdentifiers[manifest.identifier] = directory

        let loaded = LoadedExtension(manifest: manifest, directory: directory)
        extensions.append(loaded)
        // swiftlint:disable:next line_length
        logger.info("Loaded extension '\(manifest.identifier, privacy: .public)' from \(directory.path, privacy: .public)")

        guard isEnabled(loaded.identifier), let contributes = manifest.contributes else { return }
        applyContributions(contributes, from: manifest, at: directory)
    }

    private func record(_ reason: ExtensionLoadError, at directory: URL) {
        failures.append(ExtensionLoadFailure(directory: directory, reason: reason))
        // swiftlint:disable:next line_length
        logger.warning("Failed to load extension at \(directory.path, privacy: .public): \(String(describing: reason), privacy: .public)")
    }

    private func applyContributions(
        _ contributions: ExtensionManifest.Contributions,
        from manifest: ExtensionManifest,
        at directory: URL
    ) {
        for point in contributionPoints {
            do {
                try point.apply(contributions, from: manifest, at: directory)
            } catch {
                // swiftlint:disable:next line_length
                logger.error("Contribution point '\(point.contributionKey, privacy: .public)' failed to apply '\(manifest.identifier, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                // The console is not a UI. This layer collects what went
                // wrong rather than throwing it, so a point that refuses is
                // recorded where a caller can see it — otherwise the
                // extension lists as healthy while a contribution it declared
                // is silently absent. Loading does not abort: the extension
                // stays loaded and the remaining points still apply.
                failures.append(ExtensionLoadFailure(
                    directory: directory,
                    reason: .contributionPointFailed(
                        key: point.contributionKey,
                        message: error.localizedDescription
                    )
                ))
            }
        }
    }

    // MARK: - Enablement

    /// Whether `identifier` is enabled. Disabled is the tracked state
    /// (`UserSettings.disabledExtensionIdentifiers`), so an identifier this
    /// setting has never seen is enabled by default.
    public func isEnabled(_ identifier: String) -> Bool {
        !UserSettings.disabledExtensionIdentifiers.value.contains(identifier)
    }

    /// Enables or disables `identifier`, applying or withdrawing its
    /// contributions through every registered point in the same call so the
    /// setting and the live contribution state never disagree.
    ///
    /// A call that does not change the state does nothing at all. Callers
    /// re-emit their current value routinely — a `Toggle` bound through a
    /// setter, a settings panel writing every row on save — and applying
    /// twice would leave a contribution point holding two copies of the same
    /// contribution, which one `withdraw` cannot undo.
    public func setEnabled(_ enabled: Bool, for identifier: String) {
        let wasEnabled = isEnabled(identifier)
        guard wasEnabled != enabled else { return }

        var disabled = UserSettings.disabledExtensionIdentifiers.value
        if enabled {
            disabled.remove(identifier)
        } else {
            disabled.insert(identifier)
        }
        UserSettings.disabledExtensionIdentifiers.value = disabled

        guard let loaded = extensions.first(where: { $0.identifier == identifier }) else { return }

        if enabled {
            guard let contributes = loaded.manifest.contributes else { return }
            applyContributions(contributes, from: loaded.manifest, at: loaded.directory)
        } else {
            for point in contributionPoints {
                point.withdraw(extensionIdentifier: identifier)
            }
        }
    }

    // MARK: - Uninstall

    /// Removes `identifier`'s directory from disk and withdraws its
    /// contributions. Throws only the file-system error; withdrawal itself
    /// cannot fail (see `ContributionPoint.withdraw`).
    ///
    /// An uninstall either happens or it does not. The delete — the one
    /// fallible step — runs first, and everything in memory follows it, so a
    /// throw leaves the extension fully intact: still in `extensions`, still
    /// contributed, still on disk. Half-uninstalled is the worse state,
    /// because the UI would show the extension gone while the next
    /// `loadAll()` resurrects it with no explanation.
    ///
    /// An identifier this registry does not know is not an error — a caller
    /// uninstalling something already gone gets a silent no-op with no side
    /// effects, not a throw.
    public func uninstall(_ identifier: String) throws {
        guard let index = extensions.firstIndex(where: { $0.identifier == identifier }) else { return }
        let directory = extensions[index].directory

        try FileManager.default.removeItem(at: directory)

        extensions.remove(at: index)
        for point in contributionPoints {
            point.withdraw(extensionIdentifier: identifier)
        }

        // Clear the tombstone too. `disabledExtensionIdentifiers` is a set of
        // identifiers, not of installs, so an identifier left in it outlives
        // the extension: reinstalling later comes back disabled with nothing
        // in any UI to explain why, breaking the "freshly installed is on by
        // default" promise the setting is shaped around.
        var disabled = UserSettings.disabledExtensionIdentifiers.value
        disabled.remove(identifier)
        UserSettings.disabledExtensionIdentifiers.value = disabled
    }
}

extension ExtensionRegistry: Loggable {
    public static nonisolated let logger = makeLogger()
}

/// A successfully decoded extension and the directory it was loaded from.
/// `directory` is kept (rather than re-derived) because every contribution
/// path in the manifest is relative to it.
public struct LoadedExtension: Sendable, Equatable {
    public let manifest: ExtensionManifest
    public let directory: URL

    public var identifier: String { manifest.identifier }
}

/// One extension directory that failed to load, and why.
public struct ExtensionLoadFailure: Sendable, Equatable {
    public let directory: URL
    public let reason: ExtensionLoadError
}

/// Why a single extension directory failed to load. Every case names enough
/// to explain the failure to a user or log line without re-reading the
/// manifest.
public enum ExtensionLoadError: Error, Sendable, Equatable {
    case manifestMissing
    case manifestUnreadable(String)
    case manifestMalformed(String)
    case engineRangeUnparsable(String)
    case engineIncompatible(required: String, host: String)
    /// A second directory claiming an identifier an earlier search path had
    /// already loaded. Nothing is wrong with this manifest — `existing` is
    /// the path of the copy that won, because "which one is live" is the only
    /// question a user staring at a duplicate install actually has.
    case duplicateIdentifier(existing: String)
    /// A registered `ContributionPoint` threw from `apply`. `key` is that
    /// point's `contributionKey` and `message` the thrown error's
    /// description: this enum is `Equatable` and so cannot carry an
    /// `any Error`, and a point's identity plus its reason is what a log line
    /// or a settings row needs anyway. The extension itself stayed loaded.
    case contributionPointFailed(key: String, message: String)
}
