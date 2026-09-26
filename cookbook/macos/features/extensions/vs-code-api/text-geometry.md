---
id: 214977ad-b330-4e32-97cf-9383ad9d4e8c
title: TextGeometry
domain: agentictoolkit://cookbook/macos/features/extensions/vs-code-api/text-geometry
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: The VSCodeAPI extension installing real, instanceof-checkable vscode.Position,
  vscode.Range and vscode.Location classes, and the Swift bridge that reads and
  builds them.
platforms:
- swift
- macos
tags:
- extension-host
- vscode-api
- text-geometry
- javascriptcore
- bridge
depends-on: []
related:
- agentictoolkit://cookbook/macos/features/extensions/host
- agentictoolkit://cookbook/macos/features/extensions/vs-code-api/diagnostic-types
references:
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/TextGeometry.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitMacOSTests/Extensions/TextGeometryTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/VSCodeAPI.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/Uri.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/DiagnosticTypes.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Core/Loggable.swift (agentictoolkit)
- packages/apple/AgenticToolkit/project.yml (agentictoolkit)
approved-by: ''
approved-date: ''
---

# TextGeometry

## Overview

`TextGeometry.swift` is a `VSCodeAPI` extension that gives the extension host's embedded `JSContext` real, `instanceof`-checkable implementations of `vscode.Position`, `vscode.Range` and `vscode.Location` (`vscode.d.ts`, `:408-513` and `:6960-6979` at the pinned commit named in the file's own header), plus the Swift-side mirror types (`ExtensionPosition`, `ExtensionRange`, `ExtensionLocation`) and bidirectional bridging functions that let host code read an extension-built value back into Swift and build a real JS instance from a Swift value to hand back to an extension. `Position` and `Range` ship the declared `vscode.d.ts` surface complete — every member the declaration names, not a subset — because both are prerequisites of later editor APIs; `Location` is `Uri` plus `Range` and is built in this same file, one evaluation later, because its constructor must call `new Range(...)`. All three classes are constructed inside one evaluated IIFE so `Range`'s constructor can see `Position` and `Location`'s constructor can see `Range` as ordinary lexical bindings. Every instance of `Position` and `Range` is frozen via `Object.freeze`; `Location` is the one exception — its `uri`/`range` are plain, declared-mutable stored properties, so its instances are deliberately left unfrozen while its class and prototype are frozen like the other two. The `Range` constructor's own `start.isBefore(end)` check is the only place the start/end swap invariant is enforced; nothing on the Swift side reorders a pair before or after crossing the JS boundary.

## Behavioral Requirements

