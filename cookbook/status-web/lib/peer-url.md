---
id: ad8ad3fe-e3ba-4c1c-a601-62b1a2c1a3b2
title: Status Web Peer URL
domain: agentictoolkit://cookbook/status-web/lib/peer-url
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The fleet board''s client-side mirror of the backend''s peer base-URL rules:
  a total normalizer to the canonical stored form and an http(s) validity check.'
platforms:
- typescript
- web
tags:
- peers
- fleet
- validation
depends-on:
- agenticdevelopercookbook://guidelines/implementing/security/input-validation
related:
- agentictoolkit://cookbook/status-server/peers
references:
- https://url.spec.whatwg.org/
approved-by: ''
approved-date: ''
---

# Status Web Peer URL

## Overview

`packages/web/packages/status-web/src/lib/peer-url.ts` gives the status board (a
separate Next.js app) the same peer base-URL rules the backend enforces in
`status-server/src/peers/base-url.ts`. It exports two pure functions:

- `normalizePeerBaseUrl(value)` returns the canonical stored form
  `scheme://host[:port][/path]` — lower-cased scheme and host, default port dropped,
  no trailing slash, no query or fragment — and never throws.
- `isValidPeerBaseUrl(value)` reports whether the backend will accept the string: an
  absolute `http:` or `https:` URL.

