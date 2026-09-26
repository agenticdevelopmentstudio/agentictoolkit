---
id: 0cb9069f-57c6-4ac2-a952-6b331c4b6889
title: WebviewResourceURL
domain: agentictoolkit://cookbook/core/extensions/webview-resource-url
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Names and gatekeeps every file a webview extension panel may load, deciding
  from the URL alone whether a request is the panel's own document, an allowed file,
  or refused.
platforms:
- swift
- macos
tags:
- extension-host
- webview
- path-safety
- containment
depends-on: []
related:
- agentictoolkit://cookbook/core/extensions/extension-resource-path
references:
- packages/apple/AgenticToolkit/Core/Extensions/WebviewResourceURL.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Extensions/WebviewResourceURLTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/Webview/WebviewSchemeHandler.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# WebviewResourceURL

## Overview

`WebviewResourceURL` is `AgenticToolkitCore`'s definition of the `agentic-webview`
URL scheme that an extension's webview panel loads from, and the single place
that decides whether a URL in that scheme names something the panel is allowed
to have. Per the source's own header comment, a webview runs an extension's own
HTML and JavaScript, so the page is hostile by assumption, and it cannot be
handed `file:` URLs — WebKit will not load them from a custom-scheme document
— so every resource is re-spelled as `agentic-webview://<panel id>/<absolute
file path>` and the scheme handler asks `target(of:panelID:localResourceRoots:)`
here whether a request for one may be answered. The panel id is the URL's
authority rather than a path segment specifically because that is what makes
two panels two WebKit origins; an empty path is defined as the panel's own
host document (its `webview.html` string) rather than a file; and containment
of a file path against the panel's declared `localResourceRoots` is delegated
component-wise to `ExtensionResourcePath`, the same rule `ExtensionResourcePath`'s
own recipe documents as this project's one containment check, rather than a
second implementation of it.

## Behavioral Requirements

- **scheme-constant**: `WebviewResourceURL.scheme` MUST equal the literal
  string `"agentic-webview"`. Per the source's own doc comment this is a
  storage format: an extension that persists a resource URI through
  `setState` writes this string into the pane state database, and a restored
  panel hands it straight back, so changing the value orphans that persisted
  state silently.
- **error-case**: `WebviewResourceURLError` MUST be declared as a `public
  enum` conforming to `Error` and `Equatable`, with exactly three cases:
  `unexpectedScheme(String)`, `unexpectedPanel(declared: String, expected:
  String)`, and `outsideLocalResourceRoots(resolved: String)`.
- **error-message**: `WebviewResourceURLError` MUST conform to
  `LocalizedError`, and `errorDescription` MUST return, for each case, one of
  exactly these three sentence forms, substituting the case's payload
  verbatim: for `unexpectedScheme`, "A webview asked for" the scheme in curly
  quotes "which is not the webview scheme."; for `unexpectedPanel`, "A
  webview asked for panel" the declared value in curly quotes "from panel"
  the expected value in curly quotes; for `outsideLocalResourceRoots`, "A
  webview asked for" the resolved value "which is outside its
  localResourceRoots."
- **target-type**: `WebviewResourceURL.Target` MUST be declared as a nested
  `public enum` conforming to `Equatable`, with exactly two cases:
  `hostDocument` (no payload) and `file(URL)`.
- **host-document-url**: `hostDocumentURL(panelID:)` MUST return the URL
  built by composing the scheme, the given `panelID` as authority, and the
  path `"/"`.
- **resource-url-naming-only**: `url(forFile:panelID:)` MUST return the URL
  built by composing the scheme, the given `panelID` as authority, and
  `file.path` as the path, performing no existence check, no symlink
  resolution, and no containment check against any root; naming a file this
  way is not permission to read it.
- **percent-encoding-round-trip**: URL construction (both `hostDocumentURL`
  and `url(forFile:)`) MUST build the URL through `URLComponents` from the
  decoded `panelID` and path values, letting `URLComponents` percent-encode
  both, so that a path containing a space, a `#`, a `%`, or a non-ASCII
  character round-trips through `target(of:)` to the same file it named.
- **leading-slash-normalization**: URL construction MUST prefix the composed
  path with `/` when the caller-supplied path does not already start with
  one, because a `URLComponents` value with a non-empty `host` produces a
  `nil` `url` for a path that does not start with `/`.
