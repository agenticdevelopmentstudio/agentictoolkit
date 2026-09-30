<!-- leaf: implement-extension-host-core-2/extensions-webview-host-document · source: extension-host-core-extensions-webview-host-document.md -->

**Rules** (cite as `implement-extension-host-core-2/extensions-webview-host-document#<slug>`):

- `bootstrap-injection-point` MUST
- `bootstrap-prepend-fallback` MUST
- `head-tag-match-case-insensitive` MUST
- `head-vs-header-disambiguation` MUST
- `head-tag-closing-detection` MUST
- `quoted-attribute-ambiguity-bailout` MUST
- `unterminated-head-tag-bailout` MUST
- `extension-markup-passthrough` MUST
- `initial-state-undefined-vs-value` MUST
- `script-element-escaping` MUST
- `message-handler-name-constant` MUST
- `message-kind-closed-set` MUST
- `acquire-once-guard` MUST
- `post-message-relay-is-fire-and-forget` MUST
- `get-state-returns-in-memory-value` MUST
- `set-state-updates-and-relays` MUST
- `pure-synchronous-string-transform` MUST
- `no-explicit-concurrency-isolation` MUST
- `platform-i18n-layer-decide-design-choice-outside` MUST — The string above is hardcoded English embedded directly into the generated JavaScript, with no lookup table, ICU …

# WebviewHostDocument

## Overview

`WebviewHostDocument` (`packages/apple/AgenticToolkit/Core/Extensions/WebviewHostDocument.swift`,
Foundation-only, macOS today) is the pure string-assembly layer that turns an
extension's `webview.html` into the document a `WKWebView` actually loads. It
has no visual surface of its own: `html(wrapping:initialState:)` takes the
extension's HTML exactly as assigned and the JSON text of the panel's last
persisted state, and returns one `String` with a `<script>` bootstrap
injected immediately after the opening `<head>` tag (or prepended, when no
head can be located with certainty). That bootstrap implements the page-side
half of the bridge: `window.acquireVsCodeApi()`, `postMessage`, `getState`,
and `setState`, wired to a single named `WKUserContentController` handler,
`messageHandlerName`. Because `webview.html` is a string an extension
assigns and nothing validates as well-formed markup, this component makes no
assumption about its shape — a fragment, a headless document, or an empty
string must all still come back with a working bridge — and because the
state it embeds was authored by the extension, the escaping in
`escapedForScriptElement(_:)` is a security boundary against that state
breaking out of the `<script>` element it is placed inside, not a
convenience.

## Behavioral Requirements

- **bootstrap-injection-point**: `html(wrapping:initialState:)` MUST return
  the extension's markup with a `<script>` element containing the bootstrap
  script inserted at the index immediately following the extension's own
  opening `<head>` tag when `headStartTagEnd(in:)` locates one unambiguously.
- **bootstrap-prepend-fallback**: When `headStartTagEnd(in:)` returns `nil`,
  `html(wrapping:initialState:)` MUST prepend the bootstrap `<script>`
  element to the start of `extensionHTML` unmodified, rather than inserting
  it anywhere else in the document.
- **head-tag-match-case-insensitive**: `headStartTagEnd(in:)` MUST search for
  the literal `<head` case-insensitively, so `<HEAD>`, `<Head>`,
  and `<head>` are each recognized as a candidate head start.
- **head-vs-header-disambiguation**: `headStartTagEnd(in:)` MUST treat a
  `<head` match as a genuine head start only when the character immediately
  following it is `>` or whitespace; when it is any other character (as in
  `<header` or `<heading`), the match MUST be rejected and the search MUST
  continue from just past that match.
- **head-tag-closing-detection**: When `<head` is immediately followed by
  `>`, `headStartTagEnd(in:)` MUST return the index immediately after that
  `>`. When `<head` is followed by whitespace, it MUST scan forward for the
  tag's closing `>` and return the index immediately after that character.
- **quoted-attribute-ambiguity-bailout**: While scanning forward for a
  `<head ...>` tag's closing `>`, `headStartTagEnd(in:)` MUST return `nil`
  immediately on encountering a `"` or `'` character before an unquoted `>`,
  because a quoted attribute value could itself contain `>` and the true tag
  boundary cannot be determined without full HTML parsing.
- **unterminated-head-tag-bailout**: `headStartTagEnd(in:)` MUST return `nil`
  when a `<head` match is found but no closing `>` is ever reached — either
  because the match sits at the very end of the string or the
  whitespace-scan loop exhausts the string without finding an unquoted `>`.
- **extension-markup-passthrough**: Every character of `extensionHTML`
  outside the single insertion point MUST appear unchanged in the returned
  document; `html(wrapping:initialState:)` MUST NOT reformat, re-encode, or
  otherwise alter the extension's own markup.
- **initial-state-undefined-vs-value**: A `nil` `initialState` MUST render as
  the bare JavaScript token `undefined`; a non-nil `initialState` MUST
  render as `JSON.parse` applied to a double-quoted, escaped string literal
  wrapping that text, so a caller can distinguish "never called `setState`"
  from "called `setState` with a JSON-encoded value".
- **script-element-escaping**: `escapedForScriptElement(_:)` MUST escape
  every Unicode scalar of its input for safe embedding inside a
  double-quoted JavaScript string literal that itself lives inside an HTML
  `<script>` element: backslash to `\\`, `"` to `\"`, newline to `\n`,
  carriage return to `\r`, tab to `\t`; `<`, `>`, `&`, U+2028, and U+2029 to
  their `\u` hex escapes; every other scalar below U+0020 to its `\u` hex
  escape; every other scalar passed through unescaped.
