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
            var unavailable: [ExtensionUpdateUnavailable] = []
            for await outcome in group {
                switch outcome {
                case .update(let update): updates.append(update)
                case .upToDate: break
                case .notCheckable(let entry): unavailable.append(entry)
                }
            }
            return ExtensionUpdateReport(
                updates: updates.sorted { $0.identifier < $1.identifier },
                notCheckable: unavailable.sorted { $0.identifier < $1.identifier })
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
            let description = String(describing: error)
            Self.logger.debug(
                "No update answer for \(installed.identifier, privacy: .public): \(description, privacy: .public)")
            return .notCheckable(ExtensionUpdateUnavailable(
                identifier: installed.identifier,
                reason: Self.reason(for: error)))
        }
    }

    /// Which kind of "no answer" this was.
    ///
    /// **A 404 and a 503 are not the same news.** A 404 is the registry saying
    /// it has never heard of this extension — the ordinary case for a dev
    /// checkout or a private build, and nothing is wrong. Anything else is the
    /// registry not answering: a name that fails to resolve, a proxy, a
    /// registry that is down. Folding them together told a user whose network
    /// was out that eleven of their extensions do not exist.
    ///
    /// The two that never reach the registry at all are kept apart for the
    /// same reason: neither is the registry's doing, and the reader can only
    /// act on one of them.
    private static func reason(for error: Error) -> ExtensionUpdateUnavailable.Reason {
        switch error {
        case let updateError as ExtensionUpdateError:
            switch updateError {
            case .noPublisher: return .noPublisher
            case .versionNotComparable: return .versionNotComparable
            }
        case OpenVSXError.requestFailed(_, status: 404):
            return .notPublished
        default:
            return .registryUnreachable
        }
    }

    private enum ExtensionUpdateOutcome: Sendable {
        case update(ExtensionUpdate)
        case upToDate
        case notCheckable(ExtensionUpdateUnavailable)
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

/// An extension the check could not answer for, and why not.
///
/// The reason is carried rather than reconstructed from the identifier,
/// because from the outside every one of these looks identical — a name and no
/// version — and the difference between "you installed this by hand and it was
/// never published" and "the registry is down" is the whole of what a reader
/// needs to know *(explicit-over-implicit)*.
public struct ExtensionUpdateUnavailable: Sendable, Equatable {

    public enum Reason: Sendable, Equatable {

        /// The registry answered 404: it has no such extension. The ordinary
        /// case for a dev checkout, a private build, or anything installed
        /// from a `.vsix` by hand.
        case notPublished

        /// The registry did not answer, or answered something unusable — the
        /// network, a proxy, a self-hosted registry that is down, a response
        /// that would not decode. Nothing has been learned about the extension
        /// either way.
        case registryUnreachable

        /// The manifest declares no `publisher`, so there is no registry
        /// coordinate to ask about. Nothing was asked.
        case noPublisher

        /// Both versions exist and neither side can order them, so no update
        /// can be offered without risking proposing a downgrade.
        case versionNotComparable
    }

    public let identifier: String
    public let reason: Reason

    public init(identifier: String, reason: Reason) {
        self.identifier = identifier
        self.reason = reason
    }
}

/// The result of one pass over everything installed.
///
/// `notCheckable` is carried beside the updates rather than dropped, because
/// "nothing to update" and "I could not ask about four of them" are different
/// answers and a UI that shows the first for the second is lying quietly.
public struct ExtensionUpdateReport: Sendable, Equatable {
    public let updates: [ExtensionUpdate]
    public let notCheckable: [ExtensionUpdateUnavailable]

    public init(updates: [ExtensionUpdate], notCheckable: [ExtensionUpdateUnavailable]) {
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
