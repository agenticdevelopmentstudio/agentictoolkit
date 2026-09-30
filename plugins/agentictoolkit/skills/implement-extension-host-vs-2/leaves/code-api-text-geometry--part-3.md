<!-- leaf: implement-extension-host-vs-2/code-api-text-geometry--part-3 · source: extension-host-vs-code-api-text-geometry.md -->

# TextGeometry — continued (part 3)

**Rules** (cite as `implement-extension-host-vs-2/code-api-text-geometry--part-3#<slug>`):

- `range-with-dispatch` MUST
- `range-with-null-throws` MUST
- `range-with-new-object-when-changed` MUST
- `range-with-identity-on-no-change` MUST
- `range-to-json` MUST
- `location-constructor-position-becomes-empty-range` MUST
- `location-constructor-range-reused-by-identity` MUST
- `location-constructor-range-like-rebuilt` MUST
- `location-constructor-falsy-range-leaves-unset` MUST
- `location-constructor-invalid-argument-throws` MUST
- `location-constructor-uri-assigned-unchecked` MUST
- `location-instance-not-frozen` MUST
- `classes-and-prototypes-frozen` MUST
- `position-from-not-duck-typed` MUST
- `position-from-decodes-real-instance` MUST
- `position-from-exact-integer-fields` MUST
- `range-from-not-duck-typed` MUST
- `range-from-decodes-both-endpoints` MUST
- `location-from-not-duck-typed` MUST
- `location-from-decodes-uri-and-range` MUST
- `position-value-constructs-real-instance` MUST
- `position-value-clears-exception-on-throw` MUST
- `range-value-constructs-real-instance` MUST
- `range-value-does-not-duplicate-swap` MUST
- `range-value-clears-exception-on-throw` MUST
- `location-value-constructs-real-instance` MUST
- `location-value-clears-exception-on-throw` MUST
- `extension-position-value-type` MUST
- `extension-range-value-type` MUST
- `extension-location-value-type` MUST
- `geometry-static-helpers-not-published` MUST

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