- **script-close-tag-neutralized**: Because `escapedForScriptElement` escapes
  `<` and `>`, no value supplied as `initialState` can cause the sequence
  formed by a less-than sign, "script", and a greater-than sign to appear
  literally in the rendered document, so persisted state can never terminate
  the injected `<script>` element early.
- **html-comment-open-neutralized**: Because `escapedForScriptElement`
  escapes `<`, no value supplied as `initialState` can cause an HTML comment
  opener to appear literally in the rendered document, so persisted state
  can never open a comment that would swallow the rest of the bootstrap,
  including the `acquireVsCodeApi` definition.
- **message-handler-name-constant**: `messageHandlerName` MUST be the fixed
  string `"agenticWebview"`; the bootstrap script MUST address
  `window.webkit.messageHandlers.agenticWebview` by interpolating this exact
  constant rather than restating it, so the Swift value and the generated
  JavaScript identifier cannot diverge.
- **message-kind-closed-set**: `MessageKind` MUST expose exactly two cases,
  `postMessage` (raw value `"postMessage"`) and `setState` (raw value
  `"setState"`), and MUST conform to `Sendable` and `CaseIterable`; the
  bootstrap script MUST send only these two kind strings via
  `send(kind:body:)`.
- **acquire-once-guard**: The rendered `window.acquireVsCodeApi` function
  MUST return a frozen API object on its first call within a page, and MUST
  throw a JavaScript `Error` with the exact message "An instance of the VS
  Code API has already been acquired" on every subsequent call in that same
  page, mirroring the real `acquireVsCodeApi()` contract extensions are
  written against.
- **post-message-relay-is-fire-and-forget**: The returned API's
  `postMessage(message)` MUST call `send('postMessage', message)`, which
  MUST post an object carrying `kind` and `body` to the `agenticWebview`
  message handler when `window.webkit.messageHandlers.agenticWebview`
  exists, and MUST do nothing else — no throw, no fallback delivery — when
  it does not.
- **get-state-returns-in-memory-value**: The returned API's `getState()`
  MUST return the script's in-memory `state` variable exactly as it was last
  set — either the value decoded from `initialState` at page-load time or
  the argument of the most recent `setState` call in that page's lifetime.
- **set-state-updates-and-relays**: The returned API's `setState(newState)`
  MUST reassign the in-memory `state` variable to `newState`, MUST call
  `send('setState', newState)`, and MUST return `newState`.
- **pure-synchronous-string-transform**: `html(wrapping:initialState:)` MUST
  be a synchronous function of its two arguments only, performing no file,
  network, or process I/O, and MUST NOT throw; it MUST return the same
  `String` value for repeated calls given identical arguments (no `throws` clause and no I/O API anywhere in the file).
- **no-explicit-concurrency-isolation**: `WebviewHostDocument` MUST be
  declared with no `Sendable` conformance, no `actor`, and no `@MainActor`
  isolation; it declares zero cases and only `static` members, so it holds
  no stored instance state, and its lack of an isolation annotation has no
  observable effect — every member is callable from any actor or thread
  without crossing an isolation boundary a caller could violate. The nested
  `MessageKind` MUST be declared explicitly `Sendable`.
- **initial-state-json-validity**: NEEDS REVIEW: Not implemented in source. `html(wrapping:initialState:)`'s doc comment names `initialState` as "The JSON text of whatever the panel last passed to `setState`", but neither `html(wrapping:initialState:)` nor `escapedForScriptElement(_:)` validates that a non-nil `initialState` is syntactically valid JSON before wrapping it in a `JSON.parse` call; a non-nil value that is not valid JSON (an empty string, or state corrupted wherever it was persisted) makes the generated immediately-invoked function expression throw a `SyntaxError` at page-load time — uncaught inside that expression and never reaching the native host — so the page loads with no `window.acquireVsCodeApi` and no signal that this happened. What is missing: whether `html(wrapping:initialState:)` should validate `initialState` before embedding it, or fall back to `undefined` on invalid input. Evidence that would settle it: confirmation from whoever owns the pane-state persistence layer (`packages/apple/AgenticToolkit/Core/Extensions/WebviewPanelState.swift`) that it can only ever produce syntactically valid JSON text and never an empty string, or a decision on the fallback behavior here.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `extensionHTML` | `String` | none — required | The extension's own `webview.html` markup, exactly as it assigned it. |
| `initialState` | `String?` | `nil` | The JSON text of the panel's last `setState` call, or `nil` if it never called one. |

No environment variable, settings key, feature flag, or injected dependency
exists anywhere in this file. `messageHandlerName` and the
`postMessage`/`setState` raw values are compile-time
constants baked into every call, not runtime configuration a caller can
vary.

## Localization

| String | Text | Source |
|--------|------|--------|
| acquire-once error message | An instance of the VS Code API has already been acquired | `bootstrapScript(initialState:)` |

The string above is hardcoded English embedded directly into the generated
JavaScript, with no lookup table, ICU message, or locale parameter anywhere
in this file. This is a deliberate compatibility fact, not a gap: the exact
wording mirrors the error the real `acquireVsCodeApi()` throws (doc comment name replicating that API as this file's purpose), so
extensions that inspect `Error.message` continue to work unmodified; a port
to a platform with an i18n layer MUST decide, as a design choice outside
this contract, whether to keep the literal English text for that
compatibility or route it through localization.

