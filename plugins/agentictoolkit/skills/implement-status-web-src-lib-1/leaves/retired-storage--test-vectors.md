<!-- leaf: implement-status-web-src-lib-1/retired-storage--test-vectors · source: status-web-src-lib-retired-storage.md -->

# Retired Storage

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| retired-storage-001 | purge-removes-key, retired-key-list | Storage holds `adh-activity-v1` = `[{"id":"phantom"}]` as JSON; call `purgeRetiredStorage()` | `localStorage.getItem("adh-activity-v1")` returns `null` (test: "removes the retired activity blob") |
| retired-storage-002 | named-allow-list | Storage holds `adh-font-scale` = `"1.2"`, `adh-env-filter` = `["production"]` as JSON, `adh-healthy-ttl` = `"3600000"`; call `purgeRetiredStorage()` | All three keys keep their original values (test: "leaves keys the app still uses alone") |
| retired-storage-003 | purge-idempotent | Empty storage; call `purgeRetiredStorage()` | Does not throw; storage size stays 0 (test: "is a no-op when the key was never written") |
| retired-storage-004 | purge-never-throws, purge-failure-silent | `localStorage.removeItem` throws `DOMException("The operation is insecure.", "SecurityError")`; call `purgeRetiredStorage()` | Does not throw; `removeItem` was called with `"adh-activity-v1"` (test: "swallows a throwing localStorage") |
| retired-storage-005 | purge-ssr-noop | `window` is `undefined`; call `purgeRetiredStorage()` | Does not throw and touches no storage (test: "does nothing when there is no window (SSR)") |
| retired-storage-006 | purge-idempotent | Storage holds `adh-activity-v1`; call `purgeRetiredStorage()` twice | After both calls `getItem("adh-activity-v1")` is `null`, and the second call does not throw |
| retired-storage-007 | purge-never-throws | Reading the `window.localStorage` property throws `SecurityError`; call `purgeRetiredStorage()` | Does not throw, because the property read happens inside the per-key `try` |
| retired-storage-008 | purge-signature, purge-synchronous | Call `purgeRetiredStorage()` | Returns `undefined`, not a promise |
