<!-- leaf: implement-status-web-src-lib-1/row-detail--test-vectors · source: status-web-src-lib-row-detail.md -->

# Row Detail

## Conformance Test Vectors

Vectors 001 to 013 are derived from the assertions in `row-detail.test.ts`. The rest are traced to the function bodies. The base row is the test's `row()` helper: `platform: "vercel"`, `name: "adh"`, `environment: "production"`, `statusWord: "deployed"`, `tone: "good"`, `at: "2026-06-04T18:00:00.000Z"`, every other field null.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| row-detail-001 | deploy-title-url, title-name-fallback, platform-text, platform-link, commit-fields, commit-body, problem-dedupe | base row with `statusWord: "built"`, `sourceUrl: "https://vercel.com/team/adh/dpl"`, `liveUrl: "https://adh.app"`, `message: "fix login"`, `commitBody: "fix login\n\nlonger body"` | `title` `"adh"`, `titleUrl` and `platformLink` `"https://vercel.com/team/adh/dpl"`, `platformText` `"built on vercel"`, `commitSubject` `"fix login"`, `commitBody` unchanged, `problem` null |
| row-detail-002 | endpoint-title-host, endpoint-title-url, platform-text, problem-link | `platform: "http"`, `statusWord: "down"`, `detail: "HTTP 503"`, `liveUrl` and `sourceUrl` `"https://x.example.com/health"` | `title` `"x.example.com"`, `platformText` null, `problem` `"HTTP 503"`, `problemLink` `"https://x.example.com/health"` |
| row-detail-003 | resolved-classification, platform-text | `statusWord: "[deploy failed] resolved"` | `platformText` null |
| row-detail-004 | problem-dedupe | `detail: "fix login"`, `message: "fix login"` | `problem` null, `commitSubject` `"fix login"` |
| row-detail-005 | status-code, response-time-format, since-precedence, last-checked | endpoint row with `statusCode: 503`, `responseTimeMs: 1200`, `downSince: "2026-06-04T17:00:00.000Z"`, `lastCheckedAt: "2026-06-04T18:05:00.000Z"` | `statusCode` 503, `responseTime` `"1200ms"`, `since` `"2026-06-04T17:00:00.000Z"`, `lastChecked` `"2026-06-04T18:05:00.000Z"` |
| row-detail-006 | branch | `branch: "main"` | `branch` `"main"` |
| row-detail-007 | since-precedence, optional-fields-null | base row, no diagnostics | `since` `"2026-06-04T18:00:00.000Z"`; `statusCode`, `responseTime`, `branch`, `lastChecked`, `errorText` all null |
| row-detail-008 | error-text | `errorText: "[buildStep] next build exited 1"` | `errorText` unchanged |
| row-detail-009 | deploy-outcome-failed, deploy-outcome-success, deploy-outcome-unsettled | `tone` `"bad"`, `"good"`, `"progress"` on the base row | `"failed"`, `"success"`, null |
| row-detail-010 | deploy-outcome-no-platform, non-deploy-platforms | `platform: "http"`, `tone: "bad"`; `statusWord: "[deploy failed] resolved"`, `tone: "good"`; `platform: "crunchy"`, `statusWord: "suspended"`, `tone: "bad"` | `deployOutcome` null in all three |
| row-detail-011 | text-line-format, text-commit-line, text-link-precedence, text-commit-body | deploy row `statusWord: "build failed"`, `branch: "production"`, `sourceUrl: "https://vercel.com/team/olylo/dpl123"`, `sha: "9f952c9"`, `message: "restructure repo"`, `commitBody: "restructure repo\n\nlonger detail"`, passed through `rowToDetailProps` then `rowDetailToText` | text contains `platform: build failed on vercel`, `environment: production`, `branch: production`, `commit: 9f952c9 restructure repo`, `link: https://vercel.com/team/olylo/dpl123` and `longer detail` |
| row-detail-012 | text-populated-only | endpoint row `platform: "http"`, `statusWord: "down"`, no diagnostics, serialized | text contains none of `branch:`, `http status:`, `response:`, `error:` |
| row-detail-013 | text-error-block | `errorText` with two lines, serialized | text contains `\nerror:\n` followed by the first error line, and contains the second line |
| row-detail-014 | non-deploy-platforms, platform-text | `platform: "glitchtip"`, `statusWord: "new"`, `tone: "bad"` | `deployOutcome` null; `platformText` `"new on glitchtip"` |
| row-detail-015 | deploy-outcome-unsettled | base row with `tone: "stale"`, then `tone: "neutral"` | `deployOutcome` null for both |
| row-detail-016 | text-url-distinct, text-field-order | `RowDetail` with `title: "x.example.com"`, `titleUrl: "https://x.example.com/health"`, other fields null | text is exactly `endpoint: x.example.com\nurl: https://x.example.com/health\nlink: https://x.example.com/health` |
| row-detail-017 | no-throw, endpoint-title-host, text-url-distinct | endpoint row with `liveUrl: "not a url"` | `title` `"not a url"` (from `hostOf`'s fallback); serialized text has no `url:` line |
| row-detail-018 | text-populated-only, response-time-format | `statusCode: 0`, `responseTimeMs: 0`, serialized | `responseTime` `"0ms"`; text contains `http status: 0` and `response: 0ms` |
| row-detail-019 | text-commit-line | `RowDetail` with `sha: null`, `commitSubject: "fix"` | text contains `commit: fix` |
| row-detail-020 | text-commit-body | `commitSubject: "fix"`, `commitBody: "fix"` | text contains no empty line; the body is not repeated |
| row-detail-021 | pure-functions | call `rowToDetailProps` twice on one row | results are deep-equal, and the input row is unchanged |