- **unroutable-fallback**: URL construction MUST return the fixed value
  `URL(fileURLWithPath: "/")` in place of a `nil` result from `URLComponents`,
  rather than trapping or returning `nil` itself, for the case where
  `Foundation` declines to spell the given `panelID` as a URL authority at
  all.
- **scheme-validation-first**: `target(of:panelID:localResourceRoots:)` MUST
  check `url.scheme` against `WebviewResourceURL.scheme` before any other
  check, and MUST throw `unexpectedScheme` carrying `url.scheme` (or the
  empty string when `url.scheme` is `nil`) when they do not match exactly.
- **panel-validation-second**: after the scheme check passes,
  `target(of:panelID:localResourceRoots:)` MUST decode `url.host` with
  percent-encoding removed (treating an absent host as the empty string) and
  MUST throw `unexpectedPanel(declared:expected:)`, carrying that decoded
  value as `declared` and the caller-supplied `panelID` as `expected`, when
  the two differ, before any file-path resolution is attempted.
- **host-document-detection**: after the scheme and panel checks pass,
  `target(of:panelID:localResourceRoots:)` MUST return `.hostDocument`, with
  no file-path resolution and no containment check, when the URL's decoded
  path is the empty string or exactly `"/"`.
- **candidate-canonicalization**: for a path that is neither empty nor `"/"`,
  `target(of:panelID:localResourceRoots:)` MUST build the candidate file URL
  by constructing a file URL from the decoded path, then resolving symlinks,
  then standardizing the result, applying exactly these three steps in this
  order before any containment decision.
- **containment-delegation**: `target(of:panelID:localResourceRoots:)` MUST
  decide whether the candidate is allowed by calling
  `ExtensionResourcePath.url(_:isContainedIn:)` against
  `ExtensionResourcePath.canonicalDirectory(root)` for each root in
  `localResourceRoots`, in the order the array supplies them, rather than
  comparing paths as strings or re-implementing containment.
- **first-matching-root-wins**: `target(of:panelID:localResourceRoots:)` MUST
  return `.file(candidate)` as soon as any one declared root contains the
  candidate; it MUST NOT require containment in every declared root.
- **empty-roots-refuses-every-file**: when `localResourceRoots` is empty,
  `target(of:panelID:localResourceRoots:)` MUST throw
  `outsideLocalResourceRoots` for every non-host-document path, treating no
  declared root as no file access at all.
- **containment-failure-payload**: when no declared root contains the
  candidate, `target(of:panelID:localResourceRoots:)` MUST throw
  `outsideLocalResourceRoots(resolved:)` carrying the fully canonicalized
  candidate's `.path` (post symlink-resolution and standardization), not the
  raw path the URL carried.
- **stateless-re-derivation**: `target(of:panelID:localResourceRoots:)` MUST
  compute its answer solely from its three arguments on every call; it MUST
  NOT consult or maintain any cache, table, or other state mapping a panel id
  or a URL to a previously computed answer, so a root narrowed between two
  requests narrows the second request's outcome as well.
- **no-actor-isolation**: neither `WebviewResourceURLError`,
  `WebviewResourceURL`, nor its nested `Target` declares a `Sendable`
  conformance or any actor / `@MainActor` isolation in the source. Because
  every stored payload (`String`, `URL`) is itself `Sendable`, and
  `WebviewResourceURL` declares no case and cannot be instantiated so it
  holds no stored state, every operation MUST be safe to invoke from any
  isolation domain, concurrently, without additional synchronization.
- **no-filesystem-mutation**: `target(of:panelID:localResourceRoots:)` MUST
  consult the file system only to resolve symlinks while canonicalizing the
  candidate and the declared roots; no function in this file MUST create,
  delete, write, or read the contents of any file or directory.

## Appearance

Not applicable — this is a URL-naming and access-decision utility, not a
visual component.

## States

Not applicable — this is a URL-naming and access-decision utility, not a
visual component.

## Accessibility

