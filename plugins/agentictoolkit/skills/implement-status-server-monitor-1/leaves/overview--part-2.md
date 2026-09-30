<!-- leaf: implement-status-server-monitor-1/overview--part-2 · source: status-server-monitor-overview.md -->

# Status Server Monitor Overview — continued (part 2)

## Design Decisions

- **Decision**: group `summarizeByPlatform`'s tallies by the raw `d.platform` string rather than by `platformCanon(d.platform)`, even though this same file's endpoint-correlation functions canonicalize the platform before comparing.
  **Rationale**: the source gives no comment explaining this asymmetry; it is stated here as an observed fact of the code (platform-grouping), not a defect this recipe is asserting — a Vercel/Cloudflare/Railway/Crunchy deploy's `d.platform` is written by this fleet's own upsert path using one of the four fixed literals, so in practice the raw and canonicalized groupings agree for every row this code currently sees; the divergence would only surface for a `"cloudflare-pages"`/`"cloudflare"` mix that the rest of this codebase does not currently produce.
  **Approved**: pending
- **Decision**: treat a `"unknown"`-status deploy identically to a `"canceled"` one — total-only in `summarizeByPlatform`, and skipped by `latestTerminalForEndpoint`'s terminal-status check — even though the source's own doc comments on both functions name only `canceled`/`building`/`queued` and never mention `unknown`.
  **Rationale**: this is the actual, traceable behavior of the `if`/`else if` chain (status-bucket-omission) and the `find` predicate (latest-terminal-selection): both are closed lists of literal comparisons, so any `DeployStatus` value not explicitly named — currently only `"unknown"` — falls through to the same "not a counted/terminal outcome" treatment as `"canceled"`. Recorded here because a reader trusting only the doc comments would not expect `"unknown"` to be covered at all.
  **Approved**: pending
- **Decision**: keep exporting `summarizeByPlatform`, `deploysForEndpoint`, `latestTerminalForEndpoint`, `failuresForEndpoint`, `PlatformSummary`, and `EndpointLike` even though, at the time of this recipe's authoring, no other file in the `status-server` package imports any of the six.
  **Rationale**: recorded as an observed fact of the current call graph, not a defect in this file — all six behave exactly as documented here, and the two re-exported helpers (`platformCanon`, `deployTargetKey`) remain in heavy use across `status-server`. `status-web`'s `src/lib/deploy-view.ts` re-implements the same four functions and two interfaces for the browser, with an added staleness-demotion parameter this server-side version does not take, rather than importing this file — the two currently diverge in that one respect, and a future consolidation is an open question for whoever owns both packages, not a gap in either file's own documented behavior.
  **Approved**: pending
