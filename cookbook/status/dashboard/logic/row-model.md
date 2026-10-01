---
id: a0ae2ae1-7d51-4639-8f3b-062dcf750b66
title: Status Row Model
domain: agentictoolkit://cookbook/status/dashboard/logic/row-model
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The one row shape every status-dashboard pane renders: builders from problems
  and activity rows, the status-row adapter, search text, clipboard text, deploy demotion.'
platforms:
- typescript
- web
tags: []
depends-on:
- agentictoolkit://cookbook/status/dashboard/logic/board-types
- agentictoolkit://cookbook/status/dashboard/logic/format
- agentictoolkit://cookbook/status/dashboard/logic/deploy-status
- agentictoolkit://cookbook/status/dashboard/logic/colors
- agentictoolkit://cookbook/status/dashboard/logic/issue-sources
related: []
references: []
approved-by: ''
approved-date: ''
---

# Status Row Model

## Overview

This logic is "The ONE row model" of the status dashboard. Active problems, recently-resolved rows and the activity feed are all built into a single row shape, then rendered by one status row view through the display adapter, "so every pane has identical row capabilities (clickable commits, consistent links) and a new field is added in one place".

This logic provides:

- **Tone** and **the row shape** — the row's data shape.
- **The problem-to-row builder** and **the activity-to-row builder** — spell a server-derived problem or activity row (specified in Board Types) as a row. "The server has already decided what is a problem, what happened, and when — these builders only spell the row."
- **The display adapter** — maps a row, plus the current time, to the status row view's rendering props.
- **The search-text function** — the free text the pane filter boxes match against.
- **The row-text function** and **the rows-text function** — clipboard serialization, one tab-separated line per row (used by the activity panel view's copy button).
- **The commit-URL function** — a GitHub commit URL or null.
- **The state-label table** — the problem state to status-word table.
- **The unconfirmed floor**, **the unconfirmed-window function** and **the deploy-unconfirmed function** — the client's only remaining freshness clock, applied to raw deploy records by the deploy list view and the deploy view logic, never to a row.

Every export is pure and synchronous. This logic performs no I/O, holds no state, and is covered by the implementation's test suite (see Platform Notes).

## Behavioral Requirements

### Row shape

- **row-tone-values**: Tone MUST be exactly one of `"good"`, `"bad"`, `"progress"`, `"neutral"`, `"stale"`.
- **row-required-fields**: A row MUST carry `key` (string), `source` (string), `platform` (string or null), `name` (string), `environment` (string or null), `statusWord` (string), `tone` (as above), `sha`, `commitUrl`, `message`, `detail` (each string or null), `at` (string), `sourceUrl` and `liveUrl` (each string or null).
- **row-optional-fields**: A row MAY carry `commitBody`, `lastCheckedAt`, `downSince`, `branch`, `errorText` (each string or null), and `statusCode` and `responseTimeMs` (each number or null); an absent optional field MUST be treated as not present by consumers ("undefined elsewhere so existing builders stay unchanged").
- **row-at-iso**: A row's `at` MUST be an ISO timestamp; it is "shown as a relative time and used for window filtering". This is a documented caller precondition, not validated here.
- **row-message-subject**: A row's `message` MUST hold only the commit subject line, while its `commitBody` holds the full commit message.

### The problem-to-row builder

- **problem-key**: The problem-to-row builder MUST set `key` to `"problem:"` followed by the problem's `target`.
- **problem-source-platform**: The problem-to-row builder MUST set both `source` and `platform` to the problem's `source`.
- **problem-status-word**: The problem-to-row builder MUST set `statusWord` to the state-label table's entry for the problem's `state` when that lookup is defined, and otherwise to the problem's `state` verbatim.
- **state-label-table**: The state-label table MUST map `down` to `"down"`, `degraded` to `"degraded"`, `failed` to `"deploy failed"`, `stuck` to `"deploy stuck"`, `stale` to `"deployment failed"`, `unreachable` to `"platform unreachable"` and `erroring` to `"app errors"`.
- **problem-tone-minor**: The problem-to-row builder MUST set `tone` to `"progress"` when the problem's `severity` is `"minor"`.
- **problem-tone-other**: The problem-to-row builder MUST set `tone` to `"bad"` when the problem's `severity` is `"major"` or `"critical"`; a problem row MUST NOT be `"good"`.
- **problem-at**: The problem-to-row builder MUST set `at` to the problem's `since`.
- **problem-down-since**: The problem-to-row builder MUST set `downSince` to the problem's `since` for every problem, whatever its source, so `downSince` equals `at` on every problem row.
- **problem-passthrough**: The problem-to-row builder MUST copy `name`, `environment`, `detail`, `sourceUrl`, `liveUrl`, `statusCode`, `branch` and `errorText` from the problem unchanged.
- **problem-no-probe-diagnostics**: The problem-to-row builder MUST leave `responseTimeMs` and `lastCheckedAt` absent.

### The activity-to-row builder

- **activity-key**: The activity-to-row builder MUST set `key` to the activity's `id` unchanged.
- **activity-platform**: The activity-to-row builder MUST set `platform` to the activity's `source`, or `null` when it is null or absent; it MUST NOT derive the platform by parsing the activity's `target`.
- **activity-source-fallback**: The activity-to-row builder MUST set `source` to the activity's `source` when non-null, and otherwise to the activity's `kind` (one of `"deploy"`, `"probe"` or `"platform"`).
- **activity-verb-tone**: The activity-to-row builder MUST set `statusWord` to the activity's `verb` and `tone` to the activity's `tone`, both verbatim; there is no phase table.
- **activity-passthrough**: The activity-to-row builder MUST copy `name`, `environment`, `detail`, `at`, `sourceUrl`, `liveUrl`, `branch` and `errorText` from the activity unchanged.
- **activity-no-diagnostics**: The activity-to-row builder MUST leave `statusCode`, `responseTimeMs`, `lastCheckedAt` and `downSince` absent.

### Commit fields (both builders)

- **commit-url**: The commit-URL function MUST return the literal text `"https://github.com/"` followed by the repository, then `"/commit/"`, then the hash, when both the repository and hash are non-empty strings.
- **commit-url-null**: The commit-URL function MUST return `null` when the repository or hash is null or the empty string.
- **commit-url-field**: Both builders MUST set `commitUrl` using the commit-URL function on their input's commit repository and hash.
- **sha-only-when-linked**: Both builders MUST set `sha` to the first 7 characters of the commit hash (via the short-sha function) only when `commitUrl` is non-null, and to `null` otherwise — "a bare, non-clickable hash is noise".
- **commit-message-subject**: Both builders MUST set `message` to the commit's first line (via the commit-first-line function): the text before the first line feed, capped at 200 characters, or `null` for a null or empty message; the message MUST be set even when `sha` is null.
- **commit-body-full**: Both builders MUST set `commitBody` to the input commit message unchanged.

### The display adapter

- **props-tone-color**: The display adapter MUST set `statusColor` from the tone: `good` to `var(--color-apt-green)`, `bad` to `var(--color-apt-red)`, `progress` to `var(--color-apt-gold)`, `neutral` to `var(--color-apt-gold)`, `stale` to `var(--color-apt-text-muted)`.
- **props-bold**: The display adapter MUST set `statusBold` to `true` only when the tone is `"bad"`.
- **props-verbatim-word**: The display adapter MUST set `statusWord` to the row's `statusWord` unchanged; it MUST NOT re-judge or demote a row based on its age.
- **props-time-label**: The display adapter MUST set `timeLabel` to the relative-time rendering of the row's `at` against the current time: `"just now"` under 60 seconds, then whole minutes as `"<n>m"` under 60 minutes, whole hours as `"<n>h"` under 24 hours, else whole days as `"<n>d"`.
- **props-platform**: The display adapter MUST set `platform` to the row's `platform`, converting `null` to absent.
- **props-passthrough**: The display adapter MUST copy `environment`, `name`, `sourceUrl` and `liveUrl` from the row unchanged.
- **props-no-copy**: The display adapter MUST NOT set `copyGetText` or any commit, detail or diagnostic field on its output.

### The search-text function

- **search-text-shape**: The search-text function MUST return `name`, `environment`, `statusWord`, `detail` and `commitBody` joined by single spaces, in that order, with a null or absent field contributing the empty string.
- **search-text-rendered-word**: The search-text function MUST use the same `statusWord` that the display adapter renders, so a filter matches the on-screen word.
- **search-text-excludes**: The search-text function MUST NOT include `source`, `platform`, `sha`, `message`, URLs or `branch`; the subject is searchable only through `commitBody`.

### Clipboard serialization

- **text-columns**: The row-text function MUST return exactly seven columns joined by a single tab character, in order: time label, environment badge, source label, name, status word, commit-or-detail, URL.
- **text-time**: The time column MUST be the relative-time rendering of the row's `at` against the current time.
- **text-env**: The environment column MUST be the environment-badge function's result for `environment` (`production` to `PROD`, `staging` to `STAG`, `testing` to `TEST`, any other value upper-cased) when `environment` is non-empty, and the empty string otherwise.
- **text-source**: The source column MUST be the source-label table's entry for `source` when `source` is a known issue-source identifier (see Issue Sources) (`dns` to `DNS`, `http` to `HTTP`, `glitchtip` to `GlitchTip`, `vercel` to `Vercel`, `cloudflare-pages` to `Cloudflare`, `railway` to `Railway`, `crunchy` to `Crunchy Bridge`), and `source` verbatim otherwise.
- **text-status**: The status column MUST be the row's `statusWord` verbatim.
- **text-commit-precedence**: The commit column MUST be the non-empty values of `sha` and `message` joined by one space when at least one is non-empty, else `detail` when non-empty, else the empty string.
- **text-url**: The URL column MUST be `liveUrl`, else `sourceUrl`, else the empty string; the column MUST be present even when empty.
- **text-field-escaping**: NEEDS REVIEW: Not implemented. The row-text function declares that "every row has the same number of tab-separated fields", but it neither escapes nor strips tab and newline characters inside `name`, `detail`, `statusWord`, `environment` or the URLs; one such character silently adds a column or splits the row. Settling it needs an owner decision on whether fields are sanitized, quoted (tab/comma-separated-value style) or guaranteed tab-free by the server.
- **rows-text**: The rows-text function MUST return each row's row-text joined by a single line feed, in input order, with no trailing line feed; an empty list MUST yield the empty string.

### Deploy demotion clock

- **unconfirmed-floor**: The unconfirmed floor MUST equal 600000 milliseconds (10 minutes).
- **unconfirmed-window**: The unconfirmed-window function MUST return the larger of the unconfirmed floor and five times the probe interval, treating an absent interval as 0.
- **dto-terminal-never-demoted**: The deploy-unconfirmed function MUST return `false` when the deploy's `status` is not in flight; only `"building"` and `"queued"` are in flight.
- **dto-clock-source**: The deploy-unconfirmed function MUST measure from the deploy's `phaseConfirmedAt`, falling back to `createdAt` when `phaseConfirmedAt` is null or absent.
- **dto-fail-closed**: The deploy-unconfirmed function MUST return `true` for an in-flight deploy whose clock string does not parse to a finite time.
- **dto-threshold**: The deploy-unconfirmed function MUST return `true` for an in-flight deploy when the current time minus the confirmed time is strictly greater than the unconfirmed window, and `false` when it is less than or equal.
- **row-never-clocked**: This logic MUST NOT apply a freshness clock to a row; an unconfirmed activity phase arrives already expired by the server (outside this logic) as verb `"unknown"`, tone `"stale"`.

### Module-wide

- **pure-synchronous**: Every exported function MUST be pure and synchronous: it MUST NOT read a clock (time is passed in as `nowMs`), perform I/O or mutate its inputs.
- **single-threaded**: This logic MUST run synchronously to completion; each call completes before another starts, so there is no ordering or locking contract.

## Appearance

Not applicable — this is a data model and adapter module, not a visual component.

## States

Not applicable — this is a data model and adapter module, not a visual component.

## Accessibility

Not applicable — this is a data model and adapter module, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| row-model-001 | problem-source-platform, problem-status-word, problem-tone-other, problem-at, problem-passthrough | the problem-to-row builder applied to a problem with `source: "vercel"`, `state: "failed"`, `severity: "major"`, `sourceUrl: "https://vercel.com/team/adh"`, `liveUrl: "https://app.example.com"`, `since: "2026-06-04T18:00:00.000Z"` | `source` and `platform` `"vercel"`, `statusWord` `"deploy failed"`, `tone` `"bad"`, URLs unchanged, `at` `"2026-06-04T18:00:00.000Z"` (from the implementation's test suite) |
| row-model-002 | commit-url-field, sha-only-when-linked, commit-message-subject | the problem-to-row builder applied to a problem with `commitHash: "abc1234def"`, `commitRepo: "example-org/example-app"`, `commitMessage: "fix the thing\nbody text"` | `sha` `"abc1234"`, `commitUrl` `"https://github.com/example-org/example-app/commit/abc1234def"`, `message` `"fix the thing"` (from the implementation's test suite) |
| row-model-003 | sha-only-when-linked, commit-url-null | the problem-to-row builder applied to a problem with `commitHash: "abc1234def"`, `commitRepo: null`, `commitMessage: "fix the thing\nbody"` | `commitUrl` null, `sha` null, `message` `"fix the thing"` (from the implementation's test suite) |
| row-model-004 | state-label-table, problem-status-word | the problem-to-row builder applied to a problem with `state: "stuck"` | `statusWord` `"deploy stuck"` (from the implementation's test suite) |
| row-model-005 | problem-status-word | the problem-to-row builder applied to a problem with `state: "mystery"` | `statusWord` `"mystery"` |
| row-model-006 | problem-tone-minor | the problem-to-row builder applied to a problem with `severity: "minor"`, `state: "degraded"` | `tone` `"progress"` (from the implementation's test suite) |
| row-model-007 | commit-body-full, row-message-subject | the problem-to-row builder applied to a problem with `commitMessage: "fix the thing\n\nbody line 1\nbody line 2"`, repository `"o/r"`, hash set | `message` `"fix the thing"`, `commitBody` the full message (from the implementation's test suite) |
| row-model-008 | problem-passthrough | the problem-to-row builder applied to a problem with `branch: "prepared"`, `errorText: "next build exited 1"` | row `branch` `"prepared"`, `errorText` `"next build exited 1"` (from the implementation's test suite) |
| row-model-009 | problem-key, problem-down-since, problem-no-probe-diagnostics | the problem-to-row builder applied to a problem with `target: "adh-app-production"`, `since: "2026-06-04T18:00:00.000Z"` | `key` `"problem:adh-app-production"`, `downSince` `"2026-06-04T18:00:00.000Z"`, `responseTimeMs` and `lastCheckedAt` absent |
| row-model-010 | activity-platform, activity-verb-tone | the activity-to-row builder applied to an activity with `kind: "deploy"`, `source: "vercel"`, `verb: "deployed"`, `tone: "good"` | `platform` and `source` `"vercel"`, `statusWord` `"deployed"`, `tone` `"good"` (from the implementation's test suite) |
| row-model-011 | activity-platform | the activity-to-row builder applied to an activity with `kind: "probe"`, `source: "http"`, `target: "adh-app-production"` | `platform` and `source` `"http"` (from the implementation's test suite) |
| row-model-012 | activity-platform | the activity-to-row builder applied to an activity with `kind: "deploy"`, `source: "cloudflare-pages"`, `target: "cloudflare\|proj123\|"` | `platform` and `source` `"cloudflare-pages"`, not the target's `"cloudflare"` (from the implementation's test suite) |
| row-model-013 | activity-source-fallback | the activity-to-row builder applied to an activity with `kind: "deploy"`, `source: null` | `platform` null, `source` `"deploy"` (from the implementation's test suite) |
| row-model-014 | activity-key, activity-no-diagnostics, activity-passthrough | the activity-to-row builder applied to an activity with `id: "a1"`, `branch: "staging"`, `errorText: "next build exited 1"` | `key` `"a1"`, `branch` `"staging"`, `errorText` `"next build exited 1"`, `downSince` and `statusCode` absent (partly from the implementation's test suite) |
| row-model-015 | props-tone-color, props-bold | the display adapter applied to rows with tones `good`, `bad`, `progress` | `var(--color-apt-green)`/not bold, `var(--color-apt-red)`/bold, `var(--color-apt-gold)`/not bold (from the implementation's test suite) |
| row-model-016 | props-tone-color | the display adapter applied to rows with tones `neutral` and `stale` | `var(--color-apt-gold)` and `var(--color-apt-text-muted)`, both not bold |
| row-model-017 | props-verbatim-word, row-never-clocked | the display adapter applied to an activity row with `verb: "building"`, `tone: "progress"`, with the current time one hour after `at` | `statusWord` `"building"`, `statusColor` `var(--color-apt-gold)` (from the implementation's test suite) |
| row-model-018 | props-verbatim-word | the display adapter applied to a problem row with `state: "failed"`, with the current time 30 days after `since` | `statusWord` unchanged, `statusColor` `var(--color-apt-red)` (from the implementation's test suite) |
| row-model-019 | props-time-label, props-platform, props-passthrough | the display adapter applied to a row with `at: "2026-06-04T18:00:00.000Z"`, `platform: null`, `liveUrl: "https://live"`, `sourceUrl: "https://src"`, with the current time `2026-06-04T18:01:00.000Z` | `timeLabel` `"1m"`, `platform` absent, URLs unchanged |
| row-model-020 | search-text-shape | the search-text function applied to the row built from a problem with `name: "adh"`, `environment: "production"`, `state: "failed"`, `commitMessage: "broke login\nbody"` | text contains `"adh"`, `"production"`, `"deploy failed"`, `"broke login"` and `"body"` (from the implementation's test suite) |
| row-model-021 | search-text-rendered-word | the search-text function and the display adapter applied to a row with `statusWord: "unknown"`, `tone: "stale"` | search text contains `"unknown"`; props `statusWord` `"unknown"` (from the implementation's test suite) |
| row-model-022 | search-text-shape, search-text-excludes | the search-text function applied to a row with `name: "a"`, `environment: null`, `statusWord: "s"`, `detail: null`, no `commitBody`, `sha: "abc1234"` | `"a  s  "` (the sha is not included) |
| row-model-023 | commit-url, commit-url-null | the commit-URL function called with repository `"o/r"` and hash `"deadbeef"`; with repository `null` and hash `"deadbeef"`; with repository `"o/r"` and hash `null` | `"https://github.com/o/r/commit/deadbeef"`; null; null (from the implementation's test suite) |
| row-model-024 | text-columns, text-time, text-env, text-source, text-commit-precedence, text-url | the row-text function applied to a row with `at` 18:00:00, current time 18:01:00, `environment: "production"`, `source: "cloudflare-pages"`, `name: "adh"`, `statusWord: "deployed"`, `sha: "abc1234"`, `message: "fix"`, `detail: "x"`, `liveUrl: null`, `sourceUrl: "https://src"` | `"1m"`, `"PROD"`, `"Cloudflare"`, `"adh"`, `"deployed"`, `"abc1234 fix"`, `"https://src"` joined by tabs |
| row-model-025 | text-source, text-commit-precedence, text-url, text-env | the row-text function applied to a row with `source: "deploy"`, `environment: null`, `sha: null`, `message: null`, `detail: "HTTP 503"`, both URLs null | source column `"deploy"`, env column `""`, commit column `"HTTP 503"`, URL column `""`; seven columns (six tabs) |
| row-model-026 | rows-text | the rows-text function called with an empty list; with a two-row list `[r1, r2]` | `""`; the row-text of `r1` plus `"\n"` plus the row-text of `r2` |
| row-model-027 | unconfirmed-floor, unconfirmed-window | the unconfirmed-window function called with an absent interval; with `60000`; with `300000` | 600000; 600000; 1500000 (from the implementation's test suite) |
| row-model-028 | dto-threshold | the deploy-unconfirmed function applied to a deploy with `status: "building"`, `phaseConfirmedAt` T, with the current time T + 599999; then T + 600001 | `false`; `true` (from the implementation's test suite) |
| row-model-029 | dto-terminal-never-demoted | the deploy-unconfirmed function applied to a deploy with `status: "success"`, with the current time 30 days after `phaseConfirmedAt` | `false` (from the implementation's test suite) |
| row-model-030 | dto-clock-source, dto-fail-closed | the deploy-unconfirmed function applied to a deploy with `status: "building"`, no `phaseConfirmedAt`, `createdAt` T, with the current time T + 600001; then with `createdAt: "nope"`, current time T | `true`; `true` (from the implementation's test suite) |
| row-model-031 | unconfirmed-window, dto-threshold | the deploy-unconfirmed function applied to a deploy with `status: "building"`, `probeIntervalMs` 360000, with the current time T + 600001; then T + 1800001 | `false`; `true` (from the implementation's test suite) |
| row-model-032 | dto-threshold | the deploy-unconfirmed function applied to a deploy with `status: "queued"`, with the current time exactly T + 600000 | `false` (strictly greater is required) |
| row-model-033 | text-field-escaping | the row-text function applied to a row with `detail: "a\tb"`, no `sha` or `message` | eight tab-separated fields; the open question on text-field-escaping decides the conformant output |
| row-model-034 | pure-synchronous, single-threaded | call each exported function twice with the same arguments | identical results; inputs unmodified; no deferred (asynchronous) result returned |

## Edge Cases

- **Null commit fields**: A null `commitHash`, `commitRepo` or `commitMessage` MUST yield `sha`, `commitUrl` and `message` of null, and `commitBody` of null (row-model-003).
- **Empty strings**: The commit-URL function called with an empty repository or an empty hash MUST return null. An empty `environment` MUST produce an empty env column in the row-text function's output, and an empty `sha` or `message` MUST be dropped from the commit column.
- **Unknown problem state**: A state absent from the state-label table MUST render verbatim (row-model-005). The server's documented state vocabulary contains only the seven names in state-label-table.
- **Unknown source**: A row's `source` that is not a known issue-source identifier (an activity row's `kind` fallback) MUST appear verbatim in the clipboard source column (row-model-025).
- **Malformed `at`**: A row's `at` is documented as an ISO timestamp. An unparseable value makes the relative-time calculation produce a non-numeric duration and render `"NaNd"`; this MUST be treated as a caller precondition violation, not handled here.
- **Future `at`**: A timestamp later than the current time gives a negative elapsed time and MUST render `"just now"`.
- **Boundary of the demotion window**: Elapsed time exactly equal to the window MUST NOT demote (row-model-032); one millisecond more MUST (row-model-028).
- **Missing probe interval**: An absent `probeIntervalMs` (older backend) MUST use the 10-minute floor; an interval of 120000 ms or less also yields the floor because five times it is at most 600000.
- **Unparseable deploy clock**: An in-flight deploy whose `phaseConfirmedAt` (or fallback `createdAt`) does not parse MUST demote — fail closed (row-model-030). A terminal deploy with an unparseable clock MUST NOT demote, since the in-flight test runs first.
- **Tabs and newlines in clipboard fields**: Not escaped; see the open question on text-field-escaping (row-model-033).
- **Commit subject over 200 characters**: `message` MUST be the first 200 characters with no ellipsis, while `commitBody` and the search-text function keep the full text.
- **Concurrent access**: Not applicable — every export is pure and synchronous, so calls cannot interleave.
- **Error states**: Not applicable — no function touches a network, file or other dependency, and none throws for well-formed input.
- **Offline or disconnected state**: Not applicable — no network is involved; freshness of the server data is judged elsewhere, by other logic outside this module.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|--------------|
| `nowMs` (used by the display adapter, the row-text function, the rows-text function, and the deploy-unconfirmed function) | number | none (required) | Epoch milliseconds used for relative time labels and the demotion clock; injected so the functions stay pure. |
| `probeIntervalMs` (used by the unconfirmed-window function and the deploy-unconfirmed function) | number or absent | absent, treated as 0 | The backend probe cadence (from the board's `probeIntervalMs`); the window is five times it, floored at 10 minutes. |
| the unconfirmed floor | constant number | `600000` | Floor of the unconfirmed window. |

There are no environment variables, settings keys or injected services.

## Deep Linking

Not applicable: this logic defines no routes; it only copies provider and GitHub URLs (`sourceUrl`, `liveUrl`, `commitUrl`) onto rows.

## Localization

This logic holds hardcoded English strings with no localization layer:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `state-label.down` | `down` | Problem status word |
| `state-label.degraded` | `degraded` | Problem status word |
| `state-label.failed` | `deploy failed` | Problem status word |
| `state-label.stuck` | `deploy stuck` | Problem status word |
| `state-label.stale` | `deployment failed` | Problem status word for a production deploy behind newer unpromoted builds |
| `state-label.unreachable` | `platform unreachable` | Problem status word when a provider API cannot be polled |
| `state-label.erroring` | `app errors` | Problem status word when the app throws while its host answers |

Activity status words arrive already spelled by the server (an activity row's `verb`). Time labels (`just now`, `m`, `h`, `d`), environment badges and source labels come from other logic (see Platform Notes), also English-only.

## Accessibility Options

Not applicable: this logic renders nothing; the tone-to-color mapping it produces is consumed by the status row view, which owns display.

## Feature Flags

Not applicable: this logic reads no flags; every export is always active.

## Analytics

Not applicable: this logic emits no events.

## Privacy

Not applicable: this logic collects and stores nothing; commit messages, branches and provider error text pass through in memory, and only the user's own copy action puts row text on the clipboard.

## Logging

Not applicable: this logic contains no logging calls.

## Platform Notes

- **SwiftUI**: Model `Row` as a `struct Row: Sendable, Hashable, Identifiable` (id = `key`) and `RowTone` as a `String`-backed `enum`; builders become `init(problem:)` and `init(activity:)`. Map tones to `Color` assets rather than CSS variables, and bold via `.fontWeight(.bold)` when tone is `.bad`. Use `RelativeDateTimeFormatter` only if you accept its different wording; to match `timeAgo` port the four thresholds by hand. Parse ISO dates with `ISO8601DateFormatter` (enable fractional seconds) and treat a nil parse as the fail-closed path. Clipboard: `UIPasteboard.general.string` or `NSPasteboard`.
- **Compose**: A Kotlin `data class Row` and `enum class RowTone`; builders as extension functions `Problem.toRow()`. Tone colors map to `MaterialTheme` or app color tokens. `Instant.parse` throws on bad input, unlike `Date.parse`'s `NaN`, so catch `DateTimeParseException` and return `true` to keep dto-fail-closed. Clipboard via `ClipboardManager.setText(AnnotatedString(...))`.
- **React/Web**: The source is `packages/web/packages/status-web/src/lib/row-model.ts`, tested by `row-model.test.ts` (Vitest). `rowToStatusRowProps` feeds `components/StatusRow.tsx`; `ActivityPanel.tsx` uses `rowSearchText` and `rowsToText` (through `CopyButton`); `DeployList.tsx` and `deploy-view.ts` call `deployDtoUnconfirmed`. Tone colors are CSS custom properties (`--color-apt-*`) resolved by the theme. `STATE_LABEL` is a plain JavaScript object; a state spelled like an inherited object member (for example `"constructor"`) would resolve to that inherited value rather than falling back — the server's documented state vocabulary contains no such names, so this is a latent risk rather than an observed bug. The single-threaded guarantee noted under Concurrent access comes from the JavaScript runtime. Time labels, environment badges and source labels are supplied by `time-ago.ts`, `colors.ts` and `issue-sources.ts` respectively. The freshness-elsewhere note under Offline/disconnected refers to `board-staleness.ts` and `snapshot-staleness.ts`.
- **AppKit / UIKit**: Same Swift model as SwiftUI; tone colors become `NSColor`/`UIColor` named assets, and the adapter output drives an `NSTableCellView` or `UICollectionViewListCell` content configuration. Clipboard via `NSPasteboard.general.setString(_:forType: .string)` or `UIPasteboard.general.string`.
- **WinUI 3**: Put `Row` in a shared .NET class library as a `sealed record Row` with a `RowTone` enum, and `ProblemToRow`/`ActivityToRow` as static factory methods over DTOs deserialized with `System.Text.Json` (use `JsonStringEnumConverter` with camel-case naming for `tone`). The `StatusRowProps` adapter becomes a view-model type implementing `INotifyPropertyChanged` (or CommunityToolkit.Mvvm `ObservableObject`), exposing `StatusBrush` as a `SolidColorBrush` looked up from `Application.Current.Resources` theme resources (for example `SystemFillColorSuccessBrush`, `SystemFillColorCriticalBrush`, `SystemFillColorCautionBrush`, `TextFillColorSecondaryBrush`) and `StatusWeight` as `FontWeights.Bold` or `FontWeights.Normal`; bind a `ListView` to an `ObservableCollection<RowViewModel>`. Parse timestamps with `DateTimeOffset.TryParse(..., CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var t)` and return `true` on failure to keep dto-fail-closed. `rowsToText` maps to `string.Join("\n", rows.Select(RowToText))`; write it with `DataPackage.SetText` and `Clipboard.SetContent`. Pass `nowMs` as a `DateTimeOffset` or inject `TimeProvider` so the functions stay testable. Keep `STATE_LABEL` in a `.resw` file if localizing, which the source does not do.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/lib/row-model.ts` |

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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to status/dashboard/logic/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation from `packages/web/packages/status-web/src/lib/row-model.ts` |
