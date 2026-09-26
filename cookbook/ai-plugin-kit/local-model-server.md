---
id: ff1089d7-170c-4658-91c6-e3946710b29f
title: LocalModelServer
domain: agentictoolkit://cookbook/ai-plugin-kit/local-model-server
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: AIPluginKit's stateless Foundation helper for loopback-host detection, Ollama's
  native /api/tags URL derivation, and tolerant model-size JSON parsing.
platforms:
- swift
- macos
tags:
- ai-plugin
- local-model
- ollama
- foundation
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

# LocalModelServer

## Overview

`LocalModelServer` is an `AIPluginKit` **logic** component — no visual
surface — a `public enum` with no cases, used purely as a namespace for four
static functions. Its own doc comment states its purpose directly: it is
"shared by the inference guard and hosts' model pickers so loopback
detection, the native-API URL derivation, and `/api/tags` size parsing
cannot drift" between call sites. Concretely, three independent concerns
that a local (loopback) OpenAI-compatible model server touches are
centralized here: (1) `isLoopback(baseURL:)` decides whether a configured
`baseURL` points at this machine; (2) `nativeTagsURL(baseURL:)` derives
Ollama's native `/api/tags` listing URL from an OpenAI-compatible `baseURL`,
because that native endpoint is the only one that reports a model's on-disk
`size`; (3) `parseSizes(_:)` and `size(of:in:)` decode that endpoint's JSON
response into a `model → size bytes` map and look up one model in it,
tolerating the `:latest` shorthand. Direct callers in this package are
`DaemonAIChat.swift` (`isLoopback`, to decide whether the inference guard
applies to a request), `LocalModelCatalog.swift` and
`LocalProviderModelStore.swift` (`nativeTagsURL`, `parseSizes`, and
`size(of:in:)`, to populate and query a model-size cache), and, one layer up
the call chain, the macOS settings UI `ModelChooserContent.swift` /
`ModelChooserViewController.swift`. Unlike its caller `LocalModelCatalog`
(an `actor` with a TTL-based cache), `LocalModelServer` holds no state at
all beyond the fixed `loopbackHosts` literal — every requirement below is a
pure function of its arguments, which is why this recipe is smaller than a
stateful sibling of the same family.

## Behavioral Requirements

- **namespace-shape**: `LocalModelServer` MUST be declared as a `public
  enum` with zero cases and only `static` members, so it functions as an
  uninstantiable namespace rather than a value or reference type with
  instance state.
- **concurrency-safety**: Every one of `LocalModelServer`'s four static
  functions MUST be callable concurrently, from any thread or actor
  isolation domain, without external synchronization. `LocalModelServer` is
  declared `public` with no explicit `Sendable` conformance, so per Swift's
  isolation rules it is not treated as `Sendable` across a module boundary;
  this is immaterial here because the type has no case, no stored instance
  property, and no instance is ever constructed or passed anywhere — the
  only stored value, `loopbackHosts`, is an immutable `private static let`
  computed once, so there is no mutable state for a concurrent call to race
  against.
- **synchronous-non-throwing**: None of `isLoopback(baseURL:)`,
  `nativeTagsURL(baseURL:)`, `parseSizes(_:)`, or `size(of:in:)` MUST be
  declared `async` or `throws`; each MUST execute synchronously and return
  its result (`Bool`, `URL?`, `[String: Int]`, or `Int?`) directly, including
  when its input is malformed.
- **no-side-effects**: `LocalModelServer`'s four functions MUST perform no
  file-system access, network request, process launch, or notification;
  each MUST compute its result purely from its arguments (and, for
  `nativeTagsURL`/`parseSizes`, from `Foundation`'s `URL` and `JSONDecoder`
  APIs applied to that input).
- **loopback-hosts-literal-set**: The private `loopbackHosts` set MUST
  contain exactly these five string literals, and no others: `"localhost"`,
  `"127.0.0.1"`, `"0.0.0.0"`, `"::1"`, `"[::1]"`.
- **is-loopback-host-extraction**: `isLoopback(baseURL:)` MUST construct a
  `URL` from `baseURL` via `URL(string:)` and read its `.host` component as
  the candidate to test.
- **is-loopback-case-insensitive-compare**: `isLoopback(baseURL:)` MUST
  lowercase the extracted host before comparing it against `loopbackHosts`.
