import Foundation
import Testing
@testable import AgenticToolkitCore

/// Installing from a registry: which verification artifacts get fetched, and
/// what the resulting install record is allowed to claim.
///
/// Separate from `VSIXInstallerTests` because these run against
/// `StubbedRegistry`, whose table is process-wide — so this suite is
/// `.serialized` and that one is free to stay parallel.
///
/// The adversary throughout is **the registry itself**, not the network. Every
/// URL fetched here was named by a registry response, the archive's digest was
/// named by the same response, and so was the key the signature is checked
/// against. That is the fact the assertions below are about.
@Suite(.serialized)
struct VSIXRegistryInstallTests {

    private static let host = SemanticVersion(major: 1, minor: 138, patch: 0)
    private static let base = "https://registry.test/api/acme/widget/1.0.0/file/"

    private func makeClient() -> OpenVSXClient {
        StubbedRegistry.reset()
        return OpenVSXClient(
            registryBase: StubbedRegistry.registryBase,
            session: StubbedRegistry.makeSession())
    }

    /// A version record naming exactly the artifacts the caller asks for.
    /// Every entry is a URL the registry chose, which is the whole point.
    private func detailJSON(files: [String: String]) -> String {
        let entries = files
            .sorted { $0.key < $1.key }
            .map { "\"\($0.key)\": \"\($0.value)\"" }
            .joined(separator: ", ")
        return """
        {
          "namespace": "acme",
          "name": "widget",
          "version": "1.0.0",
          "engines": { "vscode": "^1.74.0" },
          "downloads": { "universal": "\(Self.base)acme.widget-1.0.0.vsix" },
          "files": { \(entries) }
        }
        """
    }

    private func fetchDetail(_ client: OpenVSXClient) async throws -> OpenVSXExtensionDetail {
        try await client.detail(namespace: "acme", name: "widget", version: "1.0.0")
    }

    /// Registered **after** every artifact stub, not before.
    ///
    /// The detail URL (`…/acme/widget/1.0.0`) is a prefix of every artifact URL
    /// it names (`…/acme/widget/1.0.0/file/…`), and `StubURLProtocol` matches a
    /// fragment with `contains` and takes the first entry that hits. Register
    /// this first and the `.vsix` download is answered with the metadata JSON —
    /// which fails as a digest mismatch quoting the JSON, a long way from the
    /// cause. So: artifacts first, this last.
    private func respondWithDetail(files: [String: String]) {
        StubbedRegistry.respond(to: "/acme/widget/1.0.0", json: detailJSON(files: files))
    }

    // MARK: - Half an advertisement

