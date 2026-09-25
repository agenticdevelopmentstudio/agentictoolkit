import Foundation
import Network

public enum LoopbackAuthServerError: Error, Equatable, Sendable {
    /// Every allow-listed port was already taken — another sign-in attempt,
    /// or the `adh` CLI mid-login. The set is fixed by the backend's origin
    /// allow-list, so there is no fallback port to try.
    case noFreePort([UInt16])
    /// The listener bound, but not to the port we asked for, so the `return`
    /// origin would not be one the backend allows.
    case wrongPort(requested: UInt16, bound: UInt16?)
    /// The browser never came back inside the window.
    case timedOut(TimeInterval)
}

/// The app's half of the OAuth round-trip: a one-shot HTTP listener on
/// `127.0.0.1` that the backend redirects the browser back to.
///
/// This exists because of two backend rules, both documented on
/// ``SignInConfiguration``: `/oauth/signin/start` refuses a custom-scheme
/// `return`, and the exchange code is bound to the `User-Agent` of whoever
/// received it. A loopback `return` satisfies the first. The second is why
/// there are *two* routes rather than one:
///
/// - `GET /cb?n=<nonce>` is where the backend lands the browser, with the
///   code in the URL **fragment** — which never reaches a server. The page
///   it serves is a scrap of JavaScript that moves the fragment into a query
///   and navigates on.
/// - `GET /done?n=<nonce>&code=…` is that navigation. It is a top-level
///   browser navigation, the same request kind as the `/callback` redirect
///   that minted the code, so the `User-Agent` it presents is exactly the one
///   the code is bound to. Capturing it here is what lets the app redeem the
///   code at all.
///
/// A same-origin navigation is used rather than the `fetch` the `adh` CLI's
/// capture page does, because production's CORS allow-list does not include
/// the loopback origins — a cross-origin `fetch` to the backend from this page
/// would be blocked. Navigation involves no CORS.
///
/// Both routes require the per-attempt `nonce`, which only this process and
/// the browser it sent know: the port is predictable and any local process can
/// hit it, so the nonce is what makes "a code arrived" mean "the code this
/// attempt asked for".
public final class LoopbackAuthServer: @unchecked Sendable {
    public static let defaultTimeout: TimeInterval = 300

    /// The port actually bound, one of ``SignInConfiguration/loopbackPorts``.
    public let port: UInt16
    /// Per-attempt secret, required by both routes.
    public let nonce: String

    private let listener: NWListener
    private let dismissURL: URL
    private let timeout: TimeInterval
    private let queue: DispatchQueue

    private let lock = NSLock()
    private var outcome: Result<SocialSignInResult, any Error>?
    private var waiter: CheckedContinuation<SocialSignInResult, any Error>?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var isStopped = false

    /// A request head over this is not a browser talking to us.
    private static let maxRequestBytes = 64 * 1024

    private init(listener: NWListener, port: UInt16, nonce: String, dismissURL: URL, timeout: TimeInterval) {
        self.listener = listener
        self.port = port
        self.nonce = nonce
        self.dismissURL = dismissURL
        self.timeout = timeout
        self.queue = DispatchQueue(label: "com.agentic-cookbook.hubkit.loopback-auth.\(port)")
    }