- **main-actor-isolation**: Every function this file adds MUST execute on the main actor; `VSCodeAPI` is declared `@MainActor` (`VSCodeAPI.swift`), a caseless `enum` with no state of its own, and this file adds no conformance of its own.
- **install-once-per-context**: `installTextGeometryClasses(in:)` MUST evaluate `textGeometryClassesSource` at most once for a given `JSContext`; when the context already carries an object-valued cached container under the global name `__vscodeTextGeometryClasses` (`textGeometryGlobalName`), it MUST reuse that cached container rather than re-evaluating the source.
- **cache-write-optional**: When the trailing cache-write `Object.defineProperty(globalThis, textGeometryGlobalName, ...)` inside the evaluated source fails, the evaluation MUST still return the freshly built `{ Position, Range, Location }` result for that one call rather than treat the failed cache write as an error; the failure MUST be caught and silently ignored.
- **member-presence-check-runs-every-call**: Whether the container comes from the cache or a fresh evaluation, `installTextGeometryClasses(in:)` MUST check, on every call, that `Position`, `Range` and `Location` each resolve to an object-valued property of the container.
- **install-evaluate-failure**: `installTextGeometryClasses(in:)` MUST return `nil`, and MUST log an error via `VSCodeAPI.logger`, when `context.evaluateScript(textGeometryClassesSource)` returns a value that is `nil` or not an object.
- **install-installed-error**: `installTextGeometryClasses(in:)` MUST return `nil`, and MUST log an error naming the underlying message, when the evaluated result carries a non-`undefined` `installedError` property — the shape the evaluated source's own outer catch returns instead of discarding the caught error.
- **install-missing-member**: `installTextGeometryClasses(in:)` MUST return `nil`, and MUST log an error, when the resolved container is missing an object-valued `Position`, `Range`, or `Location` property.
- **install-failure-is-non-fatal**: `installTextGeometryClasses(in:)` MUST return `nil` rather than throw a Swift error or crash on any installation failure, so a context where installation fails is recoverable: `vscode.Position`/`vscode.Range`/`vscode.Location` simply stay the shim's not-implemented stub for that context.
- **members-returned-as-dictionary**: On success, `installTextGeometryClasses(in:)` MUST return a `[String: JSValue]` keyed `"Position"`, `"Range"`, `"Location"`.
- **single-evaluation-builds-all-three**: `textGeometryClassesSource` MUST construct `Position`, `Range` and `Location` inside one evaluated IIFE, so `Range`'s constructor can call `new Position` and `Location`'s constructor can call `new Range` as ordinary lexical bindings rather than by re-finding them off `globalThis`.
- **position-constructor-validates-line**: `Position`'s constructor MUST throw when `line` is negative.
- **position-constructor-validates-character**: `Position`'s constructor MUST throw, independently of the `line` check, when `character` is negative.
- **position-fields-readonly**: `Position.prototype.line` and `.character` MUST be defined as read-only accessor properties over private backing fields, not plain writable own properties.
- **position-instance-frozen**: Every constructed `Position` instance MUST be frozen via `Object.freeze` at the end of its constructor.
- **position-is-before**: `Position.prototype.isBefore` MUST compare `line` first and compare `character` only when both `line` values are equal, returning `true` only when strictly earlier.
- **position-is-before-or-equal**: `Position.prototype.isBeforeOrEqual` MUST use the same line-then-character comparison as `isBefore`, returning `true` on an equal `character` too.
- **position-is-after-derived**: `Position.prototype.isAfter` MUST be defined as the logical negation of `isBeforeOrEqual`, not as an independent comparison.
- **position-is-after-or-equal-derived**: `Position.prototype.isAfterOrEqual` MUST be defined as the logical negation of `isBefore`, not as an independent comparison.
- **position-is-equal**: `Position.prototype.isEqual` MUST return `true` if and only if both `line` and `character` are equal.
- **position-compare-to**: `Position.prototype.compareTo` MUST return `-1`, `0`, or `1`, ordering by `line` first and `character` second.
- **position-translate-dispatch**: `Position.prototype.translate` MUST accept either two numeric arguments (`lineDelta`, `characterDelta`) or a single `{ lineDelta, characterDelta }` object, dispatching on the first argument's `typeof`.
- **position-translate-omitted-defaults-zero**: In `translate`, an omitted `lineDelta`/`characterDelta` (positional `undefined`, or a missing/non-number object field) MUST be treated as a zero delta for that field.
- **position-translate-null-throws**: `translate` MUST throw when either argument is explicitly `null`.
- **position-translate-new-object-when-changed**: When the computed `lineDelta`/`characterDelta` is non-zero in either field, `translate` MUST return a new `Position` instance distinct from the receiver, leaving the receiver's own `line`/`character` unchanged.
- **position-translate-identity-on-no-change**: `translate` MUST return the receiver itself (`this`), not a new object, when the computed `lineDelta` and `characterDelta` are both zero.
- **position-with-dispatch**: `Position.prototype.with` MUST accept either two positional arguments (`line`, `character`) or a single `{ line, character }` object, dispatching on the first argument's `typeof`.
- **position-with-omitted-keeps-current-value**: In `with`, an omitted `line`/`character` (positional `undefined`, or a missing/non-number object field) MUST keep that field's current value, never default it to zero.
- **position-with-null-throws**: `with` MUST throw when either argument is explicitly `null`.
- **position-with-identity-on-no-change**: `with` MUST return the receiver itself (`this`) when the computed `line` and `character` both equal the receiver's current values.
- **position-to-json**: `Position.prototype.toJSON` MUST return a plain `{ line, character }` object built from the `line`/`character` accessors, not the instance's own enumerable backing fields.
- **range-constructor-four-number-form**: `Range`'s constructor MUST accept four numeric arguments and build `start`/`end` as new `Position` instances from them.
- **range-constructor-two-position-form**: `Range`'s constructor MUST accept two position-like arguments — a real `Position` or a duck-typed `{ line, character }` object — converting each through the same position-like acceptance the constructor uses for the four-number form's endpoints.
- **range-constructor-invalid-arguments-throws**: `Range`'s constructor MUST throw `Error('Invalid arguments')` when the given arguments match neither the four-number form nor the two-position form.
- **range-constructor-swaps-strictly-ordered**: `Range`'s constructor MUST compare `start.isBefore(end)`; when that is `false` — including when `start` and `end` are equal-but-distinct `Position` objects — it MUST swap `start` and `end` before storing them.
- **range-fields-readonly**: `Range.prototype.start` and `.end` MUST be defined as read-only accessor properties, not plain writable own properties.
- **range-instance-frozen**: Every constructed `Range` instance MUST be frozen via `Object.freeze` at the end of its constructor.
- **range-contains-duck-typed**: `Range.prototype.contains` MUST accept either a position-like or a range-like argument, determined structurally rather than by `instanceof`, recursing into two `Position`-shaped `contains` calls for a range-like argument.
- **range-contains-position-not-strictly-outside**: For a position-like argument, `contains` MUST return `true` when the converted position is not strictly before `start` and not strictly after `end`, and MUST return `false` for any argument that is neither position-like nor range-like.
- **range-is-equal-not-duck-typed**: `Range.prototype.isEqual` MUST compare the receiver's and the other value's `start`/`end` by reading the other value's fields directly, with no structural shape check first, so a plain object literal shaped like a `Range` throws rather than comparing.
- **range-intersection-undefined-when-disjoint**: When two ranges share no point at all (the computed start is strictly after the computed end), `intersection` MUST return `undefined`.
- **range-intersection-empty-not-undefined-when-touching**: When two ranges merely touch at one point (the computed start equals the computed end), `intersection` MUST return a new, empty `Range`, not `undefined`.
- **range-intersection-span**: When two ranges overlap, `intersection` MUST return a new `Range` from the later of the two starts to the earlier of the two ends.
- **range-union-identity-shortcut**: `Range.prototype.union` MUST return the receiver itself when it already contains `other`, and MUST return `other` itself when `other` already contains the receiver, without constructing a new `Range` in either case.
- **range-union-span**: When neither range contains the other, `union` MUST return a new `Range` spanning the earlier of the two starts to the later of the two ends.
- **range-with-dispatch**: `Range.prototype.with` MUST accept either a position-like `start` argument plus an optional `end`, or a single `{ start, end }` object, dispatching on whether the first argument is position-like.
- **range-with-null-throws**: `with` MUST throw when either argument is explicitly `null`.
- **range-with-new-object-when-changed**: When the computed `start`/`end` differ from the receiver's current values, `with` MUST return a new `Range` instance distinct from the receiver, leaving the receiver unchanged.
- **range-with-identity-on-no-change**: `with` MUST return the receiver itself (`this`) when the computed `start` and `end` both equal the receiver's current values.
- **range-to-json**: `Range.prototype.toJSON` MUST return a two-element array `[start, end]`, not an object with `start`/`end` keys.
- **location-constructor-position-becomes-empty-range**: `Location`'s constructor MUST, when its second argument is position-like, set `range` to a new, empty `Range` at that position.
- **location-constructor-range-reused-by-identity**: `Location`'s constructor MUST, when its second argument is already a real `Range` instance, assign that same instance to `range` by reference, not a copy.
- **location-constructor-range-like-rebuilt**: `Location`'s constructor MUST, when its second argument is range-like but not `instanceof Range`, build a new `Range` from its `start`/`end` rather than reusing the literal.
- **location-constructor-falsy-range-leaves-unset**: `Location`'s constructor MUST, when its second argument is falsy (omitted or explicitly falsy), leave `range` entirely unset rather than assigning `undefined` to it or defaulting it some other way.
- **location-constructor-invalid-argument-throws**: `Location`'s constructor MUST throw `Error('Illegal argument')` when its second argument is truthy but neither position-like nor range-like.
- **location-constructor-uri-assigned-unchecked**: `Location`'s constructor MUST assign its first argument to `uri` with no validation.
- **location-instance-not-frozen**: A constructed `Location` instance MUST NOT be frozen; `uri` and `range` MUST remain assignable after construction.
- **classes-and-prototypes-frozen**: `Position`, `Position.prototype`, `Range`, `Range.prototype`, `Location`, and `Location.prototype` MUST each be frozen via `Object.freeze`, inside the same evaluation that builds them.
- **position-from-not-duck-typed**: `VSCodeAPI.position(from:in:)` MUST return `nil` for a value that is not `instanceof` the installed `Position` class, without reading any of that value's properties first.
- **position-from-decodes-real-instance**: For a value that is `instanceof` the installed `Position` class, `position(from:in:)` MUST return an `ExtensionPosition` whose `line` and `character` equal the instance's own `line`/`character`.
- **position-from-exact-integer-fields**: `position(from:in:)` MUST return `nil` when either `line` or `character` is not exactly representable as an `Int32` (via `Int32(exactly:)`), rather than wrapping or truncating the value.
- **range-from-not-duck-typed**: `VSCodeAPI.range(from:in:)` MUST return `nil` for a value that is not `instanceof` the installed `Range` class.
- **range-from-decodes-both-endpoints**: `range(from:in:)` MUST return `nil` unless both `start` and `end` decode via `position(from:in:)`.
- **location-from-not-duck-typed**: `VSCodeAPI.location(from:in:)` MUST return `nil` for a value that is not `instanceof` the installed `Location` class, even when its `uri`/`range` properties are themselves real `Uri`/`Range` instances.
- **location-from-decodes-uri-and-range**: `location(from:in:)` MUST return `nil` unless `uri` decodes via `url(from:in:)` and `range` decodes via `range(from:in:)`.
- **position-value-constructs-real-instance**: `VSCodeAPI.positionValue(for:in:)` MUST construct the JS value by calling the installed `Position` class's constructor with `[position.line, position.character]`, not by building a plain object literal.
- **position-value-clears-exception-on-throw**: When the `Position` constructor throws, `positionValue(for:in:)` MUST clear `context.exception` and return `nil`, rather than leaving the exception armed for a later, unrelated call.
- **range-value-constructs-real-instance**: `VSCodeAPI.rangeValue(for:in:)` MUST construct the JS value by calling the installed `Range` class's constructor with the two JS `Position` values built via `positionValue(for:in:)`.
- **range-value-does-not-duplicate-swap**: `rangeValue(for:in:)` MUST hand `start` and `end` to the `Range` constructor in the order `ExtensionRange` carries them, relying on the JS constructor's own swap branch to reorder them if needed, rather than reordering them itself.
- **range-value-clears-exception-on-throw**: When the `Range` constructor throws, `rangeValue(for:in:)` MUST clear `context.exception` and return `nil`.
- **location-value-constructs-real-instance**: `VSCodeAPI.locationValue(for:in:)` MUST construct the JS value by calling the installed `Location` class's constructor with a JS `Uri` value (via `uriValue(for:in:)`) and a JS `Range` value (via `rangeValue(for:in:)`).
- **location-value-clears-exception-on-throw**: When the `Location` constructor throws, `locationValue(for:in:)` MUST clear `context.exception` and return `nil`.
- **extension-position-value-type**: `ExtensionPosition` MUST be a `Sendable`, `Equatable`, `Hashable` struct carrying exactly `line: Int` and `character: Int`, both immutable after `init`.
- **extension-range-value-type**: `ExtensionRange` MUST be a `Sendable`, `Equatable`, `Hashable` struct carrying exactly `start: ExtensionPosition` and `end: ExtensionPosition`, both immutable after `init`.
- **extension-location-value-type**: `ExtensionLocation` MUST be a `Sendable`, `Equatable` struct, with no `Hashable` conformance, carrying exactly `uri: URL` and `range: ExtensionRange`, both immutable after `init`.
- **geometry-static-helpers-not-published**: `positionIsPositionLike`, `positionOf`, `positionMin`, `positionMax`, and `rangeIsRangeLike` MUST remain private helper functions inside the evaluated closure, reachable only from `Position`/`Range`'s own methods, and MUST NOT be attached to `Position` or `Range` as a static member visible to extension code.

