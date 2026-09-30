<!-- leaf: implement-status-web-src-lib-2/stale-monitors--part-2 · source: status-web-src-lib-stale-monitors.md -->

# Stale Monitors — continued (part 2)

## Design Decisions

**Decision**: Offer only down-for-a-week monitors that the backend has not already deleted, and never delete automatically.
**Rationale**: The backend cycle deletes a monitor no platform inventory claims. What remains is still claimed, so it is ambiguous (abandoned site or unfixed outage), and only the operator can decide; the banner arms a per-row destructive confirm.
**Approved**: pending

**Decision**: Use a 7-day threshold, inclusive.
**Rationale**: The `STALE_MONITOR_MS` doc comment says a genuine outage lasting a week is essentially unheard of, so an endpoint still failing at that age is almost always abandoned. It is purely a view threshold.
**Approved**: pending

**Decision**: DNS resolution selects nothing and is carried through only for the confirm wording.
**Rationale**: The header says a name that stopped resolving is not evidence the deployment was deleted, nor is resolving evidence it exists. The test notes DNS once gated this list in both directions on a 7-day DNS clock; that was removed with the clock, because withholding a row would leave it unremovable.
**Approved**: pending

**Decision**: Skip rows whose age is not finite, rather than treating them as old.
**Rationale**: A malformed or absent `downSince` means the age "can't judge"; skipping ensures a bad timestamp never offers a live monitor for retirement, and the explicit guard avoids the `NaN < x` quirk.
**Approved**: pending

**Decision**: Project to a minimal row with no site or ownership data.
**Rationale**: Retiring is a single `deleteEndpoint(slug)` call, and the backend drops an emptied site atomically, so the view needs only the fields it displays plus the slug.
**Approved**: pending

**Decision**: Keep the function pure over `(services, now)`.
**Rationale**: The header states this makes the rule unit-testable; the caller supplies a day-floored clock so ages and memoisation stay stable between ticks.
**Approved**: pending