    /// Binds the first free port in `ports`, in order.
    ///
    /// `ports` is not ours to choose — see
    /// ``SignInConfiguration/loopbackPorts``.
    public static func bind(
        ports: [UInt16] = SignInConfiguration.loopbackPorts,
        dismissURL: URL,
        timeout: TimeInterval = defaultTimeout,
        nonce: String = UUID().uuidString
    ) async throws -> LoopbackAuthServer {
        for port in ports {
            guard let endpointPort = NWEndpoint.Port(rawValue: port) else { continue }
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: endpointPort)
            guard let listener = try? NWListener(using: parameters) else { continue }
            let server = LoopbackAuthServer(
                listener: listener,
                port: port,
                nonce: nonce,
                dismissURL: dismissURL,
                timeout: timeout
            )
            do {
                try await server.start()
                return server
            } catch {
                server.shutdown()
                continue
            }
        }
        throw LoopbackAuthServerError.noFreePort(ports)
    }

    /// Where the backend sends the browser back to. Its origin must be a
    /// verbatim member of the client's allow-list, which is why the port is
    /// pinned and the nonce rides in the query.
    public var returnURL: URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(port)
        components.path = "/cb"
        components.queryItems = [URLQueryItem(name: "n", value: nonce)]
        guard let url = components.url else {
            preconditionFailure("could not build loopback return URL for port \(port)")
        }
        return url
    }

    /// Resolves with the first valid delivery, or throws: `CancellationError`
    /// if ``abort()`` ran first (the user closed the browser),
    /// ``SessionControllerError/missingOAuthCode`` if the provider came back
    /// with an error instead of a code, or
    /// ``LoopbackAuthServerError/timedOut(_:)``.
    public func waitForDelivery() async throws -> SocialSignInResult {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let outcome {
                lock.unlock()
                continuation.resume(with: outcome)
                return
            }
            waiter = continuation
            lock.unlock()
        }
    }

    /// Gives up on this attempt. A no-op once a delivery has landed, so the
    /// browser session ending *after* a successful hand-off cannot turn a
    /// success into a cancellation.
    public func abort() {
        fail(CancellationError())
    }

    /// Ends the wait with `error`, unless an outcome already landed. Used when
    /// the browser session itself failed — that error says more than a bare
    /// cancellation would.
    public func fail(_ error: any Error) {
        complete(.failure(error))
    }

    /// Tears down the listener and every open connection. Safe to call twice.
    public func shutdown() {
        lock.lock()
        if isStopped {
            lock.unlock()
            return
        }
        isStopped = true
        let open = connections.values
        connections.removeAll()
        lock.unlock()

        listener.stateUpdateHandler = nil
        listener.newConnectionHandler = nil
        listener.cancel()
        for connection in open {
            connection.cancel()
        }
    }

    // MARK: - Lifecycle

    private func start() async throws {
        let once = ResumeOnce()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    once.run { continuation.resume() }
                case .failed(let error):
                    once.run { continuation.resume(throwing: error) }
                    self?.complete(.failure(error))
                case .cancelled:
                    once.run { continuation.resume(throwing: CancellationError()) }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: queue)
        }

        let bound = listener.port?.rawValue
        guard bound == port else {
            throw LoopbackAuthServerError.wrongPort(requested: port, bound: bound)
        }

        let deadline = timeout
        queue.asyncAfter(deadline: .now() + deadline) { [weak self] in
            self?.complete(.failure(LoopbackAuthServerError.timedOut(deadline)))
        }
    }

    private func complete(_ result: Result<SocialSignInResult, any Error>) {
        lock.lock()
        guard outcome == nil else {
            lock.unlock()
            return
        }
        outcome = result
        let pending = waiter
        waiter = nil
        lock.unlock()
        pending?.resume(with: result)
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        lock.lock()
        if isStopped {
            lock.unlock()
            connection.cancel()
            return
        }
        connections[ObjectIdentifier(connection)] = connection
        lock.unlock()

        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func forget(_ connection: NWConnection) {
        lock.lock()
        connections[ObjectIdentifier(connection)] = nil
        lock.unlock()
        connection.cancel()
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 16 * 1024
        ) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if error != nil {
                self.forget(connection)
                return
            }
            var buffer = buffer
            if let data {
                buffer.append(data)
            }
            if let head = HTTPRequestHead.parse(buffer) {
                self.respond(to: head, on: connection)
                return
            }
            if isComplete || buffer.count > Self.maxRequestBytes {
                self.forget(connection)
                return
            }
            self.receive(connection, buffer: buffer)
        }
    }

    private func respond(to head: HTTPRequestHead, on connection: NWConnection) {
        let response: Data
        switch head.path {
        case "/cb" where head.query["n"] == nonce:
            response = Self.page(status: "200 OK", body: Self.capturePage)
        case "/done" where head.query["n"] == nonce:
            if let code = head.query["code"], !code.isEmpty {
                complete(.success(SocialSignInResult(code: code, userAgent: head.userAgent ?? "")))
                response = Self.page(status: "200 OK", body: Self.donePage(dismissURL: dismissURL, failed: false))
            } else {
                complete(.failure(SessionControllerError.missingOAuthCode))
                response = Self.page(status: "200 OK", body: Self.donePage(dismissURL: dismissURL, failed: true))
            }
        default:
            // Includes a missing or wrong nonce: an unrelated local process
            // gets the same answer as a wrong path, and learns nothing.
            response = Self.page(status: "404 Not Found", body: Self.notFoundPage)
        }
        send(response, on: connection)
    }

    private func send(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { [weak self] _ in
            guard let self else {
                connection.cancel()
                return
            }
            self.forget(connection)
        })
    }
}

/// Resumes a continuation at most once, from whichever callback gets there
/// first. `NWListener` can report `.failed` after `.ready`.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var hasRun = false

    func run(_ body: () -> Void) {
        lock.lock()
        let shouldRun = !hasRun
        hasRun = true
        lock.unlock()
        if shouldRun {
            body()
        }
    }
}

/// Just enough HTTP to read a browser's `GET`. The listener never reads a
/// body, so a complete head is a complete request.
struct HTTPRequestHead: Equatable {
    let method: String
    let path: String
    let query: [String: String]
    let userAgent: String?

