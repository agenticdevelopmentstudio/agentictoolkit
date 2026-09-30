<!-- leaf: implement-extension-host-vs-2/code-api-uri--part-4 · source: extension-host-vs-code-api-uri.md -->

# Uri — continued (part 4)

## Design Decisions

**Decision**: `Uri.swift` implements five deliberate narrowings of real VS Code's `Uri`: no Windows drive-letter/UNC handling in `Uri.file` (POSIX-only paths); `path` stays percent-encoded while `fsPath` is `decodeURIComponent(path)` with a same-`try`/`catch` fallback to the raw path; `query`/`fragment` are never decoded by their own getters or by `toString()`'s default output, only by `toString(true)`; `strict` in `Uri.parse` checks only that some scheme is present, not the scheme's own grammar; and `Uri.joinPath` collapses duplicate `/` but does not resolve `.`/`..` segments.
**Rationale**: each is traced to `Uri.swift`'s own header comment as a stated boundary, not an oversight — the host only ever runs on macOS, and nothing in the tasks this class was built for constructs or joins a path containing `.`/`..` or needs Windows path semantics. See **file-encodes-segments-preserves-slashes**, **fs-path-derivation**, **to-string-skip-encoding**, **parse-strict-requires-scheme**, and **join-path-collapses-duplicate-slashes-not-dot-segments**.
**Approved**: pending

**Decision**: the URI-splitting pattern in `uriClassSource` is built as a plain JavaScript string handed to `new RegExp(...)`, never written as a `/…/` regex literal.
**Rationale**: the pattern needs an unescaped `/` inside its own text to match a URI's own path separators, and a `/…/` literal's delimiter would end early on the first unescaped `/` inside it; building the string directly means nothing in the pattern needs escaping in either JavaScript's or Swift's string-literal reader, which the source's own comment calls "the property worth having when this source cannot be compiled and exercised before it ships." See **parse-splits-components**.
**Approved**: pending

**Decision**: `url(from:in:)` reads `value`'s `toString` property and calls it through `VSCodeAPI.call(_:thisArg:arguments:)` rather than `JSValue.invokeMethod(_:withArguments:)`, while `uriValue(for:in:)` calls `Uri.parse` directly via `JSValue.call(withArguments:)`, unguarded.
**Rationale**: `url(from:in:)` accepts a `value` the bridge does not control — an extension could subclass `vscode.Uri` and shadow `toString` — so a throwing `toString` must be caught the same way a hostile `.then` getter is, rather than landing in `ExtensionHost.pendingException`. `uriValue(for:in:)` calls the constructor's *own* `Uri.parse` (never `strict`), which is safe unguarded only when `installUriClass(in:)` returned the genuinely frozen class `uriClassSource` builds — the residual risk when it did not is recorded under **lazy-adoption-race**. See **url-from-uri-instance** and **uri-value-builds-via-parse**.
**Approved**: pending

**Decision**: `installUriClass(in:)`'s caching write (`Object.defineProperty(globalThis, uriClassGlobalName, ...)`) is wrapped in its own `try`/`catch` inside `uriClassSource`, separate from the outer `try`/`catch` that produces `null` on a construction failure.
**Rationale**: per the source's own comment, "caching is an optimisation ... the class works without it, just re-evaluated per call" — a failure to define the global property must not be conflated with a failure to build the class itself, since the class returned from that same evaluation is still fully usable for its own caller. See **class-caching-write-best-effort**.
**Approved**: pending

**Decision**: this recipe is deliberately larger than sibling `extension-host-vs-code-api-js-value-bridge`, which documents a smaller, stateless helper in the same directory.
**Rationale**: `Uri.swift` builds and freezes an entire JavaScript class (six getters, three prototype methods, three static methods, a caching global, and two Swift-facing bridge functions) rather than a handful of one-line pure functions, so its behavioral surface is proportionate to its actual scope, per the cross-recipe-consistency guideline's "genuinely warranted" allowance for a depth disparity between siblings of different real complexity.
**Approved**: pending
