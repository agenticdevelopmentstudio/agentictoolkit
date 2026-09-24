---
id: b0e815fd-22cc-4d58-a0c6-001c21bad468
title: Uri
domain: agentictoolkit://recipes/extension-host-vs-code-api-uri
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The frozen vscode.Uri JavaScript class VSCodeAPI installs, plus the url(from:in:)
  and uriValue(for:in:) Swift bridge built on top of it.
platforms:
- swift
- macos
tags:
- extension-host
- vscode-api
- uri
- javascriptcore
depends-on: []
related:
- agentictoolkit://recipes/extension-host-vs-code-api-js-value-bridge
- agentictoolkit://recipes/extension-host-vs-code-api-main-thread-commands
- agentictoolkit://recipes/extension-host-vs-code-api-main-thread-diagnostics
- agentictoolkit://recipes/extension-host-vs-code-api-extension-webview-presenting
- agentictoolkit://recipes/extension-host-vs-code-api-language-model-message-vocabulary
references:
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/Uri.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Extensions/UriTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/VSCodeAPI.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/Host/ExtensionHost.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/project.yml (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Uri

## Overview

`Uri.swift` is an `extension VSCodeAPI` (`VSCodeAPI` is the `@MainActor public enum` every `vscode.*` adaptor installs through) holding the JavaScript `vscode.Uri` class and the Swift-facing bridge built on it. `installUriClass(in:)` evaluates a single ES5 source string (`uriClassSource`) that builds a real JavaScript constructor function — `scheme`/`authority`/`path`/`query`/`fragment`/`fsPath` as frozen prototype getters, `with`/`toString`/`toJSON` as prototype methods, `Uri.file`/`Uri.parse`/`Uri.joinPath` as static methods — and caches the result under a non-enumerable global so every context builds the class at most once. `url(from:in:)` reads a `URL` out of a JavaScript value that is either a real `Uri` instance or a plain string, the two shapes VS Code's own API accepts wherever it documents a `Uri | string` parameter, answering `nil` for anything else without raising. `uriValue(for:in:)` is the reverse: it builds a `vscode.Uri` instance for a Swift `URL` by calling `Uri.parse(url.absoluteString)`. The class is deliberately narrower than real VS Code's `Uri` in five stated ways (POSIX-only paths, `path` kept percent-encoded while `fsPath` is decoded, `query`/`fragment` never decoded except by `toString(true)`, `strict` checking only that a scheme is present, and `joinPath` collapsing duplicate `/` without resolving `.`/`..`); see Design Decisions.

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
- **url-from-rejects-non-uri-non-string**: `url(from:in:)` MUST return `nil`, without reading any property off `value`, for a `value` that is neither `isString` nor `isInstance(of:)` the installed `Uri` constructor — including a number, a plain object shaped like a `Uri`, and JavaScript `undefined` (`Uri.swift`-`373`).
- **url-from-swallows-to-string-failure**: `url(from:in:)` MUST return `nil` — with no signal to its caller — when `value`'s `toString` property is absent or not `isObject`, when the guarded call to it does not settle as `.returned` (i.e., it `.threw` or was `.unavailable`), or when the returned value is not a JavaScript string (`Uri.swift`-`378`).
- **uri-value-builds-via-parse**: `uriValue(for:in:)` MUST call `Uri.parse` directly via `JSValue.call(withArguments:)` — not through `VSCodeAPI.call(_:thisArg:arguments:)` — passing `[url.absoluteString]` and no `strict` argument, so the throwing branch of **parse-strict-requires-scheme** is never reached from this path (`Uri.swift`-`430`).
- **uri-value-nil-when-class-or-parse-unavailable**: `uriValue(for:in:)` MUST return `nil` when `installUriClass(in:)` returns `nil`, when the constructor's `parse` property is absent or not `isObject`, or when the call's result is `nil`, `isUndefined`, or `isNull` (`Uri.swift`-`431`).
- **uri-value-round-trips-with-url-from**: For a `URL` built in Swift, `url(from:in:)` applied to `uriValue(for:in:)`'s result MUST return a `URL` whose `absoluteString` equals the original `URL`'s `absoluteString` (`Uri.swift`-`432`).
- **main-actor-isolation**: `installUriClass(in:)`, `url(from:in:)`, and `uriValue(for:in:)` MUST run only on the main actor, inherited from `VSCodeAPI`'s own `@MainActor public enum` declaration, because every `JSContext`/`JSValue` argument they take is a non-`Sendable` JavaScriptCore type that the Swift compiler already confines to the isolation domain that created it (`Uri.swift`-`37`).

## Appearance

Not applicable — this is a JavaScript value-type class and its Swift bridge, not a visual component.

## States

Not applicable — this is a JavaScript value-type class and its Swift bridge, not a visual component.

## Accessibility

Not applicable — this is a JavaScript value-type class and its Swift bridge, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|--------------|-------|----------|
| uri-001 | file-sets-scheme-and-authority | `Uri.file('/tmp/example.txt')`. | `scheme == 'file'`, `path == '/tmp/example.txt'`, `authority == ''` (`UriTests.uriFileSetsSchemeAndPath`). |
| uri-002 | file-encodes-segments-preserves-slashes | `Uri.file('/tmp/a b/c.txt')`. | `path == '/tmp/a%20b/c.txt'` — the space is encoded, the slashes are not (`UriTests.uriFilePercentEncodesASpaceButNotTheSlashes`). |
| uri-003 | file-ensures-leading-slash | `Uri.file('tmp/x.txt')` (no leading `/` supplied). | `path` starts with `/` (traced to the `if (encoded.charAt(0) !== '/')` branch at `Uri.swift`-`207`; no dedicated test — every given test already supplies a leading `/`). |
| uri-004 | parse-splits-components | `Uri.parse('https://example.com/a/b?x=1#frag')`. | `scheme == 'https'`, `authority == 'example.com'`, `path == '/a/b'`, `query == 'x=1'`, `fragment == 'frag'` (`UriTests.uriParseSplitsSchemeAuthorityPathQueryAndFragment`). |
| uri-005 | parse-splits-components, parse-non-strict-allows-schemeless | `Uri.parse('mailto:a@b.com')`. | `authority == ''`, `scheme == 'mailto'`, and `toString()` equals `'mailto:a@b.com'` — no `//` reappears (`UriTests.uriParseWithNoAuthorityMarkerOmitsTheSlashesOnToString`). |
| uri-006 | parse-strict-requires-scheme | `Uri.parse('not-a-uri-at-all', true)`. | Throws a JavaScript `Error` whose `message` is `"Uri.parse: 'not-a-uri-at-all' must contain a scheme when 'strict' is true"` (traced to `Uri.swift`-`223`; no dedicated test in `UriTests.swift` exercises the `strict` parameter — see Compliance). |
| uri-007 | parse-lowercases-scheme | `Uri.parse('HTTPS://example.com/a')`. | `scheme == 'https'` (traced to the `.toLowerCase()` call at `Uri.swift`; no dedicated test — every given test already supplies a lower-case scheme). |
| uri-008 | fs-path-derivation | `Uri.parse('file:///a%20b')`. | `path == '/a%20b'`, `fsPath == '/a b'` (`UriTests.fsPathDecodesWherePathIsEncoded`). |
| uri-009 | fs-path-derivation | `Uri.parse('untitled:Untitled-1')`. | `path == 'Untitled-1'`, `fsPath == 'Untitled-1'` (`UriTests.fsPathIsSaneForANonFileScheme`). |
| uri-010 | with-overrides-only-given-fields | `Uri.file('/a/b').with({ path: '/a/c' })`. | `path == '/a/c'`, `scheme == 'file'` (unchanged) (`UriTests.withReplacesOnlyWhatIsGiven`). |
| uri-011 | with-returns-new-instance, instance-frozen | `var base = Uri.file('/a/b'); var changed = base.with({ path: '/a/c' });` then read `base`. | `base.path == '/a/b'` — the receiver is untouched (`UriTests.withLeavesTheReceiverUntouched`). |
| uri-012 | with-authority-promotes-has-authority | `Uri.parse('mailto:a@b.com').with({ authority: 'example.com' }).toString()`. | Result begins `'mailto://example.com'` — `hasAuthority` flips to `true` even though the receiver had none (traced to `Uri.swift`-`140`; no dedicated test). |
| uri-013 | to-string-default-assembly, parse-to-string-round-trips | `Uri.parse('https://example.com/a/b?x=1#frag').toString()`, then `Uri.parse(...)` of that result. | Every component (`scheme`, `authority`, `path`, `query`, `fragment`) of the round-tripped `Uri` equals the original's (`UriTests.toStringRoundTripsThroughParseToAnEqualUri`). |
| uri-014 | to-string-default-assembly, parse-to-string-round-trips | `Uri.parse('mailto:a@b.com').toString()`, then `Uri.parse(...)` of that result, then `.toString()` again. | Both `toString()` outputs are identical (`UriTests.toStringRoundTripsForANoAuthorityScheme`). |
| uri-015 | to-string-skip-encoding | `Uri.parse('https://example.com/a%20b').toString(true)`. | Returns `'https://example.com/a b'` — `path` decoded for this call only, stored `path` unchanged (traced to `Uri.swift`-`152`; no dedicated test exists for `skipEncoding` in `UriTests.swift` — see Compliance). |
| uri-016 | join-path-inserts-separator | `Uri.joinPath(Uri.file('/a/b'), 'c', 'd.txt')`. | `path == '/a/b/c/d.txt'` (`UriTests.joinPathInsertsASlashWhenTheBaseHasNoTrailingOne`). |
| uri-017 | join-path-inserts-separator | `Uri.joinPath(Uri.file('/a/b/'), 'c.txt')`. | `path == '/a/b/c.txt'` — no doubled slash (`UriTests.joinPathDoesNotDoubleASlashWhenTheBaseAlreadyHasATrailingOne`). |
| uri-018 | join-path-collapses-duplicate-slashes-not-dot-segments | `Uri.joinPath(Uri.file('/a/b/'), '/c')`. | `path == '/a/b/c'` — the doubled `/` the naive concatenation would produce is collapsed to one (traced to the `MULTIPLE_SLASHES` replace at `Uri.swift`-`241`; no dedicated test produces a double slash to collapse). |
| uri-019 | join-path-empty-appended-is-unchanged | `Uri.joinPath(Uri.file('/a/b'))` (no extra segments). | `path == '/a/b'`, unchanged (traced to `Uri.swift`-`236`; no dedicated test). |
| uri-020 | join-path-requires-uri-instance | `Uri.joinPath({ path: '/a' }, 'b')` (a plain object, not a `Uri`). | Throws `TypeError` with message `'Uri.joinPath: the base argument must be a vscode.Uri'` (traced to `Uri.swift`-`229`; no dedicated test). |
| uri-021 | readonly-accessors, instance-frozen, class-and-prototype-frozen | `Uri.file('/tmp') instanceof Uri`, `Uri.parse('https://h/a') instanceof Uri`, and `({ scheme: 'file', path: '/tmp' }) instanceof Uri`. | First two are `true`; the plain object is `false` (`UriTests.uriInstancesAreInstancesOfUri`). |
| uri-022 | to-json-plain-object | `Uri.parse('file://server/share/a%20b').toJSON()`, then `JSON.stringify(Uri.file('/tmp'))`. | `toJSON()` carries `scheme`, `authority`, `path`, `fsPath`, `query`, `fragment`; `JSON.stringify` output contains `"path":"/tmp"` (`UriTests.toJSONAnswersEveryComponentIncludingFsPath`). |
| uri-023 | class-and-prototype-frozen, frozen-members-resist-reassignment | `Object.isFrozen(Uri)`, `Object.isFrozen(Uri.prototype)`, then reassign `Uri.parse` and `Uri.prototype.toString` and re-read both. | Both `isFrozen` checks are `true`; both properties still equal their original functions after the reassignment attempt (`UriTests.uriClassAndPrototypeAreFrozen`). |
| uri-024 | url-from-uri-instance | `VSCodeAPI.url(from: Uri.file('/tmp/example.txt'), in: context)`. | Returns a `URL` whose `path == '/tmp/example.txt'` (`UriTests.urlFromAcceptsARealUriInstance`). |
| uri-025 | url-from-string | `VSCodeAPI.url(from: 'https://example.com/a' as JSValue, in: context)`. | Returns a `URL` whose `absoluteString == 'https://example.com/a'` (`UriTests.urlFromAcceptsABareString`). |
| uri-026 | url-from-rejects-non-uri-non-string | `VSCodeAPI.url(from: JSValue(double: 42, in: context), in: context)`. | Returns `nil` (`UriTests.urlFromAnswersNilForANumberRatherThanAWrongURL`). |
| uri-027 | url-from-rejects-non-uri-non-string | `VSCodeAPI.url(from: ({ path: '/a/b', scheme: 'file' }), in: context)`. | Returns `nil` — no property is read off the arbitrary object (`UriTests.urlFromAnswersNilForAnArbitraryObject`). |
| uri-028 | url-from-rejects-non-uri-non-string | `VSCodeAPI.url(from: JSValue(undefinedIn: context), in: context)`. | Returns `nil` (`UriTests.urlFromAnswersNilForUndefined`). |
| uri-029 | url-from-swallows-to-string-failure | A real `Uri` instance whose `toString` property has been reassigned, from sloppy-mode extension code, to a function that throws; call `VSCodeAPI.url(from:in:)` on it. | Returns `nil` with no exception surfaced to the caller (traced to the `.threw`/`.unavailable` branches folded into the `guard case .returned` at `Uri.swift`-`377`; no dedicated test — reassignment onto a frozen `Uri.prototype.toString` is refused per **frozen-members-resist-reassignment**, so this path is reachable only via a subclass that shadows `toString` on its own instance, which no given test constructs). |
| uri-030 | uri-value-builds-via-parse, uri-value-round-trips-with-url-from | `VSCodeAPI.uriValue(for: URL(string: "https://example.com/a/b?x=1#frag")!, in: context)`, then `VSCodeAPI.url(from:in:)` on that result. | Round-tripped `URL.absoluteString` equals the original's (`UriTests.aUrlCrossingToJSAndBackIsUnchanged`). |
| uri-031 | uri-value-nil-when-class-or-parse-unavailable | `VSCodeAPI.uriValue(for:in:)` called with a `JSContext` in which `installUriClass(in:)` has been made to fail (e.g., `evaluateScript` disabled). | Returns `nil` (traced to the `guard let uriClass = installUriClass(in: context), ... else { return nil }` at `Uri.swift`-`426`; no dedicated test forces `installUriClass(in:)` to fail). |
| uri-032 | class-installed-once-per-context | Call `VSCodeAPI.installUriClass(in: context)` twice on the same `context`. | Both calls return the identical `JSValue` object (`===` in JavaScript), because the second call finds `globalThis.__vscodeUriClass` already set (traced to `Uri.swift`-`328`; every `UriTests.swift` test's `makeContext()` relies on this by installing once per test, but no test asserts identity across two direct calls). |
| uri-033 | main-actor-isolation | Any `@MainActor`-isolated call site (e.g. `ExtensionHost.installRuntime`, `Uri.swift`) calls `VSCodeAPI.uriValue(for:in:)` or `VSCodeAPI.url(from:in:)` synchronously. | Compiles with no actor-isolation diagnostic, because these members inherit `@MainActor` from `VSCodeAPI`'s own declaration and every real call site in this codebase is itself `@MainActor` (verified by inspection: `VSCodeAPI.swift`'s `@MainActor public enum VSCodeAPI`, no `nonisolated` on these three functions). |

## Edge Cases

- **Null/empty input**: `Uri.parse('')` MUST produce a `Uri` with every field `''` and `hasAuthority` `false`, taking the non-strict path (**parse-non-strict-allows-schemeless**). `Uri.file('')` MUST still produce a leading `'/'` (**file-ensures-leading-slash**) since the empty string is not itself falsy-as-a-path in the encoding step. `with()` and `with({})` (no argument, or an empty object) MUST return a `Uri` equal in every field to the receiver, since no key of `change` has a value `!== undefined` (**with-overrides-only-given-fields**). `Uri.joinPath(base)` with zero appended segments MUST leave `path` unchanged (**join-path-empty-appended-is-unchanged**).
- **Boundary values**: not applicable — no function in `Uri.swift` constrains `path`, `scheme`, `authority`, `query`, `fragment`, or the number of `joinPath` segments to a minimum or maximum length or count; none is declared in the source.
- **Concurrent access**: not applicable to a `Uri` instance itself — it is frozen at construction (**instance-frozen**) and every accessor is a pure read (**readonly-accessors**), so there is nothing for two readers to race over. The class object itself is a different story — see **lazy-adoption-race** below, and **class-caching-write-best-effort** for the narrower, fully-specified case of the global caching write itself failing (which produces two distinct-but-equally-real `Uri` classes, not a race between a real and a counterfeit one).
- **lazy-adoption-race**: `ExtensionHost.installRuntime` installs the frozen `Uri` eagerly, before any extension code runs. If that eager install failed or was skipped, the first `installUriClass(in:)` call MUST adopt whatever object already sits under `uriClassGlobalName`, real or not, and `uriValue(for:in:)` MUST call that object's `parse` directly (**uri-value-builds-via-parse**), not through `VSCodeAPI.call(_:thisArg:arguments:)`. An extension-supplied `parse` that throws therefore lands in `ExtensionHost.pendingException` rather than being returned to `uriValue(for:in:)`'s caller. The source's doc comment names this as the one accepted residual corner of the original defect, narrowed by the freeze rather than eliminated, and no test exercises it.
- **Error states**: when `function.context` is `nil` in the `VSCodeAPI.call(_:thisArg:arguments:)` helper `url(from:in:)` depends on (**url-from-uri-instance**), that helper answers `.unavailable`, which `url(from:in:)`'s guard converts to a plain `nil` with no further signal (**url-from-swallows-to-string-failure**) — this is the documented, deliberate shape of `.unavailable`, not a swallowed error. `Uri.parse(value, true)` with no scheme throws a JavaScript `Error` rather than swallowing the failure (**parse-strict-requires-scheme**); that throw is not caught anywhere in `Uri.swift` itself, so it propagates to whatever installed `context.exceptionHandler` or invoked the call, per that caller's own contract.
- **Offline/disconnected state**: not applicable — `Uri.swift` performs no network or file-system I/O of its own; every member only builds or reads in-memory `JSValue`/`URL` values already resident in a caller-supplied `JSContext`.

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

## Deep Linking

Not applicable: `Uri.swift` has no user-facing navigation surface or URL scheme of its own; every member only builds or reads a `Uri`/`URL` value already resident in a caller-supplied `JSContext` or passed in from Swift.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal, not externalized) | `Uri.parse: '{value}' must contain a scheme when 'strict' is true` | The `Error.message` `Uri.parse(value, true)` throws when `value` carries no scheme, with `{value}` substituted by `String(value)` (**parse-strict-requires-scheme**). |
| (none — literal, not externalized) | `Uri.joinPath: the base argument must be a vscode.Uri` | The `TypeError.message` `Uri.joinPath` throws when `base` is not a `Uri` instance (**join-path-requires-uri-instance**). |

