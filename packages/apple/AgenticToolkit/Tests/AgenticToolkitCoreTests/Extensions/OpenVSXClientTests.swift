import Foundation
import Testing
@testable import AgenticToolkitCore

/// What the client asks the registry for, and what it does with the answer.
///
/// Served from `StubbedRegistry` rather than the real `open-vsx.org`: the
/// catalog there changes daily, so an assertion about a real extension would
/// be an assertion about what someone else published this morning.
@Suite(.serialized)
struct OpenVSXClientTests {

    private func makeClient() -> OpenVSXClient {
        StubbedRegistry.reset()
        return OpenVSXClient(
            registryBase: StubbedRegistry.registryBase,
            session: StubbedRegistry.makeSession())
    }

    private let emptyPage = """
    { "offset": 0, "totalSize": 0, "extensions": [] }
    """

    // MARK: - Searching

    @Test("a typed query is sent as a query item, with the paging the caller asked for")
    func searchSendsTheQuery() async throws {
        let client = makeClient()
        StubbedRegistry.respond(to: "/-/search", json: emptyPage)

        _ = try await client.search("vim", offset: 100, size: 25)

        let url = try #require(StubbedRegistry.requestedURLs.first)
        let items = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(
            uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(url.path.hasSuffix("/-/search"))
        #expect(values["query"] == "vim")
        #expect(values["size"] == "25")
        #expect(values["offset"] == "100")
        #expect(values["sortBy"] == "downloadCount")
        // One row per extension, not one per published version: `true` here
        // turns a single popular extension into a page of its own history.
        #expect(values["includeAllVersions"] == "false")
    }

    /// The browse case. An empty query is not an error and is not sent as an
    /// empty `query=` — the registry answers a query-less search with the
    /// whole catalog in the requested order, which is what a panel opening on
    /// nothing typed wants.
    @Test("an empty or whitespace query omits the query item entirely")
    func emptyQueryOmitsTheItem() async throws {
        let client = makeClient()
        StubbedRegistry.respond(to: "/-/search", json: emptyPage)

        _ = try await client.search("")
        _ = try await client.search("   \n ")

        for url in StubbedRegistry.requestedURLs {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(!items.contains { $0.name == "query" })
        }
    }

    @Test("a query is trimmed before it is sent")
    func queryIsTrimmed() async throws {
        let client = makeClient()
        StubbedRegistry.respond(to: "/-/search", json: emptyPage)

        _ = try await client.search("  dracula  ")

        let url = try #require(StubbedRegistry.requestedURLs.first)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first { $0.name == "query" }?.value == "dracula")
    }

    @Test("a search page decodes into its rows")
    func searchDecodes() async throws {
        let client = makeClient()
        StubbedRegistry.respond(to: "/-/search", json: """
        {
          "offset": 0, "totalSize": 412,
          "extensions": [
            { "namespace": "vscodevim", "name": "vim", "version": "1.32.4",
              "displayName": "Vim", "downloadCount": 5000000 }
          ]
        }
        """)

        let page = try await client.search("vim")
        #expect(page.totalSize == 412)
        #expect(page.extensions.map(\.identifier) == ["vscodevim.vim"])
    }

    // MARK: - One extension

    @Test("detail addresses namespace and name, and a version when one is named")
    func detailAddressesTheVersion() async throws {
        let client = makeClient()
        StubbedRegistry.respond(to: "/vscodevim/vim", json: """
        { "namespace": "vscodevim", "name": "vim", "version": "1.32.4" }
        """)

        _ = try await client.detail(namespace: "vscodevim", name: "vim")
        _ = try await client.detail(namespace: "vscodevim", name: "vim", version: "1.0.0")

        let paths = StubbedRegistry.requestedURLs.map(\.path)
        #expect(paths.first?.hasSuffix("/vscodevim/vim") == true)
        #expect(paths.last?.hasSuffix("/vscodevim/vim/1.0.0") == true)
    }

    // MARK: - When the registry says no

    /// A 404 arrives as a perfectly valid HTTP response carrying an error
    /// document. Without the status check the JSON decode fails instead, and
    /// the caller is told its model is wrong when what is wrong is the name it
    /// asked for.
    @Test("a 404 is a request failure, not a decoding failure")
    func notFoundIsAStatusFailure() async throws {
        let client = makeClient()
        StubbedRegistry.respond(
            to: "/acme/nothing", json: "{\"error\":\"not found\"}", status: 404)

        await #expect(throws: OpenVSXError.self) {
            _ = try await client.detail(namespace: "acme", name: "nothing")
        }
        do {
            _ = try await client.detail(namespace: "acme", name: "nothing")
        } catch let error as OpenVSXError {
            guard case .requestFailed(_, let status) = error else {
                Issue.record("expected .requestFailed, got \(error)")
                return
            }
            #expect(status == 404)
        }
    }

