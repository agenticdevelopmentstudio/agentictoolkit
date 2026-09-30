<!-- leaf: implement-extension-host-core-2/extensions-webview-host-document--part-2 · source: extension-host-core-extensions-webview-host-document.md -->

# WebviewHostDocument — continued (part 2)

## Privacy

- **Data collected**: This file collects nothing itself; it passes through
  whatever `initialState` (the JSON text of persisted pane state) and, once
  a page runs the generated bootstrap, whatever `postMessage`/`setState`
  bodies the extension supplies — content this file never inspects.
- **Storage**: Not applicable to this file. `WebviewHostDocument` performs
  no persistence of its own; the pane-state database this file's doc
  comment names (`packages/apple/AgenticToolkit/Core/Extensions/WebviewPanelState.swift`)
  is a separate component outside this file's scope.
- **Transmission**: The document this file produces is loaded into a
  `WKWebView` in the same process; the injected bootstrap relays
  `postMessage`/`setState` bodies to the native host via
  `WKUserContentController`'s `agenticWebview` handler, which is an
  in-process call, not a network transmission.
- **Retention**: Not applicable to this file — `html(wrapping:initialState:)`
  returns a `String` per call and retains nothing between calls.

## Platform Notes

- **SwiftUI**: `WKWebView` has a SwiftUI wrapper via `NSViewRepresentable`
  (macOS) or `UIViewRepresentable` (iOS); this file's string-assembly logic
  is UI-framework-agnostic and unchanged under SwiftUI — only the code that
  owns the `WKWebView` and calls
  `webView.loadHTMLString(WebviewHostDocument.html(wrapping:initialState:), baseURL:)`
  moves into the representable's `updateNSView`/`updateUIView`. The
  `WKScriptMessageHandler` registration against `messageHandlerName` has no SwiftUI equivalent and stays as imperative
  `WKUserContentController` setup inside the representable's coordinator.
- **Compose**: Android has no `WKWebView`/`WKUserContentController`
  equivalent; the nearest composition is Jetpack Compose's `AndroidView`
  wrapping a platform `android.webkit.WebView`, with
  `WebView.addJavascriptInterface` (a method annotated `@JavascriptInterface`)
  replacing the `WKScriptMessageHandler` bridge the bootstrap script
  addresses through `window.webkit.messageHandlers.agenticWebview`. The head-insertion and escaping logic ports directly,
  since it is plain string manipulation with no WebKit dependency.
- **React/Web**: If the "webview" is itself an `iframe` rather than a native
  WebView, the DOM's own `postMessage`/`onmessage` pair replaces the
  `WKScriptMessageHandler` bridge entirely, and there is no HTML-string
  injection step at all — the host page and the framed page communicate
  directly. The `acquireVsCodeApi`-shaped bootstrap this file generates is worth keeping only if the product wants VS Code
  extension source code to run unmodified inside a web-hosted panel.
- **AppKit / UIKit (source)**: This file is Foundation-only (no
  `AppKit`, `UIKit`, or `WebKit` import) — the `WKWebView` and
  `WKUserContentController.add(_:name:)` calls that actually consume
  `WebviewHostDocument.html(wrapping:initialState:)` and
  `messageHandlerName` live in
  `packages/apple/AgenticToolkit/macOS/Features/Extensions/Webview/WebviewPanelViewController.swift`,
  which is macOS/AppKit-only in this repository today; there is no
  iOS/UIKit counterpart under this package.
- **WinUI 3**: `Microsoft.Web.WebView2` (the `WebView2` control) replaces
  `WKWebView`. The closer match to this file's actual bridge shape — a
  single named channel carrying a `kind`/`body` pair — is
  `CoreWebView2.WebMessageReceived` paired with the page calling
  `chrome.webview.postMessage`/`window.chrome.webview.postMessage` (WebView2's
  own bridge global), rather than `AddHostObjectToScript`. The bootstrap
  script's `window.acquireVsCodeApi`/`postMessage`/`getState`/`setState`
  shim is generated identically via C# string interpolation
  before being handed to `CoreWebView2.NavigateToString(html)`. The
  head-insertion scan (`headStartTagEnd`) ports as a
  `string`-index walk using `IndexOf`/`Span<char>` with the same
  case-insensitive `<head`-vs-`<header>` and quoted-attribute bailout rules;
  `escapedForScriptElement` ports as a `switch` over `char`
  values feeding a `StringBuilder`, producing the equivalent `\u` hex
  escape for each blocked character. `System.Text.Json`'s
  `JsonSerializer.Serialize` is what a caller uses to produce `initialState`
  before it ever reaches this function — this file's own contract is
  unaffected either way, since it treats `initialState` as opaque,
  already-serialized text.

## Design Decisions

**Decision**: The bootstrap is injected immediately after the extension's
opening `<head>` tag — ahead of the extension's own
`<meta http-equiv="Content-Security-Policy">`, if it declares one — rather
than at any later point in the document.
**Rationale**: A meta CSP only governs content the HTML parser reads after
it, so injecting before means the extension's own CSP constrains the
extension's own scripts exactly as intended, without being able to disable
the bridge it is delivered through; it also guarantees `acquireVsCodeApi` is
defined before the extension's own first script runs, which matters because
calling it there is the normal way a restored panel gets its state back
(doc comment).
**Approved**: pending

**Decision**: An ambiguous or unterminated `<head ...>` match makes
`headStartTagEnd(in:)` return `nil` and fall back to prepending, rather than
attempting a best-effort insertion at a guessed boundary.
**Rationale**: Certainty is the whole point — a wrong insertion point would
corrupt markup this function promised only to insert into, whereas
prepending is always correct, merely less tidy (doc comment).
**Approved**: pending

**Decision**: Persisted state is escaped for safe embedding inside a
`<script>` element rather than validated as JSON before being embedded.
**Rationale**: The doc comment on `escapedForScriptElement(_:)` explains the escaping exists to close HTML-parser-level break-outs
(`</script>`, `<!--`) that JSON encoding alone does not close, since the
HTML parser reads a script element's contents before JavaScript ever does.
The function does not additionally verify that the escaped text parses as
JSON — that gap is **initial-state-json-validity**.
**Approved**: pending
