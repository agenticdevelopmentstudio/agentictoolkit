<!-- leaf: implement-extension-host-core-1/extensions-open-vsx-client--part-3 · source: extension-host-core-extensions-open-vsx-client.md -->

# OpenVSXClient — continued (part 3)

**Rules** (cite as `implement-extension-host-core-1/extensions-open-vsx-client--part-3#<slug>`):

- `cancellation-stops-the-transfer` MUST
- `network-failure-propagates-untyped` MUST
- `logging-conformance-declared-unused` MUST
- `error-cases-carry-the-failing-url` MUST

- **cancellation-stops-the-transfer**: Cancelling the `Task` that awaits
  `search`, `detail`, `data`, or `text` MUST cancel the underlying
  `URLSessionDataTask` via `withTaskCancellationHandler`'s `onCancel`, rather
  than continuing to accumulate a response body no one will read
  (`BoundedBodyLoader.swift`).
- **network-failure-propagates-untyped**: `body` MUST NOT catch any error
  from `loader.body(at:limit:)` other than `BoundedBodyLoader.Failure.tooLarge`
  — a session-level failure that arrives before or during the transfer (host
  unreachable, TLS failure, timeout, or the cancellation above) MUST
  propagate to the caller of `search`, `detail`, `data`, or `text` as its
  original error type (for example a `URLError`), not wrapped in
  `OpenVSXError`.
- **logging-conformance-declared-unused**: `OpenVSXClient` MUST conform to
  `Loggable`, declaring `public static nonisolated let logger = makeLogger()`
  scoped by that protocol's default to category `"OpenVSXClient"`, but no
  method on `OpenVSXClient` calls `logger` — every failure surfaces to the
  caller as a thrown `OpenVSXError` case instead of a log line (`Loggable.swift`).
- **error-cases-carry-the-failing-url**: Every case of `OpenVSXError` except
  `unsafeIdentity` MUST carry the `URL` the failure happened at, so a report
  is actionable when `registryBase` is a configurable, possibly self-hosted,
  value (doc comment).
## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `registryBase` | `URL` | `OpenVSXClient.openVSXRegistry` (`https://open-vsx.org/api`) | Base URL of the Open VSX-compatible registry API; overridable to address a self-hosted instance. |
| `session` | `URLSession` | `.shared` | Only its `configuration` is read, to construct the internal `BoundedBodyLoader` — in particular any injected `protocolClasses`. |
| `maximumArtifactBytes` | `Int` | `OpenVSXClient.defaultMaximumArtifactBytes` (536,870,912) | Ceiling on the bytes `data(at:)`/`text(at:)` will read before throwing `artifactTooLarge`. |
| `maximumMetadataBytes` | `Int` | `OpenVSXClient.defaultMaximumMetadataBytes` (8,388,608) | Ceiling on the bytes `search`/`detail` will read before throwing `responseTooLarge`. |
| `query` (`search` parameter) | `String` | `""` | Free-text search term; empty means browse the whole catalog. |
| `offset` (`search` parameter) | `Int` | `0` | Row offset into the result set. |
| `size` (`search` parameter) | `Int` | `OpenVSXClient.defaultPageSize` (50) | Rows requested per page. |
| `sortBy` (`search` parameter) | `SortOrder` | `.downloadCount` | One of `downloadCount`, `relevance`, `rating`, `timestamp`. |
| `version` (`detail` parameter) | `String?` | `nil` | Named version to address; `nil` addresses the latest published version. |

## Privacy

- **Data collected**: The free-text `query` a caller passes to `search`, and
  the `namespace`/`name`/`version` identifiers a caller passes to `detail`,
  are sent to the configured registry as URL query items or path
  components; `OpenVSXClient` itself collects and attaches nothing beyond
  what the caller supplies as arguments.
- **Storage**: None. `OpenVSXClient` holds no cache and persists nothing
  between calls — whichever caller receives the decoded `OpenVSXSearchPage`,
  `OpenVSXExtensionDetail`, `Data`, or `String` decides whether to store it
  (doc comment).
- **Transmission**: Every `search`/`detail` request, and every artifact
  fetch that passes `requireFetchable`, leaves the device for `registryBase`
  (`https://open-vsx.org/api` by default, or a caller-configured self-hosted
  host) over `https`; the doc comment states that nothing beyond the request
  itself is sent that the registry could attribute to a user.
- **Retention**: Not applicable — no value returned by this type is retained
  past the call that produced it; the type stores nothing between calls
  (doc comment).

## Platform Notes