- **is-loopback-membership-result**: `isLoopback(baseURL:)` MUST return
  `true` if and only if the lowercased host is a member of
  `loopbackHosts`, and `false` otherwise.
- **is-loopback-unparseable-false**: `isLoopback(baseURL:)` MUST return
  `false` when `baseURL` cannot be parsed into a `URL`, or the parsed `URL`
  has no `host` component (covers `baseURL: ""` and a scheme-less string
  such as `"localhost:11434"`, whose `URL.host` is `nil`).
- **native-tags-url-whitespace-trim**: `nativeTagsURL(baseURL:)` MUST trim
  leading and trailing characters in `.whitespacesAndNewlines` from
  `baseURL` before any other processing.
- **native-tags-url-strip-trailing-slashes-first-pass**: `nativeTagsURL(baseURL:)`
  MUST repeatedly strip a trailing `"/"` character from the trimmed string
  until none remains, before checking for a `"/v1"` suffix.
- **native-tags-url-strip-v1-suffix**: `nativeTagsURL(baseURL:)` MUST strip
  one trailing three-character `"/v1"` suffix, compared case-insensitively
  (`trimmed.lowercased().hasSuffix("/v1")`), from the string produced by the
  first slash-stripping pass.
- **native-tags-url-strip-trailing-slashes-second-pass**: `nativeTagsURL(baseURL:)`
  MUST repeatedly strip a trailing `"/"` character again after the `"/v1"`
  suffix has been removed, until none remains.
- **native-tags-url-empty-yields-nil**: `nativeTagsURL(baseURL:)` MUST
  return `nil` when the fully-trimmed string is empty.
- **native-tags-url-append-and-construct**: `nativeTagsURL(baseURL:)` MUST
  append the literal path `"/api/tags"` to the fully-trimmed, non-empty
  string and construct the result via `URL(string:)`; it MUST return `nil`
  (propagated from `URL(string:)`) if that construction fails.
- **parse-sizes-decode-shape**: `parseSizes(_:)` MUST decode `data` as JSON
  matching the shape `{"models": [{"name": String?, "model": String?,
  "size": Int?}, ...]}`.
- **parse-sizes-whole-decode-failure-empty**: `parseSizes(_:)` MUST return
  an empty dictionary (`[:]`) when the top-level document does not decode
  into that `Tags` shape at all (malformed JSON, or a missing/wrong-typed
  `models` key).
- **parse-sizes-per-element-tolerance**: `parseSizes(_:)` MUST decode each
  element of the `models` array individually (via the `Element` wrapper's
  `try? Model(from: decoder)`), so that one element failing to decode MUST
  be dropped without causing any other element in the array to be dropped.
- **parse-sizes-missing-size-excluded**: `parseSizes(_:)` MUST exclude a
  decoded entry from the returned dictionary under any key when that
  entry's `size` field is `nil` or absent.
- **parse-sizes-dual-key-indexing**: `parseSizes(_:)` MUST store a decoded
  entry's `size` under its `name` key when `name` is present, and MUST
  independently store the same `size` value under its `model` key when
  `model` is present; an entry with both fields present MUST be indexed
  under both keys.
- **parse-sizes-neither-key-excluded**: `parseSizes(_:)` MUST exclude a
  decoded entry from the returned dictionary entirely when it has neither a
  `name` nor a `model` value, regardless of whether `size` is present.
- **parse-sizes-array-order-last-write-wins**: When two entries in `models`
  produce the same dictionary key (through either their `name` or `model`
  field), `parseSizes(_:)` MUST resolve the collision to the value of
  whichever entry is later in the `models` array — ordinary Swift
  dictionary-literal-assignment overwrite semantics — with no de-duplication
  or validation against the collision.
- **size-of-exact-match**: `size(of:in:)` MUST return `sizes[model]` when
  `sizes` contains that exact key.
- **size-of-latest-fallback**: `size(of:in:)` MUST return `sizes[model +
  ":latest"]` when the exact `model` key is absent from `sizes` and the
  `":latest"`-suffixed key is present.
- **size-of-total-miss-nil**: `size(of:in:)` MUST return `nil` when neither
  the exact `model` key nor the `":latest"`-suffixed key is present in
  `sizes`.

## Appearance

Not applicable — this is a stateless Foundation namespace enum, not a
visual component.

## States

Not applicable — this is a stateless Foundation namespace enum, not a
visual component.

## Accessibility

