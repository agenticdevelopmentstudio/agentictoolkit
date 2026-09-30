<!-- leaf: implement-status-web-src-lib-1/board-staleness--part-2 · source: status-web-src-lib-board-staleness.md -->

# Board Staleness — continued (part 2)

## Design Decisions

**Decision**: Judge read staleness against the client clock, not a server timestamp.
**Rationale**: The board and live feeds usually freeze together in the same backend outage, so a server-to-server comparison goes blind in the common failure. The client clock keeps moving no matter which feed died. Skew beyond `BOARD_STALE_MS` is accepted and left uncorrected.
**Approved**: pending

**Decision**: Judge data staleness server clock against server clock (`generatedAt` minus `dataAsOfMs`).
**Rationale**: A wedged monitor keeps re-stamping `generatedAt` while its facts stay frozen, so `isBoardStale` cannot see it. Comparing two server clocks is immune to client skew and to throttled timers in a sleeping tab.
**Approved**: pending

**Decision**: An unparseable `generatedAt` fails closed, reading as stale or `"frozen"`.
**Rationale**: This mirrors `deployDtoUnconfirmed` in `row-model.ts`. An absence of a judgeable claim must never render as health, and it deliberately differs from `snapshotFreshness`, which treats a missing clock as fresh.
**Approved**: pending

**Decision**: Derive the data window from `snapshotStaleMs` times 2, rather than using a fixed constant.
**Rationale**: Fix Round 2 item C2. A fixed 5-minute window made the whole board permanently unknown at `PROBE_INTERVAL_SECONDS=3600`. On a fleet with no HTTP endpoints it also made the board flap once per cycle, because the window exactly equalled the platform-sample cadence. Two cycles of headroom absorb one missed cycle.
**Approved**: pending

**Decision**: Use three freshness states, keeping `"no-data"` distinct from `"frozen"`.
**Rationale**: Fix Round 2 item C3. A roster with nothing to observe, or a monitor that has not finished its first cycle, is expected and not a fault. Reporting it as frozen sent fresh installs to debug a working monitor.
**Approved**: pending

**Decision**: Set the read threshold at three poll cycles (180 000 ms).
**Rationale**: One missed poll must not false-trip the check, but a permanently failing `/api/board` has to be caught within a wallboard viewer's attention span.
**Approved**: pending
