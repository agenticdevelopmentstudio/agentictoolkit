<!-- leaf: implement-status-web-hooks/use-env-filter--test-vectors · source: status-web-hooks-use-env-filter.md -->

# useEnvFilter

## Conformance Test Vectors

| ID | Requirements | Input / Precondition | Action | Expected |
|----|-------------|----------------------|--------|----------|
| env-filter-001 | signature, default-all-selected, all-list | Empty storage | Render the hook; read the first render's result | `envs` equals `{production, staging, testing}`; `all` is `["production","staging","testing"]`; `toggle` is a function |
| env-filter-002 | deferred-hydration, array-hydration, storage-key | `"adh-env-filter"` = `["production"]` | Render; capture first render; flush effects | First render `envs` = all three; after effects `envs` = `{production}` |
| env-filter-003 | absent-value-keeps-default | `"adh-env-filter"` = `""` (empty string) | Render; flush effects | `envs` stays all three; `JSON.parse` is not reached |
| env-filter-004 | invalid-entries-dropped, duplicates-collapse | `"adh-env-filter"` = `["staging", 7, "prod", "staging", null]` | Render; flush effects | `envs` = `{staging}` (size 1) |
| env-filter-005 | filtered-to-empty | `"adh-env-filter"` = `[]` | Render; flush effects | `envs` is an empty `Set` |
| env-filter-006 | filtered-to-empty | `"adh-env-filter"` = `["qa","dev"]` | Render; flush effects | `envs` is an empty `Set` (not the default) |
| env-filter-007 | non-array-keeps-default | `"adh-env-filter"` = `{"production":true}` | Render; flush effects | `envs` stays all three |
| env-filter-008 | read-failure-keeps-default | `"adh-env-filter"` = `{not json` | Render; flush effects | No exception escapes; `envs` stays all three |
| env-filter-009 | read-failure-keeps-default | `localStorage.getItem` throws `SecurityError` | Render; flush effects | No exception escapes; `envs` stays all three |
| env-filter-010 | toggle-flip, toggle-persist, envs-immutability | Default state (all three) | Call `toggle("staging")` | `envs` = `{production, testing}` and is a different `Set` instance; storage holds `["production","testing"]` |
| env-filter-011 | toggle-flip, toggle-order, toggle-persist | State after env-filter-010 | Call `toggle("staging")` | `envs` = `{production, testing, staging}`; storage holds `["production","testing","staging"]` |
| env-filter-012 | toggle-may-empty | `envs` = `{production}` | Call `toggle("production")` | `envs` is empty; storage holds `[]` |
| env-filter-013 | toggle-functional-update | Default state | Call `toggle("production")` and `toggle("testing")` in one batch | `envs` = `{staging}`; storage holds `["staging"]` |
| env-filter-014 | write-failure-ignored | `localStorage.setItem` throws `QuotaExceededError` | Call `toggle("testing")` | No exception escapes; `envs` = `{production, staging}` |
| env-filter-015 | toggle-unvalidated | Default state | Call `toggle("qa")`; then remount and flush effects | Before remount `envs` has 4 members including `qa`, storage holds `["production","staging","testing","qa"]`; after remount `envs` = all three |
| env-filter-016 | toggle-identity, all-list | Any state | Call `toggle` to force a re-render; compare the returned `toggle` and `all` with the previous render's | Both are reference-equal to the previous values |
| env-filter-017 | storage-key | Storage holds `"adh-env-filter"` = `["production"]` | Run `purgeRetiredStorage()` (from `lib/retired-storage`) | The key survives unchanged; this is asserted in `retired-storage.test.ts` ("leaves keys the app still uses alone") |
