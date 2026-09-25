import Foundation
import HTTPTypes
import OpenAPIRuntime

/// A `ClientTransport` that answers from an in-memory route table keyed by
/// `"<METHOD> <path>"` (query string stripped). Every request is recorded so
/// tests can assert on paths, bodies, and call counts. Unrouted requests get
/// a 404 with a JSON error body naming the missing route, which makes a
/// missing stub obvious in the failure message.
final class StubClientTransport: ClientTransport, @unchecked Sendable {
    struct Response {
        var status: Int
        var headers: [String: String]
        var json: String

        init(status: Int = 200, headers: [String: String] = [:], json: String = "{}") {
            self.status = status
            self.headers = headers
            self.json = json
        }
    }

    struct Recorded {
        let request: HTTPRequest
        let body: Data?
        var path: String { StubClientTransport.pathOnly(request.path ?? "") }
    }

    typealias Handler = @Sendable (HTTPRequest, Data?) throws -> Response

    private let lock = NSLock()
    private var routes: [String: Handler] = [:]
    private var recorded: [Recorded] = []

    var requests: [Recorded] {
        lock.withLock { recorded }
    }

    func on(_ method: HTTPRequest.Method, _ path: String, respond: @escaping Handler) {
        lock.withLock { routes[Self.key(method, path)] = respond }
    }

    func on(
        _ method: HTTPRequest.Method,
        _ path: String,
        status: Int = 200,
        headers: [String: String] = [:],
        json: String = "{}"
    ) {
        on(method, path) { _, _ in Response(status: status, headers: headers, json: json) }
    }

    func requestCount(_ method: HTTPRequest.Method, _ path: String) -> Int {
        requests.filter { $0.request.method == method && $0.path == path }.count
    }

    func lastRequest(_ method: HTTPRequest.Method, _ path: String) -> HTTPRequest? {
        requests.last { $0.request.method == method && $0.path == path }?.request
    }

    func lastBody(_ method: HTTPRequest.Method, _ path: String) -> [String: Any]? {
        guard let data = requests.last(where: { $0.request.method == method && $0.path == path })?.body else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    func send(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var data: Data?
        if let body {
            data = try await Data(collecting: body, upTo: 4 * 1024 * 1024)
        }
        let path = Self.pathOnly(request.path ?? "")
        let handler = lock.withLock { () -> Handler? in
            recorded.append(Recorded(request: request, body: data))
            return routes[Self.key(request.method, path)]
        }
        let response: Response
        if let handler {
            response = try handler(request, data)
        } else {
            response = Response(
                status: 404,
                json: #"{"error":"StubClientTransport: no route for \#(request.method.rawValue) \#(path)"}"#
            )
        }
        var fields = HTTPFields()
        fields[.contentType] = "application/json"
        for (name, value) in response.headers {
            guard let field = HTTPField.Name(name) else {
                preconditionFailure("StubClientTransport: invalid header name \(name)")
            }
            fields[field] = value
        }
        let http = HTTPResponse(status: .init(code: response.status), headerFields: fields)
        return (http, HTTPBody(Data(response.json.utf8)))
    }

    static func key(_ method: HTTPRequest.Method, _ path: String) -> String {
        "\(method.rawValue) \(pathOnly(path))"
    }

    static func pathOnly(_ path: String) -> String {
        String(path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
    }
}
