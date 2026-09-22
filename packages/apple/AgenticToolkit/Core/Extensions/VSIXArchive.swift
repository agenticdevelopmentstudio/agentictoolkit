//
//  VSIXArchive.swift
//  AgenticToolkit
//

import CryptoKit
import Foundation
import OSLog

/// The `.vsix` file itself: proving the bytes are the ones the registry
/// published, and getting them onto disk as a directory.
///
/// A `.vsix` is a zip with the extension's tree under `extension/`, plus
/// packaging metadata (`extension.vsixmanifest`, `[Content_Types].xml`) this
/// host ignores — `ExtensionManifest` reads `extension/package.json` and
/// nothing else.
public enum VSIXArchive {

    /// The subdirectory inside a `.vsix` that holds the extension itself.
    public static let payloadDirectoryName = "extension"

    // MARK: - Proving the bytes

    /// Checks `archive` against the digest and signature the registry
    /// published for it, and returns what was actually proved.
    ///
    /// **Both checks are against things the registry published, and neither
    /// establishes a publisher.** That is worth stating plainly, because the
    /// obvious reading of "the signature verified" is the one thing it cannot
    /// mean here: `publicKeyPEM` reaches this function from
    /// `OpenVSXExtensionDetail.publicKeyURL`, a string in the same JSON
    /// response that named the archive and its digest. A registry serving
    /// altered bytes signs them with a key of its own, publishes that key at
    /// that URL, and every check below passes. There is no anchor to compare
    /// it against — Open VSX publishes no publisher key out of band, and this
    /// host has pinned none — so the result is named `.registryAttested`
    /// rather than `.verified`, and the line the settings panel shows says
    /// "the registry published" rather than "the publisher signed".
    ///
    /// What the two checks do establish is still worth having, and differs
    /// between them. The digest proves the bytes are the ones the registry's
    /// own record names, which catches a truncated transfer and a CDN or
    /// mirror serving something else. The signature proves the archive was not
    /// altered between being signed and arriving here, over a path the digest
    /// does not cover.
    ///
    /// **Nothing published is allowed; half of it is not.** Most of Open VSX
    /// is unsigned, so refusing everything unsigned would refuse the catalog.
    /// One half of the pair is a different situation: something *was*
    /// published, and reporting that as an unsigned extension states the
    /// opposite of what happened. A signature that is present and does not
    /// verify is a third — someone published a signature and these are not the
    /// bytes it covers. Both of the latter throw *(fail-fast)*.
    public static func verify(
        _ archive: Data,
        expectedDigest: String?,
        signature: Data?,
        publicKeyPEM: String?
    ) throws -> VSIXVerification {

        let actual = sha256Hex(of: archive)

        // `.matched` rather than leaving the caller to infer it from `sha256`
        // being filled in: the hash is computed either way, so its presence
        // says only that these bytes were hashed, never that they were
        // compared with anything *(explicit-over-implicit)*.
        var digest = VSIXVerification.DigestResult.notPublished
        if let expectedDigest {
            let expected = expectedDigest
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard expected == actual else {
                throw VSIXVerificationError.digestMismatch(expected: expected, actual: actual)
            }
            digest = .matched
        }

        switch (signature, publicKeyPEM) {
        case (nil, nil):
            return VSIXVerification(sha256: actual, digest: digest, signature: .notPublished)

        // Half a pair proves nothing, but it is not "nothing was published"
        // either, which is what this used to return. Whoever gets the throw
        // can say which half is missing, which is the fact a report against
        // the registry needs.
        case (.some, nil):
            throw VSIXVerificationError.signatureIncomplete(missing: "publicKey")
        case (nil, .some):
            throw VSIXVerificationError.signatureIncomplete(missing: "signature")

        case (let signature?, let publicKeyPEM?):
            // The `.sigzip` is itself a zip holding `.signature.sig` (the raw
            // 64-byte Ed25519 signature), `.signature.manifest` (a JSON
            // listing of every entry's own digest) and an empty
            // `.signature.p7s` left over from the Marketplace's format. The
            // signature covers the `.vsix` bytes directly, so the manifest is
            // redundant here: verifying it instead would prove only that the
            // listing is authentic, and would then need every entry hashed to
            // say anything about the archive.
            let raw = try signatureBytes(fromSigZip: signature)
            let key = try ed25519Key(fromPEM: publicKeyPEM)
            guard key.isValidSignature(raw, for: archive) else {
                throw VSIXVerificationError.signatureInvalid
            }
            return VSIXVerification(
                sha256: actual, digest: digest, signature: .registryAttested)
        }
    }

