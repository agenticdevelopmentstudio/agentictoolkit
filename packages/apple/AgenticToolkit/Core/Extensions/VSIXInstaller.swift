//
//  VSIXInstaller.swift
//  AgenticToolkit
//

import Foundation
import OSLog

/// Puts a `.vsix` on disk as a directory `ExtensionRegistry` can load, and
/// takes the previous install of the same extension away in the same step.
///
/// The whole of this type's care is about the two states a half-done install
/// leaves behind, both of which are worse than a failure:
///
/// - **A partly written directory.** `ExtensionRegistry.load(from:)` silently
///   skips a folder whose `package.json` has not landed yet, calls the scan
///   complete anyway, and `pruneOrphans` then deletes that extension's themes
///   — including the user's selected one, which does not come back. So nothing
///   is ever written into place incrementally: the tree is assembled somewhere
///   else entirely and arrives by a single rename.
/// - **Two directories claiming one identifier.** The registry resolves that by
///   sorted directory name, which is not version order — `…-1.10.0` sorts
///   before `…-1.9.0` — so an update that merely adds a folder can leave the
///   *old* version winning, with a `duplicateIdentifier` failure blaming the
///   new one. Installing therefore removes every other directory claiming the
///   identifier, rather than trusting a naming convention to keep them apart.
public struct VSIXInstaller: Sendable {

    /// Where installs land: `~/Library/Application Support/<App>/Extensions`
    /// in the shipping app. Injected rather than derived for the same reason
    /// `ExtensionRegistry`'s search paths are — `AppStorageLocation` is in a
    /// tier this one cannot import — and because a test that installs into a
    /// real user's extensions directory is not a test.
    public let installDirectory: URL

    /// The VS Code version this host claims. The archive's own manifest is
    /// checked against it, not just the registry's metadata: the two can
    /// disagree, and the manifest is the one the registry will be loaded by.
    public let hostVersion: SemanticVersion

    /// `FileManager.default` throughout rather than an injected one: it is not
    /// `Sendable`, and the seam a test actually needs is `installDirectory`,
    /// which already points wherever the test says.
    private var fileManager: FileManager { .default }

    public init(
        installDirectory: URL,
        hostVersion: SemanticVersion = ExtensionRegistry.declaredVSCodeVersion
    ) {
        self.installDirectory = installDirectory
        self.hostVersion = hostVersion
    }

    // MARK: - Installing

    /// Fetches, verifies and installs one registry version.
    ///
    /// The order is the contract: everything that can refuse does so before
    /// anything is written. Metadata decides installability, the bytes are
    /// proved against the published digest and signature, the archive's own
    /// manifest is checked against both the host version and the identity the
    /// registry claimed — and only then does anything touch
    /// `installDirectory`.
    public func install(
        _ detail: OpenVSXExtensionDetail,
        using client: OpenVSXClient
    ) async throws -> VSIXInstallation {

        let installability = detail.installability(forHostVersion: hostVersion)
        guard installability == .installable else {
            throw VSIXInstallError.registryVersionUnusable(installability)
        }
        guard let download = detail.universalDownloadURL else {
            throw VSIXInstallError.registryVersionUnusable(.noUniversalBuild)
        }

        // Decided from the record, before the download, for the same reason
        // `installability` is: a refusal the metadata already settles should
        // not cost several megabytes.
        //
        // A signature and its key are one artifact in two files, and the two
        // used to be read under a single `if let … , let …`. That made a
        // record naming one and not the other fetch *neither* — so an
        // extension whose record advertises a signature installed with
        // `signature: .notPublished`, and the settings panel went on to tell
        // the user the publisher had signed nothing for it. Dropping the key
        // from the record was then all it took to drop the check, which is the
        // one thing a verification step must never allow *(fail-fast)*.
        switch (detail.signatureURL, detail.publicKeyURL) {
        case (nil, nil), (.some, .some):
            break
        case (.some, nil):
            throw VSIXInstallError.verificationIncomplete(
                published: "signature", missing: "publicKey")
        case (nil, .some):
            throw VSIXInstallError.verificationIncomplete(
                published: "publicKey", missing: "signature")
        }

        let archive = try await client.data(at: download)

        // Each artifact is fetched only if the registry named it. One it named
        // and then could not serve is a failure, though — that is evidence
        // something is wrong at the registry, and the throw out of `client`
        // carries the URL that failed.
        var digest: String?
        if let sha256URL = detail.sha256URL {
            digest = try await client.text(at: sha256URL)
        }
        var signature: Data?
        var publicKey: String?
        if let signatureURL = detail.signatureURL, let publicKeyURL = detail.publicKeyURL {
            signature = try await client.data(at: signatureURL)
            publicKey = try await client.text(at: publicKeyURL)
        }

        let verification = try VSIXArchive.verify(
            archive,
            expectedDigest: digest,
            signature: signature,
            publicKeyPEM: publicKey)

        return try install(
            archive: archive,
            verification: verification,
            expectedIdentifier: detail.identifier,
            source: .registry(detail.namespace + "/" + detail.name, version: detail.version))
    }

