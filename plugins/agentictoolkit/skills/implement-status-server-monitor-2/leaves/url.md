<!-- leaf: implement-status-server-monitor-2/url · source: status-server-monitor-url.md -->

**Rules** (cite as `implement-status-server-monitor-2/url#<slug>`):

- `host-of-extraction` MUST
- `host-of-invalid-fallback` MUST
- `project-page-url-null-on-falsy` MUST
- `project-page-url-vercel-collapse` MUST
- `project-page-url-drops-suffix` MUST
- `project-page-url-vercel-short-path-passthrough` MUST
- `project-page-url-non-vercel-passthrough` MUST
- `project-page-url-invalid-fallback` MUST
- `pure-synchronous` MUST
- `no-throw` MUST

# Status Server Monitor URL

## Overview

`url.ts` (`packages/web/packages/status-server/src/monitor/url.ts`) is the status server's
shared home for two small, unrelated URL-string helpers used when building links for deploy
rows: `hostOf`, which extracts a URL's `host` for display or comparison, and
`projectPageUrl`, whose own doc comment states its purpose directly — "The platform PROJECT
page for a deploy URL — so clicking a project name always lands on the same place,
regardless of which specific deploy the row is about" — by collapsing a Vercel inspector URL
down to its team/project page and passing every other URL through unchanged. Both functions
are pure, synchronous, and defensive: each wraps its call to the `URL` constructor in a
`try`/`catch` and falls back to the raw input string on any parse failure, so neither
function ever throws.

`hostOf` is called from `sync.ts` — once to build the lower-cased live host a deploy row
stamps from its owning roster entry's URL, and once to compose the message a retired
monitor's removal is logged with — and from `routes/reads.ts`'s `ownerHostFor`, which
derives the live custom-domain host a deploy DTO reports, again lower-cased. `projectPageUrl`
is called from `deploy-view.ts`'s `deployLinks`, whose own comment says the derived
`sourceUrl` is "used by all three panes (active problems, resolved, activity) and the issue
recorder — so every row everywhere renders the same clickable link." Neither function has a
dedicated test file in the given source tree.

## Behavioral Requirements

### hostOf

- **host-of-extraction**: `hostOf(url)` MUST return the `host` property of `new URL(url)` —
  the hostname, plus a non-default port when one is present, per the WHATWG URL standard —
  when `url` parses as an absolute URL.
- **host-of-invalid-fallback**: `hostOf(url)` MUST return `url` unchanged, verbatim, when the
  `URL` constructor throws for a malformed or relative URL string; the `catch` block's only
  action is `return url`.

### projectPageUrl

- **project-page-url-null-on-falsy**: `projectPageUrl(url)` MUST return `null` when `url` is
  `null`, `undefined`, or the empty string `''`, via the guard `if (!url) return null;`,
  before any URL parsing is attempted.
- **project-page-url-vercel-collapse**: `projectPageUrl(url)` MUST return
  `` `${u.origin}/${parts[0]}/${parts[1]}` `` — the parsed URL's origin joined with the first
  two non-empty path segments — when `new URL(url).hostname` is exactly `vercel.com` and
  `u.pathname.split("/").filter(Boolean)` yields 3 or more segments.
- **project-page-url-drops-suffix**: when collapsing a Vercel URL, `projectPageUrl` MUST
  discard the third and every subsequent path segment (the deploy id and anything after it)
  together with the URL's query string and fragment, since the returned string is built from
  only `u.origin`, `parts[0]`, and `parts[1]`.
- **project-page-url-vercel-short-path-passthrough**: `projectPageUrl(url)` MUST return `url`
  unchanged when the hostname is `vercel.com` but `u.pathname.split("/").filter(Boolean)`
  yields fewer than 3 segments.
- **project-page-url-non-vercel-passthrough**: `projectPageUrl(url)` MUST return `url`
  unchanged when `new URL(url).hostname` is any value other than `vercel.com`.
- **project-page-url-invalid-fallback**: `projectPageUrl(url)` MUST return `url` unchanged
  when the `URL` constructor throws for a truthy `url` (a malformed or relative URL string);
  this fallback is the same string the function returns for a recognized-but-unaffected
  hostname, so a caller cannot tell a parse failure apart from an intentional passthrough.

### Purity and Side Effects

- **pure-synchronous**: `hostOf` and `projectPageUrl` MUST each execute synchronously and
  MUST perform no I/O, network call, logging, or persistence of any kind; each is a pure
  function of its single argument with no dependency on module-level or external state.
- **no-throw**: neither function MUST throw for any input within its declared parameter type
  (`string` for `hostOf`; `string | null | undefined` for `projectPageUrl`) — every branch,
  including the `URL` constructor's thrown error, is caught and converted to a return value.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `url` (`hostOf`) | `string` | n/a (required positional argument) | The URL string to extract a host from; not validated as an absolute URL before parsing — a parse failure falls back to returning it unchanged. |
| `url` (`projectPageUrl`) | `string \| null \| undefined` | n/a (required positional argument) | The deploy/provider URL to derive a stable project-page link from; `null`, `undefined`, or `''` short-circuits to `null` before any parsing. |

## Privacy