    public static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Getting it onto disk

    /// Expands `archive` into `destination`, which must not already exist.
    ///
    /// `/usr/bin/ditto -x -k` rather than a zip library: it is the platform's
    /// own unarchiver, it is what `open`ing a zip in the Finder runs, and it
    /// refuses the two ways a hostile archive escapes its destination. Both
    /// were checked against a purpose-built archive rather than assumed:
    ///
    /// - A `../escaped.txt` entry lands at `destination/escaped.txt`, and an
    ///   absolute `/tmp/x` entry lands at `destination/tmp/x`. Nothing is
    ///   written outside, and the extraction succeeds.
    /// - An entry that is a symlink pointing outside, followed by an entry
    ///   written *through* it, fails the whole extraction with a non-zero exit
    ///   and leaves nothing behind the symlink. The escape does not happen and
    ///   it is not silent.
    ///
    /// A pure-Swift unzip would have had to re-earn both, and getting either
    /// subtly wrong is a directory traversal in a path that takes third-party
    /// archives off the internet.
    /// - Parameter timeout: How long the unarchiver gets. Defaults to
    ///   `expansionTimeout`, which is the only value production uses; it is a
    ///   parameter so the giving-up path can be reached by a test in under a
    ///   second instead of never *(dependency-injection)*.
    /// - Parameter byteCeiling: How much may land in `destination` before the
    ///   unarchiver is stopped. Defaults to `expansionByteCeiling`, and is a
    ///   parameter for the same reason `timeout` is.
    /// - Parameter checkInterval: How often the destination is measured
    ///   against `byteCeiling`. Defaults to `expansionCheckInterval`; a test
    ///   lowers it so a bomb it can afford to build — megabytes, not
    ///   gigabytes — is still measured more than once while it lands.
    public static func expand(
        _ archive: URL,
        to destination: URL,
        timeout: TimeInterval = VSIXArchive.expansionTimeout,
        byteCeiling: Int64 = VSIXArchive.expansionByteCeiling,
        checkInterval: TimeInterval = VSIXArchive.expansionCheckInterval
    ) throws {
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw VSIXArchiveError.destinationExists(destination)
        }
        try FileManager.default.createDirectory(
            at: destination, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, destination.path]

        // `CommandRunner` rather than run-and-wait here, for both of the
        // reasons it exists. `ditto` normally writes nothing to stdout, so the
        // undrained pipe this used to hand it was a deadlock waiting for the
        // one archive that makes it talkative — and nothing bounded how long
        // an expansion could take, on bytes fetched from a third party.
        let outcome: CommandRunner.Outcome
        do {
            outcome = try CommandRunner.runToCompletion(
                process,
                timeout: timeout,
                watchdog: CommandRunner.Watchdog(interval: checkInterval) {
                    expandedSize(of: destination, stoppingAbove: byteCeiling) > byteCeiling
                })
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw VSIXArchiveError.expansionUnavailable(String(describing: error))
        }

