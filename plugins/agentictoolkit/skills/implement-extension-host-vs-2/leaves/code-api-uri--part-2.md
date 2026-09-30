<!-- leaf: implement-extension-host-vs-2/code-api-uri--part-2 · source: extension-host-vs-code-api-uri.md -->

# Uri — continued (part 2)

**Rules** (cite as `implement-extension-host-vs-2/code-api-uri--part-2#<slug>`):

- `class-installed-once-per-context` MUST
- `class-evaluated-on-first-need` MUST
- `class-install-failure-returns-nil-and-logs` MUST
- `class-caching-write-best-effort` MUST
- `instance-fields-default-empty` MUST
- `has-authority-flag` MUST
- `instance-frozen` MUST
- `readonly-accessors` MUST
- `fs-path-derivation` MUST
- `with-overrides-only-given-fields` MUST
- `with-returns-new-instance` MUST
- `with-authority-promotes-has-authority` MUST
- `to-string-default-assembly` MUST
- `to-string-skip-encoding` MUST
- `to-json-plain-object` MUST
- `file-sets-scheme-and-authority` MUST
- `file-encodes-segments-preserves-slashes` MUST
- `file-ensures-leading-slash` MUST
- `parse-splits-components` MUST
- `parse-lowercases-scheme` MUST
- `parse-strict-requires-scheme` MUST
- `parse-non-strict-allows-schemeless` MUST
- `parse-to-string-round-trips` MUST
- `join-path-requires-uri-instance` MUST
- `join-path-inserts-separator` MUST
- `join-path-collapses-duplicate-slashes-not-dot-segments` MUST
- `join-path-preserves-other-fields` MUST
- `join-path-empty-appended-is-unchanged` MUST
- `class-and-prototype-frozen` MUST
- `frozen-members-resist-reassignment` MUST
- `url-from-string` MUST
- `url-from-uri-instance` MUST

## Behavioral Requirements

