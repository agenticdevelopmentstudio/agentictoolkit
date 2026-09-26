---
id: 5b0fea72-dbb8-4299-a54f-dc16486df1ae
title: ExtensionIdentityComponent
domain: agentictoolkit://cookbook/core/extensions/extension-identity-component
type: ingredient
version: 1.0.2
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Denylist predicate deciding whether a string from an extension manifest is
  safe to splice as one path or URL component.
platforms:
- swift
- macos
tags:
- extension-host
- path-safety
- input-validation
depends-on: []
related: []
references: []
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a stateless string-validation predicate, not a
visual component.

## States

Not applicable — this is a stateless string-validation predicate, not a
visual component.

## Accessibility

Not applicable — this is a stateless string-validation predicate, not a
visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|--------------|-------|----------|
| extension-identity-001 | empty-value-refused | `""` | `false` |
| extension-identity-002 | leading-dot-refused | `".."` | `false` |
| extension-identity-003 | leading-dot-refused | `".hidden"` | `false` |
| extension-identity-004 | forward-slash-refused | `"../../etc"` | `false` |
| extension-identity-005 | backslash-refused | `"..\..\windows"` | `false` |
| extension-identity-006 | colon-refused | `"Macintosh HD:Users"` | `false` |
| extension-identity-007 | control-character-refused | `"a\nb"` (contains `U+000A`) | `false` |
| extension-identity-008 | control-character-refused | `"\u{7F}"` | `false` |
| extension-identity-009 | c0-boundary-accepted | `"a\u{20}b"` and `"a\u{7E}b"` | `true` |
| extension-identity-010 | c1-range-accepted | `"a\u{80}b"` | `true` |
| extension-identity-011 | interior-dot-accepted | `"ms-python.python"` | `true` |
| extension-identity-012 | non-ascii-accepted | `"日本語パック"`, `"расширение"`, `"emoji-🎉-pack"` | `true` |
| extension-identity-013 | literal-percent-sequence-accepted | `"a%2Fb"` | `true` |
| extension-identity-014 | pure-function, synchronous-non-throwing | `"1.0.0"` | `true` |

All fourteen vectors are traced to
`packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/Extensions/ExtensionIdentityComponentTests.swift`
(`emptyIsRefused`, `aLeadingDotIsRefused`, `separatorsAreRefused`,
`controlCharactersAreRefused`, `theControlRangeEdgesAreRight`,
`interiorDotsAreAccepted`, `internationalisedNamesAreAccepted`,
`anEncodedSeparatorIsNotASeparator`, `ordinaryNamesAreAccepted`).

## Edge Cases

- **Empty input**: `value == ""` MUST return `false` (traced to
  `emptyIsRefused`).
- **Boundary values at the control-character edges**: `U+001F` MUST be
  refused, `U+0020` MUST be accepted, `U+007E` MUST be accepted, `U+007F`
  MUST be refused, and `U+0080` MUST be accepted (traced to
  `theControlRangeEdgesAreRight`).
- **Boundary: a value that is only a dot**: `"."` and `".."` MUST be refused
  identically to a longer leading-dot name such as `".ssh"` (traced to
  `aLeadingDotIsRefused`).
- **Malformed input**: not applicable as a distinct condition — `value` is a
  Swift `String`, already a well-formed sequence of Unicode scalars for any
  argument a caller can construct, so `isSafe` has no notion of "malformed"
  input; it never throws or traps regardless of content, including
  combining sequences and emoji (traced to `internationalisedNamesAreAccepted`
  and the absence of any input-shape precondition in the source).
- **Concurrent access**: not applicable in the shared-mutable-state sense —
  `isSafe` is a pure function of its argument, `ExtensionIdentityComponent`
  has no cases and cannot be instantiated, and the source declares no stored
  property anywhere in the type. Concurrent calls from multiple threads or
  actors MUST produce results that depend only on each call's own `value`
  argument, never on the order or overlap of other calls.
