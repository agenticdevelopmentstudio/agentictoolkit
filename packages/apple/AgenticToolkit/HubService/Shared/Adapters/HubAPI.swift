import AgenticDeveloperHubClient
import AgenticToolkitHub
import Foundation
import HTTPTypes

/// The one door every feature adapter uses to reach the backend: JSON in, JSON out, `HubError` on failure.
/// Built on `ADHClient.rawJSON` so the same middleware chain (auth header, refresh-on-401, daemon routing)
/// applies to every request, and so adapters can name endpoints the generated client does not cover.
@MainActor
public struct HubAPI {
    private let environment: HubEnvironment

    public init(environment: HubEnvironment) {
        self.environment = environment
    }

    /// Request-body encoder: ISO-8601 dates, stable key order so tests can compare bodies.
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    /// Builds a query dictionary from optional values, dropping the nils.
    public static func query(_ pairs: [String: String?]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in pairs {
            if let value { result[key] = value }
        }
        return result
    }

    public func get<T: Decodable>(_ path: String, query: [String: String] = [:], as type: T.Type) async throws -> T {
        let response = try await perform(.get, path, query: query, body: nil)
        return try decode(type, from: response, method: .get, path: path)
    }

    public func send<T: Decodable>(
        _ method: HTTPRequest.Method, _ path: String, query: [String: String] = [:], as type: T.Type
    ) async throws -> T {
        let response = try await perform(method, path, query: query, body: nil)
        return try decode(type, from: response, method: method, path: path)
    }

    public func send<B: Encodable, T: Decodable>(
        _ method: HTTPRequest.Method, _ path: String, query: [String: String] = [:], body: B, as type: T.Type
    ) async throws -> T {
        let data = try encode(body, method: method, path: path)
        let response = try await perform(method, path, query: query, body: data)
        return try decode(type, from: response, method: method, path: path)
    }

    public func send<B: Encodable>(
        _ method: HTTPRequest.Method, _ path: String, query: [String: String] = [:], body: B
    ) async throws {
        let data = try encode(body, method: method, path: path)
        _ = try await perform(method, path, query: query, body: data)
    }

    public func send(_ method: HTTPRequest.Method, _ path: String, query: [String: String] = [:]) async throws {
        _ = try await perform(method, path, query: query, body: nil)
    }

    // MARK: - Internals

    private func perform(
        _ method: HTTPRequest.Method, _ path: String, query: [String: String], body: Data?
    ) async throws -> RawResponse {
        do {
            return try await environment.client.rawJSON(method: method, path: path, query: query, body: body)
        } catch {
            throw HubError.from(error)
        }
    }

    private func encode<B: Encodable>(_ body: B, method: HTTPRequest.Method, path: String) throws -> Data {
        do {
            return try Self.encoder.encode(body)
        } catch {
            throw HubError.unexpected("Unencodable request for \(method.rawValue) \(path): \(error)")
        }
    }

    private func decode<T: Decodable>(
        _ type: T.Type, from response: RawResponse, method: HTTPRequest.Method, path: String
    ) throws -> T {
        do {
            return try response.decode(type)
        } catch {
            throw HubError.unexpected("Unreadable response for \(method.rawValue) \(path): \(error)")
        }
    }
}
