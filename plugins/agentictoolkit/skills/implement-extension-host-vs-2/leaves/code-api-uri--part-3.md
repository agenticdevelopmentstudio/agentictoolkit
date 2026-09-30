<!-- leaf: implement-extension-host-vs-2/code-api-uri--part-3 · source: extension-host-vs-code-api-uri.md -->

# Uri — continued (part 3)

**Rules** (cite as `implement-extension-host-vs-2/code-api-uri--part-3#<slug>`):

- `url-from-rejects-non-uri-non-string` MUST
- `url-from-swallows-to-string-failure` MUST
- `uri-value-builds-via-parse` MUST
- `uri-value-nil-when-class-or-parse-unavailable` MUST
- `uri-value-round-trips-with-url-from` MUST
- `main-actor-isolation` MUST

- **url-from-rejects-non-uri-non-string**: `url(from:in:)` MUST return `nil`, without reading any property off `value`, for a `value` that is neither `isString` nor `isInstance(of:)` the installed `Uri` constructor — including a number, a plain object shaped like a `Uri`, and JavaScript `undefined` (`Uri.swift`-`373`).
- **url-from-swallows-to-string-failure**: `url(from:in:)` MUST return `nil` — with no signal to its caller — when `value`'s `toString` property is absent or not `isObject`, when the guarded call to it does not settle as `.returned` (i.e., it `.threw` or was `.unavailable`), or when the returned value is not a JavaScript string (`Uri.swift`-`378`).
- **uri-value-builds-via-parse**: `uriValue(for:in:)` MUST call `Uri.parse` directly via `JSValue.call(withArguments:)` — not through `VSCodeAPI.call(_:thisArg:arguments:)` — passing `[url.absoluteString]` and no `strict` argument, so the throwing branch of **parse-strict-requires-scheme** is never reached from this path (`Uri.swift`-`430`).
- **uri-value-nil-when-class-or-parse-unavailable**: `uriValue(for:in:)` MUST return `nil` when `installUriClass(in:)` returns `nil`, when the constructor's `parse` property is absent or not `isObject`, or when the call's result is `nil`, `isUndefined`, or `isNull` (`Uri.swift`-`431`).
- **uri-value-round-trips-with-url-from**: For a `URL` built in Swift, `url(from:in:)` applied to `uriValue(for:in:)`'s result MUST return a `URL` whose `absoluteString` equals the original `URL`'s `absoluteString` (`Uri.swift`-`432`).
- **main-actor-isolation**: `installUriClass(in:)`, `url(from:in:)`, and `uriValue(for:in:)` MUST run only on the main actor, inherited from `VSCodeAPI`'s own `@MainActor public enum` declaration, because every `JSContext`/`JSValue` argument they take is a non-`Sendable` JavaScriptCore type that the Swift compiler already confines to the isolation domain that created it (`Uri.swift`-`37`).
## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `context` | `JSContext` | (required, no default) | The JavaScriptCore context `installUriClass(in:)` installs the class into, `url(from:in:)` reads `value` against, and `uriValue(for:in:)` builds a result in. |
| `path` (`Uri.file`) | `String` | (required, no default) | The filesystem path `Uri.file(path)` percent-encodes and stores as `path`, prefixed with `/` if needed (**file-encodes-segments-preserves-slashes**, **file-ensures-leading-slash**). |
| `value` (`Uri.parse`) | `String`-coercible | (required, no default) | The URI string `Uri.parse(value, strict)` decomposes via `String(value)` before matching (**parse-splits-components**). |
| `strict` (`Uri.parse`) | JavaScript truthy/falsy | falsy | When truthy, requires `value` to carry a scheme or `Uri.parse` throws (**parse-strict-requires-scheme**); never validates the scheme's own grammar. |
| `change` (`with`) | plain object or omitted | `{}` | The field overrides `with(change)` applies; a key with value `undefined` or an absent key both leave that field unchanged (**with-overrides-only-given-fields**). |
| `skipEncoding` (`toString`) | JavaScript truthy/falsy | falsy | When truthy, decodes `authority`/`path`/`query`/`fragment` for that call's return value only (**to-string-skip-encoding**). |
| `base` (`Uri.joinPath`) | `Uri` instance | (required, no default) | The `Uri` whose `path` is extended; MUST be `instanceof` the installed `Uri` constructor or a `TypeError` is thrown (**join-path-requires-uri-instance**). |
| `...segments` (`Uri.joinPath`) | zero or more strings | (none) | The path segments appended to `base`'s `path`, encoded and joined with `'/'` before insertion (**join-path-inserts-separator**, **join-path-empty-appended-is-unchanged**). |
| `value` (`url(from:in:)`) | `JSValue` | (required, no default) | The JavaScript value read as either a real `Uri` instance or a string (**url-from-string**, **url-from-uri-instance**). |
| `url` (`uriValue(for:in:)`) | `URL` | (required, no default) | The Swift `URL` bridged into a `vscode.Uri` via `Uri.parse(url.absoluteString)` (**uri-value-builds-via-parse**). |

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal, not externalized) | `Uri.parse: '{value}' must contain a scheme when 'strict' is true` | The `Error.message` `Uri.parse(value, true)` throws when `value` carries no scheme, with `{value}` substituted by `String(value)` (**parse-strict-requires-scheme**). |
| (none — literal, not externalized) | `Uri.joinPath: the base argument must be a vscode.Uri` | The `TypeError.message` `Uri.joinPath` throws when `base` is not a `Uri` instance (**join-path-requires-uri-instance**). |