Not applicable — this is a URL-naming and access-decision utility, not a
visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| wru-001 | resource-url-naming-only, percent-encoding-round-trip, candidate-canonicalization, containment-delegation, first-matching-root-wins | `url(forFile: root/"media/style.css", panelID: "panel-1")`, then `target(of:, panelID: "panel-1", localResourceRoots: [root])` | `.file(root/"media/style.css")`, canonicalized (source: `fileURLRoundTrips`) |
| wru-002 | percent-encoding-round-trip | the same round trip for the relative paths `"media/my style.css"`, `"media/a#b.css"`, `"media/100%.css"`, and `"média/ü.css"` | each round-trips to `.file(<that same file>)` (source: `awkwardPathsRoundTrip`) |
| wru-003 | host-document-url, host-document-detection | `hostDocumentURL(panelID: "panel-1")`, then `target(of:, panelID: "panel-1", localResourceRoots: [])` | `.hostDocument` (source: `hostDocumentIsDistinctFromAFile`) |
| wru-004 | host-document-detection, empty-roots-refuses-every-file | `target(of: hostDocumentURL(panelID: "panel-1"), panelID: "panel-1", localResourceRoots: [])` | `.hostDocument`, unaffected by an empty `localResourceRoots` (source: `hostDocumentNeedsNoRoots`) |
| wru-005 | empty-roots-refuses-every-file | `target(of: url(forFile: root/"style.css", panelID: "panel-1"), panelID: "panel-1", localResourceRoots: [])` | throws `WebviewResourceURLError` (source: `noRootsRefusesEveryFile`) |
| wru-006 | containment-delegation, containment-failure-payload | a file inside `elsewhere` looked up with `localResourceRoots: [allowed]`, where `elsewhere` is not `allowed` | throws `WebviewResourceURLError` (source: `outsideEveryRootIsRefused`) |
| wru-007 | containment-delegation, first-matching-root-wins | a file inside `second`, looked up with `localResourceRoots: [first, second]` | `.file(<that file>)`, allowed because the second root contains it (source: `anyDeclaredRootAllows`) |
| wru-008 | candidate-canonicalization, containment-delegation | `url(forFile: root/"../../../etc/passwd", panelID: "panel-1")` looked up against `localResourceRoots: [root]` | throws `WebviewResourceURLError` (source: `traversalOutOfTheRootIsRefused`) |
| wru-009 | containment-delegation | a file inside a directory named `"ext-evil"`, looked up against `localResourceRoots: [<the sibling directory "ext">]` | throws `WebviewResourceURLError`, even though `"ext-evil"` has `"ext"` as a string prefix (source: `siblingNamePrefixIsRefused`) |
| wru-010 | candidate-canonicalization, containment-delegation | `url(forFile: root, panelID: "panel-1")` (the root directory itself) looked up against `localResourceRoots: [root]` | throws `WebviewResourceURLError`; the root is not contained in itself (source: `theRootItselfIsRefused`) |
| wru-011 | panel-validation-second | a URL built with `panelID: "panel-2"`, looked up with `target(of:, panelID: "panel-1", localResourceRoots: [root])` | throws `WebviewResourceURLError.unexpectedPanel(declared: "panel-2", expected: "panel-1")` (source: `anotherPanelsURLIsRefused`) |
| wru-012 | scheme-validation-first | `target(of:, panelID:, localResourceRoots:)` for the raw URLs `"file:///etc/passwd"`, `"https://example.com/x.js"`, and `"data:text/html,<b>x</b>"` | each throws `WebviewResourceURLError` (source: `anotherSchemeIsRefused`) |
| wru-013 | scheme-constant | `WebviewResourceURL.scheme` | equals `"agentic-webview"`; is not one of `http`, `https`, `file`, `data`, `blob`, `about`, `ws`, `wss`, `ftp`, `javascript`; starts with a letter; and every character is a lowercase letter, digit, `+`, `-`, or `.` (source: `schemeIsStable`) |
| wru-014 | stateless-re-derivation, no-actor-isolation | call `target(of:panelID:localResourceRoots:)` concurrently from many detached tasks with different URLs and root arrays against the shared `WebviewResourceURL` namespace | every call returns the outcome its own arguments imply, with no crash and no result influenced by another concurrent call (traced to the absence of any stored property, actor, or `@MainActor` annotation, and to every parameter being passed by value) |

## Edge Cases