    /// Installs archive bytes already in hand — the local half of the flow
    /// above, and the whole of it for a `.vsix` a user dropped on the app.
    ///
    /// - Parameter expectedIdentifier: the identity the *source* claimed, or
    ///   `nil` when there was no claim to check against. A registry record
    ///   naming `publisher.extension` whose archive contains something else is
    ///   a substitution, and installing it would put an extension on disk
    ///   under a name nothing in the UI expects *(fail-fast)*.
    public func install(
        archive: Data,
        verification: VSIXVerification,
        expectedIdentifier: String? = nil,
        source: VSIXInstallation.Source
    ) throws -> VSIXInstallation {

        let scratch = fileManager.temporaryDirectory
            .appendingPathComponent("vsix-install-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: scratch) }
        try fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)

        let archiveURL = scratch.appendingPathComponent("extension.vsix")
        try archive.write(to: archiveURL)
        let expanded = scratch.appendingPathComponent("expanded", isDirectory: true)
        try VSIXArchive.expand(archiveURL, to: expanded)

        let payload = VSIXArchive.payloadDirectory(in: expanded)
        guard fileManager.fileExists(atPath: payload.path) else {
            throw VSIXInstallError.noPayloadDirectory
        }

        let manifest = try readManifest(in: payload)

        if let expectedIdentifier, expectedIdentifier != manifest.identifier {
            throw VSIXInstallError.identityMismatch(
                claimed: expectedIdentifier, found: manifest.identifier)
        }
        // The same two gates `ExtensionRegistry.load(from:)` applies, applied
        // here so the refusal happens before the directory exists rather than
        // as a failure row beside an extension the user was told installed
        // fine. An unreadable range is kept distinct from an incompatible one
        // for the same reason it is there: the extension may be fine and it is
        // the string that is odd.
        guard let range = VSCodeEngineRange(manifest.engines.vscode) else {
            throw VSIXInstallError.engineRangeUnreadable(manifest.engines.vscode)
        }
        guard range.accepts(hostVersion) else {
            throw VSIXInstallError.engineIncompatible(
                manifest.engines.vscode, host: hostVersion.description)
        }

        // Before the directory is created, and before anything is moved: the
        // manifest is the archive's own document, and two of its fields are
        // about to become a path component. `expectedIdentifier` above guards
        // one of them and only on the registry path; `version` is compared
        // with nothing, anywhere, on any path.
        try Self.requireSafeComponent(manifest.identifier, field: "identifier")
        try Self.requireSafeComponent(manifest.version, field: "version")

        let destination = installDirectory.appendingPathComponent(
            Self.directoryName(identifier: manifest.identifier, version: manifest.version),
            isDirectory: true)

        // Belt and braces, and not redundant: the component check is a
        // predicate over a string, this is a fact about the path that was
        // actually built. They fail for different reasons — a future change to
        // `directoryName` that joined the parts differently would slip past
        // the first and be caught here. `moveIntoPlace` finishes with
        // `rename(2)`, which resolves `..` in the kernel rather than in
        // Foundation, so nothing downstream will catch what these two miss.
        let root = ExtensionResourcePath.canonicalDirectory(installDirectory)
        guard ExtensionResourcePath.url(
            ExtensionResourcePath.canonicalDirectory(destination), isContainedIn: root)
        else {
            throw VSIXInstallError.unsafeIdentity(
                field: "identifier", value: destination.lastPathComponent)
        }

        try fileManager.createDirectory(at: installDirectory, withIntermediateDirectories: true)

        // Re-installing the same version is a no-op that succeeds, not a
        // conflict: an interrupted download, a retry after a network error, or
        // a user pressing Install twice all arrive here, and none of them
        // wants an error *(idempotency)*. The directory is replaced rather
        // than left alone because the bytes are already proved and the
        // existing copy is not — it may be the half-written tree an earlier
        // attempt died inside.
        let superseded = try otherInstallDirectories(
            claiming: manifest.identifier, besides: destination)

        try moveIntoPlace(payload, to: destination)

        for stale in superseded {
            // Not fatal. The new version is in place and loadable; a leftover
            // older directory that could not be deleted costs a
            // `duplicateIdentifier` failure row, which is visible and
            // recoverable, whereas throwing here would report an install that
            // actually succeeded as having failed.
            do {
                try fileManager.removeItem(at: stale)
            } catch {
                let identifier = manifest.identifier
                let reason = error.localizedDescription
                Self.logger.warning(
                    """
                    Installed \(identifier, privacy: .public) but could not remove the \
                    superseded copy at \(stale.path, privacy: .public): \(reason, privacy: .public)
                    """)
            }
        }

        return VSIXInstallation(
            identifier: manifest.identifier,
            version: manifest.version,
            displayName: manifest.displayName,
            directory: destination,
            verification: verification,
            source: source,
            supersededDirectories: superseded,
            runnableHere: manifest.browser != nil || manifest.main == nil)
    }

