<!-- leaf: implement-extension-host-core-1/extensions-extension-identity-component · source: extension-host-core-extensions-extension-identity-component.md -->

**Rules** (cite as `implement-extension-host-core-1/extensions-extension-identity-component#<slug>`):

- `empty-value-refused` MUST
- `leading-dot-refused` MUST
- `forward-slash-refused` MUST
- `backslash-refused` MUST
- `colon-refused` MUST
- `control-character-refused` MUST
- `c0-boundary-accepted` MUST
- `c1-range-accepted` MUST
- `interior-dot-accepted` MUST
- `non-ascii-accepted` MUST
- `literal-percent-sequence-accepted` MUST
- `pure-function` MUST
- `synchronous-non-throwing` MUST
- `non-isolated-static-member` MUST

# ExtensionIdentityComponent

## Overview

`ExtensionIdentityComponent` is a one-member `enum` namespace holding a single
static predicate, `isSafe(_:)`, that decides whether a string an extension
manifest claims as its identity (a publisher, name, or version field) may be
spliced as a single path or URL component. `VSIXInstaller.requireSafeComponent`
calls it before joining `identifier` and `version` into an install directory
name, and `OpenVSXClient.requireSafeComponent` calls it before joining a
namespace, name, and version onto a registry detail URL — one predicate
shared by both splice sites (source:
`packages/apple/AgenticToolkit/Core/Extensions/VSIXInstaller.swift`; `packages/apple/AgenticToolkit/Core/Extensions/OpenVSXClient.swift`).

## Behavioral Requirements

- **empty-value-refused**: `isSafe` MUST return `false` when `value` is the
  empty string.
- **leading-dot-refused**: `isSafe` MUST return `false` when the first
  character of `value` is `.`, regardless of what follows — this covers a
  bare `.`, `..`, and any name beginning with a hidden-file dot such as
  `.hidden`.
- **forward-slash-refused**: `isSafe` MUST return `false` when `value`
  contains a `/` character anywhere in the string, including as the first,
  last, or only character.
