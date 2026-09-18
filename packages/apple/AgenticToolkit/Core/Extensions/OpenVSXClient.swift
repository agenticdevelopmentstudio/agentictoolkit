//
//  OpenVSXClient.swift
//  AgenticToolkit
//

import Foundation
import OSLog

/// Reads an Open VSX registry: search, per-version metadata, and the bytes of a
/// `.vsix` and its verification artifacts.
///
/// **Open VSX, not the Visual Studio Marketplace.** The Marketplace's terms of
/// use permit its content to be fetched only by Microsoft's own products, so
/// pointing this at `marketplace.visualstudio.com` is not a configuration
/// choice — it is a licence violation (Finding 7 in the plan). `registryBase`
/// is configurable for the case that motivated it: an organisation running its
/// own Open VSX instance, which speaks the same API at a different host.
///
/// Read-only by construction. There is no publish, review, or account surface
/// here, and nothing in this type sends anything the registry could attribute
/// to a user beyond the request itself.
///
/// Stateless and `Sendable`: it holds a base URL and a `URLSession` and keeps
/// no cache. Caching belongs to whoever is showing the results — a client that
/// memoized would hand a settings panel a stale "latest version" for an update
/// check whose whole job is to be current.
public struct OpenVSXClient: Sendable {

    /// The public registry. Not a default anyone has to remember: it is the
    /// default argument of `init`.
    public static let openVSXRegistry = URL(string: "https://open-vsx.org/api")!

    /// How many rows one search page asks for when the caller does not say.
    /// The registry caps a page well above this; 50 is a screenful plus room
    /// to scroll, not a limit anyone is meant to tune.
    public static let defaultPageSize = 50

    private let registryBase: URL
    private let session: URLSession

    public init(registryBase: URL = OpenVSXClient.openVSXRegistry, session: URLSession = .shared) {
        self.registryBase = registryBase
        self.session = session
    }

    // MARK: - Reading the catalog

    /// One page of search results, most-downloaded first by default.
    ///
    /// An empty `query` is the browse case, not an error — the registry answers
    /// it with the whole catalog in the requested order, which is exactly what
    /// a panel opening on nothing typed should show.
    public func search(
        _ query: String = "",
        offset: Int = 0,
        size: Int = OpenVSXClient.defaultPageSize,
        sortBy: SortOrder = .downloadCount
    ) async throws -> OpenVSXSearchPage {
        var components = URLComponents(
            url: registryBase.appendingPathComponent("-/search"),
            resolvingAgainstBaseURL: false)
        var items = [
            URLQueryItem(name: "size", value: String(size)),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "sortBy", value: sortBy.rawValue),
            URLQueryItem(name: "sortOrder", value: "desc"),
            // One row per extension, not one per published version. The browse
            // list is a list of extensions; `true` here turns a single popular
            // extension into a page of its own history.
            URLQueryItem(name: "includeAllVersions", value: "false")
        ]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            items.append(URLQueryItem(name: "query", value: trimmed))
        }
        components?.queryItems = items
        guard let url = components?.url else {
            throw OpenVSXError.malformedRegistryURL(registryBase)
        }
        return try await decode(OpenVSXSearchPage.self, from: url)
    }

    /// The full record for one extension — the latest published version when
    /// `version` is `nil`, a named one otherwise.
    public func detail(
        namespace: String,
        name: String,
        version: String? = nil
    ) async throws -> OpenVSXExtensionDetail {
        var url = registryBase
            .appendingPathComponent(namespace)
            .appendingPathComponent(name)
        if let version {
            url.appendPathComponent(version)
        }
        return try await decode(OpenVSXExtensionDetail.self, from: url)
    }

    // MARK: - Reading artifacts

    /// The bytes at `url`, with a non-2xx status turned into a throw.
    ///
    /// Used for the `.vsix`, the `.sigzip` and the public key alike — they
    /// differ only in what the caller does with them, and a per-artifact method
    /// each would be three copies of one download *(dry)*.
    public func data(at url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        try Self.checkStatus(of: response, for: url)
        return data
    }

    /// The text at `url`, stripped of surrounding whitespace.
    ///
    /// The registry's `.sha256` artifact is a bare hex digest with a trailing
    /// newline, and its public key is PEM. Both are text files whose surrounding
    /// whitespace is noise, and a digest compared with a `\n` still attached
    /// never matches anything.
    public func text(at url: URL) async throws -> String {
        let data = try await data(at: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw OpenVSXError.artifactNotText(url)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)
        try Self.checkStatus(of: response, for: url)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw OpenVSXError.undecodableResponse(url, underlying: String(describing: error))
        }
    }

    /// A 404 from this API means "no such extension", and a 5xx means the
    /// registry is having a bad day — both of which arrive as a perfectly
    /// valid HTTP response carrying an error document. Without this check the
    /// JSON decode fails instead, and the caller is told its model is wrong
    /// when what is wrong is the name it asked for *(fail-fast)*.
    private static func checkStatus(of response: URLResponse, for url: URL) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw OpenVSXError.requestFailed(url, status: http.statusCode)
        }
    }

    /// The orderings the registry supports that mean anything for browsing.
    /// `relevance` is what a typed query wants; `downloadCount` is what an
    /// empty one wants, since "relevance" to no query is arbitrary.
    public enum SortOrder: String, Sendable {
        case downloadCount
        case relevance
        case rating
        case timestamp
    }
}

extension OpenVSXClient: Loggable {
    public static nonisolated let logger = makeLogger()
}

/// What can go wrong between this host and a registry.
///
/// Every case carries the URL it happened at. A failure reported without one
/// is unactionable when the registry is configurable: "the search failed" does
/// not say whether the self-hosted instance is down or the URL in settings has
/// a typo.
public enum OpenVSXError: Error, Sendable, Equatable {

    /// `registryBase` could not be composed into a request URL — a
    /// misconfigured self-hosted registry, caught before any request.
    case malformedRegistryURL(URL)

    case requestFailed(URL, status: Int)

    /// The response was not the JSON this client expects. The underlying
    /// decoding error is carried as text rather than as itself because
    /// `DecodingError` is not `Equatable`, and a case that cannot be compared
    /// cannot be asserted on.
    case undecodableResponse(URL, underlying: String)

    /// An artifact that must be text (the digest, the public key) was not
    /// UTF-8.
    case artifactNotText(URL)
}