- **SwiftUI**: Source:
  `packages/apple/AgenticToolkit/Core/Extensions/OpenVSXClient.swift`, its
  return types in `Core/Extensions/OpenVSXCatalog.swift`, its shared bounded
  body reader in `Core/Networking/BoundedBodyLoader.swift`, its identity
  guard in `Core/Extensions/ExtensionIdentityComponent.swift`, and its
  `Loggable` conformance from `Core/Loggable.swift`. The type is plain
  `Foundation` and `OSLog` with no SwiftUI dependency; a SwiftUI-hosted
  settings screen calls `search`, `detail`, `data`, or `text` directly with
  `async`/`await` from a `Task`, and decodes the results into its own
  `@State`/`@Observable` view state — `OpenVSXClient` itself has none.
- **Compose**: On Kotlin/Android, port to a class built on OkHttp or Ktor's
  `HttpClient`, exposing `suspend fun search(...): OpenVSXSearchPage`,
  `suspend fun detail(...): OpenVSXExtensionDetail`,
  `suspend fun data(url: HttpUrl): ByteArray`, and
  `suspend fun text(url: HttpUrl): String`. Decode `OpenVSXSearchPage` and
  `OpenVSXExtensionDetail` with `kotlinx.serialization`; reproduce the
  bounded read by installing a response interceptor or a custom
  `ResponseBody` wrapper that counts bytes as they stream and cancels the
  call past the ceiling, mirroring `BoundedBodyLoader`'s per-chunk check
  rather than trusting `Content-Length` alone. Reuse the ported
  `ExtensionIdentityComponent.isSafe` before appending `namespace`, `name`,
  or `version` to an `HttpUrl.Builder`, and restrict artifact URLs to
  `https` with a non-empty host before calling `OkHttpClient.newCall`.
- **React/Web**: In TypeScript, port to an async client using `fetch`,
  exposing `async function search(...): Promise<OpenVSXSearchPage>`,
  `detail(...)`, `data(url: string): Promise<Uint8Array>`, and
  `text(url: string): Promise<string>`. `fetch` alone cannot be
  size-bounded any more than `URLSession.data(from:)` can, so read the
  response body via its `ReadableStream` reader chunk-by-chunk, summing
  byte counts against the same two ceilings and aborting with an
  `AbortController` once either is passed. Parse JSON with a `try`/`catch`
  around `JSON.parse` mapped to the same tagged-error union `OpenVSXError`
  represents; reuse the ported `isSafe` before building the request URL with
  the `URL` and `URLSearchParams` constructors; restrict artifact URLs to
  `https:` with a non-empty `hostname` before calling `fetch` on them.
- **AppKit / UIKit**: No divergence from the SwiftUI bullet above — the
  source is framework-agnostic `Foundation`/`URLSession` code, callable
  identically from an AppKit-hosted (macOS) or UIKit-hosted (iOS) caller.
  `AgenticToolkitCore`, the framework target that builds this file, is
  configured `platform: macOS` in `packages/apple/AgenticToolkit/project.yml`
  today, so an iOS caller would first need the type made available to an
  iOS target; `OpenVSXClient` itself needs no AppKit/UIKit-specific change
  to run there.
- **WinUI 3**: Port to a class built on `System.Net.Http.HttpClient`,
  exposing `async Task<OpenVSXSearchPage> SearchAsync(...)`,
  `async Task<OpenVSXExtensionDetail> DetailAsync(...)`,
  `async Task<byte[]> DataAsync(Uri url)`, and
  `async Task<string> TextAsync(Uri url)`. Decode `OpenVSXSearchPage` and
  `OpenVSXExtensionDetail` with `System.Text.Json`'s
  `JsonSerializer.DeserializeAsync` against matching record types. Enforce
  the two byte ceilings by requesting with
  `HttpCompletionOption.ResponseHeadersRead`, checking
  `HttpResponseMessage.Content.Headers.ContentLength` against the ceiling
  before reading further, and then reading the body via a manual
  `Stream.ReadAsync` loop that counts bytes and throws once the running
  count passes the ceiling — `HttpClient.GetByteArrayAsync` cannot be
  bounded any more than `URLSession.data(from:)` can, which is why the
  source reads by hand instead of calling it. Check
  `HttpResponseMessage.IsSuccessStatusCode` and read the status code before
  attempting to deserialize, exactly as `checkStatus` does ahead of
  `JSONDecoder`. Port `ExtensionIdentityComponent.IsSafe` and call it on
  `namespace`, `name`, and `version` before building the request `Uri` —
  WinUI has no path-join operator equivalent to `appendingPathComponent`, so
  a caller who skips this guard would have to concatenate path segments by
  hand, making the same traversal risk even easier to introduce by accident.
  Restrict artifact URLs to `Uri.Scheme == "https"` with a non-empty `Uri.Host`
  before calling `HttpClient.GetAsync` on them, mirroring `requireFetchable`.
  Cancellation flows through the ordinary `CancellationToken` passed to each
  `Async` method rather than through `withTaskCancellationHandler`. No
  `ObservableCollection` or `INotifyPropertyChanged` belongs on this type
  itself, since it has no UI-observable state of its own — those apply only
  to whatever ViewModel wraps calls into it.