        // The half-written tree is not a partial install anyone can use, and
        // leaving it means the next attempt hits `destinationExists` and fails
        // for the wrong reason.
        guard !outcome.timedOut else {
            try? FileManager.default.removeItem(at: destination)
            throw VSIXArchiveError.expansionTimedOut(seconds: timeout)
        }
        guard !outcome.aborted else {
            try? FileManager.default.removeItem(at: destination)
            throw VSIXArchiveError.expansionTooLarge(bytes: byteCeiling)
        }
        guard outcome.status == 0 else {
            try? FileManager.default.removeItem(at: destination)
            throw VSIXArchiveError.expansionFailed(
                status: outcome.status, message: outcome.diagnostics)
        }
    }

    /// How long one archive gets to expand.
    ///
    /// Generous on purpose: this covers a large extension on a slow disk, and
    /// the number is not a performance budget — it is the point at which
    /// waiting has stopped being waiting. What it bounds is an archive crafted
    /// so that expanding it takes forever, which arrives here from the
    /// internet.
    ///
    /// It bounds **time, and only time**. This comment used to claim it
    /// covered zip bombs too, on the premise that a bomb "expands forever,
    /// not merely large" — which is backwards. A zip bomb is compression
    /// ratio, not duration: the canonical ones write tens of gigabytes as
    /// fast as the disk accepts them, and finish. Two minutes of that is a
    /// full volume, and the timeout never fires. `expansionByteCeiling` is
    /// what bounds the other axis.
    public static let expansionTimeout: TimeInterval = 120

    /// How much may be written into the destination before the unarchiver is
    /// stopped.
    ///
    /// The `.vsix` that produced it is already capped at 512 MB by
    /// `OpenVSXClient`, and what this caps is the *ratio*: deflate reaches
    /// about 1000:1 on adversarial input, so that 512 MB is licence to write
    /// half a terabyte. 2 GB is several times the largest real extension —
    /// the big ones bundle a language-server binary per platform and land in
    /// the hundreds of megabytes — and small enough that reaching it leaves a
    /// volume with room to report the failure.
    ///
    /// Not a substitute for the timeout and not substituted by it: one bounds
    /// how long a hostile archive can hold a thread, the other how much of
    /// the disk it can take. An archive can do either without doing the other.
    public static let expansionByteCeiling: Int64 = 2 * 1024 * 1024 * 1024

    /// How often the growing destination is measured.
    ///
    /// Half a second against a 2 GB ceiling means an overshoot of whatever the
    /// disk writes in half a second — tens or low hundreds of megabytes, which
    /// is noise against the ceiling and against the free space it protects.
    /// Measuring more often would not buy accuracy that matters and would walk
    /// the tree more.
    public static let expansionCheckInterval: TimeInterval = 0.5

    /// The bytes under `directory`, giving up as soon as the answer is known
    /// to be over `ceiling`.
    ///
    /// **The early exit is what makes this affordable to poll.** A tree being
    /// written by a zip bomb is a handful of enormous files, so the sum passes
    /// the ceiling within a few entries and the walk stops there rather than
    /// enumerating a volume's worth of output. The opposite shape — millions
    /// of tiny files — makes each walk proportionally longer, and that one is
    /// bounded by the expansion timeout instead: the walk runs on the thread
    /// that is already waiting out the deadline.
    ///
    /// Allocated size rather than logical size, because what is being defended
    /// is the volume. A file's last block is charged in full either way, and a
    /// sparse file is charged for what it occupies rather than what it claims.
    private static func expandedSize(of directory: URL, stoppingAbove ceiling: Int64) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let walk = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            // A hostile archive gets no discount for naming its payload with a
            // leading dot, and `ditto` restores package directories as
            // directories, not as opaque single items.
            options: [.skipsPackageDescendants])
        else { return 0 }

        var total: Int64 = 0
        for case let url as URL in walk {
            let values = try? url.resourceValues(forKeys: keys)
            let size = values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0
            total += Int64(size)
            if total > ceiling { return total }
        }
        return total
    }

    /// `<expanded>/extension` — the directory that becomes the installed
    /// extension. Everything beside it in the archive is packaging.
    public static func payloadDirectory(in expanded: URL) -> URL {
        expanded.appendingPathComponent(payloadDirectoryName, isDirectory: true)
    }

    // MARK: - Private

    private static func signatureBytes(fromSigZip sigzip: Data) throws -> Data {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("vsix-signature-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let archive = scratch.appendingPathComponent("signature.zip")
        let expanded = scratch.appendingPathComponent("expanded", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: scratch, withIntermediateDirectories: true)
            try sigzip.write(to: archive)
            try expand(archive, to: expanded)
        } catch {
            throw VSIXVerificationError.signatureArchiveUnreadable(String(describing: error))
        }

        let signature = expanded.appendingPathComponent(".signature.sig")
        guard let bytes = try? Data(contentsOf: signature), bytes.count == ed25519SignatureLength
        else {
            throw VSIXVerificationError.signatureArchiveUnreadable(
                "no \(ed25519SignatureLength)-byte .signature.sig inside the signature archive")
        }
        return bytes
    }

    private static func ed25519Key(fromPEM pem: String) throws -> Curve25519.Signing.PublicKey {
        // An Ed25519 SPKI public key is 44 DER bytes: a 12-byte header naming
        // the algorithm, then the 32-byte key. Taking the tail rather than
        // parsing the DER is safe *because* the length is checked — a
        // structure of any other size is not this key type, and a wrong 32
        // bytes fails verification rather than passing it.
        let base64 = pem
            .split(whereSeparator: \.isNewline)
            .filter { !$0.hasPrefix("-----") }
            .joined()
        guard let der = Data(base64Encoded: base64), der.count == ed25519SPKILength else {
            throw VSIXVerificationError.publicKeyUnreadable
        }
        guard let key = try? Curve25519.Signing.PublicKey(
            rawRepresentation: Data(der.suffix(ed25519KeyLength)))
        else {
            throw VSIXVerificationError.publicKeyUnreadable
        }
        return key
    }

    private static let ed25519SignatureLength = 64
    private static let ed25519KeyLength = 32
    private static let ed25519SPKILength = 44
}

