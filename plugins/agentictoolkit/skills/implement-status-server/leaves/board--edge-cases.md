<!-- leaf: implement-status-server/board--edge-cases · source: status-server-board.md -->

# Status Server Board

**Rules** (cite as `implement-status-server/board--edge-cases#<slug>`):

- `upstream-deletion-renaming` MUST — a Vercel project deleted upstream (vanishedVercel) while a live sibling project survives; a project renamed upstream, …
- `configuration-off-states` MUST — monitorHttp, monitorDeploys, or isActive turned off on a roster entry (Requirement A: every dependent Problem and …
- `provider-unreachable-frozen-feed-state` MUST — a platform whose poll cannot reach the provider API (frozen error feed, suspended recency test, but never silently "not …

## Edge Cases

- **Null and empty input**: `boardTargetKey` with a `null` platform, `null`/empty `id`, or `null` environment on a non-Railway platform (the environment segment is always empty for those); `entryIdentity` on an entry with neither `providerProjectId` nor a usable `projectName`; an `ErrorFact` with `level: null` or `lastSeenMs: null`.
- **Boundary values**: an endpoint exactly at `DEGRADED_CONFIRM_MS`; a platform exactly at `PLATFORM_UNREACHABLE_POLLS`; a deploy exactly at `STUCK_DEPLOY_MS`; an issue's `lastSeenMs` exactly at `ERROR_RECENT_MS`; an activity event exactly at the 24-hour window edge (kept, per `test/board-activity.test.ts` › "keeps an event exactly at the window edge").
- **Tie-breaking**: two deployments of one project created within the same second (`supersedes`' full tie-break chain); two issue events on one target in one second; a count tie between two GlitchTip issues (`byImpact`'s `issueKey` tie-break); a `pageActivity` tie group whose cursor uses the retired id grammar.
- **Concurrent / repeated invocation**: `reconcileBoardLedger` called from multiple threads or API routes against the same storage; `deriveBoard` called twice with identical facts (purity); a scrolled activity page reusing a cached `base` via `createActivityPageReader` while newer facts land underneath it.
- **Upstream deletion / renaming**: a Vercel project deleted upstream (`vanishedVercel`) while a live sibling project survives; a project renamed upstream, matched by provider id despite the name change; an empty or all-vanished `liveVercelProjects` read, which MUST narrow nothing rather than silence the whole fleet.
- **Malformed or legacy targets**: a ledger row minted before the escaping fix, holding a raw four-segment target that can no longer be parsed and closes as unmonitored; an activity cursor id from the retired five-plus-segment deploy-row grammar.
- **Configuration-off states**: `monitorHttp`, `monitorDeploys`, or `isActive` turned off on a roster entry (Requirement A: every dependent Problem and watch-set membership must disappear); GlitchTip unconfigured (`errorsConfigured: false`, which MUST empty both `errorProblems` and the error portion of `monitoredTargets`).
- **Provider-unreachable / frozen-feed state**: a platform whose poll cannot reach the provider API (frozen error feed, suspended recency test, but never silently "not configured"); a Crunchy cluster, which has no HTTP host at all but MUST still be watched.