    /// `<publisher>.<name>-<version>` — the layout the Marketplace installer
    /// writes and the one a user comparing this app's extensions directory
    /// with VS Code's will expect.
    ///
    /// Path-unsafe characters are not escaped, they are refused — by
    /// `requireSafeComponent(_:field:)`, which `install(...)` calls on both
    /// halves before this runs. Rewriting them instead would install an
    /// extension under a name that no longer matches what the registry and the
    /// settings list call it.
    ///
    /// This function itself is pure string joining and guarantees nothing. It
    /// was previously documented as safe because "npm already constrains"
    /// `name` and `publisher` — which was wrong twice over: nothing here runs
    /// npm, and `publisher` is not an npm field at all. The constraint is the
    /// check, and the check is in the caller.
    public static func directoryName(identifier: String, version: String) -> String {
        "\(identifier)-\(version)"
    }

    /// Refuses a manifest field that is not a single, safe path component,
    /// before it can become one.
    ///
    /// **An allowlist of shapes to reject, not of characters to accept**, and
    /// deliberately so: extension names are internationalised, and an
    /// allowlist of characters would refuse a legitimate publisher long before
    /// it refused an attacker. What is rejected is what changes where the path
    /// points — a separator, a `.` that hides the directory or climbs out of
    /// it, a `:` that HFS still maps to `/` in some APIs, an empty component,
    /// and the control characters that make a name unprintable in the settings
    /// list that has to show it.
    ///
    /// The refusal names the field and the value rather than saying "invalid":
    /// this is the one error here whose cause is a hostile document, and the
    /// person reading the message is the one who needs to see what it claimed.
    static func requireSafeComponent(_ value: String, field: String) throws {
        func refuse() -> VSIXInstallError {
            .unsafeIdentity(field: field, value: value)
        }
        guard !value.isEmpty else { throw refuse() }
        guard !value.hasPrefix(".") else { throw refuse() }
        guard !value.contains("/"), !value.contains("\\"), !value.contains(":") else {
            throw refuse()
        }
        guard !value.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else {
            throw refuse()
        }
    }

    // MARK: - Private