Both are hardcoded English literals with no localization mechanism (no string catalog, no key lookup) anywhere in `Uri.swift`; see the `no-hardcoded-strings` row in Compliance.

## Accessibility Options

Not applicable: `Uri.swift` renders no UI and has no motion, contrast, or color-differentiation behavior to adapt — it imports only `Foundation`, `JavaScriptCore`, `OSLog`, and `AgenticToolkitCore`.

## Feature Flags

Not applicable: no feature flag or `{{app_prefix}}`-keyed toggle gates any member of this file; `installUriClass(in:)`, `url(from:in:)`, and `uriValue(for:in:)` are unconditionally available for any `JSContext`/`URL` a caller supplies.

## Analytics

Not applicable: `Uri.swift` contains no analytics event, telemetry call, or event-name literal of any kind.

## Privacy

- **Data collected**: None. `Uri.swift` neither reads nor stores any credential, token, or user-identifying data; it only encodes, decodes, and reassembles the components of a URI string a caller already holds.
- **Storage**: A `Uri` instance's own fields live only in memory, frozen for the lifetime of the JavaScript object; the class constructor itself is cached under `globalThis.__vscodeUriClass` for the lifetime of its `JSContext` (**class-installed-once-per-context**).
- **Transmission**: Nothing in this file transmits data off-device; it performs no network I/O.
- **Retention**: A `Uri` instance and the cached class constructor are retained only as long as their `JSContext` is retained; nothing here persists across a context's lifetime.

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via the `Loggable` protocol `VSCodeAPI` conforms to) | Category: `VSCodeAPI`