## Appearance

Not applicable — this is a `JSContext` class-installer and Swift/JS bridge for `vscode.Position`/`vscode.Range`/`vscode.Location`, not a visual component.

## States

Not applicable — this is a `JSContext` class-installer and Swift/JS bridge, not a visual component. Its only lifecycle-shaped behavior is the once-per-context installation and caching sequence, captured under Behavioral Requirements (**install-once-per-context**, **cache-write-optional**, **member-presence-check-runs-every-call**) rather than as a visual-state table.

## Accessibility

Not applicable — this is a `JSContext` class-installer and Swift/JS bridge, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| geom-001 | range-constructor-swaps-strictly-ordered | `new Range(new Position(5, 0), new Position(1, 0))` | `start.line === 1`, `end.line === 5` — `TextGeometryTests.rangeConstructorSwapsOutOfOrderPositions` |
| geom-002 | range-constructor-four-number-form, range-constructor-two-position-form, range-constructor-swaps-strictly-ordered, position-is-equal | `new Range(5, 0, 1, 0)` vs. `new Range(new Position(5, 0), new Position(1, 0))` | Both have `start.line === 1`, `end.line === 5`, and `isEqual` between them is `true` — `TextGeometryTests.rangeFourNumberConstructorMatchesTwoPositionConstructorIncludingSwap` |
| geom-003 | position-constructor-validates-line | `new Position(-1, 0)` | Throws; the caught error's `message` contains `"line"` — `TextGeometryTests.positionConstructorThrowsOnANegativeLine` |
| geom-004 | position-constructor-validates-character | `new Position(0, -1)` | Throws; the caught error's `message` contains `"character"` — `TextGeometryTests.positionConstructorThrowsOnANegativeCharacter` |
| geom-005 | position-translate-new-object-when-changed | `var p = new Position(2, 3); var t = p.translate(1, 1);` | `p` stays `(2, 3)`, `t` is `(3, 4)`, `p !== t` — `TextGeometryTests.positionTranslateReturnsNewObjectAndLeavesReceiverUnchanged` |
| geom-006 | range-with-dispatch, range-with-new-object-when-changed | `var r = new Range(new Position(0, 0), new Position(0, 5)); var changed = r.with(new Position(0, 1));` | `r` stays `(0,0)`-`(0,5)`, `changed.start` is `(0, 1)`, `r !== changed` — `TextGeometryTests.rangeWithReturnsNewObjectAndLeavesReceiverUnchanged` |
| geom-007 | position-translate-identity-on-no-change, position-with-identity-on-no-change | `var p = new Position(2, 3); p.translate(0, 0) === p; p.with() === p;` | Both comparisons are `true` — `TextGeometryTests.translateAndWithReturnTheReceiverItselfWhenNothingChanges` |
| geom-008 | range-intersection-undefined-when-disjoint | `new Range(0,0,0,5).intersection(new Range(1,0,1,5))` | `undefined` — `TextGeometryTests.intersectionOfDisjointRangesIsUndefined` |
| geom-009 | range-intersection-empty-not-undefined-when-touching | `new Range(0,0,0,5).intersection(new Range(0,5,0,10))` | A `Range` (not `undefined`) with `isEmpty === true`, both endpoints at `(0, 5)` — `TextGeometryTests.intersectionOfTouchingRangesIsAnEmptyRangeNotUndefined` |
| geom-010 | range-intersection-span | `new Range(0,0,0,10).intersection(new Range(0,5,0,15))` | `start.character === 5`, `end.character === 10` — `TextGeometryTests.intersectionOfOverlappingRangesIsTheOverlappingSpan` |
| geom-011 | range-union-span | `new Range(0,0,0,5).union(new Range(2,0,2,5))` | `start` is `(0, 0)`, `end` is `(2, 5)` — `TextGeometryTests.unionOfDisjointRangesSpansBoth` |
| geom-012 | range-union-identity-shortcut | `var a = new Range(0,0,5,0); var b = new Range(1,0,2,0); a.union(b)` | Result `=== a` (identity, no new `Range` constructed) — traced to the source's `if (this.contains(other)) return this;` branch, not exercised by `TextGeometryTests.swift` |
| geom-013 | range-contains-position-not-strictly-outside | `var r = new Range(0,5,0,10); r.contains(new Position(0,7)); r.contains(new Position(0,20));` | `true`, then `false` — `TextGeometryTests.containsAcceptsAPositionInsideAndRejectsOneOutside` |
| geom-014 | range-contains-duck-typed, range-contains-position-not-strictly-outside | `var r = new Range(0,0,0,20); r.contains(new Range(0,5,0,10)); r.contains(new Range(0,15,0,25));` | `true`, then `false` — `TextGeometryTests.containsAcceptsARangeInsideAndRejectsOneExtendingOutside` |
| geom-015 | range-is-equal-not-duck-typed | `new Range(0,0,0,5).isEqual({ start: {line:0,character:0}, end: {line:0,character:5} })` | Throws (`context.exception` is set) — `TextGeometryTests.isEqualIsNotDuckTypedAndThrowsOnAPlainObjectLiteral` |
| geom-016 | range-contains-duck-typed | `new Range(0,0,0,5).contains({ line: 1, character: 2 })` | Returns the boolean `false`, no exception raised — `TextGeometryTests.containsIsDuckTypedAndAnswersFalseRatherThanThrowing` |
| geom-017 | position-compare-to | `(new Position(1, 99)).compareTo(new Position(2, 0))` | `-1` — `TextGeometryTests.compareToOrdersByLineFirstThenCharacter` |
| geom-018 | position-is-before, position-is-before-or-equal, position-is-after-derived, position-is-after-or-equal-derived | Two `Position` instances both at `(3, 4)`; call all four comparisons | `isBefore` `false`, `isBeforeOrEqual` `true`, `isAfter` `false`, `isAfterOrEqual` `true` — `TextGeometryTests.comparisonMethodsAgreeOnEqualPositions` |
| geom-019 | position-translate-dispatch, position-translate-omitted-defaults-zero | `(new Position(2,3)).translate({lineDelta:1,characterDelta:1})` vs. `.translate(1,1)`; `.translate({lineDelta:1})` | First two are `isEqual`; the third is `(3, 3)` (omitted `characterDelta` is zero) — `TextGeometryTests.translateObjectFormAgreesWithTwoNumberFormAndOmittedFieldIsZeroDelta` |
| geom-020 | position-with-dispatch, position-with-omitted-keeps-current-value | `(new Position(2,3)).with({line:5,character:9})` vs. `.with(5,9)`; `.with({line:5})` | First two are `isEqual`; the third is `(5, 3)` (omitted `character` keeps `3`) — `TextGeometryTests.withObjectFormAgreesWithPositionalFormAndOmittedFieldKeepsCurrentValue` |
| geom-021 | classes-and-prototypes-frozen | `Range.prototype.contains = function () { return 'tampered'; }; var r = new Range(0,0,0,10); r.contains(new Position(0,5));` | Returns the real boolean `true`, not the string `"tampered"` — `TextGeometryTests.rangePrototypeReassignmentDoesNotChangeLaterContainsCalls` |
| geom-022 | position-from-not-duck-typed | `VSCodeAPI.position(from: ({line:1, character:2}), in: context)` | `nil` — `TextGeometryTests.positionFromRefusesADuckTypedLiteral` |
| geom-023 | position-from-decodes-real-instance | `VSCodeAPI.position(from: new Position(1, 2), in: context)` | `ExtensionPosition(line: 1, character: 2)` — `TextGeometryTests.positionFromReadsARealPositionInstance` |
| geom-024 | position-value-constructs-real-instance, range-value-constructs-real-instance, range-from-decodes-both-endpoints, extension-position-value-type, extension-range-value-type | `VSCodeAPI.rangeValue(for: ExtensionRange(start: (1,2), end: (3,4)), in: context)`, then read back | `roundTripped instanceof Range` is `true`; `VSCodeAPI.range(from:in:)` on it equals the original `ExtensionRange` — `TextGeometryTests.rangeValueRoundTripsThroughTheReader` |
| geom-025 | range-value-does-not-duplicate-swap | `VSCodeAPI.rangeValue(for: ExtensionRange(start: (5,0), end: (1,0)), in: context)`, then check `written.start.isBeforeOrEqual(written.end)` | `true`; `written.start.line === 1` — `TextGeometryTests.swiftSideSwapInvariantIsEnforcedWhenWritingAnOutOfOrderRange` |
| geom-026 | install-once-per-context, member-presence-check-runs-every-call, members-returned-as-dictionary, single-evaluation-builds-all-three | Call `installTextGeometryClasses(in: context)` twice on the same `JSContext`; build a `Range` from the first call's `Range` and check `instanceof` against the second call's `Range` | Both calls' `Range` are `isEqual(to:)`-identical; the instance built from the first is `instanceof` the second — `TextGeometryTests.installIsDeterministicAndCachedAcrossCalls` |
| geom-027 | location-constructor-position-becomes-empty-range | `new Location(Uri.file('/a.txt'), new Position(3, 7))` | `loc.range.isEmpty === true`; `loc.range.start` and `.end` both `(3, 7)` — `TextGeometryTests.locationFromAPositionIsAnEmptyRangeAtThatPosition` |
| geom-028 | location-constructor-range-reused-by-identity | `var r = new Range(1,0,2,4); var loc = new Location(uri, r);` | `loc.range.isEmpty === false`, fields match `r`, and `loc.range === r` — `TextGeometryTests.locationFromARangeKeepsThatRange` |
| geom-029 | location-from-not-duck-typed | `VSCodeAPI.location(from: ({uri: Uri.file('/a.txt'), range: new Range(0,0,0,1)}), in: context)` | `nil` — `TextGeometryTests.locationFromRefusesADuckTypedLiteral` |
| geom-030 | location-from-decodes-uri-and-range | `VSCodeAPI.location(from: new Location(Uri.file('/a.txt'), new Range(1,2,3,4)), in: context)` | `ExtensionLocation` with `uri.path == "/a.txt"` and the matching `ExtensionRange` — `TextGeometryTests.locationFromReadsARealLocationInstance` |
| geom-031 | location-value-constructs-real-instance, extension-location-value-type | `VSCodeAPI.locationValue(for: ExtensionLocation(uri: ..., range: ...), in: context)`, then read back | `roundTripped instanceof Location` is `true`; decoded value equals the original `ExtensionLocation` — `TextGeometryTests.locationValueRoundTripsThroughTheReader` |
| geom-032 | geometry-static-helpers-not-published | `typeof Position.Min`, `.Max`, `.of`, `.isPosition`, `typeof Range.isRange` after install | All `'undefined'` — traced to the source's own declared-surface-only boundary, not exercised by `TextGeometryTests.swift` |
| geom-033 | position-to-json | `JSON.stringify(new Position(3, 4))` | `'{"line":3,"character":4}'`, not the frozen instance's own backing fields — traced to the source comment above `Position.prototype.toJSON`, not exercised by `TextGeometryTests.swift` |
| geom-034 | range-to-json | `JSON.stringify(new Range(0,0,0,5))` | `'[{"line":0,"character":0},{"line":0,"character":5}]'`, a two-element array, not `{start,end}` — traced to the source comment above `Range.prototype.toJSON`, not exercised by `TextGeometryTests.swift` |
| geom-035 | position-instance-frozen, position-fields-readonly | `var p = new Position(1,1); try { p.line = 5; } catch (e) {}` then read `p.line` | `p.line === 1`, unchanged — traced to the constructor's `Object.freeze(this)`, not exercised by `TextGeometryTests.swift` |
| geom-036 | range-constructor-invalid-arguments-throws | `new Range(1, 'not-a-number')` | Throws `Error('Invalid arguments')` — traced to the constructor's `if (!start `|`|` `!end)` branch, not exercised by `TextGeometryTests.swift` |
| geom-037 | location-constructor-invalid-argument-throws | `new Location(uri, 42)` | Throws `Error('Illegal argument')` — traced to the source, not exercised by `TextGeometryTests.swift` |
| geom-038 | location-constructor-falsy-range-leaves-unset | `new Location(uri)` (second argument omitted) | `'range' in loc === false` (never assigned) — traced to the source's comment citing `extHostTypes.location.ts`, not exercised by `TextGeometryTests.swift` |
| geom-039 | location-instance-not-frozen | `var loc = new Location(uri, r1); loc.range = r2;` | Assignment succeeds; `loc.range === r2` — traced to the constructor's deliberate omission of `Object.freeze(this)`, not exercised by `TextGeometryTests.swift` |
| geom-040 | install-evaluate-failure, install-installed-error, install-missing-member, install-failure-is-non-fatal | Sabotage `Object.freeze` to throw before install, or delete a member from an already-installed container, then call `installTextGeometryClasses(in:)` | Returns `nil`; `VSCodeAPI.logger` logs one matching error — derived from the source's three logged branches, not exercised by `TextGeometryTests.swift` (unlike its sibling installers' test suites, this file's own tests cover only the success and idempotency paths) |
| geom-041 | cache-write-optional | Pre-define `__vscodeTextGeometryClasses` as a non-configurable property before the first install call, then call `installTextGeometryClasses(in:)` | Returns a non-`nil` dictionary with all three members for that one call, even though the trailing cache-write throws internally and is silently caught — derived from the source, not exercised by `TextGeometryTests.swift` |
| geom-042 | range-fields-readonly, range-instance-frozen | `var r = new Range(0,0,0,5); try { r.start = new Position(1,1); } catch (e) {}` | `r.start.line === 0`, unchanged — traced to the constructor's `Object.freeze(this)`, not exercised by `TextGeometryTests.swift` |
| geom-043 | position-translate-null-throws, position-with-null-throws | `(new Position(1,1)).translate(null)`; `(new Position(1,1)).with(null)` | Both throw — traced to each method's explicit `null` check, not exercised by `TextGeometryTests.swift` |
| geom-044 | range-with-null-throws | `(new Range(0,0,0,5)).with(null)` | Throws — traced to the source, not exercised by `TextGeometryTests.swift` |
| geom-045 | range-with-identity-on-no-change | `var r = new Range(0,0,0,5); r.with(r.start, r.end) === r` | `true` (same object) — traced to the source's `if (start.isEqual(this._start) && end.isEqual(this._end)) return this;`, not exercised by `TextGeometryTests.swift` |
| geom-046 | position-value-clears-exception-on-throw, range-value-clears-exception-on-throw, location-value-clears-exception-on-throw | `VSCodeAPI.positionValue(for: ExtensionPosition(line: -1, character: 0), in: context)`, then read `context.exception` | Returns `nil`; `context.exception` is `nil` afterward (cleared, not left armed) — traced to the source's "swallowed-throw hazard" comment, not exercised by `TextGeometryTests.swift`, which exercises only the successful round-trip paths |
| geom-047 | location-constructor-range-like-rebuilt | `new Location(uri, { start: new Position(0,0), end: new Position(0,5) })` | `loc.range instanceof Range` is `true`, and is a new instance, not the literal — traced to the constructor's `new Range(rangeOrPosition.start, rangeOrPosition.end)` branch, not exercised by `TextGeometryTests.swift` |
| geom-048 | location-constructor-uri-assigned-unchecked | `new Location(42, new Range(0,0,0,1))` | Does not throw; `loc.uri === 42` — traced to the constructor's unconditional `this.uri = uri;`, not exercised by `TextGeometryTests.swift` |
| geom-049 | position-from-exact-integer-fields | A real `Position` holding `line: Number.MAX_VALUE` (the constructor only rejects negative values, not oversized ones), read via `VSCodeAPI.position(from:in:)` | `nil` — `Int32(exactly:)` rejects `Number.MAX_VALUE` — traced to the source's own `Int32(exactly:)` comment, not exercised by `TextGeometryTests.swift` |
| geom-050 | range-from-not-duck-typed | `VSCodeAPI.range(from: ({start:{line:0,character:0},end:{line:0,character:5}}), in: context)` | `nil` — mirrors **position-from-not-duck-typed**'s own guard, not exercised by `TextGeometryTests.swift` (which tests this refusal for `Position` and `Location` but not `Range` directly) |

