<!-- leaf: implement-status-web-src-lib-1/self-check--test-vectors · source: status-web-src-lib-self-check.md -->

# Self-Check View Model

## Conformance Test Vectors

Checks below default to `configured: true`, `ok: true`, `state: "ok"`, `detail: ""`, as the test fixture `check(...)` in `self-check.test.ts` does.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| self-check-001 | undefined-input-null | `computeSelfCheck(undefined)` | `null` |
| self-check-002 | nothing-to-show-null | checks `stats` and `vercel`, both `state: "ok"` | `null` |
| self-check-003 | missing-env-flatten, missing-env-dedup, missing-env-order, missing-env-warn-not-error, issues-exclude-missing-env, has-error-otherwise-false | `cloudflare` warn missingEnv `["CLOUDFLARE_ACCOUNT_ID"]`; `vercel` warn missingEnv `["VERCEL_API_TOKEN"]`; `railway` warn missingEnv `["VERCEL_API_TOKEN"]` | `missingEnv` equals `["CLOUDFLARE_ACCOUNT_ID", "VERCEL_API_TOKEN"]`; `missingEnvError` false; `hasError` false; `issues` empty |
| self-check-004 | missing-env-error-flag, has-error-missing-env, issues-exclude-missing-env | `cloudflare` `state: "error"` missingEnv `["CLOUDFLARE_ACCOUNT_ID"]` | `missingEnv` equals `["CLOUDFLARE_ACCOUNT_ID"]`; `missingEnvError` true; `hasError` true; `issues` empty |
| self-check-005 | issues-exclude-cron, has-error-issue, non-null-when-content | `cron` warn "first poll pending"; `railway` `state: "error"` "HTTP 500" | `missingEnv` empty; issue ids `["railway"]`; `hasError` true |
| self-check-006 | issues-exclude-correlated, excluded-errors-do-not-escalate | `cloudflare` warn correlated; `posthog` warn correlated; `connectivity` warn | issue ids `["connectivity"]`; `hasError` false |
| self-check-007 | issues-non-ok, has-error-otherwise-false | `railway` warn "slow" | issue ids `["railway"]`; `hasError` false |
| self-check-008 | missing-env-check-selection | `vercel` warn with `missingEnv: []` | `missingEnv` empty; issue ids `["vercel"]` (an empty list does not make it a missing-env check) |
| self-check-009 | missing-env-regardless-of-state, nothing-to-show-null | `stats` `state: "ok"` missingEnv `["X"]` | non-null view; `missingEnv` equals `["X"]`; `missingEnvError` false; `hasError` false; `issues` empty |
| self-check-010 | excluded-errors-do-not-escalate | `cron` `state: "error"` only | `null` |
| self-check-011 | issues-ignore-ok-flag | `stats` with `ok: false`, `state: "ok"` | `null` |
| self-check-012 | issues-order, issues-are-source-checks | `b` error, `a` warn, in that order | issue ids `["b", "a"]`; each entry is the same object reference passed in |
| self-check-013 | no-input-mutation, pure-synchronous | any report, called twice | both results deep-equal; `data.checks` unchanged in length and content |

Vectors 001 to 007 are the assertions of `self-check.test.ts`; 008 to 013 follow directly from the filter expressions in `computeSelfCheck`.
