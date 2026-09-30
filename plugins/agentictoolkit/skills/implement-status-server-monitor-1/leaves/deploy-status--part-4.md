<!-- leaf: implement-status-server-monitor-1/deploy-status--part-4 · source: status-server-monitor-deploy-status.md -->

# Status Server Monitor Deploy Status — continued (part 4)

**Rules** (cite as `implement-status-server-monitor-1/deploy-status--part-4#<slug>`):

- `decision` SHOULD — derive IN_FLIGHT_BUILD_ORDER's backwards-guard SQL terms programmatically from the ordering array …
- `decision-2` SHOULD — build-order-extension (SHOULD): when a new in-flight BuildPhase value is added to this module, IN_FLIGHT_BUILD_ORDER …

## Design Decisions

- **Decision**: derive `IN_FLIGHT_BUILD_ORDER`'s backwards-guard SQL terms programmatically from the ordering array (`buildPhaseBackwardsSql`, module-private) rather than hand-listing the disallowed `(incoming, stored)` pairs.
  **Rationale**: stated directly in the source comment on `buildPhaseBackwardsSql` — deriving from the ordering means "inserting a phase can't leave a stale hand-written pair behind." This is why `webhook-keeps-stored-backwards-guard`'s SHOULD companion (`build-order-extension`, below) exists: the safety property depends on every future in-flight `BuildPhase` addition also being added to `IN_FLIGHT_BUILD_ORDER`.
  **Approved**: pending
- **Decision**: make `columnOverwritableSql` and the resulting `webhookKeepsStoredSql` guard evaluate PER-COLUMN rather than as one whole-row predicate.
  **Rationale**: stated directly in the source comment — a whole-row predicate, overwritable the moment EITHER lifecycle is unknown/in-flight, would strip protection from a settled build or deploy verdict it should keep, regressing e.g. a `built`+`unknown` row's real `built` back to `building` on a stale webhook.
  **Approved**: pending
- **Decision**: treat `"unknown"` as a terminal, non-verdict phase distinct from both a real verdict and from `"canceled"`, and check it in `combinedStatus` before the in-flight fallthrough rules.
  **Rationale**: stated directly in the source comments on `BuildPhase` and `combinedStatus` — `"unknown"` is the monitor's own gave-up marker for an in-flight phase nothing could re-confirm before its expiry window, never a claim that the provider stopped the work (unlike `"canceled"`); checking it before the in-flight fallthroughs is what keeps an expired row from silently re-reading as `"building"`.
  **Approved**: pending
- **Decision**: give `railwayPhases`'s `"FAILED"` case a build-failure verdict rather than a deploy-failure verdict, and give its `"CRASHED"` case a full success verdict (`built`+`deployed`) rather than any failure.
  **Rationale**: both stated directly in the switch's own inline comments — Railway's status enum cannot distinguish a build failure from a deploy failure, and build failure is the documented common case; a runtime crash after a successful build and deploy is a health concern for a separate system to surface, not a deploy failure this module should report.
  **Approved**: pending
- **Decision**: give `crunchyPhases` a "quieter" health model where only three documented bad states (plus the `isSuspended` flag) map to `failed`, and every routine/transient/unrecognized state maps to `deployed`.
  **Rationale**: stated directly in the source comment as an owner-chosen tradeoff — routine maintenance operations (resizing, restarting, upgrading, etc.) must not page on-call, and an unrecognized or future state is deliberately not assumed bad rather than defaulted to a failure.
  **Approved**: pending
- **Decision**: `build-order-extension` (SHOULD): when a new in-flight `BuildPhase` value is added to this module, `IN_FLIGHT_BUILD_ORDER` SHOULD be updated to include it in its correct relative position.
  **Rationale**: `buildPhaseBackwardsSql` derives every backwards-guard pair from `IN_FLIGHT_BUILD_ORDER`'s contents (webhook-keeps-stored-backwards-guard); an addition to `IN_FLIGHT_BUILD_PHASES` that is never added to `IN_FLIGHT_BUILD_ORDER` would silently leave that phase's backwards moves unguarded against a stale, redelivered webhook, with no compile-time or test signal pointing at the omission.
  **Approved**: pending
