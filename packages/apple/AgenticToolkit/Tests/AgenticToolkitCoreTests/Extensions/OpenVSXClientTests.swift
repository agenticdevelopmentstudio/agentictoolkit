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
}