## Edge Cases

- **Null/empty input**: `Location` constructed with its second argument omitted MUST leave `range` entirely unset rather than assigning `undefined`, per **location-constructor-falsy-range-leaves-unset** (MUST).
- **Null/empty input**: `Range`'s constructor called with arguments matching neither the four-number nor the two-position form MUST throw `Error('Invalid arguments')` rather than construct a partial or default range, per **range-constructor-invalid-arguments-throws** (MUST).
- **Boundary values**: `line`/`character` of exactly `0` is the minimum valid value and MUST NOT throw; `Position`'s constructor only rejects strictly negative values, per **position-constructor-validates-line**/**position-constructor-validates-character** (MUST).
- **Boundary values**: two positions that are equal-but-distinct objects MUST still take `Range`'s swap branch (`start.isBefore(end)` is strict), not the "already ordered" branch, per **range-constructor-swaps-strictly-ordered** (MUST) — unobservable by value, so no test in `TextGeometryTests.swift` pins object identity for this case.
- **Boundary values**: two ranges that touch at exactly one point MUST intersect to an empty `Range`, not `undefined` — the boundary between **range-intersection-empty-not-undefined-when-touching** and **range-intersection-undefined-when-disjoint** (MUST).
- **Concurrent access**: not applicable in the sense of requiring synchronization — every function this file adds runs on the main actor (per **main-actor-isolation**), and `JSContext`/`JSValue` are not `Sendable`, so no two calls into this file's functions can execute concurrently against the same context; the compiler enforces this via `VSCodeAPI`'s own `@MainActor` declaration (MUST).
- **Concurrent access / cache identity**: if some other code has already defined an object under the global name `__vscodeTextGeometryClasses` on a context before `installTextGeometryClasses(in:)` first runs on it, this function adopts that pre-existing object as the cached container with no way to verify it is the genuine geometry classes this file built — the same residual behavior `Uri.swift`'s `installUriClass(in:)` documents for its own global, generalized here to a three-member container (per this file's own header comment; not independently re-verified against `Uri.swift`'s text in this recipe).
- **Error states**: `installTextGeometryClasses(in:)` failing for any of its three logged reasons (evaluate failure, an `installedError` result, or a missing member) MUST leave every `vscode.Position`/`Range`/`Location` global as the shim's not-implemented stub for that context rather than raise a Swift error, per **install-failure-is-non-fatal** (MUST). Unlike `LanguageModelMessageVocabulary.swift`'s installer, this file's outer catch DOES capture and return the underlying JavaScript error's own message via `installedError`, so a caller can distinguish a construction-time failure from a plain non-object result — but `TextGeometryTests.swift` exercises neither failure path directly, unlike some sibling installers' own test suites.
- **Error states**: `positionValue(for:in:)`, `rangeValue(for:in:)`, and `locationValue(for:in:)` each swallow a construction-time throw by clearing `context.exception` and returning `nil`, with nothing logged to say which field or class failed, per **position-value-clears-exception-on-throw**/**range-value-clears-exception-on-throw**/**location-value-clears-exception-on-throw** (MUST).
- **Offline or disconnected state**: not applicable — this file makes no network call and opens no file; every input it processes (a line/character number, a `Position`/`Range`/`Location` instance, a `Uri`) arrives already resident in the `JSContext` or as a Swift value.
- **Cancellation and timeouts**: not applicable — every function this file adds is synchronous; there is no long-running operation to cancel or time out.
- **Missing file or unreachable server**: not applicable — this file has no filesystem or network dependency of its own; `Location`'s `uri` field is an opaque `URL` value read via `Uri.swift`'s own `url(from:in:)`, never dereferenced or resolved here.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `context` | `JSContext` | none (required) | `installTextGeometryClasses(in:)`, `position(from:in:)`, `range(from:in:)`, `location(from:in:)`, `positionValue(for:in:)`, `rangeValue(for:in:)`, and `locationValue(for:in:)` all take the target context explicitly; there is no ambient or singleton context. |
| `textGeometryGlobalName` | `String` (fixed constant) | `"__vscodeTextGeometryClasses"` | The global key `installTextGeometryClasses(in:)` caches the built `{ Position, Range, Location }` container under; not settable per call. |
| `line`, `character` (`Position` constructor) | JS number | none (required) | Both MUST be non-negative or the constructor throws, per **position-constructor-validates-line**/**position-constructor-validates-character**. |
| `startLineOrStart`, `startColumnOrEnd`, `endLine`, `endColumn` (`Range` constructor) | four numbers, or two position-like values | none (required) | Dispatch on argument shape, per **range-constructor-four-number-form**/**range-constructor-two-position-form**. |
| `rangeOrPosition` (`Location` constructor, 2nd argument) | position-like, range-like, or falsy | falsy leaves `range` unset | Dispatch on shape, per **location-constructor-position-becomes-empty-range**/**location-constructor-range-reused-by-identity**/**location-constructor-range-like-rebuilt**/**location-constructor-falsy-range-leaves-unset**. |
| `lineDeltaOrChange`, `characterDeltaArg` (`Position.prototype.translate`) | two numbers, a `{lineDelta, characterDelta}` object, or omitted | `0` for each omitted field | Per **position-translate-omitted-defaults-zero**. |
| `lineOrChange`, `characterArg` (`Position.prototype.with`) | two numbers, a `{line, character}` object, or omitted | the receiver's current value for each omitted field | Per **position-with-omitted-keeps-current-value**. |
| `startOrChange`, `endArg` (`Range.prototype.with`) | a position-like value, a `{start, end}` object, or omitted | the receiver's current `start`/`end` for each omitted or falsy field | Per **range-with-dispatch**. |

## Deep Linking

Not applicable: `TextGeometry.swift` defines no URL, route, or navigable destination — it installs JS value-type constructors and Swift bridge functions and has no navigation surface of its own.

## Localization

- **hardcoded-thrown-error-messages**: `Position`'s constructor throws the English literals `'line must be non-negative'` and `'character must be non-negative'`; a `null` argument to `translate`/`with` on either `Position` or `Range` throws the fallback literal `'Illegal argument'` (the `illegalArgument` helper's default when called with no message); `Range`'s constructor throws `'Invalid arguments'`; `Location`'s constructor throws `'Illegal argument'` directly. None of these carries a localization key or a `String(localized:)` call — they are visible to the extension author whose code triggered the throw, not to the app's own end-user UI.
- **hardcoded-log-strings**: the three `logger.error` messages in `installTextGeometryClasses(in:)` (an evaluate failure, an `installedError` failure, and a missing container member) are hardcoded English `Logger` interpolated strings with no localization key.

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal only) | `line must be non-negative` | `Position`'s constructor, thrown for a negative `line`. |
| (none — literal only) | `character must be non-negative` | `Position`'s constructor, thrown for a negative `character`. |
| (none — literal only) | `Illegal argument` | `translate`/`with`'s `null`-argument check on `Position` and `Range`, and `Location`'s constructor for a second argument that is neither position-like nor range-like. |
| (none — literal only) | `Invalid arguments` | `Range`'s constructor, thrown when neither the four-number nor the two-position form matches. |
| (none — literal only) | `Could not install the 'vscode.Position'/'vscode.Range'/'vscode.Location' classes in context '<name>'; they stay the shim's not-implemented stub` | `installTextGeometryClasses(in:)`, logged when `context.evaluateScript(textGeometryClassesSource)` returns `nil` or a non-object. |
| (none — literal only) | `Could not install the 'vscode.Position'/'vscode.Range'/'vscode.Location' classes in context '<name>': '<message>'; they stay the shim's not-implemented stub` | `installTextGeometryClasses(in:)`, logged when the evaluated result carries an `installedError`. |
| (none — literal only) | `The 'vscode' text-geometry container in context '<name>' is missing 'Position', 'Range' or 'Location'; all three stay the shim's not-implemented stub` | `installTextGeometryClasses(in:)`, logged when the resolved container is missing an expected member. |

## Accessibility Options

Not applicable: `TextGeometry.swift` renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic; `Position`, `Range` and `Location` are always available once `installTextGeometryClasses(in:)` succeeds for a context.

## Analytics

Not applicable: the source contains no analytics or event-emission call of any kind; its only telemetry-adjacent calls are the three `logger.error` lines covered under Logging, which are diagnostic logging, not analytics events.

## Privacy

- **Data collected**: `TextGeometry.swift` collects no data of its own; it constructs `Position`/`Range`/`Location` value objects and the Swift `ExtensionPosition`/`ExtensionRange`/`ExtensionLocation` mirrors out of whatever `line`, `character`, `uri`, and range/position values an extension or host caller already supplies, without retaining a copy beyond the returned instance and the per-context class cache.
- **Storage**: this file performs no persistent storage of its own.
- **Transmission**: this file makes no network call. `Location.uri` may itself reference a remote or local resource, but this file never dereferences, resolves, or transmits it — that is `Uri.swift`'s and its callers' concern, outside this file's scope.
- **Retention**: nothing in this file is retained beyond the lifetime of one function call's local variables, except the per-context installed-class cache (`__vscodeTextGeometryClasses`), which holds only the three constructor objects, never a position, range, or location value's own data.

## Logging

Subsystem: `Bundle.main.bundleIdentifier` (via `Loggable`'s default, falling back to `"nil"`) | Category: `VSCodeAPI` (the shared logger declared once in `VSCodeAPI.swift` and reused by every `VSCodeAPI` extension file, including this one)

| Event | Level | Message |
|-------|-------|---------|
| `context.evaluateScript(textGeometryClassesSource)` returns `nil` or a non-object | error | `Could not install the 'vscode.Position'/'vscode.Range'/'vscode.Location' classes in context '<name>'; they stay the shim's not-implemented stub` |
| The evaluated result carries a non-`undefined` `installedError` | error | `Could not install the 'vscode.Position'/'vscode.Range'/'vscode.Location' classes in context '<name>': '<message>'; they stay the shim's not-implemented stub` |
| The resolved container is missing `Position`, `Range`, or `Location` | error | `The 'vscode' text-geometry container in context '<name>' is missing 'Position', 'Range' or 'Location'; all three stay the shim's not-implemented stub` |

No other event in this file is logged: the failed cache-write `Object.defineProperty` inside `textGeometryClassesSource` is caught and silently ignored (per **cache-write-optional**), and `positionValue(for:in:)`/`rangeValue(for:in:)`/`locationValue(for:in:)` each clear a construction-time exception without logging it (per their respective **-clears-exception-on-throw** requirements).

## Platform Notes

- **SwiftUI**: not applicable to this file — `TextGeometry.swift` imports only `Foundation`, `JavaScriptCore`, `OSLog`, and `AgenticToolkitCore`, with no SwiftUI dependency; nothing here renders or observes view state.
- **AppKit / UIKit**: this is the source. `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/TextGeometry.swift` is part of the `AgenticToolkitMacOS` framework target, which `project.yml` declares `platform: macOS` only — no iOS target packages this file. It is an extension of the `@MainActor` `VSCodeAPI` enum; its confirmed consumers among the repository's other files are `ExtensionHost.installRuntime`, which installs the text-geometry classes eagerly on every activation, and `DiagnosticTypes.swift`, which reads `Range`/`Location` back out of this file's installed container (via `globalThis[textGeometryGlobalName]`) to validate its own `Diagnostic`/`DiagnosticRelatedInformation` constructor arguments — both outside this recipe's scope.
- **Compose**: model `Position`, `Range`, and `Location` as Kotlin `data class`es with the non-negativity checks moved into `init` blocks that throw `IllegalArgumentException`, matching **position-constructor-validates-line**/**position-constructor-validates-character**; a `data class`'s generated `equals`/`hashCode` gives **position-is-equal** and the `Equatable`/`Hashable` shape of **extension-position-value-type**/**extension-range-value-type** for free, but Kotlin has no `Object.freeze` analogue for a class or its members, so **classes-and-prototypes-frozen**, **position-instance-frozen**, and **range-instance-frozen** have no direct Kotlin equivalent and would need documenting as an implementation gap rather than silently dropped.
- **React/Web**: this is closest to the actual runtime shape — extension code in the real VS Code product already runs against the genuine `vscode.d.ts` declarations this file mirrors. A React/Web host embedding a similar extension bridge would define `Position`, `Range`, and `Location` directly as plain ES classes in one module (no `JSContext` boundary to cross), naturally satisfying **single-evaluation-builds-all-three** by construction.
- **WinUI 3**: model `Position` and `Range` as plain mutable C# classes (not `readonly record struct`s, which would make the "return `this` on no change" identity semantics of **position-translate-identity-on-no-change**/**range-with-identity-on-no-change** awkward, and would block `Location`'s required mutability under **location-instance-not-frozen**) with constructor-time validation throwing `ArgumentException` for a negative `Line`/`Character`, matching **position-constructor-validates-line**/**position-constructor-validates-character**. Implement `IsAfter`/`IsAfterOrEqual` as literal negations of `IsBeforeOrEqual`/`IsBefore` (`!IsBeforeOrEqual(other)`, `!IsBefore(other)`) to keep **position-is-after-derived**/**position-is-after-or-equal-derived**'s contract intact rather than duplicating the comparison. Model `Location` as a plain mutable class with public settable `Uri`/`Range` properties (`System.Uri`, not the `Windows.Storage` file APIs, since `Location.uri` is opaque here) per **location-instance-not-frozen**. There is no .NET equivalent of `Object.freeze`; a WinUI 3 port has no way to reproduce **classes-and-prototypes-frozen**'s "the class itself is frozen" contract or **position-instance-frozen**/**range-instance-frozen**'s per-instance immutability, and would need to document that gap explicitly rather than silently drop it — `Task`/`async` and `ObservableCollection`/`INotifyPropertyChanged` have no role here since every operation in this file is synchronous and holds no observable collection.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Extensions/VSCodeAPI/TextGeometry.swift` |

