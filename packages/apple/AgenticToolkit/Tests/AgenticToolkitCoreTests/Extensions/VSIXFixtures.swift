import CryptoKit
import Foundation
@testable import AgenticToolkitCore

/// The `.vsix` fixtures, in one place because two suites build them.
///
/// `VSIXInstallerTests` drives the local install path and
/// `VSIXRegistryInstallTests` drives the registry one, and both need a real
/// archive: the installer's whole local path runs through `ditto`, so a fixture
/// that faked the zip would test none of it. Extracting rather than copying
/// keeps the two suites from drifting into testing two different archive
/// formats *(dry)*.
enum VSIXFixtures {

    static func makeTemporaryDirectory(_ name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VSIXFixtures-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func manifestJSON(
        name: String = "widget",
        publisher: String = "acme",
        version: String = "1.0.0",
        engine: String = "^1.74.0",
        entryPoint: String? = nil
    ) -> String {
        var fields = [
            "\"name\": \"\(name)\"",
            "\"publisher\": \"\(publisher)\"",
            "\"version\": \"\(version)\"",
            "\"displayName\": \"The \(name)\"",
            "\"engines\": { \"vscode\": \"\(engine)\" }"
        ]
        if let entryPoint {
            fields.append("\"\(entryPoint)\": \"./out/extension.js\"")
        }
        return "{ \(fields.joined(separator: ", ")) }"
    }

    /// Builds a real `.vsix`: a zip whose top-level entry is `extension/`.
    static func makeVSIX(
        manifest: String?,
        in scratch: URL,
        extraFile: String? = nil
    ) throws -> Data {
        let staging = scratch.appendingPathComponent("vsix-\(UUID().uuidString)", isDirectory: true)
        let payload = staging.appendingPathComponent(
            VSIXArchive.payloadDirectoryName, isDirectory: true)
        if let manifest {
            try FileManager.default.createDirectory(
                at: payload, withIntermediateDirectories: true)
            try Data(manifest.utf8).write(to: payload.appendingPathComponent("package.json"))
            if let extraFile {
                try Data("marker".utf8).write(to: payload.appendingPathComponent(extraFile))
            }
        } else {
            // A zip that is not a `.vsix`: no `extension/` at all.
            try FileManager.default.createDirectory(
                at: staging, withIntermediateDirectories: true)
            try Data("not an extension".utf8)
                .write(to: staging.appendingPathComponent("readme.txt"))
        }
        return try zip(contentsOf: staging, in: scratch, named: "\(UUID().uuidString).vsix")
    }

    /// A real Ed25519 signature over `bytes`, packaged the way the registry
    /// publishes one: a `.sigzip` holding `.signature.sig`, plus the key as
    /// PEM.
    ///
    /// The key is generated here and handed back, which is the whole point of
    /// the registry-path tests that use it: nothing anchors this key to a
    /// publisher, so a test can play the part of a registry that signs with its
    /// own.
    static func makeSignatureArtifacts(
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

        let staging = scratch.appendingPathComponent(
            "sig-staging-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try signature.write(to: staging.appendingPathComponent(".signature.sig"))
        let sigzip = try zip(
            contentsOf: staging, in: scratch, named: "\(UUID().uuidString).sigzip")

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
        return (sigzip, pem)
    }

    static func installedDirectoryNames(in directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    private static func zip(
        contentsOf directory: URL,
        in scratch: URL,
        named name: String
    ) throws -> Data {
        let archive = scratch.appendingPathComponent(name)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", directory.path, archive.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
        return try Data(contentsOf: archive)
    }
}
