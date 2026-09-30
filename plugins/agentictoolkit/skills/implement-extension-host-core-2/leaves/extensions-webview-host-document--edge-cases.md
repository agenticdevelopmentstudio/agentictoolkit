<!-- leaf: implement-extension-host-core-2/extensions-webview-host-document--edge-cases · source: extension-host-core-extensions-webview-host-document.md -->

# WebviewHostDocument

**Rules** (cite as `implement-extension-host-core-2/extensions-webview-host-document--edge-cases#<slug>`):

- `initialstate-is-nil` MUST — getState() MUST return undefined, not null (MUST; webview-host-document-011).
- `extensionhtml-is-the-empty-string` MUST — html(wrapping:initialState:) MUST still return a document — the bootstrap <script> element alone, with nothing appended …
- `a-head-match-sits-at-the-very-end-of-extensionhtml-or-its-whitespace-terminated-scan-never-finds-an-unquoted` MUST — headStartTagEnd(in:) MUST return nil and html(wrapping:initialState:) MUST fall back to prepending (MUST; …
- `a-head-tag-carries-a-quoted-attribute-value-containing` MUST — headStartTagEnd(in:) MUST return nil on encountering the opening quote, rather than risk splitting the tag …
- `extensionhtml-contains-header-or-heading-before-any-real-head` MUST — those matches MUST be rejected and the search MUST continue, so the real <head> — if one follows — is still found …
- `initialstate-carries-a-script-or-comment-breakout-payload` MUST — none of these sequences MUST appear literally in the rendered document (MUST; webview-host-document-009, …
- `concurrent-access` MUST — html(wrapping:initialState:) reads no shared mutable state and allocates every local value (bootstrap, document, …

## Edge Cases

- **`initialState` is `nil`**: `getState()` MUST return `undefined`, not
  `null` (MUST; webview-host-document-011).
- **`extensionHTML` is the empty string**: `html(wrapping:initialState:)`
  MUST still return a document — the bootstrap `<script>` element alone,
  with nothing appended after it, since there is no head to insert into and
  nothing to prepend before (MUST; webview-host-document-005).
- **`initialState` is a non-nil empty string**: The generated bootstrap
  embeds `JSON.parse("")`, which is not valid JavaScript and throws a
  `SyntaxError` at page-load time inside the immediately-invoked function
  expression, silently losing `window.acquireVsCodeApi` for that load; see
  **initial-state-json-validity**.
- **A `<head` match sits at the very end of `extensionHTML`, or its
  whitespace-terminated scan never finds an unquoted `>`**:
  `headStartTagEnd(in:)` MUST return `nil` and `html(wrapping:initialState:)`
  MUST fall back to prepending (MUST; **unterminated-head-tag-bailout**).
- **A `<head ...>` tag carries a quoted attribute value containing `>`**:
  `headStartTagEnd(in:)` MUST return `nil` on encountering the opening quote,
  rather than risk splitting the tag mid-attribute (MUST;
  **quoted-attribute-ambiguity-bailout**; webview-host-document-014).
- **`extensionHTML` contains `<header>` or `<heading>` before any real
  `<head>`**: those matches MUST be rejected and the search MUST continue,
  so the real `<head>` — if one follows — is still found (MUST;
  **head-vs-header-disambiguation**; webview-host-document-015).
- **`initialState` carries a script- or comment-breakout payload
  (`</script>`, `<!--`, `-->`, mixed-case `</SCRIPT >`)**: none of these
  sequences MUST appear literally in the rendered document (MUST;
  webview-host-document-009, webview-host-document-010).
- **Concurrent access**: `html(wrapping:initialState:)` reads no shared
  mutable state and allocates every local value (`bootstrap`, `document`,
  `escaped`) fresh per call; concurrent, independent calls from multiple
  threads or tasks MUST NOT require external synchronization (derived from
  **pure-synchronous-string-transform**; no shared state exists in this file
  to race over).
- **Error states**: `html(wrapping:initialState:)` itself never throws — no
  `throws` clause or error path exists anywhere in this Swift file. The one
  failure mode reachable through this component is at the JavaScript layer,
  when a non-nil `initialState` is not valid JSON text (see
  **initial-state-json-validity**); a `headStartTagEnd(in:)` bailout is not
  an error state, it is a defined, silent fallback to prepending, by design
  (see Design Decisions).
- **Offline/disconnected state**: Not applicable — this file performs no
  network access of any kind; it is pure, synchronous string assembly over
  Foundation only, so connectivity plays no role in what
  `html(wrapping:initialState:)` returns.