- **backslash-refused**: `isSafe` MUST return `false` when `value` contains a
  `\` character anywhere in the string.
- **colon-refused**: `isSafe` MUST return `false` when `value` contains a `:`
  character anywhere in the string.
- **control-character-refused**: `isSafe` MUST return `false` when `value`
  contains any Unicode scalar whose value is less than `U+0020`, or that is
  exactly `U+007F`, anywhere in the string.
- **c0-boundary-accepted**: `isSafe` MUST return `true` for a value containing
  `U+0020` (space) or `U+007E` (`~`) — the scalars immediately outside the
  refused C0/DEL range — provided no other refusal rule applies.
- **c1-range-accepted**: `isSafe` MUST return `true` for a value containing a
  scalar in the `U+0080`–`U+009F` C1 control range, provided no other refusal
  rule applies; the denylist stops at `U+007F` and does not extend into C1.
- **interior-dot-accepted**: `isSafe` MUST return `true` for a value whose
  only `.` characters occur after the first character, such as an interior
  dot in an identifier (`ms-python.python`) or a version string
  (`2024.1.0-rc.1`).
- **non-ascii-accepted**: `isSafe` MUST return `true` for a value composed of
  non-ASCII characters (for example Japanese, Cyrillic, accented Latin, or
  emoji) that contains none of the refused characters; the check is a
  denylist of shapes, not an allowlist of characters.
- **literal-percent-sequence-accepted**: `isSafe` MUST return `true` for a
  value containing a literal percent-encoded sequence such as `%2F` or
  `%2E%2E`, because the check inspects the literal scalars of `value` and
  performs no percent-decoding.
- **pure-function**: `isSafe` MUST compute its result solely from the scalars
  of `value`, MUST NOT mutate `value` or any external state, and MUST NOT
  perform file, network, or other I/O.
- **synchronous-non-throwing**: `isSafe` MUST return synchronously, MUST NOT
  declare `async` or `throws`, and MUST always return a `Bool`, never an
  error or an optional.
- **non-isolated-static-member**: `isSafe` MUST be callable synchronously
  from any thread or actor context without additional synchronization,
  because `ExtensionIdentityComponent` declares no `Sendable` conformance and
  no actor or `@MainActor` isolation, has no cases and therefore no instance
  state, and `isSafe` is a `static func` operating only on its `String`
  parameter and `Bool` return value, both `Sendable` value types.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| — | — | — | Not applicable: `isSafe` has a single required parameter, `value: String`, and no configurable options, defaults, environment variables, settings keys, or injected dependencies (traced to the function signature, which declares nothing else). |

## Privacy

- **Data collected**: None — `isSafe` receives the manifest field value the
  caller already holds in memory and returns a `Bool`; it stores nothing
  (traced to the function body, which holds no property and returns
  immediately).
- **Storage**: Not applicable — no data is persisted by this component.
- **Transmission**: Not applicable — no data leaves the device; the function
  performs no network or inter-process operation.
- **Retention**: Not applicable — `value` is not retained beyond the single
  call; the type has no instance to hold it in.

## Platform Notes

- **SwiftUI**: Source:
  `packages/apple/AgenticToolkit/Core/Extensions/ExtensionIdentityComponent.swift`.
  The predicate is plain `Foundation` — `String.isEmpty`,
  `String.hasPrefix(_:)`, `String.contains(_:)`, and `String.unicodeScalars`
  — with no SwiftUI dependency; a SwiftUI-hosted caller (for example a
  settings screen listing installed extensions) calls
  `ExtensionIdentityComponent.isSafe(_:)` directly and synchronously, on any
  thread.
- **Compose**: On Kotlin/Android, port the guard chain to a plain `object`
  (Kotlin's namespace-only singleton, the equivalent of the source's
  case-less `enum`) exposing `fun isSafe(value: String): Boolean`, using
  `String.isEmpty()`, `String.startsWith(".")`, and `String.contains(...)`
  for the three separators, then iterating `value.codePoints()` and testing
  each code point against `< 0x20 || == 0x7F`, mirroring the source's
  scalar-level check.
- **React/Web**: In TypeScript, port to a pure function
  `isSafe(value: string): boolean` using `value.length === 0`,
  `value.startsWith(".")`, and `value.includes(...)` for the three
  separators, then testing every entry of `Array.from(value)` (iterating by
  code point, not UTF-16 code unit, since a `charCodeAt` loop would split a
  surrogate pair) against the same `< 0x20 || === 0x7F` range.
- **AppKit / UIKit**: No divergence from the SwiftUI bullet above — the
  source is framework-agnostic `Foundation` code called identically from an
  AppKit-hosted (macOS) or UIKit-hosted (iOS) caller. `AgenticToolkitCore`
  itself targets only macOS today, so an iOS caller would first need the
  type made available to an iOS target, but `isSafe` itself needs no
  AppKit/UIKit-specific change.
- **WinUI 3**: Port to a plain static method, e.g.
  `internal static class ExtensionIdentityComponent { internal static bool IsSafe(string value) { ... } }`
  — no XAML, control, or visual state is involved. Use
  `string.IsNullOrEmpty(value)`, `value.StartsWith(".", StringComparison.Ordinal)`,
  and `value.Contains(...)` for the three separators, each with
  `StringComparison.Ordinal` (never a culture-aware comparison, since the
  check compares literal separator characters, not display equivalence).
  Enumerate code points with `.NET`'s `value.EnumerateRunes()` — `Rune` is
  the code-point-level equivalent of Swift's `Unicode.Scalar` — testing
  `rune.Value < 0x20 || rune.Value == 0x7F`; a plain `foreach (char c in value)`
  loop would iterate UTF-16 code units instead of code points and mis-handle
  any value outside the Basic Multilingual Plane, so `EnumerateRunes()` is
  the correct starting point, not a `char` loop. Callers reach it from
  `VSIXInstaller`- and `OpenVSXClient`-equivalent services before building a
  directory name (`System.IO.Path.Combine`) or a `Uri`, exactly as in
  `VSIXInstaller.swift` and `OpenVSXClient.swift`.

## Design Decisions

**Decision**: Use a denylist of forbidden shapes (empty, leading dot, `/`,
`\`, `:`, C0 controls, DEL) rather than an allowlist of permitted characters.
**Rationale**: Publisher and extension names are internationalized; an
allowlist of characters would refuse a legitimate Japanese or Cyrillic name
long before it refused a hostile ASCII one. What must be rejected is
whatever changes where the value points, not whatever falls outside some
alphabet (source doc comment on `ExtensionIdentityComponent`; traced by test
`internationalisedNamesAreAccepted`).
**Approved**: pending

**Decision**: Refuse a value containing a separator rather than
percent-encoding it before splicing.
**Rationale**: Percent-encoding a `/` would install or address the extension
under a mangled spelling that no longer matches what the registry and the
settings list call it — a silent identity change. A refusal is a legible
failure at the point of installation or lookup; an escape would hide the
mismatch until later (source doc comment on `ExtensionIdentityComponent`;
test `anEncodedSeparatorIsNotASeparator` confirms an already-encoded
sequence such as `%2F` is accepted, because nothing here decodes it).
**Approved**: pending

**Decision**: Reject only the leading `.`, not every interior `.`.
**Rationale**: An interior dot appears in almost every real extension
identifier and version string (`ms-python.python`, `2024.1.0-rc.1`); only a
leading `.` is structural — it produces `.`/`..` (directory climb) or a
hidden-file name. Refusing all dots would reject the overwhelming majority
of legitimate values (source doc comment on `ExtensionIdentityComponent`;
test `interiorDotsAreAccepted`).
**Approved**: pending

**Decision**: Stop the control-character denylist at `U+007F` (DEL) and do
not extend it into the `U+0080`–`U+009F` C1 range.
**Rationale**: `U+0080`–`U+009F` are technically C1 control codes, but none
of them is a path or URL separator on this platform; extending the denylist
there would start rebuilding the allowlist this predicate exists to avoid
(source: inline comment on test `theControlRangeEdgesAreRight` in
`ExtensionIdentityComponentTests.swift`).
**Approved**: pending
