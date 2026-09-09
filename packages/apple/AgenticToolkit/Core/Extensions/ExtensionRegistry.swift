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
    public func loadAll() {
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
            record(.manifestMalformed("duplicate identifier, already loaded from \(existing.path)"), at: directory)
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
    public func setEnabled(_ enabled: Bool, for identifier: String) {
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

    /// Withdraws `identifier`'s contributions and removes its directory from
    /// disk. Throws only the file-system error; withdrawal itself cannot
    /// fail (see `ContributionPoint.withdraw`).
    public func uninstall(_ identifier: String) throws {
        for point in contributionPoints {
            point.withdraw(extensionIdentifier: identifier)
        }

        guard let index = extensions.firstIndex(where: { $0.identifier == identifier }) else { return }
        let directory = extensions[index].directory
        extensions.remove(at: index)
        try FileManager.default.removeItem(at: directory)
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
}