Its doc comment calls it "a deliberate mirror" of the backend module: the board
cannot import backend code because it has its own build, and the backend stays the
authority, normalizing and validating every write whatever the UI sends. The mirror
only moves feedback earlier. The peer editor (`components/configure/PeersSection.tsx`)
runs its dirty check against the value the server will keep, and shows a typo as a
sentence under the field instead of a 400 response. See
[Status Server Peers](agentictoolkit://cookbook/status-server/peers) for the
authoritative backend contract.

## Behavioral Requirements

### normalizePeerBaseUrl

- **normalize-signature**: `normalizePeerBaseUrl` MUST take one string and return a string synchronously.
- **normalize-trim**: The function MUST trim leading and trailing whitespace from the input before any other processing.
- **normalize-canonical-form**: When the trimmed input parses as an absolute URL, the function MUST return the parsed protocol, then `//`, then the parsed host (hostname plus any non-default port), then the parsed pathname, joined in that order.
- **normalize-lowercase**: When the input parses, the returned scheme and host MUST be lower-case (for example `HTTPS://B.Example.COM` becomes `https://b.example.com`).
- **normalize-default-port**: When the input parses, a port equal to the scheme's default (443 for `https`, 80 for `http`) MUST be dropped from the result.
- **normalize-keep-port**: When the input parses, a non-default port MUST be kept, because it names a different monitor (`http://localhost:3000/` becomes `http://localhost:3000`).
- **normalize-drop-query-fragment**: When the input parses, the query string and fragment MUST NOT appear in the result.
- **normalize-drop-userinfo**: When the input parses, any username or password in the URL MUST NOT appear in the result, because only the host (not the userinfo) is copied into the output.
- **normalize-keep-path**: When the input parses, a non-root path MUST be kept (`https://b.example.com/status/` becomes `https://b.example.com/status`).
- **normalize-strip-trailing-slashes**: The result MUST have every trailing `/` character removed, whether one or many (`https://b.example.com///` becomes `https://b.example.com`).
- **normalize-total**: The function MUST NOT throw for any string input. When the trimmed input does not parse as an absolute URL, it MUST return the trimmed input with trailing slashes removed and no other change (no lower-casing). The doc comment states why: the editor normalizes on every keystroke, "long before what is typed is a URL at all".
- **normalize-idempotent**: Applying the function to its own output for an http(s) input MUST return the same string, since the canonical form has no trailing slash, default port, query or fragment left to fold.

### isValidPeerBaseUrl

- **valid-signature**: `isValidPeerBaseUrl` MUST take one string and return a boolean synchronously.
- **valid-trim**: The function MUST trim leading and trailing whitespace before parsing, so `  https://b.example.com/ ` is valid.
- **valid-http-https**: The function MUST return `true` when the trimmed input parses as an absolute URL whose protocol is exactly `http:` or `https:`.
- **valid-other-scheme**: The function MUST return `false` for any other parsed scheme, including `ftp:`, `javascript:` and `file:`.
- **valid-unparseable**: The function MUST return `false`, not throw, when the trimmed input does not parse as an absolute URL, including a bare host, a relative path and the empty string.
- **valid-no-normalize-required**: The function MUST accept a valid URL that is not yet in canonical form (a trailing slash, upper-case host or default port does not make it invalid).

### Contract-wide

- **pure-functions**: Both functions MUST be free of side effects: no network, storage, logging, or global state, and the result depends only on the argument.
- **no-self-or-duplicate-check**: The module MUST NOT offer same-URL comparison, self-peer detection, duplicate-error detection or a duplicate-message constant. The backend module also exports `isSamePeerBaseUrl`, `isSelfPeerUrl`, `DUPLICATE_PEER_MESSAGE` and `isDuplicatePeerError`; the web mirror copies only the normalize and validate rules, so those conflicts reach the board as backend responses.
- **backend-parity**: The two exported functions MUST return the same result as the backend functions of the same name for every input. The module's doc comment requires the two files to be kept in step, and `peer-url.test.ts` asserts the backend's cases.
- **backend-authority**: The board MUST NOT treat a `true` result from `isValidPeerBaseUrl` as acceptance. The backend (`createPeer`/`updatePeer` and the `peerInsert` schema in status-server) validates and normalizes every write again, and its answer is the one that counts.
- **concurrency**: Both functions are synchronous and run on the single JavaScript thread, so calls cannot interleave and need no ordering rule.

## Appearance

Not applicable — this is a pure URL-normalization and validation module, not a visual component.

## States

Not applicable — this is a pure URL-normalization and validation module, not a visual component.

## Accessibility

Not applicable — this is a pure URL-normalization and validation module, not a visual component.

## Conformance Test Vectors

Vectors 001–015 come from `peer-url.test.ts`. Vectors 016–018 follow from the code and WHATWG URL parsing.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| peer-url-001 | normalize-trim, normalize-strip-trailing-slashes | `normalizePeerBaseUrl("  https://b.example.com/// ")` | `"https://b.example.com"` |
| peer-url-002 | normalize-canonical-form, normalize-idempotent | `normalizePeerBaseUrl("https://b.example.com")` | `"https://b.example.com"` |
| peer-url-003 | normalize-keep-path | `normalizePeerBaseUrl("https://b.example.com/status/")` | `"https://b.example.com/status"` |
| peer-url-004 | normalize-lowercase | `normalizePeerBaseUrl("HTTPS://B.Example.COM")` | `"https://b.example.com"` |
| peer-url-005 | normalize-default-port | `normalizePeerBaseUrl("https://b.example.com:443")` | `"https://b.example.com"` |
| peer-url-006 | normalize-default-port | `normalizePeerBaseUrl("http://b.example.com:80")` | `"http://b.example.com"` |
| peer-url-007 | normalize-drop-query-fragment | `normalizePeerBaseUrl("https://b.example.com/?x=1#frag")` | `"https://b.example.com"` |
| peer-url-008 | normalize-keep-port | `normalizePeerBaseUrl("http://localhost:3000/")` | `"http://localhost:3000"` |
| peer-url-009 | normalize-total | `normalizePeerBaseUrl("  b.example.com/ ")` | `"b.example.com"`, no exception |
| peer-url-010 | valid-http-https | `isValidPeerBaseUrl("https://b.example.com")` | `true` |
| peer-url-011 | valid-http-https | `isValidPeerBaseUrl("http://localhost:3000")` | `true` |
| peer-url-012 | valid-trim, valid-no-normalize-required | `isValidPeerBaseUrl("  https://b.example.com/ ")` | `true` |
| peer-url-013 | valid-unparseable | `isValidPeerBaseUrl("b.example.com")`, `isValidPeerBaseUrl("/relative")`, `isValidPeerBaseUrl("")` | `false` each, no exception |
| peer-url-014 | valid-other-scheme | `isValidPeerBaseUrl("ftp://b.example.com")` | `false` |
| peer-url-015 | valid-other-scheme | `isValidPeerBaseUrl("javascript:alert(1)")`, `isValidPeerBaseUrl("file:///etc/passwd")` | `false` each |
| peer-url-016 | normalize-drop-userinfo | `normalizePeerBaseUrl("https://user:pw@b.example.com/")` | `"https://b.example.com"` |
| peer-url-017 | normalize-total | `normalizePeerBaseUrl("")` | `""` |
| peer-url-018 | normalize-total | `normalizePeerBaseUrl("B.Example.COM/")` (unparseable) | `"B.Example.COM"`, case unchanged |

## Edge Cases

- **Empty or whitespace-only input**: `normalizePeerBaseUrl` MUST return `""`, and `isValidPeerBaseUrl` MUST return `false`. The editor treats an empty normalized value as "not yet typed" and shows no invalid message (`PeersSection.tsx` sets `urlInvalid` only when the normalized URL is non-empty).
- **Half-typed input** (`https:/`, `b.exa`): `normalizePeerBaseUrl` MUST fall back to trim and strip without throwing, and `isValidPeerBaseUrl` MUST return `false` until the text parses as an absolute http(s) URL.
- **Valid but un-canonical input**: `isValidPeerBaseUrl` MUST judge the typed string, not the normalized one. The editor validates `draft.baseUrl` as typed, and validation trims internally.
- **Non-http scheme that parses** (`javascript:alert(1)`, `mailto:a@b`): `normalizePeerBaseUrl` MUST still return a string built from the parsed parts. For an opaque URL with no host this puts `//` after the scheme (`javascript:alert(1)` becomes `javascript://alert(1)`). `isValidPeerBaseUrl` rejects these inputs, so the result is never stored.
- **Credentials in the URL**: `normalizePeerBaseUrl` MUST drop the userinfo (normalize-drop-userinfo). A peer URL that needs embedded credentials cannot round-trip through the canonical form.
- **Only trailing slashes** (`"///"`): the input does not parse, so the fallback MUST return `""`.
- **Divergence from the backend**: if one copy of the rules changes without the other, the board's dirty check and inline message disagree with the server. The server's answer MUST win (backend-authority). The only guard against drift is the shared test cases.
- **Concurrent access**: not applicable. Both functions are synchronous and pure on single-threaded JavaScript.
- **Error states and offline**: not applicable. The module does no I/O, so no dependency can fail and connectivity does not matter.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `value` | `string` | — (required) | The URL text to normalize or validate. The only input to either function. |

The module reads no environment variables, settings or injected dependencies.

## Deep Linking

Not applicable: the module is a pair of pure string functions and exposes no route or URL of its own.

## Localization

Not applicable: neither function returns or formats user-facing text. The inline error sentence belongs to `PeersSection.tsx`, not this module.

## Accessibility Options

Not applicable: the module has no visual output for display options to affect.

## Feature Flags

Not applicable: neither function reads a flag or has a conditional code path beyond the URL-parse fallback.

## Analytics

Not applicable: the module emits no events.

## Privacy

Not applicable: the module stores and transmits nothing. It returns a derived string to the caller, and normalization drops any userinfo credentials from that string (normalize-drop-userinfo).

## Logging

Not applicable: neither function logs. A parse failure is an expected path, turned into the fallback string or `false` rather than an error.

## Platform Notes

- **SwiftUI**: Use Foundation `URLComponents(string:)` on the trimmed string (`trimmingCharacters(in: .whitespacesAndNewlines)`). Unlike WHATWG `URL`, it does not lower-case the host or drop a default port, so lower-case `scheme` and `host` yourself, set `port = nil` when it equals 80/443 for the scheme, and clear `query`, `fragment`, `user` and `password`. It also accepts relative strings, so validity has to check `scheme` is `http`/`https` and `host` is non-empty. Keep the functions `nonisolated` and pure.
- **Compose**: Use `java.net.URI` (or OkHttp's `HttpUrl.parse`, which does lower-case and drop default ports) in a Kotlin top-level function. `URI` throws `URISyntaxException`, so catch it to keep normalize total and validity boolean. Check `uri.isAbsolute` and the scheme set explicitly. Strip trailing slashes with `trimEnd('/')`.
- **React/Web**: Source platform. `packages/web/packages/status-web/src/lib/peer-url.ts` holds the two functions, using the global WHATWG `URL` constructor, which throws on unparseable input. `peer-url.test.ts` (vitest) holds the shared cases. `components/configure/PeersSection.tsx` is the only consumer: it normalizes on every keystroke for the dirty check and validates the typed draft. It mirrors, but does not import, `status-server/src/peers/base-url.ts`.
- **AppKit / UIKit**: Same Foundation `URLComponents` approach as SwiftUI. Run it from an `NSTextField`/`UITextField` editing-changed handler to get the same per-keystroke feedback. No framework-specific differences.
- **WinUI 3**: Use `System.Uri.TryCreate(trimmed, UriKind.Absolute, out var uri)` in a static C# helper. It returns `false` instead of throwing, which fits validity directly. `uri.Scheme` and `uri.Host` are already lower-case, and `uri.IsDefaultPort` tells you when to omit the port. Build the result from `uri.Scheme + "://" + uri.Authority + uri.AbsolutePath` and then `.TrimEnd('/')`. `Authority` includes a non-default port and leaves out userinfo, query and fragment. Two differences from the source to watch: .NET treats a rooted path such as `/relative` as an absolute `file://` URI on some platforms, and the explicit http/https check rejects it. `Uri` may also unescape or re-escape path characters differently from WHATWG. Call it from a `TextBox.TextChanged` handler, or from the setter of a view-model property on an `INotifyPropertyChanged` view model, to drive a validation message.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/lib/peer-url.ts` |

## Design Decisions

**Decision**: Duplicate the backend's normalize and validate rules in the board, not share a module.
**Rationale**: The module doc comment says the board "is a separate Next app with its own build, so it cannot import the backend's module". Duplicating moves feedback earlier (the dirty check, and an inline sentence instead of a 400), while the backend stays the authority on every write.
**Approved**: pending

**Decision**: Make `normalizePeerBaseUrl` total, falling back to trim plus trailing-slash strip.
**Rationale**: The editor normalizes on every keystroke, "long before what is typed is a URL at all", so throwing or returning a sentinel would break the dirty check while the user types.
**Approved**: pending

**Decision**: Let WHATWG `URL` parsing do the canonical folding (case, default port) instead of hand-written rules.
**Rationale**: The inline comment says this "is what keeps `https://Lewis.example.com:443/` from becoming a second peer row". The backend's unique index on `base_url` is byte-exact, so every variation that names the same monitor has to fold to one string.
**Approved**: pending

**Decision**: Mirror only normalize and validate. Leave out the self-peer and duplicate checks.
**Rationale**: Those checks need server state (`config.publicBaseUrl`, the store's unique index), which the board does not hold. The backend reports those conflicts in its responses.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | passed | Security |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |

The module is two pure functions kept separate from the editor UI, and `peer-url.test.ts`
covers every normalize and validate rule. The only parse failure, a thrown `URL`
constructor, is caught and turned into a documented result (the fallback string or
`false`), so no error goes unhandled. The validator allows only `http:` and `https:`,
which rejects `javascript:` and `file:` input before it reaches the server. Data
integrity is partial for two reasons. The client rules are a hand-kept copy of the
backend's, and nothing but matching test cases stops the two from drifting. And the
backend, not this module, is what actually guarantees one row per monitor.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial recipe extracted from `status-web/src/lib/peer-url.ts` and its tests |