- **Data collected**: None collected or retained by this file itself. It receives a
  caller-supplied URL string — a monitored endpoint's live URL, or a deploy's provider
  inspector URL — and returns a derived string, a host or a collapsed project-page URL, to
  the caller.
- **Storage**: None. The module holds no state beyond its own function definitions; it
  neither reads from nor writes to any store.
- **Transmission**: None. This file makes no network call and transmits nothing of its own;
  how a derived host or project-page URL travels onward — for example, included in a
  `sync.ts` log line or rendered as a deploy row's link — is the concern of the external
  caller.
- **Retention**: Not applicable — there is nothing this file collects or stores to retain.

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). A Swift port has no natural class or actor to
  attach to — it is two free functions (or two `static` members of a `URLHelpers`-like
  namespace) operating on `String`/`String?`. `hostOf` becomes
  `Foundation.URL(string: url)?.host ?? url`; unlike JS's `new URL(...).host`, Swift's
  `URL.host` never includes the port — a Swift port that must reproduce the JS `"host:port"`
  string has to append `URL.port` itself, a real divergence worth flagging in the port.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models the two functions as
  top-level `fun`s using `java.net.URI`, whose constructor throws `URISyntaxException` on a
  malformed string (matching the try/catch shape): `hostOf` becomes
  `runCatching { URI(url).host }.getOrDefault(url)`. As with Swift, `URI.host` excludes the
  port (a separate `.port` property returns `-1` when absent), so a Kotlin port needing the
  combined `"host:port"` form must assemble it manually.
- **React/Web** (source platform): lives at
  `packages/web/packages/status-server/src/monitor/url.ts` on the Node status backend. Its
  two exported functions are consumed by three files: `deploy-view.ts` (via
  `projectPageUrl`, to derive a deploy row's `sourceUrl`), and `sync.ts` and
  `routes/reads.ts` (via `hostOf`, to derive a stamped or reported live host). Neither
  function has a dedicated test file in the given source tree — unlike the sibling module
  `format.ts`, which has `format.test.ts`.
- **AppKit / UIKit**: same non-UI framing as SwiftUI. A macOS/iOS agent embedding this URL
  handling has no windowing or view-layer concern of its own; it would reuse the same Swift
  free functions described under SwiftUI regardless of whether the surrounding app is
  AppKit- or UIKit-based.
- **WinUI 3**: a .NET port models the two functions as `static` methods on a `UrlHelpers`
  class. `hostOf` becomes
  `Uri.TryCreate(url, UriKind.Absolute, out var u) ? u.Host + (u.IsDefaultPort ? "" : $":{u.Port}") : url`
  — .NET's bool-returning `Uri.TryCreate` replaces JS's throw-and-catch, and because
  `Uri.Host` (like Swift's and Kotlin's host accessors) excludes the port, the port must be
  appended manually via `Uri.Port`/`Uri.IsDefaultPort` to match the combined `host:port`
  string JS's `URL.host` returns. `projectPageUrl` becomes a similar `Uri.TryCreate` guard,
  checking `u.Host == "vercel.com"` and splitting `u.AbsolutePath` on `'/'` with
  `StringSplitOptions.RemoveEmptyEntries` to get the segment array, then reconstructing
  `$"{u.GetLeftPart(UriPartial.Authority)}/{parts[0]}/{parts[1]}"` when 3 or more segments
  result. None of `HttpClient`, `System.Text.Json`, `Windows.Storage`, `Task`/`async`,
  `ObservableCollection`, or `INotifyPropertyChanged` is needed: this is a synchronous,
  non-UI-bound, side-effect-free pair of string-parsing utilities with no I/O, no
  asynchronous operation, and no persistence or live-updating collection to bind to.

## Design Decisions

- **Decision**: catch a `URL` parse failure and return the original string rather than
  `null` or letting the exception propagate.
  **Rationale**: not stated in source; recorded here as a fact of the code, per this
  recipe's authoring rules, not a defended choice. The effect is that a caller — for example
  `sync.ts`'s `hostOf(ep.url)` call composing a monitor-retirement reason — always receives a
  usable string even for a URL that fails to parse, at the cost of being unable to
  distinguish a successfully extracted value from a raw fallback.
  **Approved**: pending
- **Decision**: gate `projectPageUrl`'s collapse on an exact hostname match,
  `u.hostname === "vercel.com"`, rather than a suffix or subdomain match.
  **Rationale**: stated in the function's own doc comment — "Vercel inspector URLs are
  `…/<team>/<project>/<deployId>`; drop the deploy id. Other platforms / unrecognised URLs
  pass through unchanged." The comment frames this as intentionally narrow: only the one
  known dashboard-URL shape is rewritten; anything else, including a Vercel-hosted customer
  domain, is left untouched.
  **Approved**: pending
- **Decision**: reconstruct the collapsed URL from only `u.origin` plus the first two path
  segments, discarding every further path segment together with the query string and
  fragment.
  **Rationale**: the doc comment states the intent ("so clicking a project name always lands
  on the same place, regardless of which specific deploy the row is about") and names only
  the deploy id as dropped; the code's actual origin-plus-two-segments construction also
  drops any segment past the second one and any `?query`/`#fragment`, which the comment does
  not call out explicitly — recorded here as an observed behavior beyond what the comment
  states, per this recipe's source-fidelity rules.
  **Approved**: pending
