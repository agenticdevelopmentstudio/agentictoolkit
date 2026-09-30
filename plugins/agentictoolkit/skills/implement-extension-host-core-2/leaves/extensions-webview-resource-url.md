<!-- leaf: implement-extension-host-core-2/extensions-webview-resource-url · source: extension-host-core-extensions-webview-resource-url.md -->

**Rules** (cite as `implement-extension-host-core-2/extensions-webview-resource-url#<slug>`):

- `scheme-constant` MUST
- `error-case` MUST
- `error-message` MUST
- `target-type` MUST
- `host-document-url` MUST
- `resource-url-naming-only` MUST
- `percent-encoding-round-trip` MUST
- `leading-slash-normalization` MUST
- `unroutable-fallback` MUST
- `scheme-validation-first` MUST
- `panel-validation-second` MUST
- `host-document-detection` MUST
- `candidate-canonicalization` MUST
- `containment-delegation` MUST
- `first-matching-root-wins` MUST
- `empty-roots-refuses-every-file` MUST
- `containment-failure-payload` MUST
- `stateless-re-derivation` MUST
- `no-actor-isolation` MUST
- `no-filesystem-mutation` MUST

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

## Localization

`WebviewResourceURLError.errorDescription` produces three hardcoded English
sentences, one per case, with no locale parameter and no externalized string
table entry.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — not externalized) | A webview asked for "scheme value" in curly quotes, which is not the webview scheme. | `unexpectedScheme`, shown when a URL's scheme is not `agentic-webview`. |
| (none — not externalized) | A webview asked for panel "declared value" in curly quotes from panel "expected value" in curly quotes. | `unexpectedPanel`, shown when a URL's decoded host does not match the asking panel. |
| (none — not externalized) | A webview asked for "resolved value", which is outside its localResourceRoots. | `outsideLocalResourceRoots`, shown when a candidate file is not inside any declared root. |

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

