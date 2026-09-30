<!-- leaf: implement-status-web-src-lib-1/config-status--test-vectors · source: status-web-src-lib-config-status.md -->

# Config Status Opt-Out Fold

## Conformance Test Vectors

Vectors 001–005 come from `config-status.test.ts`; its fixture defaults to `kind: "frontend"`, `platform: null`, `deployProject: null`, `ignoreProjectWarning: false`. The rest follow from `autoConfigureOptedOut` and the engine's `endpointConfigStatus` in `classify.ts`.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| config-status-001 | opt-out-paused, status-unwired-opted-out, unconfigured-derived | `endpointUnconfigured` on the fixture with `isActive: false` | `false` |
| config-status-002 | opt-out-strict-false, status-unwired-not-opted-out, is-active-optional | `endpointUnconfigured` on the fixture with `isActive: undefined`, then with `isActive: true` | `true` both times |
| config-status-003 | status-folds-before-classify, status-unwired-opted-out | `endpointConfigStatus` on the fixture with `isActive: false` | `"ignored"` |
| config-status-004 | status-paused-wired-stays-configured, status-wired | `endpointConfigStatus` on the fixture with `platform: "vercel"`, `deployProject: "p"`, `isActive: false` | `"configured"` |
| config-status-005 | unconfigured-uses-wrapper, unconfigured-derived | For each of: fixture with `isActive: false`; with `isActive: true`; wired with `isActive: false` — compare `endpointUnconfigured(c)` with `endpointConfigStatus(c) === "unconfigured"` | Equal for all three |
| config-status-006 | opt-out-ignore-flag | `autoConfigureOptedOut({ ignoreProjectWarning: true, isActive: true })` | `true` |
| config-status-007 | opt-out-default, opt-out-strict-true | `autoConfigureOptedOut({})` and `autoConfigureOptedOut({ ignoreProjectWarning: false, isActive: true })` | `false` both times |
| config-status-008 | status-infra-kind | `endpointConfigStatus({ kind: "health", platform: null, deployProject: null, isActive: true })` | `"configured"` |
| config-status-009 | status-unwired-opted-out, opt-out-ignore-flag | `endpointConfigStatus` on the fixture with `ignoreProjectWarning: true` and no `isActive` | `"ignored"` |
| config-status-010 | status-empty-string-unwired | `endpointConfigStatus({ kind: "frontend", platform: "vercel", deployProject: "", isActive: true })` | `"unconfigured"` |
| config-status-011 | status-no-mutation | Call `endpointConfigStatus` on an object with `ignoreProjectWarning: false`, `isActive: false`; then read the object's `ignoreProjectWarning` | Still `false` |
| config-status-012 | pure-synchronous, no-errors | Call each export twice with the same fixture | Same return value both times, returned synchronously, no exception |
| config-status-013 | endpoint-like-shape | Assign an object with only `kind`, `platform`, `deployProject` to `EndpointLike` | Compiles |
| config-status-014 | opt-out-minimal-input | Call `autoConfigureOptedOut({ isActive: false })` with no other fields | Compiles and returns `true` |
| config-status-015 | server-twin | Run the same `{ ignoreProjectWarning, isActive }` combinations through this function and the server's `autoConfigureOptedOut` | Identical results for every combination |
| config-status-016 | status-delegates-to-engine | For any endpoint, compare this `endpointConfigStatus(e)` with the engine's `endpointConfigStatus({ ...e, ignoreProjectWarning: autoConfigureOptedOut(e) })` | Equal |
| config-status-017 | no-validation | Pass an endpoint with an unknown `kind` such as `"frontend"` or `"xyz"` and no wiring | Treated as deploy-backed, `"unconfigured"`, no error |