## Design Decisions

**Decision**: `Range`'s constructor swaps `start`/`end` even when they are equal-but-distinct `Position` objects, not only when strictly out of order.
**Rationale**: `vscode.d.ts`'s prose reads as "equal positions are not swapped," but the implementation's own condition, `start.isBefore(end)`, is strict, so two equal-but-distinct positions take the `else` branch and are swapped anyway — traced to the source's own header commentary; unobservable by value, so this recipe follows the implementation and pins no test on object identity for this case.
**Approved**: pending

**Decision**: `Location` instances are the one case in this file not frozen via `Object.freeze`, even though `Position` and `Range` both are.
**Rationale**: `vscode.d.ts` declare `uri`/`range` as plain, assignable stored properties, and upstream's `Location` really is mutable — `location.range = someRange` is ordinary extension code, and a frozen instance would fail it. `Location`'s class object and prototype are still frozen inside the same evaluation as everything else; only the per-instance freeze is withheld, and only for this one class.
**Approved**: pending

**Decision**: `Position.Min`, `Position.Max`, `Position.of`, `Position.isPosition`, and `Range.isRange` are implemented as private helper functions inside the evaluated closure rather than as static members on the published `Position`/`Range` classes.
**Rationale**: none of the five is in `vscode.d.ts`'s declared `Position`/`Range` surface — only upstream's own implementation carries them — and a static `vscode.Position.Min` that a real, `tsc`-compiled VS Code extension can never legally call would be exactly the kind of host-only surface this file's own header says it is trying not to accumulate.
**Approved**: pending

