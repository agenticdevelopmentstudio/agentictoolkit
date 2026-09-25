import Network
import XCTest
@testable import AgenticToolkitHubService

final class LoopbackAuthServerTests: XCTestCase {
    private static let dismissURL = URL(string: "adh://auth-callback")!

    private func makeServer(
        ports: [UInt16],
        nonce: String = "n-1",
        timeout: TimeInterval = 5
    ) async throws -> LoopbackAuthServer {
        try await LoopbackAuthServer.bind(
            ports: ports,
            dismissURL: Self.dismissURL,
            timeout: timeout,
            nonce: nonce
        )
    }

    // MARK: delivery

    /// The whole point of the `/done` hop: the request that carries the code
    /// is a browser navigation, so its `User-Agent` is the one the backend
    /// bound the code to.
    func testDeliversTheCodeAndTheBrowsersUserAgent() async throws {
        let server = try await makeServer(ports: [51_811], nonce: "n-deliver")
        defer { server.shutdown() }

        async let response = LoopbackTestClient().get(
            port: server.port,
            target: "/done?n=n-deliver&code=code-42",
            userAgent: "Mozilla/5.0 (Macintosh) Safari/605.1.15"
        )
        let result = try await server.waitForDelivery()
        XCTAssertEqual(result.code, "code-42")
        XCTAssertEqual(result.userAgent, "Mozilla/5.0 (Macintosh) Safari/605.1.15")

        let text = try await response
        XCTAssertTrue(text.hasPrefix("HTTP/1.1 200 OK"), text)
    }

    /// The code arrives in the URL *fragment*, which no server ever sees —
    /// the capture page's only job is to move it somewhere one can.
    func testCapturePageMovesTheFragmentOntoTheDoneRoute() async throws {
        let server = try await makeServer(ports: [51_812], nonce: "n-capture")
        defer { server.shutdown() }

        let text = try await LoopbackTestClient().get(
            port: server.port,
            target: "/cb?n=n-capture",
            userAgent: nil
        )
        XCTAssertTrue(text.hasPrefix("HTTP/1.1 200 OK"), text)
        XCTAssertTrue(text.contains("location.hash"), text)
        XCTAssertTrue(text.contains("location.replace('/done?'"), text)
    }

    /// The port is predictable, so any local process can knock. The
    /// per-attempt nonce is what makes "a code arrived" mean "the code this
    /// attempt asked for".
    func testARequestWithTheWrongNonceIsRefusedAndDeliversNothing() async throws {
        let server = try await makeServer(ports: [51_813], nonce: "n-gate")
        defer { server.shutdown() }

        let refused = try await LoopbackTestClient().get(
            port: server.port,
            target: "/done?n=guessed&code=injected",
            userAgent: "Attacker/1.0"
        )
        XCTAssertTrue(refused.hasPrefix("HTTP/1.1 404"), refused)

        async let delivered = server.waitForDelivery()
        _ = try await LoopbackTestClient().get(
            port: server.port,
            target: "/done?n=n-gate&code=genuine",
            userAgent: "Safari/605.1.15"
        )
        let result = try await delivered
        XCTAssertEqual(result.code, "genuine")
    }

    func testTheCapturePageAlsoRequiresTheNonce() async throws {
        let server = try await makeServer(ports: [51_814], nonce: "n-cb")
        defer { server.shutdown() }

        let text = try await LoopbackTestClient().get(port: server.port, target: "/cb", userAgent: nil)
        XCTAssertTrue(text.hasPrefix("HTTP/1.1 404"), text)
    }

    func testAProviderErrorInsteadOfACodeThrowsMissingOAuthCode() async throws {
        let server = try await makeServer(ports: [51_815], nonce: "n-error")
        defer { server.shutdown() }

        _ = try await LoopbackTestClient().get(
            port: server.port,
            target: "/done?n=n-error&error=access_denied",
            userAgent: "Safari/605.1.15"
        )
        do {
            _ = try await server.waitForDelivery()
            XCTFail("expected missingOAuthCode")
        } catch {
            XCTAssertEqual(error as? SessionControllerError, .missingOAuthCode)
        }
    }

    // MARK: outcome is one-shot

