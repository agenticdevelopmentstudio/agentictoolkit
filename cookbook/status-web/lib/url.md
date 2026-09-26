---
id: 9ab21212-c31d-4a4a-b563-2a2666eec03d
title: Status Web URL Host
domain: agentictoolkit://cookbook/status-web/lib/url
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: hostOf extracts the WHATWG URL host from a string and returns the input unchanged
  when it does not parse as an absolute URL
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://cookbook/status-web/src
- agentictoolkit://cookbook/status-web/lib/row-detail
- agentictoolkit://cookbook/status-web/lib/stale-monitors
references:
- https://url.spec.whatwg.org/#dom-url-host
approved-by: ''
approved-date: ''
---

# Status Web URL Host

## Overview

`url.ts` in `packages/web/packages/status-web/src/lib/` exports one pure function, `hostOf(url: string): string`. It parses the argument with the WHATWG `URL` constructor and returns the parsed `host` (hostname plus a non-default port). If the constructor throws, the function catches the error and returns the original string unchanged.

The status board uses it to turn a monitored endpoint's URL into a short display label or a site name. Callers include `row-detail.ts` (the endpoint row title), `StatusRow`, `StatusMatrix`, `Dashboard`, `StaleMonitorsBanner`, `UnconfiguredProjectsBanner`, and the configure screens `ProjectBrowser` and `EndpointsSection`. `EndpointsSection` uses the result as the name of a new site and as the input to `slugify` for its slug. The module is not re-exported from the package entry point `src/index.ts`, so it is internal to status-web.

## Behavioral Requirements

### Operation

- **host-of-signature**: `hostOf` MUST take exactly one string argument and MUST return a string synchronously.
- **host-of-parsed-host**: When the argument parses as an absolute URL, `hostOf` MUST return that URL's WHATWG `host` value.
- **host-of-non-default-port**: When the parsed URL carries a port that is not its scheme's default, the result MUST include `:` and that port (for example `example.com:8443`).
- **host-of-default-port-dropped**: When the parsed URL carries its scheme's default port (443 for `https`, 80 for `http`), the result MUST omit the port.
- **host-of-no-path-query-userinfo**: The result MUST NOT contain the scheme, userinfo, path, query or fragment of the input.
- **host-of-normalized-host**: For special schemes (`http`, `https`, `ws`, `wss`, `ftp`), the result MUST be the parser-normalized host: ASCII-lowercased, with an internationalized domain converted to its Punycode (`xn--`) form, and with an IPv6 literal kept in brackets.
- **host-of-empty-host**: When the argument parses as an absolute URL whose host is empty (for example `mailto:`, `file:///`, or a bare `name:port` string that parses as scheme `name:`), `hostOf` MUST return the empty string rather than the input.
- **host-of-parse-failure-fallback**: When the argument does not parse as an absolute URL (for example a bare domain `example.com`, a relative path, or the empty string), `hostOf` MUST return the argument unchanged.
- **host-of-no-throw**: `hostOf` MUST NOT throw for any string argument; every parse error MUST be caught inside the function.
- **host-of-failure-indistinguishable**: The return value MUST NOT signal whether the fallback was taken. A caller receives the same kind of string for a parsed host and for an unparseable input, and the source offers no second channel. The fallback is a deliberate lossy projection for display.

### Side effects, state and concurrency

- **host-of-pure**: `hostOf` MUST have no side effects. It MUST NOT perform network, storage or DOM access, logging, or mutation of shared state.
- **host-of-deterministic**: `hostOf` MUST return the same output for the same input on every call.
- **host-of-synchronous-single-threaded**: `hostOf` runs synchronously on the calling JavaScript thread and keeps no state between calls, so concurrent callers cannot interleave. It MUST NOT introduce any ordering dependency between calls.

### Caller contract

- **caller-empty-fallback**: Because a parsed URL with an empty host yields `""`, callers that need a non-empty label MUST supply their own fallback. `StaleMonitorsBanner` and `UnconfiguredProjectsBanner` do this with `hostOf(url) || url`, and `siteUrlLabel` in `EndpointsSection` falls back to the URL or `"(no url)"`.
- **caller-nullish-guard**: The type signature accepts only `string`. Callers holding an optional URL MUST coalesce it before the call, as `ProjectBrowser` does with `hostOf(endpoint.url ?? "")`.

## Appearance

Not applicable — this is a pure URL-parsing helper, not a visual component.

## States

Not applicable — this is a pure URL-parsing helper, not a visual component.

## Accessibility

Not applicable — this is a pure URL-parsing helper, not a visual component.

