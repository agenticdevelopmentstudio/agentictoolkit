<!-- leaf: implement-extension-host-core-2/extensions-webview-resource-url--edge-cases · source: extension-host-core-extensions-webview-resource-url.md -->

# WebviewResourceURL

**Rules** (cite as `implement-extension-host-core-2/extensions-webview-resource-url--edge-cases#<slug>`):

- `empty-path-is-the-host-document-not-a-missing-file` MUST — a URL whose decoded path is the empty string or exactly "/" (for example agentic-webview://panel-1 or …
- `boundary-the-root-directory-itself-versus-a-child-of-it` MUST — a candidate equal to a declared root, byte for byte after canonicalization, is refused because …
- `nil-scheme-on-the-incoming-url` MUST — when url.scheme is nil (a relative-looking URL string with no scheme at all), unexpectedScheme MUST carry the empty …
- `absent-host-on-the-incoming-url` MUST — when url.host is absent, target(of:) MUST treat the declared panel as the empty string before comparing it to panelID, …
- `concurrent-access` MUST — WebviewResourceURL, Target, and WebviewResourceURLError hold no mutable stored state — every entry point is a pure …
- `a-symlink-planted-inside-a-declared-root` MUST — because both the candidate and each root are canonicalized (symlinks resolved, then standardized) before comparison, a …
- `a-panel-id-that-cannot-be-spelled-as-a-url-authority` SHOULD — makeURL returns the fixed URL(fileURLWithPath: "/") instead of trapping or producing nil; per the source's own comment …
- `error-states` MUST — the only three defined failures are the three WebviewResourceURLError cases, each thrown synchronously and exactly once …

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
