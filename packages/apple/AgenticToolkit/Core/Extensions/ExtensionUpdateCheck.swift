//
//  ExtensionUpdateCheck.swift
//  AgenticToolkit
//

import Foundation
import OSLog

/// Asks the registry whether anything installed has a newer version this host
/// could actually run.
///
/// **An update is only reported if installing it would succeed.** The registry
/// publishes versions that raise `engines.vscode` past what this host declares,
/// and versions built for one native platform — offering either as an update
/// produces a button whose only outcome is a refusal. So each candidate is put
/// through the same `installability(forHostVersion:)` the installer uses, and a
/// version that fails it is not an update, it is the end of that extension's
/// updates for now *(principle-of-least-astonishment)*.
public struct ExtensionUpdateCheck: Sendable {

    private let client: OpenVSXClient
    private let hostVersion: SemanticVersion

    public init(
        client: OpenVSXClient = OpenVSXClient(),
        hostVersion: SemanticVersion = ExtensionRegistry.declaredVSCodeVersion
    ) {
        self.client = client
        self.hostVersion = hostVersion
    }

    /// Checks every extension in `installed`, concurrently.
    ///
    /// One lookup per extension, run together rather than in sequence: the
    /// check is entirely latency, and a user with twenty extensions should not
    /// wait twenty round trips. The result is sorted by identifier so a panel
    /// showing it does not reshuffle between checks, which task completion
    /// order alone would guarantee.
    ///
    /// A lookup that fails does not fail the check. An extension installed by
    /// hand and never published — a dev checkout, a private build — 404s here
    /// every single time, and letting that take down the answer for everything
    /// else would make the feature useless for exactly the people most likely
    /// to have one.
    public func check(_ installed: [LoadedExtension]) async -> ExtensionUpdateReport {
        await withTaskGroup(of: ExtensionUpdateOutcome.self) { group in
            for extensionToCheck in installed {
                group.addTask { await self.outcome(for: extensionToCheck) }
            }
            var updates: [ExtensionUpdate] = []
            var unavailable: [String] = []
            for await outcome in group {
                switch outcome {
                case .update(let update): updates.append(update)
                case .upToDate: break
                case .notCheckable(let identifier): unavailable.append(identifier)
                }
            }
            return ExtensionUpdateReport(
                updates: updates.sorted { $0.identifier < $1.identifier },
                notCheckable: unavailable.sorted())
        }
    }

    /// The newest installable version of one extension, or `nil` when it is
    /// already current.
    public func update(for installed: LoadedExtension) async throws -> ExtensionUpdate? {
        // The registry is addressed by the publisher and name the manifest
        // declares, not by splitting the case-folded identifier back apart: a
        // publisher with a dot in its name would split at the wrong place, and
        // the identifier's case folding is this host's convention rather than
        // the registry's.
        guard let publisher = installed.manifest.publisher, !publisher.isEmpty else {
            throw ExtensionUpdateError.noPublisher(installed.identifier)
        }
        let latest = try await client.detail(namespace: publisher, name: installed.manifest.name)

        guard let installedVersion = SemanticVersion(installed.manifest.version),
              let latestVersion = latest.semanticVersion else {
            // A version string neither side can compare is not an update.
            // Offering one on string inequality alone would happily propose a
            // downgrade, and a downgrade presented as an update is worse than
            // no update check at all.
            throw ExtensionUpdateError.versionNotComparable(
                installed: installed.manifest.version, published: latest.version)
        }
        guard latestVersion > installedVersion else { return nil }

        let installability = latest.installability(forHostVersion: hostVersion)
        guard installability == .installable else {
            return nil
        }
        return ExtensionUpdate(
            identifier: installed.identifier,
            installedVersion: installed.manifest.version,
            latest: latest)
    }

    private func outcome(for installed: LoadedExtension) async -> ExtensionUpdateOutcome {
        do {
            if let update = try await update(for: installed) {
                return .update(update)
            }
            return .upToDate
        } catch {
            let reason = String(describing: error)
            Self.logger.debug(
                "No update answer for \(installed.identifier, privacy: .public): \(reason, privacy: .public)")
            return .notCheckable(installed.identifier)
        }
    }

    private enum ExtensionUpdateOutcome: Sendable {
        case update(ExtensionUpdate)
        case upToDate
        case notCheckable(String)
    }
}

extension ExtensionUpdateCheck: Loggable {
    public static nonisolated let logger = makeLogger()
}

/// A newer version of an installed extension that this host could install.
public struct ExtensionUpdate: Sendable, Equatable {
    public let identifier: String
    public let installedVersion: String
    public let latest: OpenVSXExtensionDetail

    public var latestVersion: String { latest.version }

    public init(identifier: String, installedVersion: String, latest: OpenVSXExtensionDetail) {
        self.identifier = identifier
        self.installedVersion = installedVersion
        self.latest = latest
    }
}

/// The result of one pass over everything installed.
///
/// `notCheckable` is carried beside the updates rather than dropped, because
/// "nothing to update" and "I could not ask about four of them" are different
/// answers and a UI that shows the first for the second is lying quietly.
public struct ExtensionUpdateReport: Sendable, Equatable {
    public let updates: [ExtensionUpdate]
    public let notCheckable: [String]

    public init(updates: [ExtensionUpdate], notCheckable: [String]) {
        self.updates = updates
        self.notCheckable = notCheckable
    }
}

public enum ExtensionUpdateError: Error, Sendable, Equatable {
    /// The manifest declares no `publisher`, so there is no registry
    /// coordinate to look the extension up by.
    case noPublisher(String)
    case versionNotComparable(installed: String, published: String)
}
