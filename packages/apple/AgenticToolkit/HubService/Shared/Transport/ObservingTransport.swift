import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Wraps any `ClientTransport` and reports each successful response to an
/// observer. `HubEnvironment` uses it to notice mirror-served responses
/// (`cache-control: no-store`) so the status strip can say the data is cached.
/// Errors thrown by the base transport propagate unchanged and are not observed.
public struct ObservingTransport: ClientTransport {
    public typealias Observer = @Sendable (HTTPResponse) -> Void

    private let base: any ClientTransport
    private let observer: Observer

    public init(base: any ClientTransport, onResponse: @escaping Observer) {
        self.base = base
        self.observer = onResponse
    }

    public func send(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let result = try await base.send(request, body: body, baseURL: baseURL, operationID: operationID)
        observer(result.0)
        return result
    }
}
