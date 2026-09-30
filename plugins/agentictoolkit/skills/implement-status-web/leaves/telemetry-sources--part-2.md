<!-- leaf: implement-status-web/telemetry-sources--part-2 · source: status-web-telemetry-sources.md -->

# Status Web Telemetry Sources — continued (part 2)

## Design Decisions

**Decision**: Hide the backend behind a single `TelemetrySource` port with two adapters selected in one composition-root line.
**Rationale**: Per the `ports.ts` and `client.ts` comments, the client "reads through a Source without knowing whether the data is live or from the database", so reconnecting Turso changes one line and leaves the hook, cache and panels untouched.
**Approved**: pending

**Decision**: Make `liveSource` the wired default and route it through `/telemetry`, which touches no database.
**Rationale**: The `live.ts` comment states that "a Turso outage cannot affect the dashboard's errors/analytics" on this path.
**Approved**: pending

**Decision**: `tursoSource` stamps `generatedAt` on the client and renames `metrics` to `analytics`.
**Rationale**: `/errors` and `/analytics` return separate bodies with no snapshot timestamp, so the adapter assembles the snapshot itself to meet the shared `TelemetrySnapshot` contract; the comment says it "Preserves the original useErrors/useAnalytics read logic as a single composable source."
**Approved**: pending

**Decision**: Sources throw on any failure and leave retry, caching and fallback to the caller.
**Rationale**: Per the `FetchResult` comment in `ports.ts`, an empty list must never be mistaken for "no data"; rejecting lets `useTelemetry` keep the cached snapshot rather than overwrite it with an empty one.
**Approved**: pending
