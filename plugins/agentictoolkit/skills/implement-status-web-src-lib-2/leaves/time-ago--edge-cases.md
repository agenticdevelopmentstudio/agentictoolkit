<!-- leaf: implement-status-web-src-lib-2/time-ago--edge-cases · source: status-web-src-lib-time-ago.md -->

# Status Web Time Ago

**Rules** (cite as `implement-status-web-src-lib-2/time-ago--edge-cases#<slug>`):

- `null-and-empty-input` MUST — iso and nowMs are required parameters with no runtime check. An empty iso parses to an invalid date and the function …
- `malformed-input` MUST — an unparseable iso, or a nowMs of NaN (possible in SnapshotStaleBanner if snapshot.generatedAt does not parse), MUST …
- `boundary-values` MUST — 59 s MUST give just now and 60 s MUST give 1m; 59 min MUST give 59m and 60 min MUST give 1h; 23 h MUST give 23h and 24 …
- `future-timestamps` MUST — an iso later than nowMs (clock skew between the server and the browser) MUST give just now for any magnitude, because …
- `large-values` MUST — the days count MUST grow without bound (365d, 3650d).

## Edge Cases

- **Null and empty input**: `iso` and `nowMs` are required parameters with no runtime
  check. An empty `iso` parses to an invalid date and the function MUST return `NaNd`
  (vector 015). Callers that may hold a missing timestamp guard it themselves before
  calling (for example `StatusMatrix` renders an em dash when there is no deploy).
- **Malformed input**: an unparseable `iso`, or a `nowMs` of `NaN` (possible in
  `SnapshotStaleBanner` if `snapshot.generatedAt` does not parse), MUST produce `NaNd` and
  MUST NOT throw, per `iso-precondition`.
- **Boundary values**: 59 s MUST give `just now` and 60 s MUST give `1m`; 59 min MUST give
  `59m` and 60 min MUST give `1h`; 23 h MUST give `23h` and 24 h MUST give `1d`. Sub-second
  remainders are floored away at every step.
- **Future timestamps**: an `iso` later than `nowMs` (clock skew between the server and the
  browser) MUST give `just now` for any magnitude, because the only lower test is
  `diffSecs < 60`.
- **Large values**: the days count MUST grow without bound (`365d`, `3650d`).
- **Concurrent access**: not applicable; the function is pure, synchronous JavaScript with
  no shared mutable state, so calls cannot interleave.
- **Error states**: the function has no dependency that can fail and never throws; its only
  failure signal is the `NaNd` string.
- **Offline / disconnected state**: not applicable; the function performs no network call.
  Callers already hold the timestamp from fetched dashboard data.
- **Cancellation and timeouts**: not applicable; the call is synchronous and O(1).
