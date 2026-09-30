<!-- leaf: implement-extension-host-core-2/extensions-webview-resource-url--part-2 · source: extension-host-core-extensions-webview-resource-url.md -->

# WebviewResourceURL — continued (part 2)

## Platform Notes

- **SwiftUI**: the source (`WebviewResourceURL.swift`) is plain Foundation —
  `URL`, `URLComponents`, and the `Error`/`LocalizedError` protocols — with
  zero dependency on SwiftUI or any view-layer framework. It sits in
  `AgenticToolkitCore` specifically so the access decision is testable
  without `WebKit`, per the source's own closing comment; a port that keeps
  this component in Swift needs nothing beyond `Foundation` plus whatever
  Swift form `ExtensionResourcePath` takes on that platform.
- **Compose**: model `WebviewResourceURLError` as a Kotlin `sealed class`
  with the same three payload shapes, and `WebviewResourceURL` as a Kotlin
  `object` namespace. Build and parse the scheme with `android.net.Uri`
  (`Uri.getScheme()`, `Uri.getHost()`, `Uri.getPath()`) rather than a raw
  string split, since `Uri` already performs the percent-decoding this file
  relies on. Android's `WebViewAssetLoader` or a custom
  `WebViewClient.shouldInterceptRequest` override is the analogue of the
  `WKURLSchemeHandler` this file's containment decision serves; neither
  enforces containment on its own, so the port must still call the
  containment decision explicitly from that override.
- **React/Web**: for a browser or Electron-hosted extension host, register a
  custom protocol handler (Electron's `protocol.handle`, or a Service
  Worker's `fetch` handler for a web-hosted equivalent) and reproduce the
  same three-step decision — scheme check, then origin/panel check against
  the request's URL authority, then a component-wise containment check
  against each declared root using Node's `path` module (never
  `String.prototype.startsWith`, for the reason `ExtensionResourcePath`'s
  own Platform Notes give). There is no browser API that grants a custom
  scheme the origin isolation `agentic-webview`'s authority-per-panel design
  achieves on WebKit; an Electron `BrowserView` per panel, or a Service
  Worker scoped per panel, is the nearest equivalent.
- **AppKit / UIKit**: identical to the SwiftUI note — the component depends
  on neither AppKit nor UIKit, so a macOS or iOS host consumes the same
  `AgenticToolkitCore` type directly with no translation needed; only the
  `WKURLSchemeHandler` that calls it (outside this file) is UIKit/AppKit-
  adjacent WebKit code.
- **WinUI 3**: there is no single .NET or Windows App SDK type that performs
  this file's exact scheme-then-panel-then-containment decision. Model
  `WebviewResourceURLError` as a small `.NET` exception type (or a
  discriminated union via a base `record`) carrying the same three payload
  shapes, and `WebviewResourceURL` as a `static class`. WebView2
  (`CoreWebView2.WebResourceRequested`, or
  `CoreWebView2.SetVirtualHostNameToFolderMapping` for the simple case) is
  the analogue of `WKURLSchemeHandler`, but it enforces no containment of
  its own: a port must parse the request's `Uri` (`Uri.Host` for the panel
  id, `Uri.AbsolutePath` for the file path) inside the
  `WebResourceRequested` handler and call the containment decision
  explicitly, using `Path.GetFullPath` plus an explicit symlink/junction
  resolution step chained before the comparison — `Path.GetFullPath` alone
  does not resolve symlinks the way `resolvingSymlinksInPath()` does in the
  source — and compare with `Path.GetRelativePath`, never
  `string.StartsWith`, for the same component-versus-string-prefix reason
  `ExtensionResourcePath`'s own WinUI 3 note gives. `HttpClient`,
  `System.Text.Json`, `Task`/`async`, `ObservableCollection`, and
  `INotifyPropertyChanged` all have no role here: every operation in the
  source is synchronous, non-networked, non-serializing, and returns a
  value rather than raising a change notification.

## Design Decisions

- **Decision**: the panel id is spelled as the URL's authority (host)
  rather than as a path segment.
  **Rationale**: the source's own header comment states this is what makes
  two panels two WebKit origins, so one extension's panel cannot read
  another's storage; a path-segment encoding would not produce that origin
  boundary at all.
  **Approved**: pending
- **Decision**: the file path is spelled into the URL as the file's own
  absolute path, rather than as an opaque identifier looked up in a table
  the handler maintains.
  **Rationale**: the source's comment states a request this way carries
  everything needed to answer it, so containment is re-derived from the URL
  on every request instead of trusting a promise about how the URL was
  built, and the handler holds no id-to-file table that could drift out of
  sync with it.
  **Approved**: pending
- **Decision**: an empty path is defined as the panel's own host document,
  not an error and not a file lookup.
  **Rationale**: the source's comment on the scheme states the host
  document still needs a real URL, because a document loaded without one
  gets an opaque origin and loses both storage and any hope of a coherent
  CSP; treating the empty path as a file path would have nothing on disk to
  resolve it to.
  **Approved**: pending
- **Decision**: containment against `localResourceRoots` is delegated
  component-wise to `ExtensionResourcePath.url(_:isContainedIn:)` rather
  than re-implemented here.
  **Rationale**: `ExtensionResourcePath`'s own header comment names this as
  its reason for existing at all — the same rule hand-rolled at other call
  sites had missed the escape half of the check — and the source's comment
  on this file states plainly that `localResourceRoots` is the fifth call
  site of that rule, not a second implementation of it.
  **Approved**: pending
- **Decision**: an unrepresentable panel id produces a fixed fallback URL
  (`URL(fileURLWithPath: "/")`) rather than a trap or a `nil` return.
  **Rationale**: the source's comment states that trapping would turn an
  unrepresentable id into a crash in the host, and that the fallback is
  itself refused by `target(of:)` on sight because it is not in the webview
  scheme — a resource that cannot be named is a resource the page cannot
  have, which the comment calls the right outcome.
  **Approved**: pending
- **Decision**: `target(of:panelID:localResourceRoots:)` re-derives its
  answer from its arguments on every call rather than caching a prior
  decision for a URL or a panel.
  **Rationale**: the source's comment states the roots are read from the
  handler's current value rather than captured, so an extension that
  narrows `localResourceRoots` narrows them for requests already in flight,
  not only for the next page; a cached answer would defeat that.
  **Approved**: pending
