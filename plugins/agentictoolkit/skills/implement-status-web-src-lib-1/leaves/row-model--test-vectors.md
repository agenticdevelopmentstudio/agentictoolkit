<!-- leaf: implement-status-web-src-lib-1/row-model--test-vectors · source: status-web-src-lib-row-model.md -->

# Status Row Model

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
