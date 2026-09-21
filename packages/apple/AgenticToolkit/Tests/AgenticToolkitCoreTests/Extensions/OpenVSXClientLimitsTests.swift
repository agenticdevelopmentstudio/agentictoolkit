import Foundation
import Testing
@testable import AgenticToolkitCore

/// How much a registry may send, and which addresses this client will go to.
///
/// Separate from `OpenVSXClientTests`, which is about what the client asks for
/// and what it does with a well-behaved answer. Everything here is about a
/// registry that is *not* well behaved: a body that does not stop, a header
/// that lies about it, and an address that is not the one the API is at.
/// Nothing in this file is hypothetical — every URL a download uses was named
/// by a response, and a response is the one thing in this system that nobody
/// here wrote.
@Suite(.serialized)
struct OpenVSXClientLimitsTests {

    private func makeClient(
        artifactBytes: Int = OpenVSXClient.defaultMaximumArtifactBytes,
        metadataBytes: Int = OpenVSXClient.defaultMaximumMetadataBytes
    ) -> OpenVSXClient {
        StubbedRegistry.reset()
        return OpenVSXClient(
            registryBase: StubbedRegistry.registryBase,
            session: StubbedRegistry.makeSession(),
            maximumArtifactBytes: artifactBytes,
            maximumMetadataBytes: metadataBytes)
    }

    private let emptyPage = """
    { "offset": 0, "totalSize": 0, "extensions": [] }
    """

    // MARK: - A length claimed before it arrives

