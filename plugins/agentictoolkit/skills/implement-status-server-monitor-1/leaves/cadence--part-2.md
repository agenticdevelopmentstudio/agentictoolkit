<!-- leaf: implement-status-server-monitor-1/cadence--part-2 · source: status-server-monitor-cadence.md -->

# Status Server Monitor Cadence — continued (part 2)

## Design Decisions

- **Decision**: compute the first pending anchor eagerly inside `createDeployCadence`, at construction time, rather than lazily on the first call to `shouldFullSync`.
  **Rationale**: the boot-grace window this file exists to guarantee is measured from when the process constructs its `DeployCadence` (i.e. from boot), not from whenever a caller happens to first invoke `shouldFullSync`. Computing the anchor lazily on first call would let a caller construct the cadence early and defer its first call, silently shrinking or growing the grace window relative to actual process boot time.
  **Approved**: pending
- **Decision**: a manual call re-anchors from that call's own clock reading (`now()`) plus `deploySyncIntervalMs`, not from whatever automatic anchor was already pending.
  **Rationale**: not spelled out in a comment on `shouldFullSync` itself, but demonstrated directly by `cadence.test.ts`'s "manual check-now" test — a user-triggered full sync pushes the NEXT automatic one a full interval into the future from the moment of that manual run, mirroring `scheduler.ts`'s own `runNow`/`runNowDetached`, which the source comment there says exist specifically to re-anchor the grid so "the next automatic tick is a full interval from now, rather than firing again moments after this manual run."
  **Approved**: pending
- **Decision**: re-anchor the pending time only when `shouldFullSync` returns `true`; never touch it on a `false` return.
  **Rationale**: not spelled out in a comment, but implied by the only two call sites in `shouldFullSync`'s body — a `false`-returning call has nothing to measure a new interval from, and anchoring on every call regardless of outcome would let a stream of ignored, cheap probe ticks perpetually push the deploy phase's due time forward, so the interval could never elapse under a probe cadence shorter than `deploySyncIntervalMs`.
  **Approved**: pending
- **Decision**: leave `deploySyncIntervalMs` and `firstDelayMs` unvalidated inside this file (see the `interval-and-delay-validation` marker under Behavioral Requirements).
  **Rationale**: this file trusts its caller's numbers rather than re-checking them itself. In the shipped composition, that trust is only partially earned: `config/port.ts`'s `deploySyncIntervalMs()` helper floors its output at 300,000ms via `Math.max`, which protects the one production call path this package ships — but nothing in `cadence.ts` itself enforces that floor for any other caller, which is exactly the gap the marker records.
  **Approved**: pending
- **Decision**: keep this recipe's Behavioral Requirements list shorter than a sibling like `status-server-monitor-alerts`.
  **Rationale**: `cadence.ts` is genuinely smaller in scope — one exported constant, one exported type, and one exported factory around roughly twenty lines of arithmetic and comparison, with no queue, no rendering, no network call, and no multi-thread module-duplication concern. The requirement count here is proportional to that smaller surface, not an authoring shortfall.
  **Approved**: pending