    @Test("a 500 is reported with its status too")
    func serverErrorIsReported() async throws {
        let client = makeClient()
        StubbedRegistry.respond(to: "/-/search", text: "upstream is unwell", status: 503)

        do {
            _ = try await client.search("anything")
            Issue.record("expected a throw")
        } catch let error as OpenVSXError {
            guard case .requestFailed(_, let status) = error else {
                Issue.record("expected .requestFailed, got \(error)")
                return
            }
            #expect(status == 503)
        }
    }

    @Test("a 200 that is not the expected JSON is an undecodable response")
    func undecodableResponse() async throws {
        let client = makeClient()
        StubbedRegistry.respond(to: "/-/search", text: "<html>hello</html>")

        do {
            _ = try await client.search("anything")
            Issue.record("expected a throw")
        } catch let error as OpenVSXError {
            guard case .undecodableResponse(_, let underlying) = error else {
                Issue.record("expected .undecodableResponse, got \(error)")
                return
            }
            // Carried as text because `DecodingError` is not `Equatable`, and
            // a case that cannot be compared cannot be asserted on.
            #expect(!underlying.isEmpty)
        }
    }

    // MARK: - Artifacts

    /// The registry's `.sha256` artifact is a bare hex digest with a trailing
    /// newline. A digest compared with a `\n` still attached never matches
    /// anything, so the trim is the whole point of this method.
    @Test("text is trimmed of surrounding whitespace")
    func textIsTrimmed() async throws {
        let client = makeClient()
        let digest = String(repeating: "ab", count: 32)
        StubbedRegistry.respond(to: "/w.sha256", text: "  \(digest)\n\n")

        let read = try await client.text(
            at: StubbedRegistry.registryBase.appendingPathComponent("w.sha256"))
        #expect(read == digest)
    }

    @Test("bytes come back untouched")
    func dataIsUntouched() async throws {
        let client = makeClient()
        let bytes = Data([0x50, 0x4B, 0x03, 0x04, 0x00, 0xFF])
        StubbedRegistry.respond(to: "/w.vsix", with: StubbedResponse(body: bytes))

        let read = try await client.data(
            at: StubbedRegistry.registryBase.appendingPathComponent("w.vsix"))
        #expect(read == bytes)
    }

