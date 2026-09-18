//
//  WebviewResourceURL.swift
//  AgenticToolkit
//

import Foundation

/// Why a webview's request for a resource was refused.
public enum WebviewResourceURLError: Error, Equatable {
    /// The URL was not in the webview scheme at all.
    case unexpectedScheme(String)
    /// The URL named a different panel than the one asking.
    case unexpectedPanel(declared: String, expected: String)
    /// The file is outside every directory the extension declared. `resolved`
    /// is where the request actually landed, which is the only thing that makes
    /// a refusal checkable.
    case outsideLocalResourceRoots(resolved: String)
}

extension WebviewResourceURLError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unexpectedScheme(let scheme):
            return "A webview asked for “\(scheme)”, which is not the webview scheme."
        case .unexpectedPanel(let declared, let expected):
            return "A webview asked for panel “\(declared)” from panel “\(expected)”."
        case .outsideLocalResourceRoots(let resolved):
            return "A webview asked for \(resolved), which is outside its localResourceRoots."
        }
    }
}

/// The scheme a webview's page speaks, and the rule for what it may load.
///
/// A webview runs an extension's own HTML and JavaScript, so the page is
/// hostile by assumption. It cannot be handed `file:` URLs — WebKit will not
/// load them from a custom-scheme document, and we would not want it to — so
/// every resource is re-spelled into this scheme, and the scheme handler asks
/// here whether the request may be answered.
///
/// The URL is `agentic-webview://<panel id>/<absolute file path>`:
///
///   * **The panel id is the authority**, not a path segment, because that is
///     what makes two panels two *origins* as far as WebKit is concerned. One
///     extension's panel therefore cannot read another's storage, and its
///     resource URLs are refused here as well — an origin boundary the server
///     does not enforce is a convention, not a boundary.
///   * **The path is the file's own absolute path**, so a request carries
///     everything needed to answer it and the handler holds no table mapping
///     opaque ids back to files. Containment is re-derived from the URL on
///     every request, because the handler is given a URL, not a promise about
///     how it was built.
///   * **An empty path is the host document** — the markup an extension
///     assigns to `webview.html`, which is a string rather than a file. It
///     still needs a real URL: a document loaded without one gets an opaque
///     origin and loses both storage and any hope of a coherent CSP.
///
/// Containment is `ExtensionResourcePath`'s, not a second implementation of
/// it: `localResourceRoots` is the fifth call site of the rule that file
/// already writes once, and its component-wise comparison is what stops
/// `/tmp/ext-evil` passing for a file inside `/tmp/ext` (`dry`).
///
/// Foundation only, so it sits in `AgenticToolkitCore` alongside that rule —
/// the whole decision is testable without WebKit, which is what a security
/// boundary needs.
public enum WebviewResourceURL {

    /// The URL scheme webview pages load from.
    ///
    /// This is a **storage format**. An extension that persists a resource URI
    /// through `setState` writes this string into the pane state database, and
    /// a restored panel hands it straight back — so renaming it orphans that
    /// state silently.
    ///
    /// It is named after the framework that owns it rather than the product
    /// that ships it. `AgenticToolkitMacOS` is consumed by the host app, the
    /// plugins, Whippet and Stenographer; the plan's proposed
    /// `whippet-webview` was stale before Stage 6 began, and a storage format
    /// that has to be renamed is a storage format that breaks.
    public static let scheme = "agentic-webview"

    /// What a URL in this scheme names.
    public enum Target: Equatable {
        /// The panel's own document — the extension's `webview.html` string.
        case hostDocument
        /// A file on disk, canonical and proven to be inside a declared root.
        case file(URL)
    }

    // MARK: - Naming

    /// The URL the panel's own document is loaded from.
    public static func hostDocumentURL(panelID: String) -> URL {
        makeURL(panelID: panelID, path: "/")
    }

    /// The URL a page uses to ask for `file` — VS Code spells this
    /// `Webview.asWebviewUri`.
    ///
    /// This does no checking. Naming a file is not permission to read it:
    /// `target(of:panelID:localResourceRoots:)` is the only place that decides,
    /// so a URL built here for a file outside every root is simply refused when
    /// the page asks for it.
    public static func url(forFile file: URL, panelID: String) -> URL {
        makeURL(panelID: panelID, path: file.path)
    }

    // MARK: - Deciding

    /// What `url` names, or why the request is refused.
    ///
    /// - Parameters:
    ///   - url: The URL the page asked for, exactly as WebKit hands it over.
    ///   - panelID: The panel doing the asking.
    ///   - localResourceRoots: The directories this panel declared. Empty means
    ///     no file access at all, which is the default posture: an extension
    ///     that declared no roots has asked for none.
    /// - Throws: `WebviewResourceURLError`.
    public static func target(
        of url: URL,
        panelID: String,
        localResourceRoots: [URL]
    ) throws -> Target {
        guard url.scheme == scheme else {
            throw WebviewResourceURLError.unexpectedScheme(url.scheme ?? "")
        }

        let declaredPanel = url.host(percentEncoded: false) ?? ""
        guard declaredPanel == panelID else {
            throw WebviewResourceURLError.unexpectedPanel(
                declared: declaredPanel, expected: panelID)
        }

        let path = url.path(percentEncoded: false)
        guard path != "", path != "/" else { return .hostDocument }

        // Canonical before comparison, and by the same route on both sides —
        // `ExtensionResourcePath` documents why normalizing the two differently
        // either refuses everything or accepts an escape through a planted
        // symlink.
        let candidate = URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL

        for root in localResourceRoots where ExtensionResourcePath.url(
            candidate, isContainedIn: ExtensionResourcePath.canonicalDirectory(root)) {
            return .file(candidate)
        }
        throw WebviewResourceURLError.outsideLocalResourceRoots(resolved: candidate.path)
    }

    // MARK: - Construction

    /// Refused by `target(of:)` on sight, because it is not in this scheme.
    ///
    /// Reached only if Foundation declines to spell a panel id as a URL
    /// authority at all — which `URLComponents` percent-encoding is there to
    /// prevent. A resource that cannot be named is a resource the page cannot
    /// have, and that is the right outcome; trapping would turn an
    /// unrepresentable id into a crash in the host.
    private static let unroutableURL = URL(fileURLWithPath: "/")

    /// `agentic-webview://<panel id><path>`, percent-encoding both halves.
    ///
    /// `URLComponents` is what does the encoding, from the *decoded* values:
    /// paths with a space, a `#`, a `%` or a non-ASCII component are ordinary
    /// here — extensions ship `my style.css`, and a user's home directory is
    /// not a name we choose.
    private static func makeURL(panelID: String, path: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = panelID
        // A URL with an authority has no way to spell a relative path, and a
        // path that does not start with "/" makes `URLComponents.url` nil.
        components.path = path.hasPrefix("/") ? path : "/" + path
        return components.url ?? unroutableURL
    }
}