Not applicable — this is a stateless Foundation namespace enum, not a
visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| LMS-001 | is-loopback-host-extraction, is-loopback-case-insensitive-compare, is-loopback-membership-result | `isLoopback(baseURL: "http://localhost:11434/v1")`, `isLoopback(baseURL: "http://127.0.0.1:11434/v1")` | Both return `true` — `LocalModelServerTests.loopbackDetection` |
| LMS-002 | is-loopback-membership-result | `isLoopback(baseURL: "https://api.anthropic.com/v1")` | Returns `false` — `LocalModelServerTests.loopbackDetection` |
| LMS-003 | is-loopback-unparseable-false | `isLoopback(baseURL: "")` | Returns `false` — `LocalModelServerTests.loopbackDetection` |
| LMS-004 | is-loopback-unparseable-false | `isLoopback(baseURL: "localhost:11434")` (no `http://`/`https://` prefix) | Returns `false`; Foundation's `URL(string:)` parses `"localhost"` as the scheme and leaves `.host == nil` for a string with no `//` authority marker, so the `guard let host = ...` branch is taken — not exercised by `LocalModelServerTests`, traced directly to the `guard let host = URL(string: baseURL)?.host?.lowercased() else { return false }` line |
| LMS-005 | native-tags-url-strip-v1-suffix, native-tags-url-append-and-construct | `nativeTagsURL(baseURL: "http://localhost:11434/v1")` | `.absoluteString == "http://localhost:11434/api/tags"` — `LocalModelServerTests.nativeTagsURLStripsV1Suffix` |
| LMS-006 | native-tags-url-strip-trailing-slashes-first-pass, native-tags-url-strip-v1-suffix, native-tags-url-strip-trailing-slashes-second-pass | `nativeTagsURL(baseURL: "http://localhost:11434/v1/")` | `.absoluteString == "http://localhost:11434/api/tags"` — `LocalModelServerTests.nativeTagsURLStripsV1Suffix` |
| LMS-007 | native-tags-url-append-and-construct | `nativeTagsURL(baseURL: "http://localhost:11434")` (no `/v1` suffix at all) | `.absoluteString == "http://localhost:11434/api/tags"` — `LocalModelServerTests.nativeTagsURLStripsV1Suffix` |
| LMS-008 | native-tags-url-whitespace-trim, native-tags-url-empty-yields-nil | `nativeTagsURL(baseURL: "")` | Returns `nil` — `LocalModelServerTests.nativeTagsURLStripsV1Suffix` |
| LMS-009 | native-tags-url-strip-v1-suffix | `nativeTagsURL(baseURL: "http://localhost:11434/V1")` (uppercase suffix) | `.absoluteString == "http://localhost:11434/api/tags"`, because the suffix comparison is `trimmed.lowercased().hasSuffix("/v1")` — not exercised by `LocalModelServerTests`, whose fixtures use only lowercase `/v1` |
| LMS-010 | parse-sizes-dual-key-indexing, parse-sizes-missing-size-excluded, size-of-exact-match, size-of-latest-fallback | `parseSizes(Data("{\"models\":[{\"name\":\"llama3.1:8b\",\"model\":\"llama3.1:8b\",\"size\":4920000000},{\"name\":\"qwen3-coder-next:latest\",\"size\":51000000000},{\"name\":\"broken-no-size\"}]}".utf8))`, then `size(of: "qwen3-coder-next", in: sizes)` and `size(of: "llama3.1:8b", in: sizes)` | `sizes["llama3.1:8b"] == 4_920_000_000`, `sizes["qwen3-coder-next:latest"] == 51_000_000_000`, `sizes["broken-no-size"] == nil`; `size(of: "qwen3-coder-next", ...) == 51_000_000_000` (via `:latest` fallback), `size(of: "llama3.1:8b", ...) == 4_920_000_000` (exact match) — `LocalModelServerTests.parseSizesIndexesNameAndModelKeys` |
| LMS-011 | parse-sizes-whole-decode-failure-empty | `parseSizes(Data("not json".utf8))` | Returns `[:]` — `LocalModelServerTests.parseSizesToleratesGarbage` |
| LMS-012 | parse-sizes-per-element-tolerance | `parseSizes` on JSON with three entries where the middle one has `"name":123,"size":"garbage"` (wrong-typed fields) and the other two are well-formed | Returns a dictionary with exactly the two well-formed entries (`count == 2`); the middle entry is dropped without discarding the other two — `LocalModelServerTests.parseSizesSkipsMalformedEntries` |
| LMS-013 | size-of-total-miss-nil | `size(of: "nonexistent", in: [:])` | Returns `nil` — not exercised directly by `LocalModelServerTests`, traced to the `sizes[model] ?? sizes[model + ":latest"]` line with both operands missing |
| LMS-014 | parse-sizes-neither-key-excluded | `parseSizes` on JSON `{"models":[{"size":100}]}` (an entry with `size` but neither `name` nor `model`) | Returns `[:]` — not exercised by `LocalModelServerTests`, traced to the `if let name = entry.name { ... }` / `if let model = entry.model { ... }` pair both being skipped when both are `nil` |
| LMS-015 | parse-sizes-array-order-last-write-wins | `parseSizes` on JSON `{"models":[{"name":"m","size":1},{"model":"m","size":2}]}` (two distinct entries whose `name`/`model` fields collide on the same string `"m"`) | Returns `["m": 2]` — the later entry's assignment overwrites the earlier one under the shared key; not exercised by `LocalModelServerTests`, traced to plain dictionary-subscript assignment (`sizes[name] = size`, `sizes[model] = size`) executed in `for entry in tags.models.compactMap(\.value)` array order |