    @Test("an artifact that is not UTF-8 is refused by text, not mangled")
    func nonTextArtifactIsRefused() async throws {
        let client = makeClient()
        StubbedRegistry.respond(
            to: "/w.bin", with: StubbedResponse(body: Data([0xFF, 0xFE, 0xFD])))

        let url = StubbedRegistry.registryBase.appendingPathComponent("w.bin")
        await #expect(throws: OpenVSXError.artifactNotText(url)) {
            _ = try await client.text(at: url)
        }
    }

    @Test("a failed artifact fetch carries the URL it failed at")
    func artifactFailureNamesTheURL() async throws {
        let client = makeClient()
        StubbedRegistry.respond(to: "/gone.vsix", text: "no", status: 410)

        let url = StubbedRegistry.registryBase.appendingPathComponent("gone.vsix")
        // The URL is on the case because `registryBase` is configurable: "the
        // download failed" does not say whether the self-hosted registry is
        // down or the URL in settings has a typo.
        await #expect(throws: OpenVSXError.requestFailed(url, status: 410)) {
            _ = try await client.data(at: url)
        }
    }

    // MARK: - Where an artifact may come from

    /// Every artifact URL here — the `.vsix`, the digest, the signature, the
    /// public key — is a string out of the registry's own JSON, handed
    /// straight to `URLSession`. `file:` is a scheme `URLSession` implements,
    /// so a registry that answered with `"download": "file:///etc/passwd"` had
    /// this client read a local file and return it as the download.
    ///
    /// A real session, deliberately: `StubURLProtocol.canInit` answers *every*
    /// request, so against a stubbed session this would be refused by the stub
    /// table and pass for the wrong reason.
    @Test("a file: artifact URL is refused rather than read")
    func fileArtifactURLIsRefused() async throws {
        let secret = FileManager.default.temporaryDirectory
            .appendingPathComponent("openvsx-local-\(UUID().uuidString).txt")
        try Data("the contents of a local file".utf8).write(to: secret)
        defer { try? FileManager.default.removeItem(at: secret) }

        let client = OpenVSXClient(
            registryBase: StubbedRegistry.registryBase,
            session: URLSession(configuration: .ephemeral))

        await #expect(throws: OpenVSXError.artifactNotFetchable(secret, scheme: "file")) {
            _ = try await client.data(at: secret)
        }
    }

    /// The registry is reached over TLS and its artifacts are named by it, so
    /// an artifact URL that drops to plain HTTP is a downgrade the registry
    /// asked for — the bytes it names then arrive from whoever is on the path
    /// rather than from the registry, and the digest that would have caught
    /// that was named by the same response.
    ///
    /// The second assertion is the one that matters: refused *before* the
    /// request, not after reading the answer.
    @Test("a plain-http artifact URL is refused before any request is made")
    func plainHTTPArtifactURLIsRefused() async throws {
        let client = makeClient()
        let url = URL(string: "http://registry.test/api/w.vsix")!
        StubbedRegistry.respond(to: "/w.vsix", text: "bytes")

        await #expect(throws: OpenVSXError.artifactNotFetchable(url, scheme: "http")) {
            _ = try await client.data(at: url)
        }
        #expect(StubbedRegistry.requestedURLs.isEmpty)
    }

    /// The guard has to be narrow enough to leave a real registry working. Open
    /// VSX names its artifacts on its own host, but a self-hosted instance
    /// commonly puts them on a CDN — so the rule is the scheme, not the host,
    /// and a test that did not say so would invite someone to "tighten" it into
    /// an outage.
    @Test("an https artifact on another host is still fetched")
    func httpsArtifactOnAnotherHostIsFetched() async throws {
        let client = makeClient()
        StubbedRegistry.respond(to: "cdn.example/w.vsix", text: "bytes")

        let read = try await client.data(at: URL(string: "https://cdn.example/w.vsix")!)
        #expect(String(bytes: read, encoding: .utf8) == "bytes")
    }

    /// `checkStatus` opened with `guard let http = response as? HTTPURLResponse
    /// else { return }` — an early return that treats "not an HTTP response" as
    /// success. Nothing should be able to reach it now that the scheme is
    /// checked first, which is exactly why it should fail closed: an early
    /// return is a status check that silently does not run.
    @Test("a response that is not an HTTP response is a failure, not a success")
    func nonHTTPResponseIsRefused() async throws {
        let client = makeClient()
        let url = StubbedRegistry.registryBase.appendingPathComponent("odd.vsix")
        StubbedRegistry.respond(
            to: "/odd.vsix",
            with: StubbedResponse(body: Data("bytes".utf8), isHTTP: false))

        await #expect(throws: OpenVSXError.responseNotHTTP(url)) {
            _ = try await client.data(at: url)
        }
    }

    // MARK: - What a name is allowed to address

    /// `appendingPathComponent` does not escape anything. It is a *path join*,
    /// so a component carrying `/` or `..` is spliced in as structure, and
    /// `URL` resolves it — `api` + `a/../../admin` + `python` standardizes to
    /// `https://registry.test/admin/python`, two levels above the API root.
    ///
    /// Neither of these names comes from a person typing. `namespace` and
    /// `name` are read off a manifest — an `ExtensionUpdateCheck` feeds in a
    /// sideloaded extension's `publisher`, which is whatever the folder someone
    /// dropped in claims — so the value reaching here is attacker-chosen in
    /// exactly the case that matters.
    @Test("a namespace that climbs out of the API root is refused, not requested")
    func detailRefusesATraversingNamespace() async throws {
        let client = makeClient()

        await #expect(throws: OpenVSXError.self) {
            _ = try await client.detail(namespace: "a/../../admin", name: "python")
        }
        // The refusal has to happen *before* the request. A throw after the
        // fact still sent the escaped URL to the registry.
        #expect(StubbedRegistry.requestedURLs.isEmpty)
    }

    @Test("a name or version that climbs out of the API root is refused, not requested")
    func detailRefusesATraversingNameAndVersion() async throws {
        let client = makeClient()

        await #expect(throws: OpenVSXError.self) {
            _ = try await client.detail(namespace: "acme", name: "../../admin")
        }
        await #expect(throws: OpenVSXError.self) {
            _ = try await client.detail(namespace: "acme", name: "widget", version: "../..")
        }
        // A bare separator is structure too, even without any `..`: it
        // addresses a different endpoint than the one the caller named.
        await #expect(throws: OpenVSXError.self) {
            _ = try await client.detail(namespace: "acme/evil", name: "widget")
        }
        #expect(StubbedRegistry.requestedURLs.isEmpty)
    }

    /// The ordinary names still have to work. A guard that refused these would
    /// be indistinguishable, from the outside, from the registry being down.
    @Test("ordinary namespaces, names and versions are unaffected")
    func detailAcceptsOrdinaryNames() async throws {
        let client = makeClient()
        StubbedRegistry.respond(to: "/ms-python", json: detailJSON)

        _ = try await client.detail(
            namespace: "ms-python", name: "python.vscode", version: "2024.1.0-rc.1")

        let url = try #require(StubbedRegistry.requestedURLs.first)
        #expect(url.absoluteString.hasSuffix("/api/ms-python/python.vscode/2024.1.0-rc.1"))
    }

    // MARK: - How much a registry may send

    /// `session.data(from:)` accumulates the whole body in memory with no
    /// ceiling, and the length is the sender's choice: a registry — or whoever
    /// is answering as one — that streams indefinitely takes the app down by
    /// growing its heap, with no request having failed.
    @Test("an artifact larger than the cap is refused mid-stream")
    func dataRefusesAnOversizeArtifact() async throws {
        StubbedRegistry.reset()
        let client = OpenVSXClient(
            registryBase: StubbedRegistry.registryBase,
            session: StubbedRegistry.makeSession(),
            maximumArtifactBytes: 64)
        let url = StubbedRegistry.registryBase.appendingPathComponent("huge.vsix")
        StubbedRegistry.respond(
            to: "/huge.vsix",
            with: StubbedResponse(body: Data(repeating: 0x41, count: 4096)))

        await #expect(throws: OpenVSXError.artifactTooLarge(url, limit: 64)) {
            _ = try await client.data(at: url)
        }
    }

    @Test("an artifact inside the cap is returned whole")
    func dataAcceptsAnArtifactInsideTheCap() async throws {
        StubbedRegistry.reset()
        let client = OpenVSXClient(
            registryBase: StubbedRegistry.registryBase,
            session: StubbedRegistry.makeSession(),
            maximumArtifactBytes: 4096)
        let url = StubbedRegistry.registryBase.appendingPathComponent("small.vsix")
        StubbedRegistry.respond(
            to: "/small.vsix",
            with: StubbedResponse(body: Data(repeating: 0x41, count: 4096)))

        let read = try await client.data(at: url)
        #expect(read.count == 4096)
    }

    private var detailJSON: String {
        """
        {
            "namespace": "ms-python",
            "name": "python.vscode",
            "version": "2024.1.0-rc.1"
        }
        """
    }
}
