<!-- leaf: implement-status-web-src-lib-1/row-model--part-2 · source: status-web-src-lib-row-model.md -->

# Status Row Model — continued (part 2)

**Rules** (cite as `implement-status-web-src-lib-1/row-model--part-2#<slug>`):

- `row-tone-values` MUST
- `row-required-fields` MUST
- `row-optional-fields` MUST
- `row-at-iso` MUST
- `row-message-subject` MUST
- `problem-key` MUST
- `problem-source-platform` MUST
- `problem-status-word` MUST
- `state-label-table` MUST
- `problem-tone-minor` MUST
- `problem-tone-other` MUST
- `problem-at` MUST
- `problem-down-since` MUST
- `problem-passthrough` MUST
- `problem-no-probe-diagnostics` MUST
- `activity-key` MUST
- `activity-platform` MUST
- `activity-source-fallback` MUST
- `activity-verb-tone` MUST
- `activity-passthrough` MUST
- `activity-no-diagnostics` MUST
- `commit-url` MUST
- `commit-url-null` MUST
- `commit-url-field` MUST
- `sha-only-when-linked` MUST
- `commit-message-subject` MUST
- `commit-body-full` MUST
- `props-tone-color` MUST
- `props-bold` MUST
- `props-verbatim-word` MUST
- `props-time-label` MUST
- `props-platform` MUST
- `props-passthrough` MUST
- `props-no-copy` MUST
- `search-text-shape` MUST
- `search-text-rendered-word` MUST
- `search-text-excludes` MUST
- `text-columns` MUST
- `text-time` MUST
- `text-env` MUST
- `text-source` MUST
- `text-status` MUST
- `text-commit-precedence` MUST
- `text-url` MUST
- `rows-text` MUST
- `unconfirmed-floor` MUST
- `unconfirmed-window` MUST
- `dto-terminal-never-demoted` MUST
- `dto-clock-source` MUST
- `dto-fail-closed` MUST
- `dto-threshold` MUST
- `row-never-clocked` MUST
- `pure-synchronous` MUST

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

