import CryptoKit
import Foundation
import Testing
@testable import AgenticToolkitCore

/// Proving downloaded bytes, and getting them onto disk.
///
/// This is the security half of installing. The bytes arrive over the network
/// from a registry nobody here controls, and everything downstream — the
/// manifest read, the extension loaded, the JavaScript run — trusts that what
/// landed is what the publisher published. So the signature is built here from
/// a real Ed25519 key rather than stubbed: a test that asserts "verify was
/// called" would pass just as happily against a `verify` that always says yes.
@Suite
struct VSIXArchiveTests {

    private func makeTemporaryDirectory(_ name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VSIXArchiveTests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Zips `directory`'s *contents* — no `--keepParent` — so a staging folder
    /// holding `extension/package.json` becomes an archive whose top-level
    /// entry is `extension/`, which is the shape of a real `.vsix`.
    private func zip(contentsOf directory: URL, to archive: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", directory.path, archive.path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    // MARK: - The digest

    @Test("the digest is lowercase hex of the bytes themselves")
    func digestIsOfTheBytes() {
        let bytes = Data("the archive".utf8)
        let expected = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        #expect(VSIXArchive.sha256Hex(of: bytes) == expected)
        #expect(VSIXArchive.sha256Hex(of: bytes) == VSIXArchive.sha256Hex(of: bytes))
        #expect(VSIXArchive.sha256Hex(of: Data("the archives".utf8)) != expected)
    }

    /// The registry serves its digest as a text file with a trailing newline,
    /// and the client trims it — but a digest that arrives padded or shouted
    /// still has to compare equal, because a mismatch here fails the install
    /// with a message accusing the publisher of substitution.
    @Test("a digest is compared after trimming and case-folding")
    func digestComparisonIsForgivingAboutFormatting() throws {
        let bytes = Data("the archive".utf8)
        let digest = VSIXArchive.sha256Hex(of: bytes)

        let verification = try VSIXArchive.verify(
            bytes,
            expectedDigest: "  \(digest.uppercased())\n",
            signature: nil,
            publicKeyPEM: nil)
        #expect(verification.sha256 == digest)
        #expect(verification.signature == .notPublished)
    }

    @Test("a digest that does not match throws, naming both sides")
    func digestMismatchThrows() {
        let bytes = Data("the archive".utf8)
        let wrong = String(repeating: "a", count: 64)
        #expect(throws: VSIXVerificationError.digestMismatch(
            expected: wrong, actual: VSIXArchive.sha256Hex(of: bytes))) {
            try VSIXArchive.verify(
                bytes, expectedDigest: wrong, signature: nil, publicKeyPEM: nil)
        }
    }

    /// Most of Open VSX publishes no digest at all. The archive's own hash is
    /// still computed, because an install record needs it to recognise these
    /// bytes later.
    @Test("no published digest still records the archive's own hash")
    func noDigestStillHashes() throws {
        let bytes = Data("the archive".utf8)
        let verification = try VSIXArchive.verify(
            bytes, expectedDigest: nil, signature: nil, publicKeyPEM: nil)
        #expect(verification.sha256 == VSIXArchive.sha256Hex(of: bytes))
    }

    // MARK: - The signature