    /// The cheap half of the ceiling, and the only half a test can see on its
    /// own: a body of ten bytes behind a header claiming a gigabyte. Counting
    /// the bytes would read all ten of them and succeed, so a run that comes
    /// back with data is a run in which the header was never consulted.
    @Test("a claimed length past the cap is refused without reading the body")
    func aClaimedLengthPastTheCapIsRefused() async throws {
        let client = makeClient(artifactBytes: 1000)
        let url = StubbedRegistry.registryBase.appendingPathComponent("liar.vsix")
        StubbedRegistry.respond(
            to: "/liar.vsix",
            with: StubbedResponse(
                body: Data(repeating: 0x41, count: 10),
                claimedLength: 1 << 30))

        await #expect(throws: OpenVSXError.artifactTooLarge(url, limit: 1000)) {
            _ = try await client.data(at: url)
        }
    }

    /// And the converse, which is why counting cannot be dropped in favour of
    /// the header: a sender that understates costs nothing to write, and a
    /// ceiling that believed the claim would wave four kilobytes past a
    /// one-kilobyte cap.
    @Test("an understated length does not get an oversize body past the cap")
    func anUnderstatedLengthIsNotBelieved() async throws {
        let client = makeClient(artifactBytes: 1000)
        let url = StubbedRegistry.registryBase.appendingPathComponent("sneak.vsix")
        StubbedRegistry.respond(
            to: "/sneak.vsix",
            with: StubbedResponse(
                body: Data(repeating: 0x41, count: 4096),
                claimedLength: 1))

        await #expect(throws: OpenVSXError.artifactTooLarge(url, limit: 1000)) {
            _ = try await client.data(at: url)
        }
    }

    // MARK: - Metadata is a body too

    /// The hole the artifact ceiling left behind. `search` and `detail` read a
    /// response into memory with exactly the same "however much the sender
    /// decides" property the download had, and they are the *first* thing any
    /// registry interaction does — a panel that has typed one character has
    /// already made this request, long before anyone has chosen to install
    /// anything.
    ///
    /// The oversize body here is junk rather than JSON, so the two outcomes
    /// are distinguishable: refused at the ceiling, or read whole and then
    /// rejected by the decoder. The second is the unbounded read passing its
    /// own test.
    @Test("a search answer larger than the cap is refused, not decoded")
    func anOversizeSearchAnswerIsRefused() async throws {
        let client = makeClient(metadataBytes: 1024)
        StubbedRegistry.respond(
            to: "/-/search",
            with: StubbedResponse(body: Data(repeating: 0x41, count: 64 * 1024)))

        do {
            _ = try await client.search("vim")
            Issue.record("an oversize answer was accepted")
        } catch let error as OpenVSXError {
            guard case .responseTooLarge(_, let limit) = error else {
                Issue.record("read to the end and failed to decode: \(error)")
                return
            }
            #expect(limit == 1024)
        }
    }

    @Test("a detail answer larger than the cap is refused too")
    func anOversizeDetailAnswerIsRefused() async throws {
        let client = makeClient(metadataBytes: 1024)
        StubbedRegistry.respond(
            to: "/ms-python/python",
            with: StubbedResponse(body: Data(repeating: 0x41, count: 64 * 1024)))

        do {
            _ = try await client.detail(namespace: "ms-python", name: "python")
            Issue.record("an oversize answer was accepted")
        } catch let error as OpenVSXError {
            guard case .responseTooLarge = error else {
                Issue.record("read to the end and failed to decode: \(error)")
                return
            }
        }
    }

    @Test("a metadata answer claiming a length past the cap is refused")
    func aClaimedMetadataLengthPastTheCapIsRefused() async throws {
        let client = makeClient(metadataBytes: 1024)
        StubbedRegistry.respond(
            to: "/-/search",
            with: StubbedResponse(body: Data(emptyPage.utf8), claimedLength: 1 << 30))

        await #expect(throws: OpenVSXError.self) {
            _ = try await client.search("vim")
        }
    }

    /// The ceiling has to let the ordinary case through, which is the
    /// assertion that stops "refuse everything" from passing the three above.
    @Test("a metadata answer inside the cap is decoded as before")
    func anOrdinaryAnswerIsStillDecoded() async throws {
        let client = makeClient(metadataBytes: 1024)
        StubbedRegistry.respond(to: "/-/search", json: emptyPage)

        let page = try await client.search("vim")

        #expect(page.extensions.isEmpty)
        #expect(page.totalSize == 0)
    }

    /// The artifact ceiling and the metadata ceiling are different numbers for
    /// a reason — a `.vsix` is three orders of magnitude larger than the JSON
    /// describing it — and a refactor that collapsed them to one would make
    /// either the metadata cap useless or the download cap impossible.
    @Test("the two published ceilings are not the same number")
    func theTwoCeilingsAreDistinct() {
        #expect(OpenVSXClient.defaultMaximumMetadataBytes
            < OpenVSXClient.defaultMaximumArtifactBytes)
    }

    // MARK: - Addresses this client will not go to

    /// `URLSession` implements `data:`, so a registry that answered
    /// `"download": "data:application/zip;base64,…"` would have this client
    /// hand the caller an archive the registry inlined into its own metadata —
    /// bytes that never crossed the network and that no digest published
    /// anywhere had to match.
    @Test("a data: artifact URL is refused rather than decoded")
    func aDataURLIsRefused() async throws {
        let client = makeClient()
        let url = try #require(URL(string: "data:text/plain;base64,aGVsbG8="))

        await #expect(throws: OpenVSXError.artifactNotFetchable(url, scheme: "data")) {
            _ = try await client.data(at: url)
        }
        #expect(StubbedRegistry.requestedURLs.isEmpty)
    }

    /// A scheme is case-insensitive by RFC 3986, so the comparison is made
    /// against a lowercased copy. Both directions of that matter: an
    /// `HTTPS:` URL a registry shouted must still be fetched, and a `FILE:`
    /// one must still be refused — a set membership test against the raw
    /// scheme gets both wrong, and the second one dangerously.
    @Test("an uppercase HTTPS scheme is still fetched")
    func anUppercaseHTTPSSchemeIsFetched() async throws {
        let client = makeClient()
        StubbedRegistry.respond(to: "/shouted.vsix", text: "hello")
        let url = try #require(URL(string: "HTTPS://registry.test/shouted.vsix"))

        let read = try await client.data(at: url)

        #expect(String(bytes: read, encoding: .utf8) == "hello")
    }

    @Test("an uppercase FILE scheme is still refused")
    func anUppercaseFileSchemeIsRefused() async throws {
        let client = makeClient()
        let url = try #require(URL(string: "FILE:///etc/passwd"))

        await #expect(throws: OpenVSXError.artifactNotFetchable(url, scheme: "file")) {
            _ = try await client.data(at: url)
        }
        #expect(StubbedRegistry.requestedURLs.isEmpty)
    }

    /// `https:///something` parses, carries the right scheme, and names no
    /// host at all. There is nothing for a request to connect to, and the
    /// failure without this check arrives from `URLSession` as an opaque
    /// `NSURLError` rather than as something that says what the registry did.
    @Test("an artifact URL with no host is refused")
    func aHostlessURLIsRefused() async throws {
        let client = makeClient()
        let url = try #require(URL(string: "https:///lonely.vsix"))

        await #expect(throws: OpenVSXError.artifactNotFetchable(url, scheme: "https")) {
            _ = try await client.data(at: url)
        }
        #expect(StubbedRegistry.requestedURLs.isEmpty)
    }

    // MARK: - Answers that are not the JSON they claim to be

    /// A 200 with nothing in it. The registry behind a misconfigured proxy
    /// does this, and a decoder handed zero bytes throws something whose text
    /// names neither the URL nor the registry.
    @Test("an empty body is an undecodable response naming the URL")
    func anEmptyBodyIsUndecodable() async throws {
        let client = makeClient()
        StubbedRegistry.respond(to: "/-/search", text: "")

        do {
            _ = try await client.search("vim")
            Issue.record("an empty body was accepted")
        } catch let error as OpenVSXError {
            guard case .undecodableResponse(let url, let underlying) = error else {
                Issue.record("wrong error: \(error)")
                return
            }
            #expect(url.path.hasSuffix("/-/search"))
            #expect(!underlying.isEmpty)
        }
    }

    /// Valid JSON of the wrong shape, which is the answer a registry gives
    /// when the endpoint moved and something else is serving that path.
    @Test("valid JSON of the wrong shape is undecodable, not a crash")
    func theWrongShapeIsUndecodable() async throws {
        let client = makeClient()
        StubbedRegistry.respond(to: "/-/search", json: "[1, 2, 3]")

        await #expect(throws: OpenVSXError.self) {
            _ = try await client.search("vim")
        }
    }

    /// Truncated mid-token — the shape a connection dropped halfway produces,
    /// and the one a length-prefixed reader would hand on as complete.
    @Test("a body cut off mid-token is undecodable")
    func aTruncatedBodyIsUndecodable() async throws {
        let client = makeClient()
        StubbedRegistry.respond(
            to: "/-/search", json: #"{ "offset": 0, "totalSize": 2, "exten"#)

        await #expect(throws: OpenVSXError.self) {
            _ = try await client.search("vim")
        }
    }
}
