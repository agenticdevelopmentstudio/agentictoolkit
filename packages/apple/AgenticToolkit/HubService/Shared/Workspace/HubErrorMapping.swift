import AgenticDeveloperHubClient
import AgenticToolkitHub
import Foundation
import OpenAPIRuntime

/// One place that turns client-tier failures into the toolkit's `HubError`
/// (spec §5.6). `AgenticToolkitHub` is Foundation-only and cannot see the
/// ADT client, so the mapping lives here; every HubKit adapter (Plans 4–5)
/// funnels its errors through `HubError.from`.
extension HubError {
    public static func from(_ error: any Error) -> HubError {
        if let hubError = error as? HubError { return hubError }
        if let raw = error as? RawRequestError {
            switch raw {
            case .http(let status, let body): return fromStatus(status, body: body)
            case .invalidPath(let path): return .unexpected("Invalid path \(path)")
            }
        }
        if let session = error as? SessionError {
            switch session {
            case .invalidCredentials: return .unauthorized
            case .notASessionClient: return .unexpected("This client cannot sign in.")
            case .unexpectedResponse(let text): return .unexpected(text)
            }
        }
        if let client = error as? ClientError {
            return from(client.underlyingError)
        }
        if error is CancellationError { return .transport("Cancelled") }
        return .transport(error.localizedDescription)
    }

    public static func fromStatus(_ status: Int, body: Data) -> HubError {
        let fallback = "HTTP \(status)"
        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 409: return .conflict(message(fromBody: body, fallback: fallback))
        case 400, 422: return .validation(message(fromBody: body, fallback: fallback))
        case 500...599: return .transport(fallback)
        default: return .unexpected(fallback)
        }
    }

    /// The backend's error envelopes: `Components.Schemas._Error`'s documented shape
    /// `{"error": {"message": "…"}}`, or an undocumented route's flatter `{"error": "…"}`
    /// or `{"message": "…"}` — an undocumented 5xx body is not guaranteed to match the
    /// schema, so the flat and bare-string shapes must keep working alongside the nested one.
    public static func message(fromBody body: Data, fallback: String) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return fallback }
        if let nested = object["error"] as? [String: Any], let text = nested["message"] as? String, !text.isEmpty {
            return text
        }
        if let text = object["error"] as? String, !text.isEmpty { return text }
        if let text = object["message"] as? String, !text.isEmpty { return text }
        return fallback
    }
}