- **Empty path is the host document, not a missing file**: a URL whose
  decoded path is the empty string or exactly `"/"` (for example
  `agentic-webview://panel-1` or `agentic-webview://panel-1/`) resolves to
  `.hostDocument` before any file resolution or containment check runs, and
  this is true even when `localResourceRoots` is empty. MUST.
- **Boundary — the root directory itself versus a child of it**: a candidate
  equal to a declared root, byte for byte after canonicalization, is refused
  because `ExtensionResourcePath.url(_:isContainedIn:)` requires the
  candidate's path-component count to be strictly greater than the root's; a
  candidate one path component below the same root is allowed. MUST.
- **`nil` scheme on the incoming URL**: when `url.scheme` is `nil` (a
  relative-looking URL string with no scheme at all),
  `unexpectedScheme` MUST carry the empty string rather than any placeholder
  or a nil-coalesced word, per the source's `url.scheme ?? ""`. MUST.
- **Absent host on the incoming URL**: when `url.host` is absent,
  `target(of:)` MUST treat the declared panel as the empty string before
  comparing it to `panelID`, so a caller-supplied `panelID` of `""` is the
  only value such a URL could ever match. MUST.
- **Concurrent access**: `WebviewResourceURL`, `Target`, and
  `WebviewResourceURLError` hold no mutable stored state — every entry point
  is a pure `static` function or computed value over its arguments — so
  calling any of them concurrently, from any thread or actor, with
  independent or shared `localResourceRoots` arrays, requires no
  synchronization of its own. MUST.
- **A symlink planted inside a declared root**: because both the candidate
  and each root are canonicalized (symlinks resolved, then standardized)
  before comparison, a candidate reached through a symlink that itself
  points outside the root is refused even though the declared path string
  contains no `..` segment; this follows from `ExtensionResourcePath`'s
  documented symmetric-canonicalization rule, which `containment-delegation`
  inherits rather than re-deriving. MUST.
- **A panel id that cannot be spelled as a URL authority**: `makeURL`
  returns the fixed `URL(fileURLWithPath: "/")` instead of trapping or
  producing `nil`; per the source's own comment this fallback is itself then
  refused by `target(of:)` on a later call, because it is a `file:` URL, not
  one in the `agentic-webview` scheme. SHOULD (see Design Decisions for why
  a trap was rejected).
- **Error states**: the only three defined failures are the three
  `WebviewResourceURLError` cases, each thrown synchronously and exactly
  once per call to `target(of:panelID:localResourceRoots:)`; no error is
  ever swallowed inside this file. What a caller does with a thrown error —
  logging it, or communicating a load failure back to WebKit — is outside
  this file's contract. MUST.
- **Offline / disconnected state**: not applicable. Every operation reads
  only URL structure and local file-system symlink metadata; there is no
  networking in this file and therefore no connectivity state to lose
  mid-operation.
- **Cancellation and timeout**: `target(of:)`, `hostDocumentURL(panelID:)`,
  and `url(forFile:panelID:)` define no timeout and no cancellation, because
  every call is synchronous and non-`async`. A slow or unresponsive volume
  underneath a declared root blocks the caller for as long as symlink
  resolution takes, with no escape hatch defined in this file. Stated as
  fact, per the absent-feature rule — not a marker, since nothing in the
  purpose of a synchronous, pure decision function calls for one.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `panelID` | `String` | none (required) | The panel doing the asking, or the panel a URL is being built for; compared against a URL's decoded host in `target(of:panelID:localResourceRoots:)`. |
| `file` | `URL` | none (required) | The file `url(forFile:panelID:)` names, without checking that it exists or is reachable. |
| `url` | `URL` | none (required) | The URL a page asked for, exactly as WebKit hands it to `target(of:panelID:localResourceRoots:)`. |
| `localResourceRoots` | `[URL]` | none (required) | The directories this panel declared it may read files from; an empty array is the default posture and means no file access at all. |

There are no settings keys, environment variables, or dependency-injection
containers involved: every input arrives as a plain function argument, and
`localResourceRoots` itself is supplied by the caller (the panel's
configuration), not read from any store by this file.

## Deep Linking

