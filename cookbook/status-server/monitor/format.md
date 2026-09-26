---
id: ae9a73de-80c8-4deb-82ab-89c7c5854c54
title: Status Server Monitor Format
domain: agentictoolkit://cookbook/status-server/monitor/format
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Pure, synchronous commit-display formatters — sha truncation and subject/full-message
  extraction — that replace copy-pasted logic across the status server's deploy fetchers
  and board row builders.
platforms:
- typescript
- web
tags:
- monitor
- formatting
- commit
- server
depends-on: []
related: []
references:
- packages/web/packages/status-server/src/monitor/format.ts (agentictoolkit)
- packages/web/packages/status-server/test/format.test.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/webhook-events.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/fetch-vercel.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/fetch-vercel-projects.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/fetch-railway.ts (agentictoolkit)
- packages/web/packages/status-server/src/monitor/fetch-cloudflare.ts (agentictoolkit)
- packages/web/packages/status-server/src/board/derive-activity.ts (agentictoolkit)
- packages/web/packages/status-server/src/board/derive-problems.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Status Server Monitor Format

## Overview

`format.ts` (`packages/web/packages/status-server/src/monitor/format.ts`) is the status
server's single source for two small pieces of commit-display formatting that its own
header comment says were "otherwise copy-pasted across the fetchers and the row
builders": truncating a commit sha to GitHub's 7-character short form, and pulling the
display subject out of a commit message. It exports three pure, synchronous functions —
`shortSha`, `commitFirstLine`, and `commitFullMessage` — with no class, no shared state,
and no I/O. `shortSha` is called from `webhook-events.ts`, `fetch-vercel.ts`,
`fetch-vercel-projects.ts`, `fetch-railway.ts`, and `fetch-cloudflare.ts` to populate a
deploy row's `commitHash` field; `commitFullMessage` is called from the same five files to
populate `commitMessage`; `commitFirstLine` is called from `derive-activity.ts` and
`derive-problems.ts` to derive the one-line `detail` string a board activity or problem
entry shows, from a deploy's already-full `commitMessage`. Per the module's own doc
comment, a commit message is shaped `"subject\n\nbody"`, and the module's job is to let a
row show only the subject (`commitFirstLine`) while a details pane can still show the
whole thing (`commitFullMessage`), rather than each call site re-deriving either from
scratch.

## Behavioral Requirements

### shortSha

- **short-sha-truncation**: `shortSha(hash)` MUST return `hash.slice(0, 7)` when `hash` is
  a non-empty string — the first 7 characters, GitHub's short-sha form.
- **short-sha-null-on-falsy**: `shortSha(hash)` MUST return `null` when `hash` is `null`,
  `undefined`, or the empty string `''`, since the function's guard is the JavaScript
  truthiness of `hash`, not an explicit `=== null || === undefined` check.
- **short-sha-no-validation**: `shortSha` MUST NOT validate `hash`'s length or character
  set before truncating; a `hash` shorter than 7 characters is returned unchanged (via
  `String.prototype.slice`, which does not pad or throw on an out-of-range end index), and
  a `hash` containing non-hexadecimal characters is truncated identically to a valid sha.

### commitFirstLine

- **commit-first-line-extraction**: `commitFirstLine(message, max)` MUST return the
  substring of `message` up to (and not including) the first `"\n"` character, obtained via
  `message.split("\n")[0]`.
- **commit-first-line-null-on-falsy**: `commitFirstLine(message, max)` MUST return `null`
  when `message` is `null`, `undefined`, or the empty string `''`.
- **commit-first-line-no-trim**: `commitFirstLine` MUST NOT trim leading or trailing
  whitespace from the extracted first line; a message whose first line is
  `"  leading and trailing  "` with no embedded `"\n"` is returned with that whitespace
  intact.
- **commit-first-line-cap**: `commitFirstLine` MUST truncate the extracted first line to
  `max` characters, via `first.slice(0, max)`, when the first line's length exceeds `max`;
  a first line whose length is exactly `max` or fewer MUST be returned unchanged.
- **commit-first-line-default-max**: `commitFirstLine` MUST default `max` to `200` when the
  caller supplies no second argument.

### commitFullMessage

- **commit-full-message-preserve-newlines**: `commitFullMessage(message, max)` MUST return
  the message with internal newlines intact — unlike `commitFirstLine`, it MUST NOT split
  on or discard anything after the first `"\n"`; the doc comment states this directly: it
  "KEEPS newlines so the details pane can show the whole 'git comment'".
- **commit-full-message-null-on-falsy**: `commitFullMessage(message, max)` MUST return
  `null` when `message` is `null`, `undefined`, or the empty string `''`.
- **commit-full-message-trailing-trim**: `commitFullMessage` MUST strip only trailing
  whitespace from `message`, via `message.replace(/\s+$/, "")` — leading and internal
  whitespace (including internal newlines) MUST be left unmodified.
