<!-- leaf: implement-status-web-src-lib-1/auto-configure--edge-cases · source: status-web-src-lib-auto-configure.md -->

# Auto Configure Match Adapter

**Rules** (cite as `implement-status-web-src-lib-1/auto-configure--edge-cases#<slug>`):

- `empty-batch` MUST — runMatch([], opts) with a valid port MUST still perform the two snapshot reads and MUST resolve to {added: 0, skipped: …
- `missing-client-and-missing-api` MUST — The run MUST reject with the client-required error before any network call.
- `project-with-null-domain` MUST — The engine's planner owns the verdict. runMatch MUST pass the ProjectLite through unchanged and report whatever skip …
- `domain-wired-to-another-live-project` MUST — The run MUST record a skip with the engine's reason that domain is already wired to <existingProject>. This is a …
- `environment-slot-already-taken` MUST — The run MUST record a skip with the reason its site's <environment> endpoint is already wired to <existingProject>.
- `opted-out-or-paused-endpoint` MUST — The endpoint MUST reach the engine with ignoreProjectWarning: true, so the engine's opt-out rules apply to it. Its …
- `per-project-network-failure` MUST — The failing project MUST appear in skipped with the error message as its reason, and the batch MUST continue.
- `snapshot-read-failure-or-server-unreachable` MUST — runMatch MUST reject. The caller renders the failure (PlatformProjects shows Match failed — <message>).
- `non-error-thrown-value` MUST — The skip reason MUST be String(value), per the engine's msg.
- `concurrent-runs` MUST — Two overlapping runMatch calls each MUST plan against their own snapshot. Neither sees the other's writes, and the …
- `hung-request` MUST — No timeout exists in this module. The run MUST stay pending until the client's transport settles, and onProgress stops …
- `detail-block-with-exactly-5-rows` MUST — The block MUST list all 5 rows with no remainder line.
- `detail-block-with-6-rows` MUST — The block MUST list 5 rows followed by …and 1 more.
- `project-names-or-reasons-containing-newlines-or-bullets` MUST — They MUST be inserted verbatim. The detail blocks do no escaping or sanitizing.

## Edge Cases

- **Empty batch**: `runMatch([], opts)` with a valid port MUST still perform the two snapshot reads and MUST resolve to `{added: 0, skipped: [], notes: []}`. `onProgress` is never called because there are no items.
- **Missing client and missing api**: The run MUST reject with the `client-required` error before any network call.
- **Project with null domain**: The engine's planner owns the verdict. `runMatch` MUST pass the `ProjectLite` through unchanged and report whatever skip reason comes back.
- **Domain wired to another live project**: The run MUST record a skip with the engine's reason `that domain is already wired to <existingProject>`. This is a conflict, not an error.
- **Environment slot already taken**: The run MUST record a skip with the reason `its site's <environment> endpoint is already wired to <existingProject>`.
- **Opted-out or paused endpoint**: The endpoint MUST reach the engine with `ignoreProjectWarning: true`, so the engine's opt-out rules apply to it. Its `isActive` value never reaches the engine directly.
- **Per-project network failure**: The failing project MUST appear in `skipped` with the error message as its reason, and the batch MUST continue.
- **Snapshot read failure or server unreachable**: `runMatch` MUST reject. The caller renders the failure (`PlatformProjects` shows `Match failed — <message>`).
- **Non-Error thrown value**: The skip reason MUST be `String(value)`, per the engine's `msg`.
- **Concurrent runs**: Two overlapping `runMatch` calls each MUST plan against their own snapshot. Neither sees the other's writes, and the backend's conflict handling decides the outcome. Guarding against this is the caller's job.
- **Hung request**: No timeout exists in this module. The run MUST stay pending until the client's transport settles, and `onProgress` stops advancing.
- **Detail block with exactly 5 rows**: The block MUST list all 5 rows with no remainder line.
- **Detail block with 6 rows**: The block MUST list 5 rows followed by `…and 1 more`.
- **Project names or reasons containing newlines or bullets**: They MUST be inserted verbatim. The detail blocks do no escaping or sanitizing.