    func testAbortCancelsTheWait() async throws {
        let server = try await makeServer(ports: [51_816], nonce: "n-abort")
        defer { server.shutdown() }

        server.abort()
        do {
            _ = try await server.waitForDelivery()
            XCTFail("expected a cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
    }

    /// The browser session always ends *after* the code has been handed over,
    /// so a late abort must not turn a success into a cancellation.
    func testALateAbortCannotUndoADeliveredCode() async throws {
        let server = try await makeServer(ports: [51_817], nonce: "n-late")
        defer { server.shutdown() }

        _ = try await LoopbackTestClient().get(
            port: server.port,
            target: "/done?n=n-late&code=already-mine",
            userAgent: "Safari/605.1.15"
        )
        server.abort()
        let result = try await server.waitForDelivery()
        XCTAssertEqual(result.code, "already-mine")
    }

    // MARK: binding

    func testReturnURLPinsTheBoundPortAndCarriesTheNonce() async throws {
        let server = try await makeServer(ports: [51_818], nonce: "n-return")
        defer { server.shutdown() }

        XCTAssertEqual(server.port, 51_818)
        XCTAssertEqual(server.returnURL, URL(string: "http://127.0.0.1:51818/cb?n=n-return"))
    }

    func testASecondServerFallsThroughToTheNextPort() async throws {
        let ports: [UInt16] = [51_819, 51_820]
        let first = try await makeServer(ports: ports)
        defer { first.shutdown() }
        let second = try await makeServer(ports: ports)
        defer { second.shutdown() }

        XCTAssertEqual(first.port, 51_819)
        XCTAssertEqual(second.port, 51_820)
    }

    /// The allow-list is the backend's, so there is no fallback port to
    /// invent when all three are busy — the attempt has to fail visibly.
    func testEveryPortTakenIsAnError() async throws {
        let ports: [UInt16] = [51_821]
        let holder = try await makeServer(ports: ports)
        defer { holder.shutdown() }

        do {
            let extra = try await makeServer(ports: ports)
            extra.shutdown()
            XCTFail("expected noFreePort")
        } catch {
            XCTAssertEqual(error as? LoopbackAuthServerError, .noFreePort(ports))
        }
    }

    // MARK: request parsing

    func testRequestHeadIsIncompleteUntilTheBlankLine() {
        let partial = Data("GET /cb?n=1 HTTP/1.1\r\nHost: 127.0.0.1\r\n".utf8)
        XCTAssertNil(HTTPRequestHead.parse(partial))
    }

    func testRequestHeadReadsPathQueryAndUserAgent() throws {
        let raw = Data("""
        GET /done?n=a&code=b%20c HTTP/1.1\r
        Host: 127.0.0.1:8517\r
        User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)\r
        Accept: text/html\r
        \r

        """.utf8)
        let head = try XCTUnwrap(HTTPRequestHead.parse(raw))
        XCTAssertEqual(head.method, "GET")
        XCTAssertEqual(head.path, "/done")
        XCTAssertEqual(head.query["n"], "a")
        XCTAssertEqual(head.query["code"], "b c")
        XCTAssertEqual(head.userAgent, "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)")
    }

    func testRequestHeadUserAgentLookupIsCaseInsensitive() throws {
        let raw = Data("GET /cb HTTP/1.1\r\nuser-agent: Lowercase/1.0\r\n\r\n".utf8)
        let head = try XCTUnwrap(HTTPRequestHead.parse(raw))
        XCTAssertEqual(head.userAgent, "Lowercase/1.0")
    }

    // MARK: pages

    func testDonePageNavigatesToTheDismissURL() {
        let page = LoopbackAuthServer.donePage(dismissURL: Self.dismissURL, failed: false)
        XCTAssertTrue(page.contains("location.replace('adh://auth-callback')"), page)
        XCTAssertTrue(page.contains("Signed in"))
    }

    func testDonePageSaysSoWhenThereWasNoCode() {
        let page = LoopbackAuthServer.donePage(dismissURL: Self.dismissURL, failed: true)
        XCTAssertTrue(page.contains("Sign-in failed"), page)
    }

    func testJavaScriptStringCannotCloseTheScriptElement() {
        XCTAssertEqual(LoopbackAuthServer.javaScriptString("</script>'x"), #"\x3c/script>\'x"#)
    }

    func testResponseHeadCarriesTheBodyLength() throws {
        let data = LoopbackAuthServer.page(status: "200 OK", body: "hello")
        let text = try XCTUnwrap(String(bytes: data, encoding: .utf8))
        XCTAssertTrue(text.hasPrefix("HTTP/1.1 200 OK\r\n"), text)
        XCTAssertTrue(text.contains("Content-Length: 5\r\n"), text)
        XCTAssertTrue(text.hasSuffix("\r\n\r\nhello"), text)
    }
}

/// A raw-socket HTTP client. `URLSession` would do, but it owns the
/// `User-Agent` header this listener exists to read, so the test has to write
/// the request itself.
private final class LoopbackTestClient: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var isFinished = false
    private var connection: NWConnection?
    private var continuation: CheckedContinuation<String, any Error>?

    func get(port: UInt16, target: String, userAgent: String?) async throws -> String {
        var head = "GET \(target) HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\n"
        if let userAgent {
            head += "User-Agent: \(userAgent)\r\n"
        }
        head += "Connection: close\r\n\r\n"
        let request = Data(head.utf8)

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()

            guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
                finish(.failure(URLError(.badURL)))
                return
            }
            let connection = NWConnection(host: .ipv4(.loopback), port: endpointPort, using: .tcp)
            self.connection = connection
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    connection.send(content: request, completion: .contentProcessed { _ in })
                    self?.read()
                case .failed(let error):
                    self?.finish(.failure(error))
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }

    private func read() {
        connection?.receive(
            minimumIncompleteLength: 1,
            maximumLength: 64 * 1024
        ) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data {
                self.lock.withLock { self.buffer.append(data) }
            }
            if let error {
                self.finish(.failure(error))
                return
            }
            if isComplete {
                let text = self.lock.withLock { String(bytes: self.buffer, encoding: .utf8) ?? "" }
                self.finish(.success(text))
                return
            }
            self.read()
        }
    }

    private func finish(_ result: Result<String, any Error>) {
        lock.lock()
        guard !isFinished, let pending = continuation else {
            lock.unlock()
            return
        }
        isFinished = true
        continuation = nil
        lock.unlock()
        connection?.cancel()
        pending.resume(with: result)
    }
}