## Edge Cases

- **Empty `baseURL` to `isLoopback`.** `isLoopback(baseURL: "")` MUST return
  `false` — the `URL(string:)?.host` chain fails on an empty string
  (`is-loopback-unparseable-false`).
- **Scheme-less `baseURL` to `isLoopback`.** A `baseURL` with no `http://`
  or `https://` prefix (e.g. `"localhost:11434"`) parses with `.host ==
  nil`, so `isLoopback` MUST return `false` even though a human reader would
  recognize the string as local (`is-loopback-unparseable-false`).
- **`baseURL` that trims to empty for `nativeTagsURL`.** A `baseURL` such
  as `"/v1"` or `"///"` reduces, through the slash- and `/v1`-stripping
  passes, to an empty string, and `nativeTagsURL(baseURL:)` MUST return
  `nil` — the same outcome as a literally empty `baseURL`
  (`native-tags-url-empty-yields-nil`).
- **Repeated trailing slashes.** A `baseURL` such as
  `"http://localhost:11434/v1////"` MUST resolve to
  `"http://localhost:11434/api/tags"`; both stripping passes loop `while
  trimmed.hasSuffix("/")`, so any number of trailing slashes is removed, not
  just one (`native-tags-url-strip-trailing-slashes-first-pass`,
  `native-tags-url-strip-trailing-slashes-second-pass`).
- **Mixed-case `/v1` suffix.** `"http://localhost:11434/V1"` MUST also
  strip to `"http://localhost:11434/api/tags"`, because the suffix check is
  case-insensitive (`native-tags-url-strip-v1-suffix`).
- **Malformed JSON to `parseSizes`.** Non-JSON bytes (e.g. `"not json"`)
  MUST yield `[:]`, not a thrown error or a crash
  (`parse-sizes-whole-decode-failure-empty`).
- **Well-formed JSON, wrong top-level shape.** JSON that is valid but does
  not contain a `models` array at all (e.g. `{}` or `{"models": {}}`) MUST
  also yield `[:]`, because the outer `Tags` struct fails to decode
  (`parse-sizes-whole-decode-failure-empty`).
- **Partially malformed entries.** An entry array where some elements have
  wrong-typed fields MUST retain the well-formed elements and drop only the
  malformed ones, per element, rather than discarding the whole listing
  (`parse-sizes-per-element-tolerance`).
- **Colliding `name`/`model` keys across distinct entries.** Two different
  entries in `models` that happen to share the same string in their
  `name`/`model` fields MUST resolve to the later entry's `size` in the
  returned dictionary, with no error and no validation of the collision
  (`parse-sizes-array-order-last-write-wins`).
- **Empty `model` string to `size(of:in:)`.** `size(of: "", in: sizes)` MUST
  return `nil` unless `sizes` literally contains the empty string as a key
  (it never does from a real `/api/tags` response, since Ollama model names
  are non-empty) — ordinary dictionary-miss behavior, with no special-casing
  in this file (`size-of-total-miss-nil`).
