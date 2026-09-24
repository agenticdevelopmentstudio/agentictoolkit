---
id: a0ae2ae1-7d51-4639-8f3b-062dcf750b66
title: Status Row Model
domain: agentictoolkit://recipes/status-web-src-lib-row-model
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The one Row shape every status-dashboard pane renders: builders from Problem
  and ActivityRow, the StatusRow adapter, search text, clipboard text, deploy demotion.'
platforms:
- typescript
- web
tags: []
depends-on:
- agentictoolkit://recipes/status-web-src-lib-board-types
- agentictoolkit://recipes/status-web-src-lib-format
- agentictoolkit://recipes/status-web-src-lib-deploy-status
- agentictoolkit://recipes/status-web-src-lib-colors
- agentictoolkit://recipes/status-web-src-lib-issue-sources
related: []
references: []
approved-by: ''
approved-date: ''
---

# Status Row Model

## Overview

`packages/web/packages/status-web/src/lib/row-model.ts` is "The ONE row model" of the status dashboard (its header comment). Active problems, recently-resolved rows and the activity feed are all built into the single `Row` shape, then rendered by the one `<StatusRow>` through `rowToStatusRowProps`, "so every pane has identical row capabilities (clickable commits, consistent links) and a new field is added in one place".

The module exports:

- `RowTone` and `Row` — the row data shape.
- `problemToRow(p)` and `activityToRow(a)` — spell a server-derived `Problem` or `ActivityRow` (from `board-types.ts`) as a `Row`. "The server has already decided what is a problem, what happened, and when — these builders only spell the row."
- `rowToStatusRowProps(row, nowMs)` — the adapter to `StatusRowProps`.
- `rowSearchText(row)` — the free text the pane filter boxes match against.
- `rowToText(row, nowMs)` and `rowsToText(rows, nowMs)` — clipboard serialization, one tab-separated line per row (used by `ActivityPanel.tsx`'s copy button).
- `commitUrlOf(repo, hash)` — a GitHub commit URL or `null`.
- `STATE_LABEL` — the problem state to status-word table.
- `UNCONFIRMED_AFTER_MS`, `unconfirmedWindowMs(probeIntervalMs?)` and `deployDtoUnconfirmed(d, nowMs, probeIntervalMs?)` — the client's only remaining freshness clock, applied to raw `DeploymentDTO`s by `DeployList.tsx` and `deploy-view.ts`, never to a `Row`.

Every export is a pure, synchronous function or constant. The module performs no I/O, holds no state and is covered by `row-model.test.ts` (Vitest).

## Behavioral Requirements

### Row shape

- **row-tone-values**: `RowTone` MUST be exactly one of `"good"`, `"bad"`, `"progress"`, `"neutral"`, `"stale"`.
- **row-required-fields**: A `Row` MUST carry `key` (string), `source` (string), `platform` (string or null), `name` (string), `environment` (string or null), `statusWord` (string), `tone` (`RowTone`), `sha`, `commitUrl`, `message`, `detail` (each string or null), `at` (string), `sourceUrl` and `liveUrl` (each string or null).
- **row-optional-fields**: A `Row` MAY carry `commitBody`, `lastCheckedAt`, `downSince`, `branch`, `errorText` (each string or null), and `statusCode` and `responseTimeMs` (each number or null); an absent optional field MUST be treated as not present by consumers ("undefined elsewhere so existing builders stay unchanged").
- **row-at-iso**: `Row.at` MUST be an ISO timestamp; it is "shown as a relative time and used for window filtering". This is a documented caller precondition, not validated here.
- **row-message-subject**: `Row.message` MUST hold only the commit subject line, while `Row.commitBody` holds the full commit message.

### problemToRow

- **problem-key**: `problemToRow` MUST set `key` to `"problem:"` followed by `Problem.target`.
- **problem-source-platform**: `problemToRow` MUST set both `source` and `platform` to `Problem.source`.
- **problem-status-word**: `problemToRow` MUST set `statusWord` to `STATE_LABEL[Problem.state]` when that lookup is defined, and otherwise to `Problem.state` verbatim.
- **state-label-table**: `STATE_LABEL` MUST map `down` to `"down"`, `degraded` to `"degraded"`, `failed` to `"deploy failed"`, `stuck` to `"deploy stuck"`, `stale` to `"deployment failed"`, `unreachable` to `"platform unreachable"` and `erroring` to `"app errors"`.
- **problem-tone-minor**: `problemToRow` MUST set `tone` to `"progress"` when `Problem.severity` is `"minor"`.
- **problem-tone-other**: `problemToRow` MUST set `tone` to `"bad"` when `Problem.severity` is `"major"` or `"critical"`; a problem row MUST NOT be `"good"`.
- **problem-at**: `problemToRow` MUST set `at` to `Problem.since`.
- **problem-down-since**: `problemToRow` MUST set `downSince` to `Problem.since` for every problem, whatever its source, so `downSince` equals `at` on every problem row.
- **problem-passthrough**: `problemToRow` MUST copy `name`, `environment`, `detail`, `sourceUrl`, `liveUrl`, `statusCode`, `branch` and `errorText` from the `Problem` unchanged.
- **problem-no-probe-diagnostics**: `problemToRow` MUST leave `responseTimeMs` and `lastCheckedAt` undefined.

### activityToRow

- **activity-key**: `activityToRow` MUST set `key` to `ActivityRow.id` unchanged.
- **activity-platform**: `activityToRow` MUST set `platform` to `ActivityRow.source`, or `null` when it is null or undefined; it MUST NOT derive the platform by parsing `ActivityRow.target`.
- **activity-source-fallback**: `activityToRow` MUST set `source` to `ActivityRow.source` when non-null, and otherwise to `ActivityRow.kind` (`"deploy"`, `"probe"` or `"platform"`).
- **activity-verb-tone**: `activityToRow` MUST set `statusWord` to `ActivityRow.verb` and `tone` to `ActivityRow.tone`, both verbatim; there is no phase table.
- **activity-passthrough**: `activityToRow` MUST copy `name`, `environment`, `detail`, `at`, `sourceUrl`, `liveUrl`, `branch` and `errorText` from the `ActivityRow` unchanged.
- **activity-no-diagnostics**: `activityToRow` MUST leave `statusCode`, `responseTimeMs`, `lastCheckedAt` and `downSince` undefined.

### Commit fields (both builders)

- **commit-url**: `commitUrlOf(repo, hash)` MUST return `"https://github.com/" + repo + "/commit/" + hash` when both `repo` and `hash` are non-empty strings.
- **commit-url-null**: `commitUrlOf` MUST return `null` when `repo` or `hash` is null or the empty string.
- **commit-url-field**: Both builders MUST set `commitUrl` to `commitUrlOf(commitRepo, commitHash)` of their input.
- **sha-only-when-linked**: Both builders MUST set `sha` to the first 7 characters of `commitHash` (via `shortSha`) only when `commitUrl` is non-null, and to `null` otherwise — "a bare, non-clickable hash is noise".
- **commit-message-subject**: Both builders MUST set `message` to `commitFirstLine(commitMessage)`: the text before the first line feed, capped at 200 characters, or `null` for a null or empty message; the message MUST be set even when `sha` is null.
- **commit-body-full**: Both builders MUST set `commitBody` to `commitMessage` unchanged.

### rowToStatusRowProps

- **props-tone-color**: `rowToStatusRowProps` MUST set `statusColor` from the tone: `good` to `var(--color-apt-green)`, `bad` to `var(--color-apt-red)`, `progress` to `var(--color-apt-gold)`, `neutral` to `var(--color-apt-gold)`, `stale` to `var(--color-apt-text-muted)`.
- **props-bold**: `rowToStatusRowProps` MUST set `statusBold` to `true` only when the tone is `"bad"`.
- **props-verbatim-word**: `rowToStatusRowProps` MUST set `statusWord` to `Row.statusWord` unchanged; it MUST NOT re-judge or demote a row based on its age.
- **props-time-label**: `rowToStatusRowProps` MUST set `timeLabel` to `timeAgo(Row.at, nowMs)`: `"just now"` under 60 seconds, then whole minutes as `"<n>m"` under 60 minutes, whole hours as `"<n>h"` under 24 hours, else whole days as `"<n>d"`.
- **props-platform**: `rowToStatusRowProps` MUST set `platform` to `Row.platform`, converting `null` to `undefined`.
- **props-passthrough**: `rowToStatusRowProps` MUST copy `environment`, `name`, `sourceUrl` and `liveUrl` from the row unchanged.
- **props-no-copy**: `rowToStatusRowProps` MUST NOT set `copyGetText` or any commit, detail or diagnostic field on the props.

### rowSearchText

- **search-text-shape**: `rowSearchText` MUST return `name`, `environment`, `statusWord`, `detail` and `commitBody` joined by single spaces, in that order, with a null or undefined field contributing the empty string.
- **search-text-rendered-word**: `rowSearchText` MUST use the same `statusWord` that `rowToStatusRowProps` renders, so a filter matches the on-screen word.
- **search-text-excludes**: `rowSearchText` MUST NOT include `source`, `platform`, `sha`, `message`, URLs or `branch`; the subject is searchable only through `commitBody`.

### Clipboard serialization

- **text-columns**: `rowToText` MUST return exactly seven columns joined by a single tab character, in order: time label, environment badge, source label, name, status word, commit-or-detail, URL.
- **text-time**: The time column MUST be `timeAgo(Row.at, nowMs)`.
- **text-env**: The environment column MUST be `envBadgeLabel(environment)` (`production` to `PROD`, `staging` to `STAG`, `testing` to `TEST`, any other value upper-cased) when `environment` is non-empty, and the empty string otherwise.
- **text-source**: The source column MUST be `SOURCE_LABEL[source]` when `source` is a known `IssueSource` (`dns` to `DNS`, `http` to `HTTP`, `glitchtip` to `GlitchTip`, `vercel` to `Vercel`, `cloudflare-pages` to `Cloudflare`, `railway` to `Railway`, `crunchy` to `Crunchy Bridge`), and `source` verbatim otherwise.
- **text-status**: The status column MUST be `Row.statusWord` verbatim.
- **text-commit-precedence**: The commit column MUST be the non-empty values of `sha` and `message` joined by one space when at least one is non-empty, else `detail` when non-empty, else the empty string.
- **text-url**: The URL column MUST be `liveUrl`, else `sourceUrl`, else the empty string; the column MUST be present even when empty.
- **text-field-escaping**: NEEDS REVIEW: Not implemented in source. `rowToText` declares that "every row has the same number of tab-separated fields", but it neither escapes nor strips tab and newline characters inside `name`, `detail`, `statusWord`, `environment` or the URLs; one such character silently adds a column or splits the row. Settling it needs an owner decision on whether fields are sanitized, quoted (TSV/CSV style) or guaranteed tab-free by the server.
- **rows-text**: `rowsToText` MUST return each row's `rowToText` joined by a single line feed, in input order, with no trailing line feed; an empty array MUST yield the empty string.

### Deploy demotion clock

- **unconfirmed-floor**: `UNCONFIRMED_AFTER_MS` MUST equal 600000 (10 minutes).
- **unconfirmed-window**: `unconfirmedWindowMs(probeIntervalMs)` MUST return the larger of `UNCONFIRMED_AFTER_MS` and five times `probeIntervalMs`, treating an undefined interval as 0.
- **dto-terminal-never-demoted**: `deployDtoUnconfirmed` MUST return `false` when the deploy `status` is not in flight; only `"building"` and `"queued"` are in flight.
- **dto-clock-source**: `deployDtoUnconfirmed` MUST measure from `phaseConfirmedAt`, falling back to `createdAt` when `phaseConfirmedAt` is null or undefined.
- **dto-fail-closed**: `deployDtoUnconfirmed` MUST return `true` for an in-flight deploy whose clock string does not parse to a finite time.
- **dto-threshold**: `deployDtoUnconfirmed` MUST return `true` for an in-flight deploy when `nowMs` minus the confirmed time is strictly greater than `unconfirmedWindowMs(probeIntervalMs)`, and `false` when it is less than or equal.
- **row-never-clocked**: Functions in this module MUST NOT apply a freshness clock to a `Row`; an unconfirmed activity phase arrives already expired by the server (`derive-activity.ts`, outside these sources) as verb `"unknown"`, tone `"stale"`.

### Module-wide

- **pure-synchronous**: Every exported function MUST be pure and synchronous: it MUST NOT read a clock (time is passed in as `nowMs`), perform I/O or mutate its inputs.
- **single-threaded**: The module runs on the browser's single JavaScript thread; each call completes before another starts, so there is no ordering or locking contract.

## Appearance

Not applicable — this is a data model and adapter module, not a visual component.

## States

Not applicable — this is a data model and adapter module, not a visual component.

## Accessibility

Not applicable — this is a data model and adapter module, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| row-model-001 | problem-source-platform, problem-status-word, problem-tone-other, problem-at, problem-passthrough | `problemToRow` of a problem with `source: "vercel"`, `state: "failed"`, `severity: "major"`, `sourceUrl: "https://vercel.com/team/adh"`, `liveUrl: "https://app.example.com"`, `since: "2026-06-04T18:00:00.000Z"` | `source` and `platform` `"vercel"`, `statusWord` `"deploy failed"`, `tone` `"bad"`, URLs unchanged, `at` `"2026-06-04T18:00:00.000Z"` (from `row-model.test.ts`) |
| row-model-002 | commit-url-field, sha-only-when-linked, commit-message-subject | problem with `commitHash: "abc1234def"`, `commitRepo: "example-org/example-app"`, `commitMessage: "fix the thing\nbody text"` | `sha` `"abc1234"`, `commitUrl` `"https://github.com/example-org/example-app/commit/abc1234def"`, `message` `"fix the thing"` (from `row-model.test.ts`) |
| row-model-003 | sha-only-when-linked, commit-url-null | problem with `commitHash: "abc1234def"`, `commitRepo: null`, `commitMessage: "fix the thing\nbody"` | `commitUrl` null, `sha` null, `message` `"fix the thing"` (from `row-model.test.ts`) |
| row-model-004 | state-label-table, problem-status-word | problem with `state: "stuck"` | `statusWord` `"deploy stuck"` (from `row-model.test.ts`) |
| row-model-005 | problem-status-word | problem with `state: "mystery"` | `statusWord` `"mystery"` |
| row-model-006 | problem-tone-minor | problem with `severity: "minor"`, `state: "degraded"` | `tone` `"progress"` (from `row-model.test.ts`) |
| row-model-007 | commit-body-full, row-message-subject | problem with `commitMessage: "fix the thing\n\nbody line 1\nbody line 2"`, repo `"o/r"`, hash set | `message` `"fix the thing"`, `commitBody` the full message (from `row-model.test.ts`) |
| row-model-008 | problem-passthrough | problem with `branch: "prepared"`, `errorText: "next build exited 1"` | row `branch` `"prepared"`, `errorText` `"next build exited 1"` (from `row-model.test.ts`) |
| row-model-009 | problem-key, problem-down-since, problem-no-probe-diagnostics | problem with `target: "adh-app-production"`, `since: "2026-06-04T18:00:00.000Z"` | `key` `"problem:adh-app-production"`, `downSince` `"2026-06-04T18:00:00.000Z"`, `responseTimeMs` and `lastCheckedAt` undefined |
| row-model-010 | activity-platform, activity-verb-tone | `activityToRow` of `kind: "deploy"`, `source: "vercel"`, `verb: "deployed"`, `tone: "good"` | `platform` and `source` `"vercel"`, `statusWord` `"deployed"`, `tone` `"good"` (from `row-model.test.ts`) |
| row-model-011 | activity-platform | activity with `kind: "probe"`, `source: "http"`, `target: "adh-app-production"` | `platform` and `source` `"http"` (from `row-model.test.ts`) |
| row-model-012 | activity-platform | activity with `kind: "deploy"`, `source: "cloudflare-pages"`, `target: "cloudflare\|proj123\|"` | `platform` and `source` `"cloudflare-pages"`, not the target's `"cloudflare"` (from `row-model.test.ts`) |
| row-model-013 | activity-source-fallback | activity with `kind: "deploy"`, `source: null` | `platform` null, `source` `"deploy"` (from `row-model.test.ts`) |
| row-model-014 | activity-key, activity-no-diagnostics, activity-passthrough | activity with `id: "a1"`, `branch: "staging"`, `errorText: "next build exited 1"` | `key` `"a1"`, `branch` `"staging"`, `errorText` `"next build exited 1"`, `downSince` and `statusCode` undefined (partly from `row-model.test.ts`) |
| row-model-015 | props-tone-color, props-bold | `rowToStatusRowProps` with tones `good`, `bad`, `progress` | `var(--color-apt-green)`/not bold, `var(--color-apt-red)`/bold, `var(--color-apt-gold)`/not bold (from `row-model.test.ts`) |
| row-model-016 | props-tone-color | tones `neutral` and `stale` | `var(--color-apt-gold)` and `var(--color-apt-text-muted)`, both not bold |
| row-model-017 | props-verbatim-word, row-never-clocked | activity row `verb: "building"`, `tone: "progress"`, `nowMs` one hour after `at` | `statusWord` `"building"`, `statusColor` `var(--color-apt-gold)` (from `row-model.test.ts`) |
| row-model-018 | props-verbatim-word | problem row `state: "failed"`, `nowMs` 30 days after `since` | `statusWord` unchanged, `statusColor` `var(--color-apt-red)` (from `row-model.test.ts`) |
| row-model-019 | props-time-label, props-platform, props-passthrough | row `at: "2026-06-04T18:00:00.000Z"`, `platform: null`, `liveUrl: "https://live"`, `sourceUrl: "https://src"`, `nowMs` of `2026-06-04T18:01:00.000Z` | `timeLabel` `"1m"`, `platform` undefined, URLs unchanged |
| row-model-020 | search-text-shape | problem row `name: "adh"`, `environment: "production"`, `state: "failed"`, `commitMessage: "broke login\nbody"` | text contains `"adh"`, `"production"`, `"deploy failed"`, `"broke login"` and `"body"` (from `row-model.test.ts`) |
| row-model-021 | search-text-rendered-word | row `statusWord: "unknown"`, `tone: "stale"` | search text contains `"unknown"`; props `statusWord` `"unknown"` (from `row-model.test.ts`) |
| row-model-022 | search-text-shape, search-text-excludes | row `name: "a"`, `environment: null`, `statusWord: "s"`, `detail: null`, no `commitBody`, `sha: "abc1234"` | `"a  s  "` (the sha is not included) |
| row-model-023 | commit-url, commit-url-null | `commitUrlOf("o/r", "deadbeef")`; `commitUrlOf(null, "deadbeef")`; `commitUrlOf("o/r", null)` | `"https://github.com/o/r/commit/deadbeef"`; null; null (from `row-model.test.ts`) |
| row-model-024 | text-columns, text-time, text-env, text-source, text-commit-precedence, text-url | row `at` 18:00:00, `nowMs` 18:01:00, `environment: "production"`, `source: "cloudflare-pages"`, `name: "adh"`, `statusWord: "deployed"`, `sha: "abc1234"`, `message: "fix"`, `detail: "x"`, `liveUrl: null`, `sourceUrl: "https://src"` | `"1m"`, `"PROD"`, `"Cloudflare"`, `"adh"`, `"deployed"`, `"abc1234 fix"`, `"https://src"` joined by tabs |
| row-model-025 | text-source, text-commit-precedence, text-url, text-env | row `source: "deploy"`, `environment: null`, `sha: null`, `message: null`, `detail: "HTTP 503"`, both URLs null | source column `"deploy"`, env column `""`, commit column `"HTTP 503"`, URL column `""`; seven columns (six tabs) |
| row-model-026 | rows-text | `rowsToText([])`; `rowsToText([r1, r2])` | `""`; `rowToText(r1) + "\n" + rowToText(r2)` |
| row-model-027 | unconfirmed-floor, unconfirmed-window | `unconfirmedWindowMs(undefined)`; `(60000)`; `(300000)` | 600000; 600000; 1500000 (from `row-model.test.ts`) |
| row-model-028 | dto-threshold | `status: "building"`, `phaseConfirmedAt` T, `nowMs` T + 599999; then T + 600001 | `false`; `true` (from `row-model.test.ts`) |
| row-model-029 | dto-terminal-never-demoted | `status: "success"`, `nowMs` 30 days after `phaseConfirmedAt` | `false` (from `row-model.test.ts`) |
| row-model-030 | dto-clock-source, dto-fail-closed | `status: "building"`, no `phaseConfirmedAt`, `createdAt` T, `nowMs` T + 600001; then `createdAt: "nope"`, `nowMs` T | `true`; `true` (from `row-model.test.ts`) |
| row-model-031 | unconfirmed-window, dto-threshold | `status: "building"`, `probeIntervalMs` 360000, `nowMs` T + 600001; then T + 1800001 | `false`; `true` (from `row-model.test.ts`) |
| row-model-032 | dto-threshold | `status: "queued"`, `nowMs` exactly T + 600000 | `false` (strictly greater is required) |
| row-model-033 | text-field-escaping | row with `detail: "a\tb"`, no sha or message | eight tab-separated fields; the open question on text-field-escaping decides the conformant output |
| row-model-034 | pure-synchronous, single-threaded | call each export twice with the same arguments | identical results; inputs unmodified; no Promise returned |

## Edge Cases

- **Null commit fields**: A null `commitHash`, `commitRepo` or `commitMessage` MUST yield `sha`, `commitUrl` and `message` of null, and `commitBody` of null (row-model-003).
- **Empty strings**: `commitUrlOf("", "abc")` and `commitUrlOf("o/r", "")` MUST return null. An empty `environment` MUST produce an empty env column in `rowToText`, and an empty `sha` or `message` MUST be dropped from the commit column.
- **Unknown problem state**: A state absent from `STATE_LABEL` MUST render verbatim (row-model-005). Because `STATE_LABEL` is a plain object, a state spelled like an inherited object member (for example `"constructor"`) resolves to that inherited value rather than falling back; the server's documented state vocabulary (`Problem.state` doc comment) contains no such names.
- **Unknown source**: A `Row.source` that is not an `IssueSource` (an activity row's `kind` fallback) MUST appear verbatim in the clipboard source column (row-model-025).
- **Malformed `at`**: `Row.at` is documented as an ISO timestamp. An unparseable value makes `timeAgo` compute `NaN` and return `"NaNd"`; this MUST be treated as a caller precondition violation, not handled here.
- **Future `at`**: A timestamp later than `nowMs` gives a negative elapsed time and MUST render `"just now"`.
- **Boundary of the demotion window**: Elapsed time exactly equal to the window MUST NOT demote (row-model-032); one millisecond more MUST (row-model-028).
- **Missing probe interval**: An undefined `probeIntervalMs` (older backend) MUST use the 10-minute floor; an interval of 120000 ms or less also yields the floor because five times it is at most 600000.
- **Unparseable deploy clock**: An in-flight deploy whose `phaseConfirmedAt` (or fallback `createdAt`) does not parse MUST demote — fail closed (row-model-030). A terminal deploy with an unparseable clock MUST NOT demote, since the in-flight test runs first.
- **Tabs and newlines in clipboard fields**: Not escaped; see the open question on text-field-escaping (row-model-033).
- **Commit subject over 200 characters**: `message` MUST be the first 200 characters with no ellipsis, while `commitBody` and `rowSearchText` keep the full text.
- **Concurrent access**: Not applicable — every export is pure and synchronous on the single JavaScript thread, so calls cannot interleave.
- **Error states**: Not applicable — no function touches a network, file or other dependency, and none throws for inputs of its declared types.
- **Offline or disconnected state**: Not applicable — no network is involved; freshness of the server data is judged elsewhere (`board-staleness.ts`, `snapshot-staleness.ts`).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `nowMs` (`rowToStatusRowProps`, `rowToText`, `rowsToText`, `deployDtoUnconfirmed`) | `number` | none (required) | Epoch milliseconds used for relative time labels and the demotion clock; injected so the functions stay pure. |
| `probeIntervalMs` (`unconfirmedWindowMs`, `deployDtoUnconfirmed`) | `number` or undefined | undefined, treated as 0 | The backend probe cadence (from `Board.probeIntervalMs`); the window is five times it, floored at 10 minutes. |
| `UNCONFIRMED_AFTER_MS` | constant `number` | `600000` | Floor of the unconfirmed window. |

There are no environment variables, settings keys or injected services.

## Deep Linking

Not applicable: `row-model.ts` defines no routes; it only copies provider and GitHub URLs (`sourceUrl`, `liveUrl`, `commitUrl`) onto rows.

## Localization

The module holds hardcoded English strings with no localization layer:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `STATE_LABEL.down` | `down` | Problem status word |
| `STATE_LABEL.degraded` | `degraded` | Problem status word |
| `STATE_LABEL.failed` | `deploy failed` | Problem status word |
| `STATE_LABEL.stuck` | `deploy stuck` | Problem status word |
| `STATE_LABEL.stale` | `deployment failed` | Problem status word for a production deploy behind newer unpromoted builds |
| `STATE_LABEL.unreachable` | `platform unreachable` | Problem status word when a provider API cannot be polled |
| `STATE_LABEL.erroring` | `app errors` | Problem status word when the app throws while its host answers |

Activity status words arrive already spelled by the server (`ActivityRow.verb`). Time labels (`just now`, `m`, `h`, `d`), environment badges and source labels come from `time-ago.ts`, `colors.ts` and `issue-sources.ts`, also English-only.

## Accessibility Options

Not applicable: `row-model.ts` renders nothing; the tone-to-color mapping it produces is consumed by `StatusRow`, which owns display.

## Feature Flags

Not applicable: `row-model.ts` reads no flags; every export is always active.

## Analytics

Not applicable: `row-model.ts` emits no events.

## Privacy

Not applicable: `row-model.ts` collects and stores nothing; commit messages, branches and provider error text pass through in memory, and only the user's own copy action puts row text on the clipboard.

## Logging

Not applicable: `row-model.ts` contains no logging calls.

## Platform Notes

- **SwiftUI**: Model `Row` as a `struct Row: Sendable, Hashable, Identifiable` (id = `key`) and `RowTone` as a `String`-backed `enum`; builders become `init(problem:)` and `init(activity:)`. Map tones to `Color` assets rather than CSS variables, and bold via `.fontWeight(.bold)` when tone is `.bad`. Use `RelativeDateTimeFormatter` only if you accept its different wording; to match `timeAgo` port the four thresholds by hand. Parse ISO dates with `ISO8601DateFormatter` (enable fractional seconds) and treat a nil parse as the fail-closed path. Clipboard: `UIPasteboard.general.string` or `NSPasteboard`.
- **Compose**: A Kotlin `data class Row` and `enum class RowTone`; builders as extension functions `Problem.toRow()`. Tone colors map to `MaterialTheme` or app color tokens. `Instant.parse` throws on bad input, unlike `Date.parse`'s `NaN`, so catch `DateTimeParseException` and return `true` to keep dto-fail-closed. Clipboard via `ClipboardManager.setText(AnnotatedString(...))`.
- **React/Web**: The source is `packages/web/packages/status-web/src/lib/row-model.ts`, tested by `row-model.test.ts` (Vitest). `rowToStatusRowProps` feeds `components/StatusRow.tsx`; `ActivityPanel.tsx` uses `rowSearchText` and `rowsToText` (through `CopyButton`); `DeployList.tsx` and `deploy-view.ts` call `deployDtoUnconfirmed`. Tone colors are CSS custom properties (`--color-apt-*`) resolved by the theme.
- **AppKit / UIKit**: Same Swift model as SwiftUI; tone colors become `NSColor`/`UIColor` named assets, and the adapter output drives an `NSTableCellView` or `UICollectionViewListCell` content configuration. Clipboard via `NSPasteboard.general.setString(_:forType: .string)` or `UIPasteboard.general.string`.
- **WinUI 3**: Put `Row` in a shared .NET class library as a `sealed record Row` with a `RowTone` enum, and `ProblemToRow`/`ActivityToRow` as static factory methods over DTOs deserialized with `System.Text.Json` (use `JsonStringEnumConverter` with camel-case naming for `tone`). The `StatusRowProps` adapter becomes a view-model type implementing `INotifyPropertyChanged` (or CommunityToolkit.Mvvm `ObservableObject`), exposing `StatusBrush` as a `SolidColorBrush` looked up from `Application.Current.Resources` theme resources (for example `SystemFillColorSuccessBrush`, `SystemFillColorCriticalBrush`, `SystemFillColorCautionBrush`, `TextFillColorSecondaryBrush`) and `StatusWeight` as `FontWeights.Bold` or `FontWeights.Normal`; bind a `ListView` to an `ObservableCollection<RowViewModel>`. Parse timestamps with `DateTimeOffset.TryParse(..., CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var t)` and return `true` on failure to keep dto-fail-closed. `rowsToText` maps to `string.Join("\n", rows.Select(RowToText))`; write it with `DataPackage.SetText` and `Clipboard.SetContent`. Pass `nowMs` as a `DateTimeOffset` or inject `TimeProvider` so the functions stay testable. Keep `STATE_LABEL` in a `.resw` file if localizing, which the source does not do.

## Design Decisions

**Decision**: One `Row` shape and one adapter serve every pane.
**Rationale**: The header comment: every pane gets "identical row capabilities (clickable commits, consistent links) and a new field is added in one place".
**Approved**: pending

**Decision**: The builders make no judgments; the server's state, verb and tone are rendered verbatim.
**Rationale**: "The server has already decided what is a problem, what happened, and when — these builders only spell the row." A removed client-side `displayStatus` step that demoted aged rows to "last seen building" was unreachable and could only disagree with the server's own expiry (`rowToStatusRowProps` doc comment and the C3 regression tests).
**Approved**: pending

**Decision**: The only client freshness clock judges raw `DeploymentDTO`s, scaled to five times the probe interval with a 10-minute floor, and fails closed.
**Rationale**: The panels that render DTOs directly are "the last place the client still holds a phase the server has not already ruled on"; scaling mirrors `snapshotStaleMs` so a slower poller does not false-demote, and an unreadable date must not assert live progress.
**Approved**: pending

**Decision**: A commit sha is shown only when it links to GitHub.
**Rationale**: "a bare, non-clickable hash is noise"; the subject still shows on its own.
**Approved**: pending

**Decision**: Activity rows take their platform from `ActivityRow.source`, falling back to `kind`.
**Rationale**: The server stamps the raw provider spelling (`cloudflare-pages`, not the canonical `cloudflare` in the target), so no parsing is needed, and the fallback keeps the clipboard and source columns non-empty.
**Approved**: pending

**Decision**: Clipboard text is one tab-separated line per row with a fixed seven columns and friendly labels.
**Rationale**: Copied panes paste as aligned spreadsheet columns and "copied text matches the screen"; the unescaped-field gap is the open question on text-field-escaping.
**Approved**: pending

**Decision**: `problemToRow` sets `downSince` to `since` for every problem.
**Rationale**: The source does this unconditionally; `row-detail.ts` reads `downSince ?? at`, and both hold the same value on problem rows, so the display is unaffected even though the field's doc comment describes it as endpoint-specific.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | best-practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | best-practices |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | reliability |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | internationalization |

The module separates row shaping from rendering (`StatusRow`) and from the server's judgments, so separation-of-concerns passes. Unit-test-coverage is partial: `row-model.test.ts` covers both builders, the adapter, search text, `commitUrlOf` and the demotion clock, but has no test for `rowToText` or `rowsToText`. Explicit-error-handling passes: nothing is caught or swallowed, and the one failure path (an unparseable deploy clock) is an explicit fail-closed branch. Graceful-degradation passes because the demotion clock degrades an unconfirmed in-flight deploy to "unknown" even when server healers are down. Data-integrity is partial because clipboard serialization promises aligned columns but does not escape tabs or newlines inside fields. No-hardcoded-strings fails because `STATE_LABEL` holds English status words inline.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | | | Initial creation from `packages/web/packages/status-web/src/lib/row-model.ts` |