## Conformance Test Vectors

These vectors follow the WHATWG URL parsing behavior that `hostOf` delegates to. They were checked against Node's `URL` implementation. The source has no test file of its own (there is no `url.test.ts`).

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| url-001 | host-of-parsed-host, host-of-no-path-query-userinfo | `"https://adh.app/health?x=1#top"` | `"adh.app"` |
| url-002 | host-of-non-default-port, host-of-normalized-host | `"https://Example.COM:8443/a?b"` | `"example.com:8443"` |
| url-003 | host-of-default-port-dropped | `"https://example.com:443/"` | `"example.com"` |
| url-004 | host-of-no-path-query-userinfo | `"http://user:pw@host.test/"` | `"host.test"` |
| url-005 | host-of-normalized-host | `"https://bücher.de/"` | `"xn--bcher-kva.de"` |
| url-006 | host-of-normalized-host, host-of-non-default-port | `"http://[::1]:8080/"` | `"[::1]:8080"` |
| url-007 | host-of-parse-failure-fallback, host-of-no-throw | `"example.com"` | `"example.com"` (returned unchanged, no exception) |
| url-008 | host-of-parse-failure-fallback, host-of-no-throw | `""` | `""` (returned unchanged, no exception) |
| url-009 | host-of-empty-host | `"localhost:3000"` | `""` (parses as scheme `localhost:` with an empty host) |
| url-010 | host-of-empty-host | `"mailto:a@b.c"` | `""` |
| url-011 | host-of-empty-host | `"file:///tmp/x"` | `""` |
| url-012 | host-of-parsed-host | `"  https://a.test  "` | `"a.test"` (the parser strips leading and trailing spaces) |
| url-013 | host-of-deterministic, host-of-pure | Call `"https://adh.app"` twice | Both calls return `"adh.app"`, and no global state changes |
| url-014 | host-of-failure-indistinguishable | `"not a url"` and `"https://not-a-url.test"` | `"not a url"` and `"not-a-url.test"`: both are plain strings, with no flag or exception telling the caller which one fell back |

## Edge Cases

- **Empty string**: `new URL("")` throws, so the function MUST return `""` (url-008).
- **Bare domain with no scheme**: `example.com` is not an absolute URL, so the function MUST return it unchanged, which makes it read like a host (url-007).
- **Host and port with no scheme**: `localhost:3000` parses as an absolute URL with scheme `localhost:` and an empty host, so the function MUST return `""`, not `localhost:3000` (url-009). Callers without a `||` fallback then render an empty label.
- **Non-special schemes**: `mailto:`, `file:` and similar URLs with no authority MUST yield `""` (url-010, url-011).
- **Surrounding whitespace**: The parser strips leading and trailing ASCII spaces and C0 controls, so a padded absolute URL MUST still yield its host (url-012). `EndpointsSection.save` also calls `trim()` before `hostOf`.
- **Mixed case and IDN**: Special-scheme hosts MUST be returned lowercased and in Punycode form (url-002, url-005). Unparseable input comes back with its original case, which is why `ProjectBrowser` applies its own `toLowerCase()`.
- **Nullish input**: The signature forbids `null` and `undefined`. `new URL(undefined)` would throw and the catch would return `undefined`, but callers coalesce first (caller-nullish-guard).
- **Concurrent access**: Not applicable. The function is synchronous, stateless and runs on the single JavaScript thread.
- **Error states**: Parse failure is the only error. It is caught and turned into the unchanged-input fallback (host-of-parse-failure-fallback). The function has no other dependency that can fail.
- **Offline or disconnected state**: Not applicable. Parsing is local and makes no network access.
- **Very long input**: The source sets no length limit and does no truncation. The function MUST return whatever the `URL` parser produces, or the input unchanged.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `url` | `string` | none (required) | The URL string to reduce to its host. This is the only input. The function reads no environment variables, settings or injected dependencies. |

## Deep Linking

Not applicable: `hostOf` only parses a string and never registers or handles a route.

## Localization

Not applicable: `hostOf` returns parser output or its own input and contains no user-facing strings.

## Accessibility Options

Not applicable: `hostOf` renders nothing, so no display option affects it.

## Feature Flags

Not applicable: `hostOf` reads no flag and always runs the same code path.

## Analytics

Not applicable: `hostOf` emits no events.

## Privacy

Not applicable: `hostOf` collects, stores and sends nothing. It drops any userinfo in the input (url-004), and the unchanged-input fallback never leaves the calling component.

## Logging

