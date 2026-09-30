<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-local-model-server--part-2 · source: ai-plugin-runtime-ai-plugin-kit-local-model-server.md -->

# LocalModelServer — continued (part 2)

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-local-model-server--part-2#<slug>`):

- `winui-3` MUST — This is the platform this recipe exists to steer. Port LocalModelServer as a static class LocalModelServer in C#, with …
- `decision` MUST — parseSizes(_:) decodes each models element individually via try? inside a private Element wrapper, rather than decoding …

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
