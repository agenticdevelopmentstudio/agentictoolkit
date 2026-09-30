<!-- leaf: implement-status-server-monitor-1/live-types--part-2 · source: status-server-monitor-live-types.md -->

# Status Server Monitor Live Types — continued (part 2)

## Design Decisions

**Decision**: `StaleProdDTO` carries no field distinguishing a stale project from a non-stale one; the type's own comment states it represents a project "(already filtered to stale)."
**Rationale**: the filtering happens in the producer (`staleProdFromBoard` in `routes/reads.ts`, outside this file's given source), not in the type. This recipe states the filtering as a producer obligation (**stale-prod-dto-shape**) rather than inventing a status field the type does not declare, per source fidelity: the type's shape is the contract, and the filtering guarantee is a documented precondition on any value of this type, not something the shape itself enforces.
**Approved**: pending

**Decision**: `configReason`'s relationship to `configDegraded` is left undocumented in the source — no comment constrains whether a `true` `configDegraded` requires a non-null `configReason`, or whether `configReason` may carry detail while `configDegraded` is `false`.
**Rationale**: rather than inventing a pairing rule the source does not state, this recipe declares `configReason` as an independently nullable field (**config-reason-nullable-and-unconstrained-when-degraded**). The one producer among this package's sibling sources (`buildLiveSnapshot` in `routes/reads.ts`) currently always emits `configDegraded: false, configReason: null` together — "a successful DB read is never the static-fallback degraded path," per that function's own comment — so the degraded branch this type anticipates is not currently exercised by any given source, and no test vector for it exists.
**Approved**: pending

**Decision**: `LiveServiceDTO` is modeled as `ServiceStatusDTO` extended with `dnsOk` and `downSince`, rather than as a flat, independently-declared interface.
**Rationale**: this mirrors the source exactly (`export interface LiveServiceDTO extends ServiceStatusDTO`), and keeps the two added fields' documentation (both carry substantial doc comments explaining why each exists) visible as the distinguishing surface of the "live" variant over the base status row, rather than diluting them across a duplicated field list.
**Approved**: pending
