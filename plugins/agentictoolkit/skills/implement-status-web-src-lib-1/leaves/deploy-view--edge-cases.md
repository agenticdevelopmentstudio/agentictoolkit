<!-- leaf: implement-status-web-src-lib-1/deploy-view--edge-cases · source: status-web-src-lib-deploy-view.md -->

# Deploy View

**Rules** (cite as `implement-status-web-src-lib-1/deploy-view--edge-cases#<slug>`):

- `empty-deploys` MUST — summarizeByPlatform MUST return [], deploysForEndpoint MUST return [], latestTerminalForEndpoint MUST return null, and …
- `endpoint-with-no-platform-or-no-project` MUST — deployTargetKey returns null, so every endpoint helper MUST report no deploys ([], null, 0). This is the documented …
- `empty-string-project` MUST — deployTargetKey treats "" as missing. The endpoint MUST correlate to nothing, and a deploy with projectName: "" MUST …
- `railway-deploy-or-endpoint-with-a-null-environment` MUST — The key's environment segment is "". A null-environment railway endpoint MUST match only null-environment railway …
- `unknown-platform-name` MUST (for example `"crunchy"` absent from the data, or `"custom-host"` present) — summarizeByPlatform MUST omit known platforms with no deploys, and MUST place unknown platforms after the known ones in …
- `canonical-alias-in-summaries` MUST — summarizeByPlatform does not canonicalize. A "cloudflare" platform string MUST produce its own summary, sorted as …
- `unparseable-phaseconfirmedat-or-createdat-on-an-in-flight-deploy` MUST — deployDtoUnconfirmed MUST fail closed. The deploy MUST count in total only.
- `future-phaseconfirmedat` MUST — The age is negative, so the deploy MUST NOT be demoted and MUST count as building.
- `exactly-at-the-window` MUST — An age exactly equal to max(600000, probeIntervalMs * 5) MUST NOT demote. The comparison is strictly greater than.
- `missing-zero-or-negative-probeintervalms` MUST — The demotion window MUST fall back to the 600 000 ms floor.
- `unparseable-createdat-in-deploysforendpoint` MUST — The comparator yields NaN, which Array.prototype.sort treats as equal. The position of such a deploy MUST be treated as …
- `equal-createdat-values` MUST — Array.prototype.sort is stable, so ties MUST keep their input order.
- `many-failures` MUST — failuresForEndpoint MUST count every failed deploy in the input. It applies no time window and no cap. Bounding the …

## Edge Cases

- **Empty `deploys`**: `summarizeByPlatform` MUST return `[]`, `deploysForEndpoint` MUST return `[]`, `latestTerminalForEndpoint` MUST return `null`, and `failuresForEndpoint` MUST return 0.
- **Endpoint with no platform or no project**: `deployTargetKey` returns `null`, so every endpoint helper MUST report no deploys (`[]`, `null`, 0). This is the documented health-only-check contract, not an error.
- **Empty-string project**: `deployTargetKey` treats `""` as missing. The endpoint MUST correlate to nothing, and a deploy with `projectName: ""` MUST never match any endpoint.
- **Railway deploy or endpoint with a null environment**: The key's environment segment is `""`. A null-environment railway endpoint MUST match only null-environment railway deploys of that project.
- **Unknown platform name** (for example `"crunchy"` absent from the data, or `"custom-host"` present): `summarizeByPlatform` MUST omit known platforms with no deploys, and MUST place unknown platforms after the known ones in first-seen order.
- **Canonical alias in summaries**: `summarizeByPlatform` does not canonicalize. A `"cloudflare"` platform string MUST produce its own summary, sorted as unknown, apart from `"cloudflare-pages"`. The endpoint helpers, by contrast, MUST treat the two as one platform.
- **Unparseable `phaseConfirmedAt` or `createdAt` on an in-flight deploy**: `deployDtoUnconfirmed` MUST fail closed. The deploy MUST count in `total` only.
- **Future `phaseConfirmedAt`**: The age is negative, so the deploy MUST NOT be demoted and MUST count as `building`.
- **Exactly at the window**: An age exactly equal to `max(600000, probeIntervalMs * 5)` MUST NOT demote. The comparison is strictly greater than.
- **Missing, zero or negative `probeIntervalMs`**: The demotion window MUST fall back to the 600 000 ms floor.
- **Unparseable `createdAt` in `deploysForEndpoint`**: The comparator yields `NaN`, which `Array.prototype.sort` treats as equal. The position of such a deploy MUST be treated as unspecified. `createdAt` is a typed server-supplied ISO string, so this is a caller precondition, not validated here.
- **Equal `createdAt` values**: `Array.prototype.sort` is stable, so ties MUST keep their input order.
- **Many failures**: `failuresForEndpoint` MUST count every failed deploy in the input. It applies no time window and no cap. Bounding the history is the caller's job (the server that fills `deploys`).
- **Concurrent access**: Not applicable. The module is stateless and runs on single-threaded JavaScript.
- **Error states and offline**: Not applicable. The module performs no I/O. A missing or failed deploy feed reaches it only as an empty or older `deploys` array. Fetching and error reporting belong to the hooks that load the board.