Not applicable: `hostOf` has no logging calls. The caught parse error is turned into the fallback value and is not logged.

## Platform Notes

- **SwiftUI**: No SwiftUI API is involved. Port it as a free function or a `String` extension using Foundation's `URL(string:)` (or `URLComponents`), reading `host` and appending `":\(port)"` when `port` is non-nil. Differences: Foundation keeps a port even when it is the default (`:443` stays), does not lowercase the host or convert IDN to Punycode, parses `example.com` as a relative URL with a nil host instead of failing, and returns IPv6 hosts without brackets. To match `hostOf`, return the input when `host` is nil, strip default ports, lowercase, and re-bracket IPv6.
- **Compose**: Use `java.net.URI(url)` inside `try`/`catch (URISyntaxException)` and return `uri.host` plus `":${uri.port}"` when `port != -1`, or `android.net.Uri.parse(url)` (which never throws, so an absent host takes the fallback). `URI` keeps default ports and does not do IDN conversion. Add `java.net.IDN.toASCII` and default-port stripping for parity. Neither API parses `localhost:3000` as a scheme the way WHATWG does, so vector url-009 differs unless the port copies that behavior on purpose.
- **React/Web**: This is the source platform. `packages/web/packages/status-web/src/lib/url.ts` relies on the global WHATWG `URL` constructor available in browsers and Node, and on the bare `catch {}` (optional catch binding) syntax. `URL.canParse` could replace the try/catch where supported. The module is imported directly by components and by `row-detail.ts` and is not part of the package's public exports.
- **AppKit / UIKit**: Same as SwiftUI: `URL(string:)?.host(percentEncoded: false)` (macOS 13 / iOS 16 and later) or `URLComponents(string:)?.host`, with the same default-port, case, IDN and relative-URL differences.
- **WinUI 3**: No XAML control is involved. The port is a static C# method, `static string HostOf(string url) => Uri.TryCreate(url, UriKind.Absolute, out var u) ? u.Authority : url;`. `System.Uri.Authority` already drops userinfo and default ports and lowercases the host, so it is closer to WHATWG than `Uri.Host`, which drops every port. Differences to handle: `Uri.IdnHost` gives the Punycode form (`Authority` returns Unicode unless IDN parsing is enabled). On Windows, `Uri.TryCreate("example.com", UriKind.Absolute, …)` fails as in the source, but a string like `c:\x` parses as a `file` URI. `mailto:` gives a non-empty `Authority` (the address host), unlike WHATWG's empty host, so check `u.Scheme` to reproduce vectors url-010 and url-011. Using `TryCreate` rather than `new Uri` inside `try`/`catch (UriFormatException)` keeps the no-throw guarantee without exceptions on the hot path. For a bound label, call it from an `IValueConverter` or compute it into a view-model property that raises `INotifyPropertyChanged`.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/lib/url.ts` |

## Design Decisions

**Decision**: A parse failure returns the input unchanged instead of an empty string or `null`.
**Rationale**: The result is a display label. Handing back the raw string means a URL typed without a scheme (`example.com`) still shows something readable in `StatusMatrix`, `Dashboard` and the other row titles, and the `string` return type needs no null handling at call sites.
**Approved**: pending

**Decision**: The function returns WHATWG `host` (with a non-default port) rather than `hostname`.
**Rationale**: `host` keeps the port, so two endpoints on the same machine with different ports get different labels and different site names and slugs in `EndpointsSection`.
**Approved**: pending

**Decision**: A parsed URL with an empty host returns `""`, not the input.
**Rationale**: The function returns `new URL(url).host` verbatim whenever parsing succeeds and applies the fallback only to thrown errors. Callers that need a non-empty label add `|| url` themselves (caller-empty-fallback).
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | failed | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | best-practices |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | reliability |

**Separation of concerns.** The module is one pure parsing function with no React, DOM or I/O. Presentation choices, such as empty-label fallbacks and lowercasing, stay with the calling components.

**Unit test coverage.** There is no `url.test.ts`. `row-detail.test.ts` reaches `hostOf` only indirectly through `rowDetail` titles, and no test asserts the fallback, empty-host or port behavior.

**Explicit error handling.** The parse error is caught on purpose and mapped to a documented fallback, so nothing throws. The catch is bare, though: the error is dropped without logging, and the return value cannot tell a caller whether parsing failed (host-of-failure-indistinguishable).

**Graceful degradation.** Unparseable input still produces a usable label (the original string) instead of an exception or a blank, so board rows render when a URL is malformed.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation from `status-web/src/lib/url.ts` |