**Decision**: **main-actor-isolation** has no row in Conformance Test Vectors.
**Rationale**: it is a compiler-enforced fact about `VSCodeAPI`'s own `@MainActor` declaration, not a runtime branch a `JSContext` script or a single Swift call can exercise as a PASS/FAIL test; this recipe follows the same precedent the `LanguageModelMessageVocabulary` recipe already sets for the identical requirement on the identical enum, covering it instead under Edge Cases ("Concurrent access").
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |
| [secure-log-output](agenticdevelopercookbook://compliance/security#secure-log-output) | passed | Security |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | passed | Security |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

`separation-of-concerns` passes because this file's only responsibility is installing three JS declarations in a `JSContext` and bridging their instances to and from Swift; it delegates `Uri` decoding to `Uri.swift` rather than duplicating that logic, and defines no UI, no networking, and no persistence. `unit-test-coverage` passes: `TextGeometryTests.swift`'s twenty-four test methods exercise all fourteen of task 5.6a-i's numbered mutation points plus the addendum's seven further mutations and task 5.6a-ii's two `Location`-constructor mutations, per that file's own header. `explicit-error-handling` is partial: constructor failures are real, typed JS errors with specific messages, and the installer's outer catch captures the underlying JavaScript error's message via `installedError` rather than discarding it — but `positionValue(for:in:)`/`rangeValue(for:in:)`/`locationValue(for:in:)` each swallow a construction-time throw into a bare `nil`, with nothing logged to say which field failed, per the open question on **position-value-clears-exception-on-throw**. `secure-log-output` passes: all three logged messages carry only the context's own name (already `privacy: .public}` in the source) and, in one case, the installed source's own internal error text — never extension-authored data read off an untrusted value. `input-sanitization` passes because every reader in this file (`position(from:in:)`, `range(from:in:)`, `location(from:in:)`) refuses a value that is not a genuine instance of the class it claims to be, via `isInstance(of:)`, before reading any of that value's properties, rather than trusting a duck-typed shape from untrusted extension-authored JavaScript; the `Position`/`Range` constructors also reject a negative `line`/`character` rather than clamping or accepting it silently. `no-hardcoded-strings` fails because both the thrown JS error messages and the three installer log messages are English literals with no localization mechanism (see Localization).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
