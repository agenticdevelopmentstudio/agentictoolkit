<!-- leaf: implement-status-web-src-lib-2/url · source: status-web-src-lib-url.md -->

**Rules** (cite as `implement-status-web-src-lib-2/url#<slug>`):

- `host-of-signature` MUST
- `host-of-parsed-host` MUST
- `host-of-non-default-port` MUST
- `host-of-default-port-dropped` MUST
- `host-of-no-path-query-userinfo` MUST
- `host-of-normalized-host` MUST
- `host-of-empty-host` MUST
- `host-of-parse-failure-fallback` MUST
- `host-of-no-throw` MUST
- `host-of-failure-indistinguishable` MUST
- `host-of-pure` MUST
- `host-of-deterministic` MUST
- `host-of-synchronous-single-threaded` MUST
- `caller-empty-fallback` MUST
- `caller-nullish-guard` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `url` | `string` | none (required) | The URL string to reduce to its host. This is the only input. The function reads no environment variables, settings or injected dependencies. |

## Platform Notes

- **SwiftUI**: No SwiftUI API is involved. Port it as a free function or a `String` extension using Foundation's `URL(string:)` (or `URLComponents`), reading `host` and appending `":\(port)"` when `port` is non-nil. Differences: Foundation keeps a port even when it is the default (`:443` stays), does not lowercase the host or convert IDN to Punycode, parses `example.com` as a relative URL with a nil host instead of failing, and returns IPv6 hosts without brackets. To match `hostOf`, return the input when `host` is nil, strip default ports, lowercase, and re-bracket IPv6.
- **Compose**: Use `java.net.URI(url)` inside `try`/`catch (URISyntaxException)` and return `uri.host` plus `":${uri.port}"` when `port != -1`, or `android.net.Uri.parse(url)` (which never throws, so an absent host takes the fallback). `URI` keeps default ports and does not do IDN conversion. Add `java.net.IDN.toASCII` and default-port stripping for parity. Neither API parses `localhost:3000` as a scheme the way WHATWG does, so vector url-009 differs unless the port copies that behavior on purpose.
- **React/Web**: This is the source platform. `packages/web/packages/status-web/src/lib/url.ts` relies on the global WHATWG `URL` constructor available in browsers and Node, and on the bare `catch {}` (optional catch binding) syntax. `URL.canParse` could replace the try/catch where supported. The module is imported directly by components and by `row-detail.ts` and is not part of the package's public exports.
- **AppKit / UIKit**: Same as SwiftUI: `URL(string:)?.host(percentEncoded: false)` (macOS 13 / iOS 16 and later) or `URLComponents(string:)?.host`, with the same default-port, case, IDN and relative-URL differences.
- **WinUI 3**: No XAML control is involved. The port is a static C# method, `static string HostOf(string url) => Uri.TryCreate(url, UriKind.Absolute, out var u) ? u.Authority : url;`. `System.Uri.Authority` already drops userinfo and default ports and lowercases the host, so it is closer to WHATWG than `Uri.Host`, which drops every port. Differences to handle: `Uri.IdnHost` gives the Punycode form (`Authority` returns Unicode unless IDN parsing is enabled). On Windows, `Uri.TryCreate("example.com", UriKind.Absolute, …)` fails as in the source, but a string like `c:\x` parses as a `file` URI. `mailto:` gives a non-empty `Authority` (the address host), unlike WHATWG's empty host, so check `u.Scheme` to reproduce vectors url-010 and url-011. Using `TryCreate` rather than `new Uri` inside `try`/`catch (UriFormatException)` keeps the no-throw guarantee without exceptions on the hot path. For a bound label, call it from an `IValueConverter` or compute it into a view-model property that raises `INotifyPropertyChanged`.

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