Not applicable: `agentic-webview` is a resource-loading scheme a
`WKURLSchemeHandler` answers inside one panel's `WKWebView`, not a route the
operating system opens into the app from outside it. Nothing in this file
registers a `CFBundleURLTypes` entry, handles a universal link, or otherwise
participates in the app-level deep-linking surface the template's Deep
Linking table describes.

## Localization

`WebviewResourceURLError.errorDescription` produces three hardcoded English
sentences, one per case, with no locale parameter and no externalized string
table entry.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — not externalized) | A webview asked for "scheme value" in curly quotes, which is not the webview scheme. | `unexpectedScheme`, shown when a URL's scheme is not `agentic-webview`. |
| (none — not externalized) | A webview asked for panel "declared value" in curly quotes from panel "expected value" in curly quotes. | `unexpectedPanel`, shown when a URL's decoded host does not match the asking panel. |
| (none — not externalized) | A webview asked for "resolved value", which is outside its localResourceRoots. | `outsideLocalResourceRoots`, shown when a candidate file is not inside any declared root. |

## Accessibility Options

Not applicable: this component has no visual or interactive surface for a
system accessibility display option to affect.

## Feature Flags

Not applicable: `WebviewResourceURL.swift` defines no feature flag, build
configuration check, or remote-config lookup; every function's outcome is
fixed entirely by the arguments it is called with.

## Analytics

Not applicable: this component emits no analytics event; it returns a
`Target`, a thrown error, or a constructed `URL` to its caller and performs
no telemetry of its own.

## Privacy

- **Data collected**: none in the sense of device- or user-identifying
  telemetry. However, the `resolved` payload of a thrown
  `outsideLocalResourceRoots` error, and every `URL` `url(forFile:panelID:)`
  and `hostDocumentURL(panelID:)` construct, embed the absolute local
  file-system path of a file inside the extension's own directory tree — a
  path that can include the local account's home-directory name when a
  declared root sits under it.
- **Storage**: none performed by this file. `WebviewResourceURL` writes
  nothing to disk; a caller that persists a resource URI through `setState`
  (named in the source's doc comment on `scheme`) does so outside this file.
- **Transmission**: none performed directly by this component — it does no
  networking. A `URL` or thrown error this file produces may later be
  handed to WebKit or logged by a caller; how far that propagates is outside
  this file.
- **Retention**: for the lifetime of whichever value — a `Target`, a thrown
  error, or a constructed `URL` — the caller holds; this component itself
  retains nothing once a call returns.

## Logging

Not applicable: `WebviewResourceURL.swift` contains no logging call and
imports no logging framework; a failure is communicated to its caller
exclusively through a thrown `WebviewResourceURLError`, never written to a
log by this component itself.

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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/Extensions/WebviewResourceURL.swift` |

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | passed | Security |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

`separation-of-concerns` passes because naming a URL (`hostDocumentURL`,
`url(forFile:)`), deciding what a URL names (`target(of:)`), and deciding
whether a path is contained (delegated entirely to `ExtensionResourcePath`)
are three distinct responsibilities that this file keeps apart rather than
folding into one function (`resource-url-naming-only`, `containment-
delegation`). `input-sanitization` passes because every URL this file
decides on is, per its own header comment, from a hostile webview page, and
`target(of:)` never trusts it: scheme, panel identity, and file containment
are each checked in order before a `.file` result is ever returned
(`scheme-validation-first`, `panel-validation-second`, `candidate-
canonicalization`). `explicit-error-handling` passes because the three
failures this file defines are never swallowed — they are typed, `Equatable`,
`LocalizedError`-conforming cases a caller must catch, and the one production
caller this recipe traced (`WebviewSchemeHandler`) does catch and act on
every one of them (`error-case`, `error-message`). `unit-test-coverage`
passes: `WebviewResourceURLTests.swift` exercises the naming round trip
(including percent-encoding), the host document, every refusal path
(no roots, outside every root, a name-prefix sibling, the root itself, a
traversal, a wrong panel, a wrong scheme), and the scheme constant's shape
directly. `no-hardcoded-strings` fails: `errorDescription` returns one of
three fixed English sentences with no localization lookup of any kind, so
the message an extension author or developer sees when a resource is
refused is English regardless of the host's locale (`error-message`,
Localization).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