- **commit-full-message-empty-after-trim**: `commitFullMessage` MUST return `null` when
  `message` consists entirely of whitespace, since stripping trailing whitespace from an
  all-whitespace string leaves the empty string, which the function then treats as absent.
- **commit-full-message-cap**: `commitFullMessage` MUST truncate the trimmed message to
  `max` characters, via `trimmed.slice(0, max)`, when its length exceeds `max`; a trimmed
  message whose length is exactly `max` or fewer MUST be returned unchanged.
- **commit-full-message-default-max**: `commitFullMessage` MUST default `max` to `4000`
  when the caller supplies no second argument.

### Purity and Side Effects

- **pure-synchronous**: `shortSha`, `commitFirstLine`, and `commitFullMessage` MUST each
  execute synchronously and MUST perform no I/O, network call, logging, or persistence of
  any kind; each is a pure function of its arguments with no dependency on module-level or
  external state.
- **no-throw**: none of the three functions MUST throw for any input within its declared
  parameter type (`string | null | undefined` for `hash`/`message`, `number` for `max`);
  every branch each function can take returns a value.

## Appearance

Not applicable — this is a commit-formatting module, not a visual component.

## States

Not applicable — this is a commit-formatting module, not a visual component; it holds no
runtime state of its own to enumerate.

## Accessibility

Not applicable — this is a commit-formatting module, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-format-001 | commit-full-message-null-on-falsy | `commitFullMessage(null)`; `commitFullMessage(undefined)`; `commitFullMessage('')` | All three resolve `null` — asserted by `format.test.ts` › "returns null for empty input" |
| status-server-monitor-format-002 | commit-full-message-empty-after-trim | `commitFullMessage('   \n  ')` | Resolves `null` — asserted by the same `format.test.ts` case |
| status-server-monitor-format-003 | commit-full-message-preserve-newlines | `commitFullMessage('subject')`; `commitFullMessage('subject\n\nbody line 1\nbody line 2')` | Resolves `'subject'`, then the full string unchanged, internal newlines intact — asserted by `format.test.ts` › "keeps the whole message including body newlines" |
| status-server-monitor-format-004 | commit-full-message-trailing-trim | `commitFullMessage('subject\n\nbody\n\n')` | Resolves `'subject\n\nbody'` — trailing newlines stripped, the internal blank line between subject and body preserved — asserted by `format.test.ts` › "strips trailing whitespace but not internal newlines" |
| status-server-monitor-format-005 | commit-full-message-cap, commit-full-message-default-max | `commitFullMessage('x'.repeat(50), 10)` | Resolves a 10-character string of `'x'` — asserted by `format.test.ts` › "caps at max chars" |
| status-server-monitor-format-006 | short-sha-truncation | `shortSha('abcdef1234567890')` | Resolves `'abcdef1'` — the first 7 characters, traced to `hash.slice(0, 7)`; no dedicated test exists for `shortSha` in the given source |
| status-server-monitor-format-007 | short-sha-null-on-falsy | `shortSha(null)`; `shortSha(undefined)`; `shortSha('')` | All three resolve `null`, traced to the `hash ? hash.slice(0, 7) : null` guard |
| status-server-monitor-format-008 | short-sha-no-validation | `shortSha('ab')` | Resolves `'ab'` unchanged — `slice(0, 7)` on a 2-character string returns the whole string, with no padding and no thrown error |
| status-server-monitor-format-009 | commit-first-line-extraction | `commitFirstLine('subject\n\nbody')` | Resolves `'subject'` — the substring before the first `"\n"`; no dedicated test exists for `commitFirstLine` in the given source |
| status-server-monitor-format-010 | commit-first-line-null-on-falsy | `commitFirstLine(null)`; `commitFirstLine(undefined)`; `commitFirstLine('')` | All three resolve `null` |
| status-server-monitor-format-011 | commit-first-line-cap, commit-first-line-default-max | `commitFirstLine('x'.repeat(250))` | Resolves a 200-character string of `'x'` — the default `max` of `200` applies with no explicit second argument |
| status-server-monitor-format-012 | commit-first-line-no-trim | `commitFirstLine('  leading and trailing  ')` | Resolves `'  leading and trailing  '` unchanged — no `"\n"` is present, so the whole string is the "first line," and no trim step runs |
| status-server-monitor-format-013 | pure-synchronous, no-throw | Call each of `shortSha`, `commitFirstLine`, `commitFullMessage` with global `fetch`, `console.*`, and `fs` spied, across every input vector above | Zero recorded calls on any spy; no call throws for any of the inputs exercised in vectors 001–012 |

## Edge Cases