    /// Returns `nil` until `buffer` holds a full head, so the caller keeps
    /// reading.
    static func parse(_ buffer: Data) -> HTTPRequestHead? {
        guard let headEnd = terminator(in: buffer) else { return nil }
        // A head that is not valid UTF-8 is not a browser's; reading on until
        // the size cap is the right answer, not guessing at replacement bytes.
        guard let text = String(bytes: buffer[buffer.startIndex..<headEnd], encoding: .utf8) else { return nil }
        var lines = text.split(separator: "\r\n", omittingEmptySubsequences: false)
            .flatMap { $0.split(separator: "\n", omittingEmptySubsequences: false) }
            .map(String.init)
        guard !lines.isEmpty else { return nil }

        let requestLine = lines.removeFirst().split(separator: " ").map(String.init)
        guard requestLine.count >= 2 else { return nil }

        var userAgent: String?
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces)
            guard name.lowercased() == "user-agent" else { continue }
            userAgent = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            break
        }

        let target = requestLine[1]
        // A relative target has no scheme, so give the parser an origin it can
        // discard; only the path and query are read back out.
        let components = URLComponents(string: "http://127.0.0.1" + (target.hasPrefix("/") ? target : "/" + target))
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] where query[item.name] == nil {
            query[item.name] = item.value ?? ""
        }
        return HTTPRequestHead(
            method: requestLine[0],
            path: components?.path ?? target,
            query: query,
            userAgent: userAgent
        )
    }

    private static func terminator(in buffer: Data) -> Data.Index? {
        for pattern in [Data("\r\n\r\n".utf8), Data("\n\n".utf8)] {
            if let range = buffer.range(of: pattern) {
                return range.lowerBound
            }
        }
        return nil
    }
}

// MARK: - Pages

extension LoopbackAuthServer {
    static func page(status: String, body: String) -> Data {
        let bodyData = Data(body.utf8)
        let head = """
        HTTP/1.1 \(status)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(bodyData.count)\r
        Cache-Control: no-store\r
        Connection: close\r
        \r

        """
        return Data(head.utf8) + bodyData
    }

    /// Moves the code from the fragment (server-invisible) into a query on a
    /// second, same-origin navigation whose `User-Agent` we can read.
    static let capturePage = """
    <!doctype html>
    <html lang="en"><head><meta charset="utf-8"><title>Signing in\u{2026}</title>
    <style>\(pageStyle)</style></head>
    <body><main><h1>Signing in\u{2026}</h1>
    <p>One moment.</p>
    <noscript><p>JavaScript is required to finish signing in. Enable it and try again.</p></noscript>
    </main>
    <script>
    (function () {
      var query = new URLSearchParams(location.search);
      var fragment = new URLSearchParams(location.hash.replace(/^#/, ''));
      var out = new URLSearchParams();
      out.set('n', query.get('n') || '');
      var code = fragment.get('code') || query.get('code');
      if (code) {
        out.set('code', code);
      } else {
        out.set('error', fragment.get('error') || query.get('error') || 'missing_code');
      }
      location.replace('/done?' + out.toString());
    })();
    </script>
    </body></html>
    """

    static func donePage(dismissURL: URL, failed: Bool) -> String {
        let heading = failed ? "Sign-in failed" : "Signed in"
        let message = failed
            ? "The provider did not return an authorization code. Return to Agentic Developer Hub and try again."
            : "You can close this window and return to Agentic Developer Hub."
        return """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8"><title>\(heading)</title>
        <style>\(pageStyle)</style></head>
        <body><main><h1>\(heading)</h1><p>\(message)</p></main>
        <script>
        setTimeout(function () { location.replace('\(javaScriptString(dismissURL.absoluteString))'); }, 200);
        </script>
        </body></html>
        """
    }

    static let notFoundPage = """
    <!doctype html>
    <html lang="en"><head><meta charset="utf-8"><title>Not found</title>
    <style>\(pageStyle)</style></head>
    <body><main><h1>Not found</h1></main></body></html>
    """

    private static let pageStyle = """
    :root { color-scheme: light dark; }
    body { font: 15px/1.5 -apple-system, system-ui, sans-serif; margin: 0; }
    body { display: grid; place-items: center; min-height: 100vh; }
    main { text-align: center; padding: 2rem; max-width: 30rem; }
    h1 { font-size: 1.25rem; font-weight: 600; margin: 0 0 .5rem; }
    p { margin: 0; opacity: .7; }
    """

    /// Escapes for a single-quoted JavaScript literal. `<` goes too, so the
    /// value can never close the surrounding `<script>`.
    static func javaScriptString(_ value: String) -> String {
        var escaped = ""
        for character in value {
            switch character {
            case "\\": escaped += "\\\\"
            case "'": escaped += "\\'"
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "<": escaped += "\\x3c"
            default: escaped.append(character)
            }
        }
        return escaped
    }
}
