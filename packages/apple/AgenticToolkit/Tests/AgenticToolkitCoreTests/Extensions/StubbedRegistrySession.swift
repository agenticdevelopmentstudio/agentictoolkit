import Foundation

/// A `URLSession` that answers from a canned table instead of the network.
///
/// `OpenVSXClient` takes a session precisely so its behaviour can be tested
/// without a registry: the real one is a third party whose catalog changes
/// daily, so a test that reached it would assert on whatever `vscodevim.vim`
/// happened to be published as this morning. Every response below is served by
/// `URLProtocol`, which means the client's own request-building — query items,
/// path components, status handling — is exercised for real; only the wire is
/// replaced.
enum StubbedRegistry {

    /// The URL each request was answered from, in order, so a test can assert
    /// on what the client *asked for* and not only on what it did with the
    /// answer.
    static var requestedURLs: [URL] {
        StubURLProtocol.lock.withLock { StubURLProtocol.requested }
    }

    /// Answers any request whose absolute string contains `fragment`. Matching
    /// on a fragment rather than the whole URL keeps a test from having to
    /// restate the query items the client composes — which are themselves
    /// under test elsewhere and would make every other test fail when one of
    /// them changed.
    static func respond(to fragment: String, with response: StubbedResponse) {
        StubURLProtocol.lock.withLock {
            StubURLProtocol.responses.append((fragment, response))
        }
    }

    static func respond(to fragment: String, json: String, status: Int = 200) {
        respond(to: fragment, with: StubbedResponse(status: status, body: Data(json.utf8)))
    }

    static func respond(to fragment: String, text: String, status: Int = 200) {
        respond(to: fragment, with: StubbedResponse(status: status, body: Data(text.utf8)))
    }

    /// Clears the table and the request log. Called at the start of each test
    /// rather than the end, so a test that fails part way through cannot leave
    /// a stub behind that makes the next one pass for the wrong reason.
    static func reset() {
        StubURLProtocol.lock.withLock {
            StubURLProtocol.responses.removeAll()
            StubURLProtocol.requested.removeAll()
        }
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// The base every stubbed test addresses. Not `open-vsx.org`: a stub table
    /// with a hole in it would then fall through to the real registry rather
    /// than failing, and a test that quietly goes to the network is worse than
    /// one that fails.
    static let registryBase = URL(string: "https://registry.test/api")!
}

struct StubbedResponse {
    var status: Int = 200
    var body: Data

    /// Delivered as a bare `URLResponse` rather than an `HTTPURLResponse`.
    ///
    /// The one shape a stub table cannot otherwise produce, and the one the
    /// client's status check quietly let through: `checkStatus` begins by
    /// casting, so a response that is not HTTP skipped every status rule. A
    /// test for that needs a session that answers a request with a non-HTTP
    /// response, which is what this flag is for.
    var isHTTP: Bool = true

    /// The `Content-Length` this response claims, when it must differ from the
    /// body actually sent.
    ///
    /// A ceiling that believes the header and a ceiling that counts the bytes
    /// are two different rules, and a stub whose header always matches its
    /// body cannot tell them apart — every test passes under either one. The
    /// shape that separates them is the dishonest one, which is also the only
    /// shape worth guarding against: a header claiming a gigabyte before a
    /// byte of it has arrived.
    var claimedLength: Int?
}

/// The protocol doing the answering. Registered per-session through
/// `protocolClasses`, so nothing outside a stubbed session is affected.
final class StubURLProtocol: URLProtocol {

    static let lock = NSLock()
    nonisolated(unsafe) static var responses: [(fragment: String, response: StubbedResponse)] = []
    nonisolated(unsafe) static var requested: [URL] = []

    override static func canInit(with request: URLRequest) -> Bool { true }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let match: StubbedResponse? = Self.lock.withLock {
            Self.requested.append(url)
            return Self.responses.first { url.absoluteString.contains($0.fragment) }?.response
        }
        guard let match else {
            // An unstubbed URL is a test bug, and a 404 says so in the one
            // place a reader will be looking — the failure message.
            let response = HTTPURLResponse(
                url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("no stub for this URL".utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let headers = match.claimedLength.map { ["Content-Length": String($0)] }
        let response: URLResponse = match.isHTTP
            ? HTTPURLResponse(
                url: url, statusCode: match.status, httpVersion: "HTTP/1.1",
                headerFields: headers)!
            : URLResponse(
                url: url, mimeType: nil, expectedContentLength: match.body.count,
                textEncodingName: nil)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: match.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
