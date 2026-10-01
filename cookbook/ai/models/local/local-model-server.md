---
id: ff1089d7-170c-4658-91c6-e3946710b29f
title: Local Model Server
domain: agentictoolkit://cookbook/ai/models/local/local-model-server
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A stateless helper for loopback-host detection, Ollama's native /api/tags
  URL derivation, and tolerant model-size parsing.
platforms:
- swift
- macos
tags:
- local-model
- ollama
depends-on: []
related: []
references:
- packages/apple/AgenticToolkit/AIPluginKit/LocalModelServer.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AIPluginKitTests/LocalModelServerTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/AIPluginKit/LocalModelCatalog.swift (agentictoolkit)
- packages/apple/AgenticToolkit/AIPluginKit/LocalProviderModelStore.swift (agentictoolkit)
- packages/apple/AgenticToolkit/AIPluginKit/DaemonAIChat.swift (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Local Model Server

## Overview

The model server helper is a **logic** component — no visual surface — a
stateless namespace holding four functions. Its purpose, stated directly by
its own documentation: it is shared by the inference guard and hosts' model
pickers so loopback detection, the native-API URL derivation, and
`/api/tags` size parsing cannot drift between call sites. Concretely, three
independent concerns that a local (loopback) OpenAI-compatible model server
touches are centralized here: (1) loopback detection decides whether a
configured base URL points at this machine; (2) native tags URL derivation
derives Ollama's native `/api/tags` listing URL from an OpenAI-compatible
base URL, because that native endpoint is the only one that reports a
model's on-disk size; (3) the response parser and size resolver decode that
endpoint's response into a model → size bytes map and look up one model in
it, tolerating the `:latest` shorthand. Direct callers include a
local-inference guard (loopback detection, to decide whether the guard
applies to a request), the model catalog and a local provider model store
(native tags URL derivation, response parsing, and size resolution, to
populate and query a model-size cache), and, one layer up the call chain, a
model-chooser settings surface. Unlike its stateful sibling the model
catalog (a time-to-live cache), the model server helper holds no state at
all beyond a fixed set of loopback host literals — every requirement below
is a pure function of its arguments, which is why this recipe is smaller
than a stateful sibling of the same family.

## Behavioral Requirements

- **namespace-shape**: The model server helper MUST be a stateless namespace
  with no case and only shared members, so it functions as an
  uninstantiable namespace rather than a value or reference type with
  instance state.
- **concurrency-safety**: Every one of the model server helper's four
  functions MUST be callable concurrently, from any execution context,
  without external synchronization. The helper carries no case, no stored
  instance property, and no instance is ever constructed or passed
  anywhere — the only stored value, the loopback host set, is immutable and
  computed once, so there is no mutable state for a concurrent call to race
  against.
- **synchronous-non-throwing**: None of loopback detection, native tags URL
  derivation, the response parser, or the size resolver MUST be
  asynchronous or fallible in a way that suspends or interrupts the caller;
  each MUST execute synchronously and return its result (a yes/no, an
  optional URL, a map of sizes, or an optional integer size) directly,
  including when its input is malformed.
- **no-side-effects**: The model server helper's four functions MUST perform
  no file-system access, network request, process launch, or notification;
  each MUST compute its result purely from its arguments (and, for native
  tags URL derivation and the response parser, from standard URL and data
  parsing applied to that input).
- **loopback-hosts-literal-set**: The loopback host set MUST contain exactly
  these five string literals, and no others: `"localhost"`, `"127.0.0.1"`,
  `"0.0.0.0"`, `"::1"`, `"[::1]"`.
- **is-loopback-host-extraction**: Loopback detection MUST parse the base
  URL and read its host component as the candidate to test.
- **is-loopback-case-insensitive-compare**: Loopback detection MUST
  lowercase the extracted host before comparing it against the loopback
  host set.
- **is-loopback-membership-result**: Loopback detection MUST return true if
  and only if the lowercased host is a member of the loopback host set, and
  false otherwise.
- **is-loopback-unparseable-false**: Loopback detection MUST return false
  when the base URL cannot be parsed, or the parsed URL has no host
  component (covers an empty base URL and a scheme-less string such as
  `"localhost:11434"`, whose host cannot be determined).
- **native-tags-url-whitespace-trim**: Native tags URL derivation MUST trim
  leading and trailing whitespace from the base URL before any other
  processing.
- **native-tags-url-strip-trailing-slashes-first-pass**: Native tags URL
  derivation MUST repeatedly strip a trailing `"/"` character from the
  trimmed string until none remains, before checking for a `"/v1"` suffix.
- **native-tags-url-strip-v1-suffix**: Native tags URL derivation MUST strip
  one trailing three-character `"/v1"` suffix, compared case-insensitively,
  from the string produced by the first slash-stripping pass.
- **native-tags-url-strip-trailing-slashes-second-pass**: Native tags URL
  derivation MUST repeatedly strip a trailing `"/"` character again after
  the `"/v1"` suffix has been removed, until none remains.
- **native-tags-url-empty-yields-nil**: Native tags URL derivation MUST
  return nothing when the fully-trimmed string is empty.
- **native-tags-url-append-and-construct**: Native tags URL derivation MUST
  append the literal path `"/api/tags"` to the fully-trimmed, non-empty
  string and construct the resulting URL; it MUST return nothing if that
  construction fails.
- **parse-sizes-decode-shape**: The response parser MUST decode the
  response body as data matching the shape `{"models": [{"name": string or
  absent, "model": string or absent, "size": integer or absent}, ...]}`.
- **parse-sizes-whole-decode-failure-empty**: The response parser MUST
  return an empty map when the top-level response does not match that shape
  at all (malformed data, or a missing/wrong-typed `models` key).
- **parse-sizes-per-element-tolerance**: The response parser MUST decode
  each element of the `models` array individually, so that one element
  failing to decode MUST be dropped without causing any other element in the
  array to be dropped.
- **parse-sizes-missing-size-excluded**: The response parser MUST exclude a
  decoded entry from the returned map under any key when that entry's
  `size` field is absent.
- **parse-sizes-dual-key-indexing**: The response parser MUST store a
  decoded entry's `size` under its `name` key when `name` is present, and
  MUST independently store the same `size` value under its `model` key when
  `model` is present; an entry with both fields present MUST be indexed
  under both keys.
- **parse-sizes-neither-key-excluded**: The response parser MUST exclude a
  decoded entry from the returned map entirely when it has neither a `name`
  nor a `model` value, regardless of whether `size` is present.
- **parse-sizes-array-order-last-write-wins**: When two entries in `models`
  produce the same map key (through either their `name` or `model` field),
  the response parser MUST resolve the collision to the value of whichever
  entry is later in the `models` array — ordinary last-write-wins map
  assignment — with no de-duplication or validation against the collision.
- **size-of-exact-match**: The size resolver MUST return the stored size
  when the sizes map contains that exact model key.
- **size-of-latest-fallback**: The size resolver MUST return the size stored
  under the model name suffixed with `":latest"` when the exact model key is
  absent from the sizes map and the `":latest"`-suffixed key is present.
- **size-of-total-miss-nil**: The size resolver MUST return nothing when
  neither the exact model key nor the `":latest"`-suffixed key is present in
  the sizes map.

## Appearance

Not applicable — this is a stateless helper namespace, not a visual
component.

## States

Not applicable — this is a stateless helper namespace, not a visual
component.

## Accessibility

Not applicable — this is a stateless helper namespace, not a visual
component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| LMS-001 | is-loopback-host-extraction, is-loopback-case-insensitive-compare, is-loopback-membership-result | Check loopback for base URL `http://localhost:11434/v1` and for `http://127.0.0.1:11434/v1` | Both return true |
| LMS-002 | is-loopback-membership-result | Check loopback for base URL `https://api.anthropic.com/v1` | Returns false |
| LMS-003 | is-loopback-unparseable-false | Check loopback for an empty base URL | Returns false |
| LMS-004 | is-loopback-unparseable-false | Check loopback for base URL `localhost:11434` (no scheme prefix) | Returns false; without a scheme and authority marker, no host can be determined |
| LMS-005 | native-tags-url-strip-v1-suffix, native-tags-url-append-and-construct | Derive the native tags URL for base URL `http://localhost:11434/v1` | Result is `http://localhost:11434/api/tags` |
| LMS-006 | native-tags-url-strip-trailing-slashes-first-pass, native-tags-url-strip-v1-suffix, native-tags-url-strip-trailing-slashes-second-pass | Derive the native tags URL for base URL `http://localhost:11434/v1/` | Result is `http://localhost:11434/api/tags` |
| LMS-007 | native-tags-url-append-and-construct | Derive the native tags URL for base URL `http://localhost:11434` (no `/v1` suffix at all) | Result is `http://localhost:11434/api/tags` |
| LMS-008 | native-tags-url-whitespace-trim, native-tags-url-empty-yields-nil | Derive the native tags URL for an empty base URL | Returns nothing |
| LMS-009 | native-tags-url-strip-v1-suffix | Derive the native tags URL for base URL `http://localhost:11434/V1` (uppercase suffix) | Result is `http://localhost:11434/api/tags`, because the suffix comparison is case-insensitive |
| LMS-010 | parse-sizes-dual-key-indexing, parse-sizes-missing-size-excluded, size-of-exact-match, size-of-latest-fallback | Parse the response body `{"models":[{"name":"llama3.1:8b","model":"llama3.1:8b","size":4920000000},{"name":"qwen3-coder-next:latest","size":51000000000},{"name":"broken-no-size"}]}`, then resolve the size for model `qwen3-coder-next` and for `llama3.1:8b` | The parsed sizes are `llama3.1:8b -> 4_920_000_000`, `qwen3-coder-next:latest -> 51_000_000_000`; `broken-no-size` is excluded (no size). Resolving `qwen3-coder-next` returns `51_000_000_000` (via the `:latest` fallback); resolving `llama3.1:8b` returns `4_920_000_000` (exact match) |
| LMS-011 | parse-sizes-whole-decode-failure-empty | Parse the response body `not json` | Returns an empty map |
| LMS-012 | parse-sizes-per-element-tolerance | Parse a response with three entries where the middle one has wrong-typed `name`/`size` fields and the other two are well-formed | Returns a map with exactly the two well-formed entries; the middle entry is dropped without discarding the other two |
| LMS-013 | size-of-total-miss-nil | Resolve the size for model `nonexistent` against an empty map | Returns nothing |
| LMS-014 | parse-sizes-neither-key-excluded | Parse the response body `{"models":[{"size":100}]}` (an entry with `size` but neither `name` nor `model`) | Returns an empty map |
| LMS-015 | parse-sizes-array-order-last-write-wins | Parse the response body `{"models":[{"name":"m","size":1},{"model":"m","size":2}]}` (two distinct entries whose `name`/`model` fields collide on the same string `m`) | Returns `{"m": 2}` — the later entry's value overwrites the earlier one under the shared key |

## Edge Cases

- **Empty base URL to loopback detection.** Loopback detection with an
  empty base URL MUST return false — parsing fails to yield a host
  (is-loopback-unparseable-false).
- **Scheme-less base URL to loopback detection.** A base URL with no
  `http://` or `https://` prefix (e.g. `"localhost:11434"`) parses with no
  host, so loopback detection MUST return false even though a human reader
  would recognize the string as local (is-loopback-unparseable-false).
- **Base URL that trims to empty for native tags URL derivation.** A base
  URL such as `"/v1"` or `"///"` reduces, through the slash- and
  `/v1`-stripping passes, to an empty string, and native tags URL derivation
  MUST return nothing — the same outcome as a literally empty base URL
  (native-tags-url-empty-yields-nil).
- **Repeated trailing slashes.** A base URL such as
  `"http://localhost:11434/v1////"` MUST resolve to
  `"http://localhost:11434/api/tags"`; both stripping passes loop until no
  trailing slash remains, so any number of trailing slashes is removed, not
  just one (native-tags-url-strip-trailing-slashes-first-pass,
  native-tags-url-strip-trailing-slashes-second-pass).
- **Mixed-case `/v1` suffix.** `"http://localhost:11434/V1"` MUST also strip
  to `"http://localhost:11434/api/tags"`, because the suffix check is
  case-insensitive (native-tags-url-strip-v1-suffix).
- **Malformed data to the response parser.** Non-JSON bytes (e.g. `"not
  json"`) MUST yield an empty map, not a thrown error or a crash
  (parse-sizes-whole-decode-failure-empty).
- **Well-formed data, wrong top-level shape.** A response that is valid but
  does not contain a `models` array at all (e.g. `{}` or `{"models": {}}`)
  MUST also yield an empty map, because the outer shape fails to match
  (parse-sizes-whole-decode-failure-empty).
- **Partially malformed entries.** An entry array where some elements have
  wrong-typed fields MUST retain the well-formed elements and drop only the
  malformed ones, per element, rather than discarding the whole listing
  (parse-sizes-per-element-tolerance).
- **Colliding `name`/`model` keys across distinct entries.** Two different
  entries in `models` that happen to share the same string in their
  `name`/`model` fields MUST resolve to the later entry's `size` in the
  returned map, with no error and no validation of the collision
  (parse-sizes-array-order-last-write-wins).
- **Empty model string to the size resolver.** Resolving an empty model
  string MUST return nothing unless the sizes map literally contains the
  empty string as a key (it never does from a real `/api/tags` response,
  since Ollama model names are non-empty) — ordinary miss behavior, with no
  special-casing here (size-of-total-miss-nil).
- **Concurrent access.** Not applicable as a race concern: the model server
  helper holds no mutable state — its only stored value, the loopback host
  set, is immutable — so any number of concurrent calls to any of its four
  functions from any concurrent context simultaneously MUST produce no data
  race, by construction, with no synchronization required.
- **Offline or disconnected state.** Not applicable to this component
  directly: it performs no network I/O itself. Native tags URL derivation
  only derives a URL string, and the response parser only parses data the
  caller has already fetched (or failed to fetch); connectivity loss and
  its handling are the caller's concern (the model catalog, a local
  provider model store, an inference guard), not this component's.