- **Concurrent access.** Not applicable as a race concern: `LocalModelServer`
  holds no mutable state — its only stored value, `loopbackHosts`, is an
  immutable `private static let` — so any number of concurrent calls to any
  of its four functions from any threads or actors simultaneously MUST
  produce no data race, by construction, with no synchronization required.
- **Offline or disconnected state.** Not applicable to this file directly:
  `LocalModelServer.swift` performs no network I/O itself.
  `nativeTagsURL(baseURL:)` only derives a URL string, and `parseSizes(_:)`
  only parses `Data` the caller has already fetched (or failed to fetch);
  connectivity loss and its handling are the caller's concern
  (`LocalModelCatalog`, `LocalProviderModelStore`, `DaemonAIChat`), not
  this file's.
- **Missing or unreachable server / cancellation / timeout.** Not
  applicable to this file directly, for the same reason as offline state:
  there is no request, file handle, or async task in `LocalModelServer.swift`
  to time out, go unreachable, or be cancelled. Every one of its functions
  is synchronous and non-throwing (`synchronous-non-throwing`).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `baseURL` | `String` | none — required per call | Passed to `isLoopback(baseURL:)` and `nativeTagsURL(baseURL:)`; the caller's configured, OpenAI-compatible base URL for a provider, e.g. `"http://localhost:11434/v1"`. |
| `data` | `Data` | none — required per call | Passed to `parseSizes(_:)`; the raw HTTP response body of a `GET` request to the URL `nativeTagsURL(baseURL:)` derived, fetched and supplied by the caller. |
| `model` | `String` | none — required per call | Passed to `size(of:in:)`; the model identifier to look up, e.g. `"llama3.1:8b"`, optionally matched via the `":latest"` fallback. |
| `sizes` | `[String: Int]` | none — required per call | Passed to `size(of:in:)`; the dictionary a prior `parseSizes(_:)` call produced, supplied by the caller (typically `LocalModelCatalog`'s cache). |

No environment variable, settings key, feature flag, or injected dependency
configures `LocalModelServer`; `import Foundation` is its only dependency,
and every input is an explicit function argument.

## Deep Linking

Not applicable: `LocalModelServer.swift` defines no route, inbound URL
scheme, or navigable destination of any kind — the only URL it constructs
(`nativeTagsURL(baseURL:)`'s result) is an outbound network fetch target for
a caller to `GET`, not a deep link into this app.

## Localization

Not applicable: `LocalModelServer.swift` contains no user-facing string
literal — its inputs and outputs are URLs, JSON keys, and a
`[String: Int]` map, none of which is displayed text.

## Accessibility Options

Not applicable: `LocalModelServer.swift` renders nothing and reads no
accessibility display setting (Reduce Motion, Increase Contrast,
Differentiate Without Color).

## Feature Flags

Not applicable: `LocalModelServer.swift` contains no feature-flag or
remote-config check of any kind; its behavior is governed entirely by the
arguments passed to each call.

## Analytics

Not applicable: `LocalModelServer.swift` emits no analytics event — it has
no telemetry call of any kind.

## Privacy

Not applicable: `LocalModelServer` carries no user data, token, or
credential. It transmits nothing itself — it only derives a URL string from
a caller-supplied `baseURL` and parses model-name/size pairs out of `Data`
the caller already fetched — and it persists nothing to disk; every
function returns its result to the caller with no side channel.

## Logging

Not applicable: `LocalModelServer.swift` contains no `Logger`/`os_log`/
`print` call. Both a whole-document decode failure and each per-entry decode
failure inside `parseSizes(_:)` are discarded via `try?` with no diagnostic
emitted — see `parse-sizes-whole-decode-failure-empty` and
`parse-sizes-per-element-tolerance` in Behavioral Requirements, which is a
deliberate choice per the type's own doc comment ("one malformed entry ...
is skipped rather than discarding the whole listing, which would fail the
guard open server-wide"), not an omission.

## Platform Notes

- **SwiftUI**: The source
  (`packages/apple/AgenticToolkit/AIPluginKit/LocalModelServer.swift`,
  tested by `Tests/AIPluginKitTests/LocalModelServerTests.swift`) has no
  SwiftUI, or any UI framework, dependency — it is a plain
  `Foundation`-only Swift `enum`. A SwiftUI model-picker view or its
  `@Observable`/`@State` view model can call any of its four static
  functions directly, synchronously, from any isolation domain (a `.task {
  }` modifier, a button action, or a background `Task`) with no adaptation.
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
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation |
