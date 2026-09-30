<!-- leaf: implement-status-server-monitor-fetch/crunchy--part-2 · source: status-server-monitor-fetch-crunchy.md -->

# Status Server Monitor Fetch Crunchy — continued (part 2)

## Design Decisions

- **Decision**: an unrecognized or absent cluster `state` is treated as healthy (`deployPhase: "deployed"`), never as unknown or failed.
  **Rationale**: stated directly in `crunchyPhases`'s doc comment in `deploy-status.ts` — "routine maintenance must not page, and an unrecognised state is not assumed bad."
  **Approved**: pending
- **Decision**: a missing or empty-string `CRUNCHY_API_TOKEN` resolves a successful, empty result rather than an error.
  **Rationale**: stated directly in the file's own header comment — "missing token then dormant" — mirroring `fetchCloudflareDeployments`'s identical gate, so a team that has not adopted the Crunchy Bridge integration reads as healthy-silent rather than raising a platform-health incident for a provider it never configured.
  **Approved**: pending
- **Decision**: every failure path (a non-`ok` HTTP response, a 429, or a thrown/aborted request) collapses to the identical `{ ok: false, deploys: [] }` return shape.
  **Rationale**: stated directly in the file's own header comment — "any failure then ok:false so the platform-health path opens a 'can't reach Crunchy' blind-spot issue" — the caller only needs to know the poll produced nothing trustworthy, not why; the distinction between failure kinds lives only in the `console.error` line.
  **Approved**: pending
- **Decision**: `fetchCrunchyClusters` makes exactly one bounded attempt per call and never retries.
  **Rationale**: not explained with its own reasoning in this file's comment beyond "poll-only, mirroring fetch-cloudflare" — the shared assumption across this monitor's provider pollers is that a failed poll is simply picked up by the next scheduled monitor cycle (external to this file), so an in-call retry is redundant with that outer cadence.
  **Approved**: pending
- **Decision**: the request timeout is a fixed 6,000ms, not exposed as a caller-configurable option (unlike the sibling Cloudflare fetcher's `overallBudgetMs`).
  **Rationale**: not stated with a numeric justification in this file's own comment; the value matches the Cloudflare fetcher's own per-script timeout, but this file gives no explicit reasoning for choosing that figure rather than another.
  **Approved**: pending