| Event | Level | Message |
|-------|-------|---------|
| `installUriClass(in:)` failure | error | `Could not install the 'vscode.Uri' class in context '<name(of: context)>'; it stays the shim's not-implemented stub` |

This is the one logging call `Uri.swift` makes (**class-install-failure-returns-nil-and-logs**); no other member of this file writes to `VSCodeAPI.logger`, and `url(from:in:)`/`uriValue(for:in:)` return `nil` on every failure path with no log call of their own.

## Platform Notes

- **SwiftUI**: not applicable to this file — `Uri.swift` imports only `Foundation`, `JavaScriptCore`, `OSLog`, and `AgenticToolkitCore`, with no SwiftUI dependency; it renders nothing and observes no view state.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/Uri.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` for — no iOS target packages this file. `Uri` here names the `extension VSCodeAPI` holding `installUriClass(in:)`/`url(from:in:)`/`uriValue(for:in:)`, all inheriting `@MainActor` from `VSCodeAPI`'s own `public enum` declaration (`VSCodeAPI.swift`); `ExtensionHost.installRuntime` (`ExtensionHost.swift`, near its `defineMember("vscode", "Uri", uriClass)` call) is the one caller that installs the class eagerly, before any extension code runs.
- **Compose**: model the JavaScript `Uri` class as a plain Kotlin `data class` (immutable by construction, so no `Object.freeze` equivalent is needed) with `scheme`/`authority`/`path`/`query`/`fragment` as `val` properties and a computed `fsPath` property, over whichever embedded JS engine the Android host uses in place of `JSContext`/`JSValue` (e.g. J2V8's `V8Object`). Reproduce **file-encodes-segments-preserves-slashes** with `java.net.URLEncoder`-per-segment plus manual `/` rejoining (not a whole-string encode, for the same reason the source avoids `encodeURIComponent(path)`), and **parse-strict-requires-scheme**/**join-path-requires-uri-instance** as thrown Kotlin exceptions with the same message text, so a `.catch`-equivalent on the JS side of the bridge still reads the same wording.
- **React/Web**: this is the runtime `Uri.swift` is emulating — a real VS Code extension already runs against a genuine `vscode.Uri` implementation, so a React/Web host has no second JS-to-native boundary to bridge `Uri` across at all. The part worth keeping if a similar sandboxed-extension host is built in this style is the deliberate narrowing itself: POSIX-only paths, percent-encoded `path` versus decoded `fsPath`, and `strict` checking only presence, not grammar (see Design Decisions) — a from-scratch reimplementation should decide those five points explicitly rather than assuming full VS Code parity.
- **WinUI 3**: model `Uri` as an immutable C# `sealed record` (or a `sealed class` with only `init`-only properties) implementing `scheme`/`authority`/`path`/`query`/`fragment` as read-only properties and `fsPath`/`toString(bool)`/`toJson()` as methods — never `System.Uri`, whose own encoding, drive-letter, and authority rules do not match **file-encodes-segments-preserves-slashes**/**parse-splits-components**'s POSIX-only, percent-encode-per-segment behavior. Host it in a `ClearScript` `V8ScriptEngine` (or an equivalent embedded JS engine) so extension code sees the same `instanceof`-checkable prototype (**readonly-accessors**, **class-and-prototype-frozen**) that `JSValue.isInstance(of:)` gives Swift; map `installUriClass(in:)`'s per-context caching onto a `ConditionalWeakTable<ScriptEngine, ScriptObject>` keyed the same way `uriClassGlobalName` keys a `JSContext`. Map `Uri.parse`'s `strict` throw and `Uri.joinPath`'s base-type check onto `ScriptEngineException`s carrying the identical message text from **parse-strict-requires-scheme**/**join-path-requires-uri-instance**, and map `url(from:in:)`'s guarded `toString` invocation onto a `try`/`catch` around the `ScriptObject` call rather than an unguarded `.Invoke("toString")`, mirroring **url-from-uri-instance**'s use of `VSCodeAPI.call(_:thisArg:arguments:)` over a direct `invokeMethod`.

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | passed | Security |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

`separation-of-concerns` passes because `Uri.swift`'s only responsibility is building the `vscode.Uri` class and bridging it to `URL`; it does not install other `vscode.*` members, decode command arguments, or manage a `JSContext`'s lifecycle — those responsibilities stay in `VSCodeAPI.swift` and `ExtensionHost.swift` (see Overview). `unit-test-coverage` is partial: `UriTests.swift` directly exercises `Uri.file`, the non-strict shape of `Uri.parse`, `fsPath`, `with`, the default `toString()`/round-trip, both `joinPath` separator cases, `instanceof`, `toJSON`, class/prototype freezing, and both bridge functions including the full round trip — but no test exercises `Uri.parse`'s `strict` throw (**parse-strict-requires-scheme**), `toString(true)`'s decoding (**to-string-skip-encoding**), `Uri.joinPath`'s base-type `TypeError` (**join-path-requires-uri-instance**) or its duplicate-slash collapsing (**join-path-collapses-duplicate-slashes-not-dot-segments**), or a forced `installUriClass(in:)` failure (**class-install-failure-returns-nil-and-logs**). `explicit-error-handling` is partial: the primary throwing paths are genuinely explicit and typed (**parse-strict-requires-scheme**, **join-path-requires-uri-instance**), but `url(from:in:)`'s and `uriValue(for:in:)`'s `nil`-returning guard branches produce no signal to any caller beyond the `nil` itself, and **lazy-adoption-race** (see Edge Cases) leaves one path where a caller-side signal from a hostile `Uri.parse` is not guaranteed to be caught at all. `input-sanitization` passes because `url(from:in:)` refuses to read a `path`-shaped property off an arbitrary object and never duck-types a value into a `URL` — it accepts only a genuine string or a genuine `Uri` instance verified via `instanceof` (**url-from-rejects-non-uri-non-string**). `no-hardcoded-strings` fails because both error messages `Uri.parse` and `Uri.joinPath` throw are English literals with no localization mechanism (see Localization).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
