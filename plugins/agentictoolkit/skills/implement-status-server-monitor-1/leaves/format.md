<!-- leaf: implement-status-server-monitor-1/format · source: status-server-monitor-format.md -->

**Rules** (cite as `implement-status-server-monitor-1/format#<slug>`):

- `short-sha-truncation` MUST
- `short-sha-null-on-falsy` MUST
- `short-sha-no-validation` MUST
- `commit-first-line-extraction` MUST
- `commit-first-line-null-on-falsy` MUST
- `commit-first-line-no-trim` MUST
- `commit-first-line-cap` MUST
- `commit-first-line-default-max` MUST
- `commit-full-message-preserve-newlines` MUST
- `commit-full-message-null-on-falsy` MUST
- `commit-full-message-trailing-trim` MUST
- `commit-full-message-empty-after-trim` MUST
- `commit-full-message-cap` MUST
- `commit-full-message-default-max` MUST
- `pure-synchronous` MUST
- `no-throw` MUST

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `hash` | `string \| null \| undefined` | n/a (required positional argument) | `shortSha`'s input sha; truncated to 7 characters when truthy. |
| `message` | `string \| null \| undefined` | n/a (required positional argument) | `commitFirstLine`'s and `commitFullMessage`'s input commit message. |
| `max` (in `commitFirstLine`) | `number` | `200` | Maximum character length of the returned first line. |
| `max` (in `commitFullMessage`) | `number` | `4000` | Maximum character length of the returned full message. |

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

