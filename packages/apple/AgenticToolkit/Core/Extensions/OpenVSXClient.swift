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
/// Stateless and `Sendable`: it holds a base URL and a body reader and keeps
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

    /// The most an artifact may weigh before this client stops reading it.
    ///
    /// A `.vsix` is a zip of an editor extension; the large ones bundle a
    /// language server binary per platform and reach a few hundred megabytes.
    /// 512 MB is above every published extension and far below what it takes
    /// to exhaust a desktop's memory, which is the only job this number has.
    /// It is not a tuning knob — it is the difference between a download that
    /// fails and a process that dies.
    public static let defaultMaximumArtifactBytes = 512 * 1024 * 1024

    /// The most a *metadata* answer may weigh — a search page or one
    /// extension's record.
    ///
    /// Three orders of magnitude below the artifact ceiling, and deliberately
    /// so: these are JSON documents describing extensions, not the extensions
    /// themselves. The largest page this client asks for is 50 rows, and Open
    /// VSX answers a detail request with URLs rather than with the readme they
    /// point at, so 8 MB is far above any honest answer and far below what it
    /// takes to matter. One number for both would have to be the download's,
    /// which would make the metadata ceiling decorative.
    public static let defaultMaximumMetadataBytes = 8 * 1024 * 1024

    private let registryBase: URL
    private let loader: BoundedBodyLoader
    private let maximumArtifactBytes: Int
    private let maximumMetadataBytes: Int

    public init(
        registryBase: URL = OpenVSXClient.openVSXRegistry,
        session: URLSession = .shared,
        maximumArtifactBytes: Int = OpenVSXClient.defaultMaximumArtifactBytes,
        maximumMetadataBytes: Int = OpenVSXClient.defaultMaximumMetadataBytes
    ) {
        self.registryBase = registryBase
        // The *configuration*, not the session: the loader needs a session of
        // its own to be the delegate of, and a configuration is what carries
        // everything a caller passes a session in order to say — including the
        // `protocolClasses` every test here stands the registry up with.
        self.loader = BoundedBodyLoader(configuration: session.configuration)
        self.maximumArtifactBytes = maximumArtifactBytes
        self.maximumMetadataBytes = maximumMetadataBytes
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
        // Before the join, not after. `appendingPathComponent` is a path
        // *join* and escapes nothing, so a namespace of `a/../../admin`
        // becomes structure and `URL` resolves it — two levels above the API
        // root, at an endpoint this method never meant to address. None of
        // these three names is typed by a person: they are manifest fields,
        // and `ExtensionUpdateCheck` feeds in a sideloaded extension's
        // `publisher`, which is whatever a folder someone dropped in claims.
        try Self.requireSafeComponent(namespace, field: "namespace")
        try Self.requireSafeComponent(name, field: "name")
        if let version {
            try Self.requireSafeComponent(version, field: "version")
        }

        var url = registryBase
            .appendingPathComponent(namespace)
            .appendingPathComponent(name)
        if let version {
            url.appendPathComponent(version)
        }
        return try await decode(OpenVSXExtensionDetail.self, from: url)
    }

    // MARK: - Reading artifacts

    /// The bytes at `url`, with anything but a 2xx over TLS turned into a
    /// throw.
    ///
    /// Used for the `.vsix`, the `.sigzip` and the public key alike — they
    /// differ only in what the caller does with them, and a per-artifact method
    /// each would be three copies of one download *(dry)*.
    ///
    /// **Every URL that arrives here was chosen by the registry**, out of the
    /// `files` and `downloads` maps of a metadata response. `URLSession`
    /// implements `file:`, so before the scheme was checked a registry could
    /// answer `"download": "file:///…"` and have this method read a local file
    /// and hand it back as the download; `http:` was a quieter version of the
    /// same, moving the fetch to whoever is on the network path. Neither is
    /// something a registry has any reason to ask for.
    ///
    /// How much of one a registry may send is `body`'s rule, not this
    /// method's — it passes the artifact ceiling and the error that names it.
    public func data(at url: URL) async throws -> Data {
        try Self.requireFetchable(url)
        return try await body(
            at: url, limit: maximumArtifactBytes, tooLarge: OpenVSXError.artifactTooLarge)
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

    /// Reads a response body to a ceiling, and no further.
    ///
    /// **Read to a ceiling, not to the end.** How many bytes arrive is the
    /// sender's decision, and `session.data(from:)` accumulates all of them:
    /// a registry — or whoever is answering as one on a compromised network
    /// path — that never stops sending grows this process's heap until it
    /// dies, with no request having failed and nothing to log. Streaming the
    /// body and abandoning it at the ceiling turns that into an ordinary
    /// throw the caller already handles.
    ///
    /// **Chunks, not bytes, and still one code path.** This streamed with
    /// `URLSession.bytes(from:)` until a review priced it: `AsyncBytes` yields
    /// one `UInt8` per `await`, which measures 23.8 MB/s against an in-process
    /// stub where `data(from:)` — which cannot be bounded — measures 2.5 GB/s.
    /// The argument for accepting that was that a download waits on the
    /// network anyway; what it missed is that the ceiling it defends is 512 MB,
    /// so the worst case it is *designed for* is twenty seconds of a
    /// cooperative-pool thread counting to five hundred million, and that the
    /// same routine serves the metadata read behind a search field, once per
    /// keystroke. `BoundedBodyLoader` gets both properties at once — whole
    /// chunks at the system's rate, with the ceiling tested per chunk — so
    /// there is still one path here, not a framed fast one and a chunked slow
    /// one *(simplicity)*.
    ///
    /// Shared by the download and the metadata read because it is one rule —
    /// how much of a stranger's answer this process is willing to hold — with
    /// two numbers *(dry)*. Which number, and which error names it, is the
    /// caller's to say; everything else about the two paths was identical, and
    /// the copy that was not written is the one where the ceiling gets fixed
    /// in one place and not the other.
    ///
    /// The status check comes first so a 404's error document is refused as a
    /// 404 rather than read. `expectedContentLength` is consulted next and
    /// decides nothing on its own: it is -1 for a chunked response and it is
    /// the sender's claim either way, so it can only short-circuit a refusal
    /// the byte count would reach anyway. Believing it in the other direction
    /// — reading to a length the sender promised — is how an understated
    /// header walks a body past the ceiling.
    private func body(
        at url: URL, limit: Int, tooLarge: (URL, Int) -> OpenVSXError
    ) async throws -> Data {
        do {
            let (data, response) = try await loader.body(at: url, limit: limit)
            try Self.checkStatus(of: response, for: url)
            return data
        } catch BoundedBodyLoader.Failure.tooLarge(let response) {
            // Still the status first. A refusal reported as "too large" when
            // what actually arrived was a 500's error document sends the
            // reader to the wrong question entirely.
            if let response {
                try Self.checkStatus(of: response, for: url)
            }
            throw tooLarge(url, limit)
        }
    }

    /// **Metadata is a body too.** `search` and `detail` read a response into
    /// memory with exactly the "however much the sender decides" property the
    /// download had, and they are the *first* thing any registry interaction
    /// does: a panel that has had one character typed into it has already made
    /// this request, long before anyone chose to install anything. Bounding
    /// the download and not this left the hole open at the cheaper end.
    private func decode<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        let data = try await body(
            at: url, limit: maximumMetadataBytes, tooLarge: OpenVSXError.responseTooLarge)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw OpenVSXError.undecodableResponse(url, underlying: String(describing: error))
        }
    }

    /// The schemes an artifact URL may use.
    ///
    /// The **scheme**, not the host: Open VSX serves its artifacts from its own
    /// host, but a self-hosted instance commonly puts them on a CDN, and a host
    /// check would turn that into an outage. TLS is what the rule is for — it
    /// is what makes "the registry named this" and "the registry served this"
    /// the same statement.
    private static let fetchableSchemes: Set<String> = ["https"]

    /// `registryBase` is deliberately not held to this. It is configuration —
    /// typed by whoever runs the instance, not supplied by a response — and an
    /// organisation's decision to run its own registry over plain HTTP inside
    /// its own network is theirs to make. What a registry *names* is a
    /// different thing entirely, and is what this guards.
    /// `ExtensionIdentityComponent` holds the predicate; this wraps it in
    /// the error a registry caller reports. The rule is shared with
    /// `VSIXInstaller`, which applies it to the same manifest fields before
    /// they become a directory name — one piece of knowledge, two splices.
    private static func requireSafeComponent(_ value: String, field: String) throws {
        guard ExtensionIdentityComponent.isSafe(value) else {
            throw OpenVSXError.unsafeIdentity(field: field, value: value)
        }
    }

    private static func requireFetchable(_ url: URL) throws {
        let scheme = url.scheme?.lowercased() ?? ""
        guard fetchableSchemes.contains(scheme), url.host?.isEmpty == false else {
            throw OpenVSXError.artifactNotFetchable(url, scheme: scheme)
        }
    }

    /// A 404 from this API means "no such extension", and a 5xx means the
    /// registry is having a bad day — both of which arrive as a perfectly
    /// valid HTTP response carrying an error document. Without this check the
    /// JSON decode fails instead, and the caller is told its model is wrong
    /// when what is wrong is the name it asked for *(fail-fast)*.
    ///
    /// A response that is not an HTTP response throws rather than returning.
    /// Returning meant the status rules below silently did not run for it, and
    /// a check that can quietly not happen is not a check.
    private static func checkStatus(of response: URLResponse, for url: URL) throws {
        guard let http = response as? HTTPURLResponse else {
            throw OpenVSXError.responseNotHTTP(url)
        }
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

    /// An artifact URL the registry named is not one this client will fetch.
    /// Carries the scheme, which is what makes the refusal legible: `file` is
    /// a very different report from a typo in a self-hosted registry's config.
    case artifactNotFetchable(URL, scheme: String)

    /// The registry kept sending past the ceiling this client reads to.
    /// Carries the limit, because the number is the actionable half: the
    /// report is either "that extension really is enormous" or "something is
    /// answering as the registry and will not stop".
    case artifactTooLarge(URL, limit: Int)

    /// A name that would have addressed something other than the extension it
    /// claims to be. Carries the field and the value it carried — this is the
    /// one error here whose cause is a hostile document, and the value is what
    /// makes the report mean anything.
    case unsafeIdentity(field: String, value: String)

    /// The response was not an HTTP response, so no status could be checked.
    case responseNotHTTP(URL)

    /// A metadata answer — a search page or one extension's record — ran past
    /// the ceiling this client reads to. Distinct from `artifactTooLarge`
    /// because the two ceilings are three orders of magnitude apart, so a
    /// report that named the wrong one would be off by a factor of 64, and
    /// because "the download was stopped" is not what happened.
    case responseTooLarge(URL, limit: Int)
}