extension VSIXArchive: Loggable {
    public static nonisolated let logger = makeLogger()
}

/// What an archive's bytes were proved to be.
public struct VSIXVerification: Sendable, Equatable {

    /// The archive's own SHA-256, lowercase hex — computed here whether or not
    /// a published digest was available to compare it against, because it is
    /// what an install record needs to recognise these bytes again later.
    public let sha256: String

    /// Whether the archive was compared with a digest the registry
    /// published, as opposed to merely hashed.
    public let digest: DigestResult

    public let signature: SignatureResult

    public enum DigestResult: Sendable, Equatable {
        /// The registry published a digest and these bytes are it.
        case matched
        /// The registry published no digest, so nothing was compared. Kept
        /// distinct from `.matched` because `sha256` is filled in either way,
        /// and a hash that was never compared with anything is not a check.
        case notPublished
    }

    public enum SignatureResult: Sendable, Equatable {
        /// A signature and key the **registry** published agree with these
        /// exact bytes. See `VSIXArchive.verify` for what that does and does
        /// not establish — in particular, not the publisher's identity.
        case registryAttested
        /// The registry published neither a signature nor a key for this
        /// version. Not a failure: most of the catalog is unsigned.
        case notPublished
    }

    public init(sha256: String, digest: DigestResult, signature: SignatureResult) {
        self.sha256 = sha256
        self.digest = digest
        self.signature = signature
    }
}

public enum VSIXVerificationError: Error, Sendable, Equatable {
    case digestMismatch(expected: String, actual: String)

    /// The registry published one half of the signature pair and not the
    /// other. Carries the name of the half that is missing, because that is
    /// the fact a bug report against the registry needs.
    case signatureIncomplete(missing: String)
    case signatureInvalid
    case signatureArchiveUnreadable(String)
    case publicKeyUnreadable
}

public enum VSIXArchiveError: Error, Sendable, Equatable {
    case destinationExists(URL)
    case expansionUnavailable(String)
    case expansionFailed(status: Int32, message: String)

    /// The unarchiver was still going after `seconds` and was stopped. Kept
    /// apart from `expansionFailed` because it is the one of the two that says
    /// nothing about the archive's contents — there is no exit status and no
    /// message, only a decision this code made.
    case expansionTimedOut(seconds: TimeInterval)

    /// The expansion passed `bytes` on disk and was stopped. Distinct from the
    /// timeout for the reason the two limits are distinct: this one is a
    /// statement about the archive — it decompresses to more than any real
    /// extension does — where a timeout says only that a clock ran out.
    case expansionTooLarge(bytes: Int64)
}