    /// Builds the registry's two artifacts for real: a PEM SPKI public key,
    /// and a `.sigzip` holding `.signature.sig`.
    private func makeSignatureArtifacts(
        signing bytes: Data,
        in scratch: URL,
        corruptSignature: Bool = false
    ) throws -> (sigzip: Data, publicKeyPEM: String) {
        let key = Curve25519.Signing.PrivateKey()
        var signature = try key.signature(for: bytes)
        if corruptSignature {
            // One flipped byte in an otherwise well-formed 64-byte signature:
            // the case where someone published a signature and these are not
            // the bytes it covers.
            signature[0] ^= 0xFF
        }

        let staging = scratch.appendingPathComponent("sig-staging", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try signature.write(to: staging.appendingPathComponent(".signature.sig"))
        let sigzip = scratch.appendingPathComponent("signature.sigzip")
        try zip(contentsOf: staging, to: sigzip)

        // An Ed25519 SPKI: the fixed 12-byte algorithm header, then the key.
        let header = Data([
            0x30, 0x2A, 0x30, 0x05, 0x06, 0x03, 0x2B, 0x65, 0x70, 0x03, 0x21, 0x00
        ])
        let der = header + key.publicKey.rawRepresentation
        let pem = """
        -----BEGIN PUBLIC KEY-----
        \(der.base64EncodedString())
        -----END PUBLIC KEY-----
        """
        return (try Data(contentsOf: sigzip), pem)
    }

    @Test("a real signature over the real bytes verifies")
    func signatureVerifies() throws {
        let scratch = try makeTemporaryDirectory("verify")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let bytes = Data("the archive, signed".utf8)
        let artifacts = try makeSignatureArtifacts(signing: bytes, in: scratch)

        let verification = try VSIXArchive.verify(
            bytes,
            expectedDigest: VSIXArchive.sha256Hex(of: bytes),
            signature: artifacts.sigzip,
            publicKeyPEM: artifacts.publicKeyPEM)
        #expect(verification.signature == .verified)
    }

    @Test("a signature over different bytes is refused")
    func signatureOverOtherBytesIsRefused() throws {
        let scratch = try makeTemporaryDirectory("substituted")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let published = Data("the archive the publisher signed".utf8)
        let artifacts = try makeSignatureArtifacts(signing: published, in: scratch)

        // The substitution the signature exists to catch: a registry that can
        // rewrite its own metadata — so the digest agrees — but cannot forge
        // the publisher's key.
        let substituted = Data("something else entirely".utf8)
        #expect(throws: VSIXVerificationError.signatureInvalid) {
            try VSIXArchive.verify(
                substituted,
                expectedDigest: VSIXArchive.sha256Hex(of: substituted),
                signature: artifacts.sigzip,
                publicKeyPEM: artifacts.publicKeyPEM)
        }
    }

