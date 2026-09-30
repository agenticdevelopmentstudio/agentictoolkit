<!-- leaf: implement-status-web-hooks/use-build-progress--test-vectors · source: status-web-hooks-use-build-progress.md -->

# useBuildProgress

## Conformance Test Vectors

Rows below are built as in `use-build-progress.test.ts`: `id: deploy:vc_<name>:build`, `kind: "deploy"`, `step: "build"`, with the tone stated. Values are read after effects flush.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| build-progress-001 | in-flight-predicate, visible-definition, total-definition, pct-definition | `[build("app", "progress")]` | `visible: true`, `total: 1`, `completed: 0`, `pct: 0` |
| build-progress-002 | completed-definition, complete-definition | `[build("app","progress")]`, then rerender with `[build("app","good")]` | `total: 1`, `completed: 1`, `pct: 100`, `complete: true` |
| build-progress-003 | completed-definition, server-owns-demotion | `[build("app","progress")]`, then rerender with `[build("app","stale")]` | `completed: 1`, `complete: true` |
| build-progress-004 | no-client-clock | `[build("wedged","progress")]` with `at` one hour before now | `visible: true`, `total: 1`, `completed: 0`, `pct: 0`, `complete: false` |
| build-progress-005 | pct-definition, hold-visible, complete-hold, reset-effect | Fake timers. `[one:progress, two:progress]` → `[one:good, two:progress]` → `[one:good, two:good]` → advance 2100 ms | `total: 2`; then `pct: 50`, `visible: true`; then `pct: 100`, `visible: true`; then `visible: false` |
| build-progress-006 | deploy-step-excluded, non-deploy-kind-excluded | `[{step:"deploy", tone:"progress", id:"deploy:vc_app:deploy"}, {kind:"probe", step:null, tone:"progress", id:"issue:ep-app:opened:<T0>:41"}]` | `visible: false`, `total: 0` |
| build-progress-007 | cohort-accumulation, completed-definition | `[build("app","progress")]`, then rerender with `[]` | `total: 1`, `completed: 1`, `complete: true` |
| build-progress-008 | hold-cancel | Fake timers. `[a:progress]` → `[a:good]` → advance 1000 ms → `[a:good, b:progress]` → advance 2000 ms | After the last step: `total: 2`, `completed: 1`, `pct: 50`, `visible: true` (the cohort was not reset) |
| build-progress-009 | pct-definition | Cohort of 3 with 1 settled | `pct: 33`; with 2 settled, `pct: 67` |
| build-progress-010 | identity-by-id | Two rows with the same `id`, both `"progress"` | `total: 1` |
| build-progress-011 | cohort-no-op-when-idle, reset-effect | `[]` on first render | `visible: false`, `total: 0`, `completed: 0`, `pct: 0`, `complete: false` |
| build-progress-012 | unmount-cleanup | Fake timers. Reach `complete: true`, unmount, advance 2000 ms | No state update is attempted after unmount (no pending timer remains) |

Vectors 001–006 are the assertions of `use-build-progress.test.ts`; 007–012 are traced to `useBuildProgress`'s accumulation and hold effects.