    /// The gate was `if let signatureURL, let publicKeyURL` — one `if` over
    /// both halves, so a record naming a signature and no key fetched neither
    /// and installed with `signature: .notPublished`. The user was then told,
    /// affirmatively, that the publisher had signed nothing, about an extension
    /// whose record says otherwise.
    ///
    /// A registry that publishes half a pair is either broken or removing a
    /// check on purpose. Both are refusals *(fail-fast)*: quietly downgrading
    /// to an unverified install is the one thing a verification step must
    /// never do, which is what the comment above that gate already said.
    @Test("a record naming a signature but no key is refused, not installed unsigned")
    func signatureWithoutAKeyIsRefused() async throws {
        let client = makeClient()
        let scratch = try VSIXFixtures.makeTemporaryDirectory("sig-no-key")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let installDirectory = scratch.appendingPathComponent("Extensions", isDirectory: true)

        let archive = try VSIXFixtures.makeVSIX(
            manifest: VSIXFixtures.manifestJSON(), in: scratch)
        StubbedRegistry.respond(to: ".vsix", with: StubbedResponse(body: archive))
        respondWithDetail(files: ["signature": Self.base + "acme.widget-1.0.0.sigzip"])

        let detail = try await fetchDetail(client)
        let installer = VSIXInstaller(
            installDirectory: installDirectory, hostVersion: Self.host)

        await #expect(throws: VSIXInstallError.verificationIncomplete(
            published: "signature", missing: "publicKey")) {
            _ = try await installer.install(detail, using: client)
        }
        #expect(VSIXFixtures.installedDirectoryNames(in: installDirectory) == [])
    }

    /// The mirror image, and the cheaper attack of the two: a registry that
    /// wants the signature check gone need only stop naming the key.
    @Test("a record naming a key but no signature is refused too")
    func keyWithoutASignatureIsRefused() async throws {
        let client = makeClient()
        let scratch = try VSIXFixtures.makeTemporaryDirectory("key-no-sig")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let installDirectory = scratch.appendingPathComponent("Extensions", isDirectory: true)

        let archive = try VSIXFixtures.makeVSIX(
            manifest: VSIXFixtures.manifestJSON(), in: scratch)
        StubbedRegistry.respond(to: ".vsix", with: StubbedResponse(body: archive))
        respondWithDetail(files: ["publicKey": Self.base + "acme.widget-1.0.0.pem"])

        let detail = try await fetchDetail(client)
        let installer = VSIXInstaller(
            installDirectory: installDirectory, hostVersion: Self.host)

        await #expect(throws: VSIXInstallError.verificationIncomplete(
            published: "publicKey", missing: "signature")) {
            _ = try await installer.install(detail, using: client)
        }
        #expect(VSIXFixtures.installedDirectoryNames(in: installDirectory) == [])
    }

    /// The refusal is decided from the record, so it costs nothing: no
    /// megabytes cross the network to reach a conclusion the metadata already
    /// settles — the same rule `installability(forHostVersion:)` follows.
    @Test("an incomplete record is refused before the archive is downloaded")
    func incompleteRecordIsRefusedBeforeTheDownload() async throws {
        let client = makeClient()
        let scratch = try VSIXFixtures.makeTemporaryDirectory("no-download")
        defer { try? FileManager.default.removeItem(at: scratch) }

        respondWithDetail(files: ["signature": Self.base + "acme.widget-1.0.0.sigzip"])
        let detail = try await fetchDetail(client)
        let installer = VSIXInstaller(
            installDirectory: scratch.appendingPathComponent("Extensions", isDirectory: true),
            hostVersion: Self.host)

        _ = try? await installer.install(detail, using: client)
        #expect(!StubbedRegistry.requestedURLs.contains { $0.absoluteString.hasSuffix(".vsix") })
    }

    // MARK: - What a signature off the registry's own key proves

    /// A complete, valid set installs — and the record says what was actually
    /// established, which is **not** that the publisher signed it.
    ///
    /// The key in this test is generated by the test and served by the test's
    /// registry, exactly as Open VSX serves the real one: from a URL named in
    /// the same response that named the archive and its digest. Nothing
    /// anchors it to a publisher. So a registry that wanted to ship different
    /// bytes would sign them with a key of its own, publish that key, and
    /// every check here would pass — which is why the result is
    /// `.registryAttested` and not `.verified`.
    @Test("a fully attested install records attestation by the registry, not by a publisher")
    func signedInstallRecordsRegistryAttestation() async throws {
        let client = makeClient()
        let scratch = try VSIXFixtures.makeTemporaryDirectory("attested")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let installDirectory = scratch.appendingPathComponent("Extensions", isDirectory: true)

        let archive = try VSIXFixtures.makeVSIX(
            manifest: VSIXFixtures.manifestJSON(), in: scratch)
        let artifacts = try VSIXFixtures.makeSignatureArtifacts(signing: archive, in: scratch)

        StubbedRegistry.respond(to: ".vsix", with: StubbedResponse(body: archive))
        StubbedRegistry.respond(to: ".sha256", text: VSIXArchive.sha256Hex(of: archive))
        StubbedRegistry.respond(to: ".sigzip", with: StubbedResponse(body: artifacts.sigzip))
        StubbedRegistry.respond(to: ".pem", text: artifacts.publicKeyPEM)
        respondWithDetail(files: [
            "sha256": Self.base + "acme.widget-1.0.0.sha256",
            "signature": Self.base + "acme.widget-1.0.0.sigzip",
            "publicKey": Self.base + "acme.widget-1.0.0.pem"
        ])

        let detail = try await fetchDetail(client)
        let installer = VSIXInstaller(
            installDirectory: installDirectory, hostVersion: Self.host)
        let installation = try await installer.install(detail, using: client)

        #expect(installation.verification.signature == .registryAttested)
        #expect(installation.verification.digest == .matched)
        #expect(VSIXFixtures.installedDirectoryNames(in: installDirectory)
            == ["acme.widget-1.0.0"])
    }

    /// Most of Open VSX is unsigned, so a record naming neither half installs.
    /// The two results are kept apart because the sentence shown to the user
    /// differs: "nothing was published to check against" is a fact about the
    /// registry, and stating it as "unsigned" would be a claim about the
    /// publisher.
    @Test("a record naming neither half installs, and says nothing was published")
    func unsignedInstallSaysSo() async throws {
        let client = makeClient()
        let scratch = try VSIXFixtures.makeTemporaryDirectory("unsigned")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let installDirectory = scratch.appendingPathComponent("Extensions", isDirectory: true)

        let archive = try VSIXFixtures.makeVSIX(
            manifest: VSIXFixtures.manifestJSON(), in: scratch)
        StubbedRegistry.respond(to: ".vsix", with: StubbedResponse(body: archive))
        respondWithDetail(files: [:])

        let detail = try await fetchDetail(client)
        let installer = VSIXInstaller(
            installDirectory: installDirectory, hostVersion: Self.host)
        let installation = try await installer.install(detail, using: client)

        #expect(installation.verification.signature == .notPublished)
        #expect(installation.verification.digest == .notPublished)
    }

    /// A digest the registry published and that does not match is a refusal —
    /// and one the install record can never be asked about afterwards, because
    /// there is no install. What the record *is* asked is the other half: a
    /// version with no published digest must not read as one that matched, or
    /// "verified" means nothing.
    @Test("a published digest that matches is distinguishable from none at all")
    func aMatchedDigestIsNotTheSameAsNoDigest() async throws {
        let client = makeClient()
        let scratch = try VSIXFixtures.makeTemporaryDirectory("digest-only")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let installDirectory = scratch.appendingPathComponent("Extensions", isDirectory: true)

        let archive = try VSIXFixtures.makeVSIX(
            manifest: VSIXFixtures.manifestJSON(), in: scratch)
        StubbedRegistry.respond(to: ".vsix", with: StubbedResponse(body: archive))
        StubbedRegistry.respond(to: ".sha256", text: VSIXArchive.sha256Hex(of: archive))
        respondWithDetail(files: ["sha256": Self.base + "acme.widget-1.0.0.sha256"])

        let detail = try await fetchDetail(client)
        let installer = VSIXInstaller(
            installDirectory: installDirectory, hostVersion: Self.host)
        let installation = try await installer.install(detail, using: client)

        #expect(installation.verification.digest == .matched)
        #expect(installation.verification.signature == .notPublished)
    }
}