- **Null and empty input**: `shortSha`, `commitFirstLine`, and `commitFullMessage` each
  treat `null`, `undefined`, and the empty string `''` identically, returning `null` for
  all three, because each function's guard is a single truthiness check
  (`if (!hash)` / `if (!message)`) rather than an explicit `null`/`undefined` comparison —
  MUST. `commitFullMessage` additionally treats a message that is present but consists
  entirely of whitespace (for example `'   \n  '`) as empty, because trailing-whitespace
  stripping leaves nothing for the string to contain — MUST.
- **Boundary values**: for both `commitFirstLine` and `commitFullMessage`, a string whose
  length is exactly `max` is returned unchanged, and only a string strictly longer than
  `max` is truncated, because the cap is a strict `length > max` comparison before slicing
  — MUST. A `max` of `0` truncates any non-empty extracted string to the empty string
  (`slice(0, 0)`), not to `null` — the empty-result guard is on `hash`/`message` only, and
  is checked before truncation runs, so a truncated-to-empty result is never re-checked
  against it — MUST.
- **Concurrent access**: not a synchronization concern by construction — all three
  functions are pure, take no shared mutable state as an argument, and hold none at module
  scope, so any number of concurrent callers, on one request or many, may call them in any
  order or in parallel with no possibility of interleaved corruption — MUST.
- **Error states**: not applicable — none of the three functions has a dependency
  (network, database, file system) that can fail; each computes its result synchronously
  from the arguments it was given, and none can throw for any input within its declared
  parameter type.
- **Offline / disconnected state**: not applicable — this module issues no network call and
  has no connectivity of its own to lose. What happens when a caller (a fetcher such as
  `fetch-vercel.ts`) cannot reach its own upstream is that caller's concern, external to
  this file.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `hash` | `string \| null \| undefined` | n/a (required positional argument) | `shortSha`'s input sha; truncated to 7 characters when truthy. |
| `message` | `string \| null \| undefined` | n/a (required positional argument) | `commitFirstLine`'s and `commitFullMessage`'s input commit message. |
| `max` (in `commitFirstLine`) | `number` | `200` | Maximum character length of the returned first line. |
| `max` (in `commitFullMessage`) | `number` | `4000` | Maximum character length of the returned full message. |

## Deep Linking

Not applicable: this file exports three string-formatting functions with no application
route or deep-link target of any kind.

## Localization

Not applicable: this file renders no text to any user and calls no logging function of its
own; it reformats caller-supplied commit hashes and commit messages (themselves
unlocalized, developer-authored VCS text) and returns them to the caller, which is
responsible for any display.

## Accessibility Options

Not applicable: this file has no user interface and responds to none of Reduce Motion,
Increase Contrast, or Differentiate Without Color.

## Feature Flags

Not applicable: this file consults no feature-flag system; all three exported functions
are unconditionally available with no flag gating any of them.

## Analytics

Not applicable: this file emits no analytics or telemetry event of any kind.

## Privacy

- **Data collected**: None collected or retained by this file itself. It reformats
  caller-supplied commit shas and commit messages — source-control metadata, not end-user
  or credential data — and returns the reformatted value to the caller.
- **Storage**: None. The module holds no state beyond its own function definitions; it
  neither reads from nor writes to any store.