Both are hardcoded English literals with no localization mechanism (no string catalog, no key lookup) anywhere in `Uri.swift`; see the `no-hardcoded-strings` row in Compliance.

## Privacy

- **Data collected**: None. `Uri.swift` neither reads nor stores any credential, token, or user-identifying data; it only encodes, decodes, and reassembles the components of a URI string a caller already holds.
- **Storage**: A `Uri` instance's own fields live only in memory, frozen for the lifetime of the JavaScript object; the class constructor itself is cached under `globalThis.__vscodeUriClass` for the lifetime of its `JSContext` (**class-installed-once-per-context**).
- **Transmission**: Nothing in this file transmits data off-device; it performs no network I/O.
- **Retention**: A `Uri` instance and the cached class constructor are retained only as long as their `JSContext` is retained; nothing here persists across a context's lifetime.

## Platform Notes

- **SwiftUI**: not applicable to this file — `Uri.swift` imports only `Foundation`, `JavaScriptCore`, `OSLog`, and `AgenticToolkitCore`, with no SwiftUI dependency; it renders nothing and observes no view state.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/Uri.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` for — no iOS target packages this file. `Uri` here names the `extension VSCodeAPI` holding `installUriClass(in:)`/`url(from:in:)`/`uriValue(for:in:)`, all inheriting `@MainActor` from `VSCodeAPI`'s own `public enum` declaration (`VSCodeAPI.swift`); `ExtensionHost.installRuntime` (`ExtensionHost.swift`, near its `defineMember("vscode", "Uri", uriClass)` call) is the one caller that installs the class eagerly, before any extension code runs.
- **Compose**: model the JavaScript `Uri` class as a plain Kotlin `data class` (immutable by construction, so no `Object.freeze` equivalent is needed) with `scheme`/`authority`/`path`/`query`/`fragment` as `val` properties and a computed `fsPath` property, over whichever embedded JS engine the Android host uses in place of `JSContext`/`JSValue` (e.g. J2V8's `V8Object`). Reproduce **file-encodes-segments-preserves-slashes** with `java.net.URLEncoder`-per-segment plus manual `/` rejoining (not a whole-string encode, for the same reason the source avoids `encodeURIComponent(path)`), and **parse-strict-requires-scheme**/**join-path-requires-uri-instance** as thrown Kotlin exceptions with the same message text, so a `.catch`-equivalent on the JS side of the bridge still reads the same wording.
- **React/Web**: this is the runtime `Uri.swift` is emulating — a real VS Code extension already runs against a genuine `vscode.Uri` implementation, so a React/Web host has no second JS-to-native boundary to bridge `Uri` across at all. The part worth keeping if a similar sandboxed-extension host is built in this style is the deliberate narrowing itself: POSIX-only paths, percent-encoded `path` versus decoded `fsPath`, and `strict` checking only presence, not grammar (see Design Decisions) — a from-scratch reimplementation should decide those five points explicitly rather than assuming full VS Code parity.
- **WinUI 3**: model `Uri` as an immutable C# `sealed record` (or a `sealed class` with only `init`-only properties) implementing `scheme`/`authority`/`path`/`query`/`fragment` as read-only properties and `fsPath`/`toString(bool)`/`toJson()` as methods — never `System.Uri`, whose own encoding, drive-letter, and authority rules do not match **file-encodes-segments-preserves-slashes**/**parse-splits-components**'s POSIX-only, percent-encode-per-segment behavior. Host it in a `ClearScript` `V8ScriptEngine` (or an equivalent embedded JS engine) so extension code sees the same `instanceof`-checkable prototype (**readonly-accessors**, **class-and-prototype-frozen**) that `JSValue.isInstance(of:)` gives Swift; map `installUriClass(in:)`'s per-context caching onto a `ConditionalWeakTable<ScriptEngine, ScriptObject>` keyed the same way `uriClassGlobalName` keys a `JSContext`. Map `Uri.parse`'s `strict` throw and `Uri.joinPath`'s base-type check onto `ScriptEngineException`s carrying the identical message text from **parse-strict-requires-scheme**/**join-path-requires-uri-instance**, and map `url(from:in:)`'s guarded `toString` invocation onto a `try`/`catch` around the `ScriptObject` call rather than an unguarded `.Invoke("toString")`, mirroring **url-from-uri-instance**'s use of `VSCodeAPI.call(_:thisArg:arguments:)` over a direct `invokeMethod`.

