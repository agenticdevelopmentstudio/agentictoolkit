//
//  WebviewSchemeHandler.swift
//  AgenticToolkit
//

import Foundation
import UniformTypeIdentifiers
import WebKit
import AgenticToolkitCore

/// Serves everything a webview panel is allowed to load, and nothing else.
///
/// One instance per panel, held by the panel's `WKWebViewConfiguration`. Per
/// panel rather than shared because the panel id is half the answer to every
/// request: `agentic-webview://<panel id>/…` makes two panels two WebKit
/// origins, and a shared handler would have to trust the id in the URL it was
/// handed to tell them apart.
///
/// **Where the containment actually is.** Not here. Deciding whether a URL
/// names something this panel may have is `WebviewResourceURL.target(of:panelID:localResourceRoots:)`
/// in `apple-core`, which is tested without a browser. This class is the WebKit
/// half only: it asks, then reads bytes or fails the task.
///
/// The named file is re-checked against the roots on every request, and the
/// roots are read from this handler's current value rather than captured — an
/// extension that narrows `localResourceRoots` narrows them for requests
/// already in flight, not only for the next page.
@MainActor
final class WebviewSchemeHandler: NSObject, WKURLSchemeHandler {

    /// The panel this serves. Requests declaring any other panel are refused.
    private let panelID: String

    /// The document served at `agentic-webview://<panel id>/`.
    ///
    /// Mutable because `webview.html` is a property an extension assigns
    /// whenever it likes; the panel writes the new document here and reloads.
    var hostDocument: String = ""

    /// The directories this panel may read files from. Empty means none, which
    /// is VS Code's default and the right one: a panel that never declared a
    /// root gets no file access at all.
    var localResourceRoots: [URL] = []

    /// The `Content-Security-Policy` every response carries — see
    /// `WebviewPanelOptions.contentSecurityPolicy(allowingForms:)`, which is
    /// where the policy is decided and why.
    ///
    /// Stored rather than computed from the panel's options, for
    /// `localResourceRoots`' reason: the panel writes it, and a handler with no
    /// panel yet serves the closed form.
    var contentSecurityPolicy = WebviewPanelOptions.contentSecurityPolicy(allowingForms: false)

    /// Tasks WebKit has started and not yet stopped.
    ///
    /// Required, not defensive: sending anything to a `WKURLSchemeTask` after
    /// `webView(_:stop:)` raises an Objective-C exception, which is not
    /// catchable from Swift and takes the app with it. A panel closed while a
    /// file is being read off the main thread is the ordinary way to get there.
    private var liveTasks: Set<ObjectIdentifier> = []

    init(panelID: String) {
        self.panelID = panelID
        super.init()
    }

    // MARK: - WKURLSchemeHandler

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let identifier = ObjectIdentifier(urlSchemeTask)
        liveTasks.insert(identifier)

        guard let url = urlSchemeTask.request.url else {
            fail(urlSchemeTask, identifier: identifier, with: URLError(.badURL))
            return
        }

        let target: WebviewResourceURL.Target
        do {
            target = try WebviewResourceURL.target(
                of: url, panelID: panelID, localResourceRoots: localResourceRoots)
        } catch {
            // The single most useful line an extension author can be given:
            // a blocked resource is otherwise an element that silently does
            // not render. The path is `.public` because it is the extension's
            // own bundle path, which is what the author is looking for.
            Self.logger.error(
                """
                Webview \(self.panelID, privacy: .public) refused \
                \(url.absoluteString, privacy: .public): \
                \(error.localizedDescription, privacy: .public)
                """)
            fail(urlSchemeTask, identifier: identifier, with: error)
            return
        }

        switch target {
        case .hostDocument:
            respond(
                to: urlSchemeTask, identifier: identifier, url: url,
                data: Data(hostDocument.utf8), mimeType: "text/html; charset=utf-8")

        case .file(let file):
            // Off the main thread: a webview resource is usually a stylesheet
            // and occasionally a video, and the main thread is where the rest
            // of the window is being drawn.
            Task { [weak self] in
                let data = await Self.contents(of: file)
                guard let self else { return }
                guard let data else {
                    self.fail(
                        urlSchemeTask, identifier: identifier,
                        with: CocoaError(.fileReadNoSuchFile))
                    return
                }
                self.respond(
                    to: urlSchemeTask, identifier: identifier, url: url,
                    data: data, mimeType: Self.mimeType(of: file))
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        liveTasks.remove(ObjectIdentifier(urlSchemeTask))
    }

    // MARK: - Answering

    private func respond(
        to task: any WKURLSchemeTask, identifier: ObjectIdentifier,
        url: URL, data: Data, mimeType: String
    ) {
        guard liveTasks.remove(identifier) != nil else { return }
        guard let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: headers(mimeType: mimeType, length: data.count)
        ) else {
            task.didFailWithError(URLError(.cannotParseResponse))
            return
        }
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private func fail(
        _ task: any WKURLSchemeTask, identifier: ObjectIdentifier, with error: any Error
    ) {
        guard liveTasks.remove(identifier) != nil else { return }
        task.didFailWithError(error)
    }

    private static func contents(of file: URL) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: file, options: .mappedIfSafe)
        }.value
    }

    // MARK: - What the response says about itself

    /// An `HTTPURLResponse` rather than a bare `URLResponse` so these can be
    /// sent at all — a custom scheme gets no headers otherwise.
    private func headers(mimeType: String, length: Int) -> [String: String] {
        [
            "Content-Type": mimeType,
            "Content-Length": String(length),
            // Without this, WebKit is free to sniff a stylesheet into
            // something executable — which undoes the point of resolving a
            // type from the extension at all.
            "X-Content-Type-Options": "nosniff",
            // Extension resources change on disk while their author is editing
            // them, and a cached stale stylesheet is a debugging trap with no
            // upside: these are local file reads.
            "Cache-Control": "no-store",
            "Content-Security-Policy": contentSecurityPolicy
        ]
    }

    /// The type WebKit is told a file is.
    ///
    /// Derived from the file name, never from its contents: sniffing is what
    /// `nosniff` above turns off, and a resource whose type this cannot name
    /// is served as `application/octet-stream` — which WebKit will render as a
    /// download-shaped nothing rather than execute.
    private static func mimeType(of file: URL) -> String {
        guard let type = UTType(filenameExtension: file.pathExtension),
              let mime = type.preferredMIMEType
        else {
            return "application/octet-stream"
        }
        return type.conforms(to: .text) ? "\(mime); charset=utf-8" : mime
    }
}

extension WebviewSchemeHandler: Loggable {
    static nonisolated let logger = makeLogger()
}