- **Transmission**: None. This file makes no network call and transmits nothing of its
  own; how a `commitHash` or `commitMessage` value travels over the network (for example,
  in a route's response body) is entirely the concern of the external callers that consume
  these functions.
- **Retention**: Not applicable — there is nothing this file collects or stores to retain.

## Logging

This file makes no logging or console call of any kind.

| Event | Level | Message |
|-------|-------|---------|
| n/a | n/a | This file emits no log line at any level; `shortSha`, `commitFirstLine`, and `commitFullMessage` produce no observable output beyond their own return values. |

## Platform Notes

- **SwiftUI**: not a SwiftUI concern (no view). A Swift port has no natural class or actor
  to attach to either — it is three free functions (or three `static` members of a
  `CommitFormatting` namespace) operating on `String?`. `shortSha` becomes
  `hash?.prefix(7).map(String.init)`; because Swift's `String` counts extended grapheme
  clusters rather than the UTF-16 code units JS's `slice` counts, a `hash` containing
  combining characters could yield a different substring length than the TS version —
  in practice a commit sha is plain ASCII hex, so this divergence does not surface.
- **Compose**: same non-UI framing as SwiftUI. A Kotlin port models the three functions as
  top-level `fun`s: `shortSha` as `hash?.take(7)`, `commitFirstLine` as
  `message?.substringBefore("\n")?.take(max)`, and `commitFullMessage`'s trailing-only trim
  as a custom `trimEnd { it.isWhitespace() }` (Kotlin's zero-argument `trimEnd()` behaves
  the same way, trimming only from the end) followed by `.take(max)` and an
  `.ifEmpty { null }` check.
- **React/Web** (source platform): lives at
  `packages/web/packages/status-server/src/monitor/format.ts` on the Node status backend.
  Its three functions are consumed by five deploy fetchers/webhook handlers
  (`webhook-events.ts`, `fetch-vercel.ts`, `fetch-vercel-projects.ts`, `fetch-railway.ts`,
  `fetch-cloudflare.ts`) to populate a deploy row's `commitHash` and `commitMessage`
  fields, and by two board-derivation modules (`derive-activity.ts`, `derive-problems.ts`)
  to derive a one-line `detail` string from an already-populated `commitMessage` via
  `commitFirstLine`. Only `commitFullMessage` has a dedicated test file,
  `status-server/test/format.test.ts`; `shortSha` and `commitFirstLine` have no test file
  of their own in the given source tree.
- **AppKit / UIKit**: same non-UI framing as SwiftUI. A macOS/iOS agent embedding this
  formatting has no windowing or view-layer concern of its own; it would reuse the same
  Swift free functions described under SwiftUI regardless of whether the surrounding app is
  AppKit- or UIKit-based. Any ellipsis-based visual truncation a `UILabel`/`NSTextField`
  applies at render time is a separate, presentation-layer concern from this file's
  data-layer character capping.
- **WinUI 3**: a .NET port models the three functions as `static` methods on a
  `CommitFormatting` class taking `string?` and returning `string?`. `shortSha` becomes
  `hash is { Length: > 0 } h ? h[..Math.Min(h.Length, 7)] : null` (the C# range operator, to
  match `slice`'s no-throw-on-short-input behavior exactly, rather than `Substring`, which
  throws when the requested length exceeds the string's length). `commitFirstLine` becomes
  a split on `'\n'` followed by the same range-based cap. `commitFullMessage`'s
  trailing-only strip is `Regex.Replace(message, @"\s+$", "")` (or plain
  `.TrimEnd()`, which trims all trailing Unicode whitespace and matches `\s+$` closely
  enough for commit-message text) followed by an empty-string check and the same
  range-based cap. None of `HttpClient`, `Task`/`async`, `Windows.Storage`,
  `ObservableCollection`, or `INotifyPropertyChanged` is needed: this is a synchronous,
  non-UI-bound, side-effect-free string-formatting utility with no I/O, no asynchronous
  operation, no persistence, and no live-updating collection to bind to.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-server/src/monitor/format.ts` |

## Design Decisions

- **Decision**: consolidate sha-truncation and first-line/full-message extraction into one
  shared module instead of leaving the logic duplicated in each fetcher and row builder.
  **Rationale**: stated directly in the source's opening comment — this file is "the
  single source for the sha-truncation and first-line extraction that was otherwise
  copy-pasted across the fetchers and the row builders." A shared module removes the
  possibility of the several call sites drifting apart on truncation length or
  whitespace handling.
  **Approved**: pending
- **Decision**: give `commitFirstLine` and `commitFullMessage` different default caps (200
  vs. 4000 characters) and different whitespace rules (no trim vs. trailing-only trim).
  **Rationale**: stated in `commitFullMessage`'s doc comment — unlike `commitFirstLine`,
  it "KEEPS newlines so the details pane can show the whole 'git comment'; the row still
  derives the subject with `commitFirstLine`." A row showing only a one-line subject needs
  a short cap; a details pane showing the whole commit message needs a much larger one and
  must not have its internal structure (the blank line separating subject from body)
  collapsed.
  **Approved**: pending
- **Decision**: treat an empty string identically to `null`/`undefined` in all three
  functions, via a single truthiness check (`!hash`, `!message`), rather than checking
  `=== null || === undefined`.
  **Rationale**: not stated in source; recorded here as a fact of the code per this
  recipe's authoring rules, not a defended choice. The effect is that a caller-supplied
  empty-string hash or commit message is indistinguishable from a genuinely absent one —
  both formatters return `null` either way.
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |

`unit-test-coverage` is `partial`: `format.test.ts` gives `commitFullMessage` full
assertion coverage across empty input, newline preservation, trailing-whitespace
stripping, and the `max` cap, but the given source tree contains no dedicated test file
exercising `shortSha` or `commitFirstLine` at all — their behavior in this recipe is
derived from reading `format.ts` directly, not from a passing assertion. `separation-of-
concerns` passes: this file owns exactly one concern, commit-display formatting, and its
own header comment frames its reason for existing as removing that concern from the
fetchers and row builders that used to duplicate it. `explicit-error-handling` passes:
none of the three functions has an error path to swallow — there is no exception handling
and no I/O that could fail — and the `null` each returns for absent or empty input is a
deliberate, documented sentinel value (per the requirements above), not a caught or ignored
failure.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 |  |  | Initial creation |
