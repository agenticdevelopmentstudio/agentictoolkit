<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-local-model-server · source: ai-plugin-runtime-ai-plugin-kit-local-model-server.md -->

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-local-model-server#<slug>`):

- `namespace-shape` MUST
- `concurrency-safety` MUST
- `synchronous-non-throwing` MUST
- `no-side-effects` MUST
- `loopback-hosts-literal-set` MUST
- `is-loopback-host-extraction` MUST
- `is-loopback-case-insensitive-compare` MUST
- `is-loopback-membership-result` MUST
- `is-loopback-unparseable-false` MUST
- `native-tags-url-whitespace-trim` MUST
- `native-tags-url-strip-trailing-slashes-first-pass` MUST
- `native-tags-url-strip-v1-suffix` MUST
- `native-tags-url-strip-trailing-slashes-second-pass` MUST
- `native-tags-url-empty-yields-nil` MUST
- `native-tags-url-append-and-construct` MUST
- `parse-sizes-decode-shape` MUST
- `parse-sizes-whole-decode-failure-empty` MUST
- `parse-sizes-per-element-tolerance` MUST
- `parse-sizes-missing-size-excluded` MUST
- `parse-sizes-dual-key-indexing` MUST
- `parse-sizes-neither-key-excluded` MUST
- `parse-sizes-array-order-last-write-wins` MUST
- `size-of-exact-match` MUST
- `size-of-latest-fallback` MUST
- `size-of-total-miss-nil` MUST

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