- **class-installed-once-per-context**: `installUriClass(in:)` MUST return the cached constructor already stored at `globalThis.__vscodeUriClass` (the value of `uriClassGlobalName`) without re-evaluating `uriClassSource`, whenever `context.objectForKeyedSubscript(uriClassGlobalName)` is non-`nil` and `isObject` (`Uri.swift`-`328`).
- **class-evaluated-on-first-need**: When no cached object exists, `installUriClass(in:)` MUST evaluate `uriClassSource` in `context` and return the resulting `JSValue` provided it `isObject` (`Uri.swift`-`331`).
- **class-install-failure-returns-nil-and-logs**: `installUriClass(in:)` MUST return `nil`, and MUST log an error through `VSCodeAPI.logger` naming the context via `VSCodeAPI.name(of:)`, when `context.evaluateScript(uriClassSource)` returns a value that is not `isObject` — the outcome of the source's own top-level `try`/`catch` converting an internal failure to `null` (`Uri.swift`-`339`).
- **class-caching-write-best-effort**: The `Object.defineProperty(globalThis, ..., { value: Uri, writable: false, enumerable: false, configurable: false })` write inside `uriClassSource` MUST be wrapped in its own `try`/`catch`, so a failure to define that global property MUST NOT prevent the `Uri` constructor from being usable for the evaluation that just produced it; it only means a later call to `installUriClass(in:)` in the same context finds no cached object, re-evaluates `uriClassSource`, and returns a second, distinct `Uri` constructor function (`Uri.swift`-`267`).
- **instance-fields-default-empty**: The `Uri` constructor MUST default `scheme`, `authority`, `path`, `query`, and `fragment` to `''` whenever the corresponding constructor argument is falsy (`Uri.swift`-`112`).
- **has-authority-flag**: The `Uri` constructor MUST set its internal `_hasAuthority` to `true` when the `hasAuthority` argument is truthy, or when `authority` is a non-empty string, and to `false` otherwise (`Uri.swift`).
- **instance-frozen**: Every `Uri` instance MUST be frozen via `Object.freeze(this)` inside the constructor before it is returned to any caller (`Uri.swift`).
- **readonly-accessors**: `scheme`, `authority`, `path`, `query`, `fragment`, and `fsPath` MUST be exposed only as enumerable getter-only properties on `Uri.prototype` (`Object.defineProperty` with a `get` and no `set`), never as writable data properties (`Uri.swift`-`128`).
- **fs-path-derivation**: The `fsPath` getter MUST return `decodeComponent(path)` — `decodeURIComponent(path)`, falling back to `path` unchanged when that throws on a malformed escape — prefixed with `'//' + authority` when `authority` is non-empty, and MUST return the decoded path alone otherwise (`Uri.swift`-`105`, `126`-`129`).
- **with-overrides-only-given-fields**: `with(change)` MUST replace only the fields present as own keys with a value `!== undefined` in `change` (`scheme`, `authority`, `path`, `query`, `fragment`), leaving every other field equal to the receiver's own value (`Uri.swift`-`141`).
- **with-returns-new-instance**: `with(change)` MUST construct and return a new `Uri` instance; it MUST NOT mutate the receiver, which `instance-frozen` already makes impossible (`Uri.swift`).
- **with-authority-promotes-has-authority**: `with(change)` MUST set the result's `_hasAuthority` to `true` when the receiver's own `_hasAuthority` is `true`, OR when `change.authority` is present and non-empty, even if the receiver itself had no authority (`Uri.swift`-`140`).
- **to-string-default-assembly**: `toString(skipEncoding)` called with no truthy `skipEncoding` MUST return `scheme + ':'` (omitted when `scheme` is `''`) followed by `'//' + authority` only when `_hasAuthority` is `true`, followed by `path` unchanged, followed by `'?' + query` only when `query` is non-empty, followed by `'#' + fragment` only when `fragment` is non-empty (`Uri.swift`-`170`).
- **to-string-skip-encoding**: `toString(true)` MUST decode `authority`, `path`, `query`, and `fragment` through `decodeComponent` before assembling the string described in **to-string-default-assembly**, for that call's return value only; the instance's own stored fields MUST remain unchanged (`Uri.swift`-`152`).
- **to-json-plain-object**: `toJSON()` MUST return a new plain object with own enumerable properties `scheme`, `authority`, `path`, `query`, `fragment`, and `fsPath` (read through the getter, not `this._fsPath`), so `JSON.stringify` on a `Uri` instance serializes these six values rather than `{}` — which is what `JSON.stringify` would otherwise produce, since none of a `Uri`'s properties are its own enumerable properties (`Uri.swift`-`180`).
- **file-sets-scheme-and-authority**: `Uri.file(path)` MUST construct a `Uri` with `scheme` `'file'`, `authority` `''`, and `hasAuthority` `true` (passed explicitly to the constructor, not inferred from a non-empty `authority`) (`Uri.swift`-`209`).
- **file-encodes-segments-preserves-slashes**: `Uri.file(path)` MUST percent-encode `path` by splitting on `'/'`, running `encodeURIComponent` on each non-empty segment, and rejoining with `'/'` — so `/` separators survive encoding while every other character in a segment is escaped exactly as `encodeURIComponent` escapes it (`Uri.swift`-`199`).
- **file-ensures-leading-slash**: `Uri.file(path)` MUST prepend a `'/'` to the encoded path when it does not already start with one, so the resulting `path` always begins with `'/'` (`Uri.swift`-`207`).
- **parse-splits-components**: `Uri.parse(value, strict)` MUST decompose `String(value)` into `scheme`, an authority-present flag, `authority`, `path`, `query`, and `fragment`, using a single pattern (built as a plain string handed to `new RegExp(...)`, never a regex literal, per the source's own comment on why) that captures, in order, an optional `scheme:` prefix, an optional `//authority` block, the remainder up to a `?` or `#`, an optional `?query` block, and an optional `#fragment` block; any group that does not match MUST default to `''` (`Uri.swift`-`38`, `210`-`225`).
- **parse-lowercases-scheme**: `Uri.parse(value, strict)` MUST lower-case the matched scheme before storing it, regardless of the case in `value` (`Uri.swift`).
- **parse-strict-requires-scheme**: `Uri.parse(value, true)` MUST throw a JavaScript `Error` with the message `"Uri.parse: '" + String(value) + "' must contain a scheme when 'strict' is true"` when no scheme was matched, and MUST NOT construct a `Uri` in that case (`Uri.swift`-`223`).
- **parse-non-strict-allows-schemeless**: `Uri.parse(value, strict)` MUST construct and return a `Uri` with `scheme` `''` when `strict` is falsy and `value` carries no scheme, taking no throwing path (`Uri.swift`, `224`).
- **parse-to-string-round-trips**: For any `Uri` produced by `Uri.parse`, `Uri.parse(original.toString())` MUST reproduce the same `scheme`, `authority`, `path`, `query`, and `fragment` as `original`, whether or not `original` carries an authority (`Uri.swift`-`170`, `210`-`225`).
- **join-path-requires-uri-instance**: `Uri.joinPath(base, ...segments)` MUST throw a `TypeError` with the message `'Uri.joinPath: the base argument must be a vscode.Uri'` when `base` is not `instanceof` the same `Uri` constructor performing the check, and MUST NOT construct a result in that case (`Uri.swift`-`229`).
- **join-path-inserts-separator**: `Uri.joinPath(base, ...segments)` MUST insert exactly one `'/'` between `base`'s `path` and the percent-encoded, `'/'`-joined `segments` when `base`'s `path` is non-empty and does not already end in `'/'`, and MUST NOT insert an additional `'/'` when it already ends in one (`Uri.swift`-`239`).
- **join-path-collapses-duplicate-slashes-not-dot-segments**: `Uri.joinPath(base, ...segments)` MUST collapse any run of two or more consecutive `'/'` characters in the assembled path to a single `'/'` (via the pattern matching one or more repeated `/` characters), and MUST NOT resolve `'.'` or `'..'` path segments in the result (`Uri.swift`, `240`-`241`).
- **join-path-preserves-other-fields**: `Uri.joinPath(base, ...segments)` MUST return a `Uri` whose `scheme`, `authority`, `query`, `fragment`, and `hasAuthority` equal `base`'s own, changing only `path` (`Uri.swift`-`244`).
- **join-path-empty-appended-is-unchanged**: `Uri.joinPath(base)`, called with no `segments`, MUST return a `Uri` whose `path` equals `base`'s `path` unchanged, because the encoded, joined suffix of zero segments is `''` (`Uri.swift`-`236`).
- **class-and-prototype-frozen**: `uriClassSource` MUST call `Object.freeze(Uri.prototype)` and then `Object.freeze(Uri)` after every static and prototype member is attached, within the same evaluation that built them, before caching the constructor or handing it to any caller (`Uri.swift`-`254`).
- **frozen-members-resist-reassignment**: Once frozen, an assignment to a static method (`Uri.parse = ...`) or a prototype method (`Uri.prototype.toString = ...`) from extension code MUST leave the original function in place — in sloppy-mode code the assignment expression evaluates to the assigned value while the property itself is untouched; in strict-mode code the same assignment MUST throw `TypeError` instead — and in neither case is the underlying function replaced (`Uri.swift`-`301`).
- **url-from-string**: `url(from:in:)` MUST return `URL(string:)` of the JavaScript string's contents when `value.isString` is `true`, and `nil` when `value.toString()` is `nil` or `URL(string:)` itself fails to parse the result (`Uri.swift`-`370`).
- **url-from-uri-instance**: `url(from:in:)` MUST, for a `value` that `isInstance(of:)` the constructor `installUriClass(in:)` returns, read its `toString` property and invoke it through `VSCodeAPI.call(_:thisArg:arguments:)` — never `JSValue.invokeMethod(_:withArguments:)` — with `value` as `thisArg` and no arguments, then return `URL(string:)` of the result only when that call's outcome is `.returned` with a non-`nil` `JSValue` for which `isString` is `true` (`Uri.swift`-`376`).