    private func readManifest(in payload: URL) throws -> ExtensionManifest {
        let manifestURL = payload.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            throw VSIXInstallError.manifestUnreadable
        }
        do {
            return try JSONDecoder().decode(
                ExtensionManifest.self, from: JSONCPreprocessor.jsonData(from: data))
        } catch {
            throw VSIXInstallError.manifestMalformed(error.localizedDescription)
        }
    }

    /// Every directory in `installDirectory` other than `destination` whose
    /// manifest claims `identifier` — the old versions this install replaces.
    ///
    /// Read from each manifest rather than matched on the folder name, because
    /// a hand-installed extension or a dev checkout is named whatever its
    /// author named it, and those are exactly the copies whose survival would
    /// shadow the one just installed.
    private func otherInstallDirectories(
        claiming identifier: String,
        besides destination: URL
    ) throws -> [URL] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: installDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])
        else { return [] }

        return contents.filter { candidate in
            guard candidate.standardizedFileURL != destination.standardizedFileURL else {
                return false
            }
            guard (try? candidate.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            else { return false }
            guard let data = try? Data(
                contentsOf: candidate.appendingPathComponent("package.json")) else { return false }
            guard let manifest = try? JSONDecoder().decode(
                ExtensionManifest.self, from: JSONCPreprocessor.jsonData(from: data))
            else { return false }
            return manifest.identifier == identifier
        }
    }

    /// Swaps `payload` into `destination` without ever leaving a partial tree
    /// there.
    ///
    /// The new copy arrives by one `moveItem`, which within a volume is a
    /// rename — the directory does not exist and then it exists whole. An
    /// existing copy is moved aside first rather than deleted, so a failure
    /// during the move can put it back: deleting first would leave the user
    /// with neither version if the rename then failed.
    private func moveIntoPlace(_ payload: URL, to destination: URL) throws {
        let aside = destination
            .deletingLastPathComponent()
            .appendingPathComponent(
                ".\(destination.lastPathComponent).replacing-\(UUID().uuidString)",
                isDirectory: true)

        let hadExisting = fileManager.fileExists(atPath: destination.path)
        if hadExisting {
            try fileManager.moveItem(at: destination, to: aside)
        }
        do {
            try fileManager.moveItem(at: payload, to: destination)
        } catch {
            if hadExisting {
                try? fileManager.moveItem(at: aside, to: destination)
            }
            throw VSIXInstallError.couldNotInstall(error.localizedDescription)
        }
        if hadExisting {
            try? fileManager.removeItem(at: aside)
        }
    }
}

extension VSIXInstaller: Loggable {
    public static nonisolated let logger = makeLogger()
}

/// What an install put on disk.
public struct VSIXInstallation: Sendable, Equatable {

    public let identifier: String
    public let version: String
    public let displayName: String?
    public let directory: URL
    public let verification: VSIXVerification
    public let source: Source

    /// Older copies of the same extension this install removed. Reported so a
    /// UI can say "replaced 1.2.0" rather than leaving an update looking like
    /// a first install.
    public let supersededDirectories: [URL]

    /// Whether this host can actually run the extension's code: it declares a
    /// `browser` entry point, or it declares no entry point at all (a theme, a
    /// snippet pack, a grammar — contributions with no JavaScript behind them).
    ///
    /// A `false` here is not a failed install. The extension is on disk, its
    /// declarative contributions work, and the registry's own metadata could
    /// not have told us this — only the archive's manifest can, which is why
    /// it is reported at the end rather than checked as a precondition. An
    /// extension with `main` and no `browser` is a Node extension, and this
    /// host runs web extensions in JavaScriptCore (Decision 1).
    public let runnableHere: Bool

    public enum Source: Sendable, Equatable {
        /// `<namespace>/<name>` at the registry, and the version asked for.
        case registry(String, version: String)
        /// A `.vsix` file the user supplied.
        case localFile(URL)
    }

    public init(
        identifier: String,
        version: String,
        displayName: String?,
        directory: URL,
        verification: VSIXVerification,
        source: Source,
        supersededDirectories: [URL],
        runnableHere: Bool
    ) {
        self.identifier = identifier
        self.version = version
        self.displayName = displayName
        self.directory = directory
        self.verification = verification
        self.source = source
        self.supersededDirectories = supersededDirectories
        self.runnableHere = runnableHere
    }
}

public enum VSIXInstallError: Error, Sendable, Equatable {

    /// The registry's own record rules this version out before anything is
    /// downloaded.
    case registryVersionUnusable(OpenVSXInstallability)

    /// The archive has no `extension/` directory — it is a zip, but not a
    /// `.vsix`.
    case noPayloadDirectory

    case manifestUnreadable
    case manifestMalformed(String)

    /// The archive's manifest names a different extension than the source
    /// claimed.
    case identityMismatch(claimed: String, found: String)

    /// The archive's own `engines.vscode` rejects this host — which the
    /// registry's metadata did not say.
    case engineIncompatible(String, host: String)

    /// The archive's `engines.vscode` is not a range this host can read, so
    /// `ExtensionRegistry` would refuse it on every scan.
    case engineRangeUnreadable(String)

    /// The registry's record names one half of the signature pair and not
    /// the other, so the archive cannot be checked against what the registry
    /// itself says it published.
    case verificationIncomplete(published: String, missing: String)

    /// A manifest field that reaches the install path is not a single, safe
    /// directory component. Carries the field and the value so the message can
    /// name what the archive actually claimed rather than say "invalid".
    case unsafeIdentity(field: String, value: String)

    case couldNotInstall(String)
}
