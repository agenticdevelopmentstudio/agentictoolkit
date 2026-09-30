<!-- leaf: implement-status-server-monitor-fetch/railway--test-vectors-part-2 · source: status-server-monitor-fetch-railway.md -->

# Status Server Monitor Fetch Railway — Conformance Test Vectors (part 2)

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| status-server-monitor-fetch-railway-021 | build-log-full-keeps-all | `buildLogFull` and `buildLogTail` both called with the same 100 lines | `buildLogFull`'s result splits into exactly 100 lines; `buildLogTail`'s result on the identical input splits into exactly 40 — `deploy-error-shaping.test.ts` › `buildLogFull` "keeps every line, unlike the 40-line tail" |
| status-server-monitor-fetch-railway-022 | no-build-permanent-sentinel, fetch-build-log-tail-contract | The `buildLogs` query returns `{ errors: [{ message: 'Deployment does not have an associated build' }] }` | `fetchRailwayBuildLogTail(...)` resolves `RAILWAY_NO_BUILD_TEXT` — `deploy-error-shaping.test.ts` › `fetchRailwayBuildLogTail` "a buildless deployment ('no associated build') gets the PERMANENT placeholder, not a retry" |
| status-server-monitor-fetch-railway-023 | no-build-permanent-sentinel, fetch-build-log-tail-contract | The `buildLogs` query returns `{ errors: [{ message: 'Not Authorized' }] }` (a different GraphQL error) | `fetchRailwayBuildLogTail(...)` resolves `null` — a transient error retries next cycle rather than persisting a placeholder — `deploy-error-shaping.test.ts` › `fetchRailwayBuildLogTail` "any other GraphQL error stays null (transient — retry next cycle)" |
| status-server-monitor-fetch-railway-024 | no-build-permanent-sentinel, fetch-build-log-full-contract | The `buildLogs` query returns 60 lines of messages | `fetchRailwayBuildLog(...)` resolves a string splitting into exactly 60 lines — the same input the tail would have capped at 40 — `deploy-error-shaping.test.ts` › `fetchRailwayBuildLog` "returns every line the build emitted" |