- **Error states (dependency unavailable)**: not applicable — `isSafe`
  performs no file, network, or database access; the entire function body
  reads only the scalars of `value`, so there is no dependency that can be
  unavailable.
- **Offline / disconnected state**: not applicable — `isSafe` does not
  operate over a network; it is a synchronous, local string computation.
- **Already-encoded separators are not decoded**: a value already containing
  an encoded separator, such as `"a%2Fb"` or `"a%2E%2E"`, MUST be accepted;
  the caller that splices the accepted value in verbatim is responsible for
  never decoding it afterward, since decoding after this check would
  reintroduce a separator behind the check (traced to
  `anEncodedSeparatorIsNotASeparator`).
- **Unbounded length**: `isSafe` MUST accept or refuse a value of any length
  according only to the shape rules above; the source enforces no minimum
  length beyond non-emptiness and no maximum length at all (traced to the
  absence of any length check in the source).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| — | — | — | Not applicable: `isSafe` has a single required parameter, `value: String`, and no configurable options, defaults, environment variables, settings keys, or injected dependencies (traced to the function signature, which declares nothing else). |

## Deep Linking

Not applicable: `ExtensionIdentityComponent` is an internal string predicate
with no navigable route, screen, or URL scheme of its own — it validates a
fragment that another URL or path is built from, it does not resolve or
present one itself (traced to the source, which defines only
`isSafe(_:) -> Bool` and no URL, route, or scheme type).

## Localization

Not applicable: the source declares no user-facing string — `isSafe` returns
a `Bool`, and the only string literals in the source are the single-character
separators (`.`, `/`, `\`, `:`) being compared against, not text shown to a
user (traced to the full body of the source file).

## Accessibility Options

Not applicable: this is a non-visual, backend string predicate with no
rendered UI to respond to Reduce Motion, Increase Contrast, or Differentiate
Without Color (traced to the source, which contains no UI code of any kind).

## Feature Flags

Not applicable: the source declares no feature-flag check; `isSafe` always
evaluates the same fixed rule set unconditionally on every call (traced to
the function body, which contains no flag or configuration lookup).

## Analytics

Not applicable: the source contains no event-emission or telemetry call;
`isSafe` returns its result directly to the caller with no recorded event
(traced to the function body, which performs no side effect of any kind).

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

## Logging

Not applicable: the source contains no logging call (no `Logger`, `os_log`,
`print`, or similar) anywhere in `isSafe` or the enclosing enum (traced to
the full body of the source file, which is limited to the guard chain and
the final boolean expression).

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

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Core/Extensions/ExtensionIdentityComponent.swift` |

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | passed | Security |
| [unicode-support](agenticdevelopercookbook://compliance/internationalization#unicode-support) | passed | Internationalization |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |

`separation-of-concerns` passes because the source's own doc comment states
the reason for the type's existence: the same denylist check was needed by
both `VSIXInstaller` and `OpenVSXClient.detail` against the same kind of
manifest field, and only one of the two callers had it, so the rule was
pulled into this one predicate rather than left duplicated (`pure-function`,
Overview). `input-sanitization` passes with a documented nuance: the
predicate refuses a value containing `/`, `\`, `:`, a leading `.`, or a
control character rather than escaping or stripping it — see the "refused,
not escaped" Design Decision above — so it satisfies the check by rejection
rather than by cleansing (`forward-slash-refused`, `backslash-refused`,
`colon-refused`, `leading-dot-refused`, `control-character-refused`).
`unicode-support` passes because the check is deliberately scalar-level and
a denylist of shapes rather than an allowlist of characters, so it accepts
internationalized publisher and extension names by design
(`non-ascii-accepted`, test `internationalisedNamesAreAccepted`).
`unit-test-coverage` passes: nine test functions in
`ExtensionIdentityComponentTests.swift` exercise every refusal branch, the
ordinary and internationalized acceptance paths, the interior-dot exception,
the encoded-separator exception, and the exact numeric edges of the
control-character range.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: removed source line-number citations; recipes cite files and symbols, not lines. |