    @Test("a corrupted signature is refused rather than ignored")
    func corruptedSignatureIsRefused() throws {
        let scratch = try makeTemporaryDirectory("corrupt")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let bytes = Data("the archive".utf8)
        let artifacts = try makeSignatureArtifacts(
            signing: bytes, in: scratch, corruptSignature: true)

        #expect(throws: VSIXVerificationError.signatureInvalid) {
            try VSIXArchive.verify(
                bytes,
                expectedDigest: nil,
                signature: artifacts.sigzip,
                publicKeyPEM: artifacts.publicKeyPEM)
        }
    }

    /// Half the pair is no pair. A key with no signature — or the reverse —
    /// cannot prove anything, and reporting `.verified` off one of them would
    /// be the exact lie this type exists to prevent.
    @Test("a signature without its key, or a key without its signature, is unsigned")
    func halfThePairIsNotVerified() throws {
        let scratch = try makeTemporaryDirectory("half")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let bytes = Data("the archive".utf8)
        let artifacts = try makeSignatureArtifacts(signing: bytes, in: scratch)

        let noKey = try VSIXArchive.verify(
            bytes, expectedDigest: nil, signature: artifacts.sigzip, publicKeyPEM: nil)
        #expect(noKey.signature == .notPublished)

        let noSignature = try VSIXArchive.verify(
            bytes, expectedDigest: nil, signature: nil,
            publicKeyPEM: artifacts.publicKeyPEM)
        #expect(noSignature.signature == .notPublished)
    }

    @Test("a public key that is not an Ed25519 SPKI is refused")
    func unreadablePublicKey() throws {
        let scratch = try makeTemporaryDirectory("badkey")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let bytes = Data("the archive".utf8)
        let artifacts = try makeSignatureArtifacts(signing: bytes, in: scratch)

        let notBase64 = """
        -----BEGIN PUBLIC KEY-----
        not base64 at all
        -----END PUBLIC KEY-----
        """
        #expect(throws: VSIXVerificationError.publicKeyUnreadable) {
            try VSIXArchive.verify(
                bytes, expectedDigest: nil, signature: artifacts.sigzip,
                publicKeyPEM: notBase64)
        }

        // Well-formed base64 of the wrong length: an RSA key, say. Refused on
        // the length check rather than mis-parsed into 32 arbitrary bytes.
        let wrongLength = """
        -----BEGIN PUBLIC KEY-----
        \(Data(repeating: 0x01, count: 64).base64EncodedString())
        -----END PUBLIC KEY-----
        """
        #expect(throws: VSIXVerificationError.publicKeyUnreadable) {
            try VSIXArchive.verify(
                bytes, expectedDigest: nil, signature: artifacts.sigzip,
                publicKeyPEM: wrongLength)
        }
    }

    @Test("a signature archive with no .signature.sig in it is refused")
    func emptySignatureArchive() throws {
        let scratch = try makeTemporaryDirectory("emptysig")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let bytes = Data("the archive".utf8)
        let artifacts = try makeSignatureArtifacts(signing: bytes, in: scratch)

        let staging = scratch.appendingPathComponent("wrong-staging", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data("nothing useful".utf8)
            .write(to: staging.appendingPathComponent("readme.txt"))
        let wrongZip = scratch.appendingPathComponent("wrong.sigzip")
        try zip(contentsOf: staging, to: wrongZip)

        #expect(throws: (any Error).self) {
            try VSIXArchive.verify(
                bytes,
                expectedDigest: nil,
                signature: try Data(contentsOf: wrongZip),
                publicKeyPEM: artifacts.publicKeyPEM)
        }
    }

    /// The digest is checked before the signature, so a truncated download is
    /// reported as what it is rather than as a signature failure — which would
    /// send someone looking at the publisher's key instead of their network.
    @Test("a wrong digest is reported even when a signature is also present")
    func digestIsCheckedFirst() throws {
        let scratch = try makeTemporaryDirectory("order")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let bytes = Data("the archive".utf8)
        let artifacts = try makeSignatureArtifacts(signing: bytes, in: scratch)

        let wrong = String(repeating: "b", count: 64)
        #expect(throws: VSIXVerificationError.digestMismatch(
            expected: wrong, actual: VSIXArchive.sha256Hex(of: bytes))) {
            try VSIXArchive.verify(
                bytes,
                expectedDigest: wrong,
                signature: artifacts.sigzip,
                publicKeyPEM: artifacts.publicKeyPEM)
        }
    }

    // MARK: - Onto disk

    @Test("expanding puts the payload where payloadDirectory says it is")
    func expandProducesThePayload() throws {
        let scratch = try makeTemporaryDirectory("expand")
        defer { try? FileManager.default.removeItem(at: scratch) }

        let staging = scratch.appendingPathComponent("staging", isDirectory: true)
        let payload = staging.appendingPathComponent(
            VSIXArchive.payloadDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: payload.appendingPathComponent("package.json"))

        let archive = scratch.appendingPathComponent("extension.vsix")
        try zip(contentsOf: staging, to: archive)

        let expanded = scratch.appendingPathComponent("expanded", isDirectory: true)
        try VSIXArchive.expand(archive, to: expanded)

        let landed = VSIXArchive.payloadDirectory(in: expanded)
            .appendingPathComponent("package.json")
        #expect(FileManager.default.fileExists(atPath: landed.path))
    }

    /// The installer expands into a fresh scratch directory every time, so an
    /// existing destination means something is wrong rather than that a retry
    /// is in progress — merging into it would mix two extensions' files.
    @Test("expanding into a destination that already exists is refused")
    func expandRefusesAnExistingDestination() throws {
        let scratch = try makeTemporaryDirectory("exists")
        defer { try? FileManager.default.removeItem(at: scratch) }

        let staging = scratch.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: staging.appendingPathComponent("file.txt"))
        let archive = scratch.appendingPathComponent("a.zip")
        try zip(contentsOf: staging, to: archive)

        let destination = scratch.appendingPathComponent("taken", isDirectory: true)
        try FileManager.default.createDirectory(
            at: destination, withIntermediateDirectories: true)

        #expect(throws: VSIXArchiveError.destinationExists(destination)) {
            try VSIXArchive.expand(archive, to: destination)
        }
    }

    /// A failed expansion must not leave the half-written tree behind: the
    /// next attempt would then hit `destinationExists` and fail for a reason
    /// that has nothing to do with what actually went wrong.
    @Test("a failed expansion leaves no directory behind")
    func failedExpansionCleansUp() throws {
        let scratch = try makeTemporaryDirectory("failed")
        defer { try? FileManager.default.removeItem(at: scratch) }

        let notAZip = scratch.appendingPathComponent("not-a-zip.vsix")
        try Data("this is not a zip file".utf8).write(to: notAZip)
        let destination = scratch.appendingPathComponent("out", isDirectory: true)

        #expect(throws: (any Error).self) {
            try VSIXArchive.expand(notAZip, to: destination)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }
}