- **Missing or unreachable server / cancellation / timeout.** Not
  applicable to this component directly, for the same reason as offline
  state: there is no request, handle, or asynchronous task here to time
  out, go unreachable, or be cancelled. Every one of its functions is
  synchronous and non-throwing (synchronous-non-throwing).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `baseURL` | string | none — required per call | Passed to loopback detection and native tags URL derivation; the caller's configured, OpenAI-compatible base URL for a provider, e.g. `"http://localhost:11434/v1"`. |
| `data` | bytes | none — required per call | Passed to the response parser; the raw response body of a request to the URL native tags URL derivation produced, fetched and supplied by the caller. |
| `model` | string | none — required per call | Passed to the size resolver; the model identifier to look up, e.g. `"llama3.1:8b"`, optionally matched via the `":latest"` fallback. |
| `sizes` | map of string to integer | none — required per call | Passed to the size resolver; the map a prior response-parser call produced, supplied by the caller (typically the model catalog's cache). |

No environment variable, settings key, feature flag, or injected dependency
configures the model server helper; it has no dependency beyond standard
URL and data parsing, and every input is an explicit argument.

## Deep Linking

Not applicable: this component defines no route, inbound URL scheme, or
navigable destination of any kind — the only URL it constructs (native tags
URL derivation's result) is an outbound network fetch target for a caller to
request, not a deep link into this app.

## Localization

Not applicable: this component contains no user-facing string literal — its
inputs and outputs are URLs, data keys, and a map of sizes, none of which is
displayed text.

## Accessibility Options

Not applicable: this component renders nothing and reads no accessibility
display setting (Reduce Motion, Increase Contrast, Differentiate Without
Color).

## Feature Flags

Not applicable: this component contains no feature-flag or remote-config
check of any kind; its behavior is governed entirely by the arguments
passed to each call.

## Analytics

Not applicable: this component emits no analytics event — it has no
telemetry call of any kind.

## Privacy

Not applicable: the model server helper carries no user data, token, or
credential. It transmits nothing itself — it only derives a URL string from
a caller-supplied base URL and parses model-name/size pairs out of data the
caller already fetched — and it persists nothing to disk; every function
returns its result to the caller with no side channel.

## Logging

Not applicable: this component performs no logging. Both a whole-response
decode failure and each per-entry decode failure inside the response parser
are discarded with no diagnostic emitted — see
parse-sizes-whole-decode-failure-empty and parse-sizes-per-element-tolerance
in Behavioral Requirements, which is a deliberate choice per the component's
own stated design (one malformed entry is skipped rather than discarding the
whole listing, which would fail the guard open server-wide), not an
omission.

## Platform Notes

- **SwiftUI**: The source
  (`packages/apple/AgenticToolkit/AIPluginKit/LocalModelServer.swift`,
  tested by `Tests/AIPluginKitTests/LocalModelServerTests.swift`) has no
  SwiftUI, or any UI framework, dependency — it is a plain
  `Foundation`-only Swift `enum` with no case. A SwiftUI model-picker view
  or its `@Observable`/`@State` view model can call any of its four static
  functions directly, synchronously, from any isolation domain (a `.task {
  }` modifier, a button action, or a background `Task`) with no adaptation.
  Concretely: loopback detection is `isLoopback(baseURL:)`, built on
  `URL(string:)?.host`; native tags URL derivation is
  `nativeTagsURL(baseURL:)`; the response parser is `parseSizes(_:)`,
  decoding with `JSONDecoder` and a private `Element` wrapper's `try?
  Model(from: decoder)` per array element to get per-entry tolerance; the
  size resolver is `size(of:in:)`. The type itself is `public` with no
  explicit `Sendable` conformance, which is immaterial given it has no
  stored instance state.
- **Compose**: There is no Compose-specific consideration since this is a
  data-shaping layer, not UI. A Kotlin port would be a top-level `object
  LocalModelServer` (a Kotlin singleton, the closest analogue to a caseless
  `enum` namespace) exposing the same four functions, using
  `java.net.URI`/`okhttp3.HttpUrl` for host parsing in place of `URL.host`,
  and `kotlinx.serialization`'s `Json` with a `JsonElement`-based per-entry
  decode loop (rather than a single `List<Model>` decode) to reproduce
  `parse-sizes-per-element-tolerance`, since a default `kotlinx.serialization`
  list decode fails the whole array on one malformed element.
- **React/Web**: A TypeScript module exporting the four functions (or a
  `LocalModelServer` namespace object) using the global `URL` for host
  parsing in `isLoopback`, plain string operations
  (`trimEnd`/`endsWith`/lowercasing) for `nativeTagsURL`'s trim-and-strip
  sequence, and a manual `for` loop over `parsed.models` with a per-element
  `try/catch` (rather than one `JSON.parse` of the whole body followed by a
  schema cast) to reproduce `parse-sizes-per-element-tolerance` — a single
  `JSON.parse` on the whole body still throws on invalid top-level JSON,
  matching `parse-sizes-whole-decode-failure-empty`'s empty-object result.
- **AppKit / UIKit**: This is exactly the source's own context. The
  `AIPluginKit` target that contains `LocalModelServer.swift` builds for
  macOS only (`platform: macOS` in `project.yml`), and is consumed from
  AppKit-hosted code at
  `AgenticToolkit/macOS/Features/AIPlugins/Settings/ModelChooserContent.swift`
  and `ModelChooserViewController.swift`, as well as from the non-UI
  callers `LocalModelCatalog.swift`, `LocalProviderModelStore.swift`, and
  `DaemonAIChat.swift`. Nothing in `LocalModelServer` itself is
  AppKit-specific; a UIKit host would call the same four functions
  identically, with no adaptation, if this target were ever built for iOS.
- **WinUI 3**: This is the platform this recipe exists to steer. Port
  `LocalModelServer` as a `static class LocalModelServer` in C#, with four
  static methods matching the source one-for-one: `bool IsLoopback(string
  baseUrl)` using `Uri.TryCreate(baseUrl, UriKind.Absolute, out var uri)`
  and `uri.Host.ToLowerInvariant()` checked against a `static readonly
  HashSet<string>` holding the same five literals
  (`"localhost"`, `"127.0.0.1"`, `"0.0.0.0"`, `"::1"`, `"[::1]"`), returning
  `false` when `TryCreate` fails or `uri.Host` is empty; `Uri?
  NativeTagsUrl(string baseUrl)` reproduces the trim → strip-trailing-`/` →
  strip-case-insensitive-`/v1`-suffix → strip-trailing-`/` → append
  `"/api/tags"` sequence with `string.Trim()` and `TrimEnd('/')`, an
  `EndsWith("/v1", StringComparison.OrdinalIgnoreCase)` check followed by
  `Substring(0, length - 3)`, and a final `Uri.TryCreate` (returning `null`
  on an empty result or a construction failure) in place of `URL(string:)`'s
  optional return; `Dictionary<string, long> ParseSizes(byte[] data)`
  deserializes with `System.Text.Json.JsonSerializer`, but because
  `System.Text.Json` fails the whole document on one malformed array
  element the same way a naive Kotlin or TypeScript port would, the
  per-element tolerance MUST be reimplemented explicitly — deserialize
  `models` as `JsonElement[]` and wrap each individual
  `element.Deserialize<Model>()` call in its own `try`/`catch` to match the
  `Element` wrapper's `try?`-per-entry semantics — populating the
  `Dictionary<string, long>` under both a `Name` and a `Model` key exactly
  as `sizes[name] = size` / `sizes[model] = size` do, including the
  later-entry-wins collision behavior of a plain dictionary-indexer
  assignment; `long? SizeOf(string model, IReadOnlyDictionary<string, long>
  sizes)` does `sizes.TryGetValue(model, out var v) ? v : sizes.TryGetValue(model
  + ":latest", out var v2) ? v2 : (long?)null`. None of `HttpClient`,
  `Windows.Storage`, `Task`/`async`, `ObservableCollection`, or
  `INotifyPropertyChanged` is needed by this type itself, since it performs
  no I/O and holds no observable state — those APIs belong to the caller
  (a `LocalModelCatalog`-equivalent) that fetches the `Uri` this type
  derives and hands this type the bytes it returns.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/AIPluginKit/LocalModelServer.swift` |

## Design Decisions

- **Decision**: `0.0.0.0` and both the bracketed (`"[::1]"`) and
  unbracketed (`"::1"`) forms of the IPv6 loopback address are included in
  `loopbackHosts` alongside `"localhost"` and `"127.0.0.1"`.
  **Rationale**: Not stated in a source comment. `0.0.0.0` is commonly used
  as a local server's bind-all address rather than strictly "loopback," and
  `URL.host` can surface an IPv6 literal with or without its brackets
  depending on how the `baseURL` string was written, so both spellings are
  listed to avoid a false negative on either form.
  **Approved**: pending
- **Decision**: `nativeTagsURL(baseURL:)` strips trailing slashes both
  before and after removing the `/v1` suffix, rather than once.
  **Rationale**: Not stated in a source comment. Stripping only once before
  the suffix check would miss a `baseURL` like
  `"http://localhost:11434/v1/"` (trailing slash after `/v1`), since
  `hasSuffix("/v1")` would see `"/v1/"` and not match; the two-pass sequence
  makes the function tolerant of a trailing slash on either side of the
  `/v1` segment.
  **Approved**: pending
- **Decision**: `parseSizes(_:)` decodes each `models` element individually
  via `try?` inside a private `Element` wrapper, rather than decoding
  `[Model]` directly and letting one bad element fail the whole array.
  **Rationale**: Stated directly in the source's doc comment: "one
  malformed entry ... is skipped rather than discarding the whole listing,
  which would fail the guard open server-wide." A single malformed entry
  MUST NOT blank every model's size, because `LocalInferenceGuard`'s
  downstream memory check depends on this data being present when it can be.
  **Approved**: pending
- **Decision**: A `parseSizes(_:)` entry is indexed under both its `name`
  and its `model` field (when present), rather than under one canonical
  key.
  **Rationale**: Stated directly in the source's doc comment: "Both `name`
  and the newer `model` key index the same entry so lookups succeed
  whichever form a config stored." Different call sites and Ollama API
  versions refer to a model by either field, and `size(of:in:)` must
  resolve either spelling without the caller knowing which one a given
  config uses.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | Reliability |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | passed | Internationalization |

Notes: graceful-degradation passes because every malformed or unexpected
input — an unparseable `baseURL`, a `baseURL` that trims to empty, garbage
JSON, or a JSON entry with wrong-typed fields — resolves to `false`, `nil`,
or `[:]` rather than a thrown error or a crash. explicit-error-handling is
partial because both the whole-document and per-entry decode failures in
`parseSizes(_:)` are discarded via `try?` with zero diagnostic signal, so a
caller cannot distinguish "server returned no models" from "server returned
garbage" (see Logging). data-integrity is partial because
`parse-sizes-array-order-last-write-wins` lets two distinct `models`
entries silently overwrite each other's size under a colliding `name`/`model`
key, with no validation or reported conflict. no-hardcoded-strings passes
because the source contains no user-facing string literal at all to
hardcode — its only string literals are the fixed `loopbackHosts` set, the
`"/v1"` and `"/api/tags"` path fragments, and JSON key names, none of which
is displayed to a user (see Localization).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ai/models/local/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation |
