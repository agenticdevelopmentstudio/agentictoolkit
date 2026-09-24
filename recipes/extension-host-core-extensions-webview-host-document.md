---
id: a380ec4a-df3f-42ee-8b07-3a8838d753e9
title: WebviewHostDocument
domain: agentictoolkit://recipes/extension-host-core-extensions-webview-host-document
type: ingredient
version: 1.0.2
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Wraps an extension's webview HTML with an injected acquireVsCodeApi/postMessage/setState
  bootstrap, escaped against script and comment breakout.
platforms:
- swift
- macos
tags:
- extensions
- webview
- script-bridge
- html-injection-prevention
depends-on: []
related: []
references:
- packages/apple/AgenticToolkit/Core/Extensions/WebviewHostDocument.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Extensions/WebviewHostDocumentTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is an HTML-document assembler, not a visual component.

## States

Not applicable — this is an HTML-document assembler, not a visual component.

## Accessibility

Not applicable — this is an HTML-document assembler, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| webview-host-document-001 | bootstrap-injection-point, head-tag-closing-detection | `wrapping: "<html><head><title>x</title></head><body>hi</body></html>", initialState: nil` | Bootstrap script text appears strictly between `<head>` and `</head>` (`bootstrapGoesInsideHead`) |
| webview-host-document-002 | bootstrap-injection-point | `wrapping: "<html><head><script>acquireVsCodeApi()</script></head><body></body></html>", initialState: nil` | The bootstrap's occurrence of `messageHandlerName` precedes the extension's own `acquireVsCodeApi()` text (`bootstrapPrecedesTheExtensionsScripts`) |
| webview-host-document-003 | bootstrap-prepend-fallback | `wrapping: "<p>hi</p>", initialState: nil` | Bootstrap precedes `<p>hi</p>` in the returned document (`bootstrapSurvivesAMissingHead`, arg 1) |
| webview-host-document-004 | bootstrap-prepend-fallback | `wrapping: "<html><body>hi</body></html>", initialState: nil` | Bootstrap precedes the given markup in the returned document (`bootstrapSurvivesAMissingHead`, arg 2) |
| webview-host-document-005 | bootstrap-prepend-fallback | `wrapping: "", initialState: nil` | Returned document contains the bootstrap's `messageHandlerName` occurrence; nothing else is present to compare against (`bootstrapSurvivesAMissingHead`, arg 3) |
| webview-host-document-006 | head-tag-match-case-insensitive, head-tag-closing-detection | `wrapping: "<HTML><HEAD></HEAD><BODY>hi</BODY></HTML>", initialState: nil` | Bootstrap injected strictly between `<HEAD>` and `</HEAD>` (`headIsMatchedCaseInsensitively`) |
| webview-host-document-007 | extension-markup-passthrough | `wrapping: "<html><head></head><body><p>café &amp; crème</p><img src=\"a#b.png\"></body></html>", initialState: nil` | Returned document contains the given `<body>...</body>` substring unchanged (`markupIsCarriedThroughUnchanged`) |
| webview-host-document-008 | initial-state-undefined-vs-value | `wrapping: "<html><head></head><body></body></html>", initialState: "{\"scrollTop\":42}"` | Returned document contains `42` (`stateIsEmbedded`) |
| webview-host-document-009 | script-close-tag-neutralized | `initialState: "{\"note\":\"</script><script>alert(1)</script>\"}"` | Returned document does not contain `<script>alert(1)` literally and does not contain the raw payload unescaped (`stateCannotBreakOutOfTheScriptElement`) |
| webview-host-document-010 | html-comment-open-neutralized | `initialState` note field containing each of `<!--`, `-->`, `<!--<script>`, `</SCRIPT >` in turn | Returned document does not contain that raw payload unescaped, for every one of the four inputs (`stateCannotOpenAComment`) |
| webview-host-document-011 | initial-state-undefined-vs-value | `wrapping: "<html><head></head><body></body></html>", initialState: nil` | Returned document contains the bare token `undefined` (`absentStateIsUndefined`) |
| webview-host-document-012 | message-handler-name-constant | `WebviewHostDocument.messageHandlerName` | Equals `"agenticWebview"`; first character is a letter; every character is a letter or digit (`messageHandlerNameIsStable`) |
| webview-host-document-013 | message-kind-closed-set | `MessageKind.allCases` against a rendered bootstrap | Every case's `rawValue` appears in the rendered document (`messageKindsAreClosed`) |
| webview-host-document-014 | quoted-attribute-ambiguity-bailout | `wrapping: "<p>x</p><head data-x=\">oops\">content</head>"` (a quoted attribute containing `>`) | `headStartTagEnd(in:)` returns `nil`; the bootstrap is prepended before `<p>x</p>` rather than inserted mid-attribute (derived directly from the source; not exercised by a named test in the given source) |
| webview-host-document-015 | head-vs-header-disambiguation | `wrapping: "<header>nav</header><head></head>"` | The bootstrap is inserted inside the real `<head></head>`, not before `<header>` (derived directly from the source; not exercised by a named test in the given source) |
| webview-host-document-016 | acquire-once-guard | The literal text of `bootstrapScript(initialState:)`'s generated string | Contains the exact substring `already been acquired` guarded by an `if (acquired)` check (derived directly from the source; the Swift test suite asserts only that the resulting document contains this JavaScript text, not that a JS engine actually throws on a second call) |

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

## Deep Linking

Not applicable: this file defines no URL scheme, universal link, or intent
handling of any kind — it assembles an HTML string only, and reads no
inbound request of any kind (whole file).

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

## Accessibility Options

Not applicable: this file renders no UI and reads no Reduce Motion, Increase
Contrast, or Differentiate-Without-Color signal anywhere — it emits a
document string that some other component later renders inside a
`WKWebView`.

## Feature Flags

Not applicable: no field, function, or comment in this file reads a
feature-flag key — the bootstrap is injected unconditionally on every call
to `html(wrapping:initialState:)`.

## Analytics

Not applicable: no file in this component emits a client-side analytics or
telemetry event. The `postMessage`/`setState` traffic the generated
bootstrap sends through `agenticWebview` is the bridge's own protocol
traffic, addressed to the native host, not analytics instrumentation.

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

## Logging

Not applicable: no `print`, `os_log`, `Logger`, or `NSLog` call appears
anywhere in this file (whole file) — this component emits no
log line of any kind.

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | passed | Security |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

`input-sanitization` **passed**: `escapedForScriptElement(_:)` escapes every
character an extension-authored `initialState` could use to break out of
the `<script>` element it is embedded in, and both break-out families —
closing the script tag early, opening an HTML comment — are covered by a
named test each (webview-host-document-009, webview-host-document-010).
`separation-of-concerns` **passed**: this file only assembles the document
and generates the bootstrap script; decoding the messages that bootstrap
sends back is a separate component's job (`WebviewMessageRelay` in
`WebviewPanelViewController.swift`), not this one's.
`unit-test-coverage` **passed**: `WebviewHostDocumentTests.swift` exercises
head insertion, the no-head fallback across three markup shapes, case
insensitivity, markup passthrough, both state-embedding paths, both
break-out families, and the two shared bridge names. `explicit-error-handling`
is **partial**: `html(wrapping:initialState:)` has no error path of its own
to swallow, but the one place an error can occur — a non-nil `initialState`
that is not valid JSON — throws inside a JavaScript IIFE with no signal
reaching this file's caller (**initial-state-json-validity**).
`idempotent-operations` **passed**: `html(wrapping:initialState:)` is a
pure function of its two arguments; repeated calls with identical arguments
return identical strings. `no-hardcoded-strings` **failed**: the
acquire-once error message is hardcoded English with no lookup table or
locale parameter anywhere in this file (see Localization) — a plain,
honestly-reported gap in the source, not a hidden one.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.0.2 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
