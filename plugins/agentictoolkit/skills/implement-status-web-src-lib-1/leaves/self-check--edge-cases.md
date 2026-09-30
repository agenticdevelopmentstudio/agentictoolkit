<!-- leaf: implement-status-web-src-lib-1/self-check--edge-cases · source: status-web-src-lib-self-check.md -->

# Self-Check View Model

**Rules** (cite as `implement-status-web-src-lib-1/self-check--edge-cases#<slug>`):

- `undefined-report` MUST — data is undefined while the fetch is loading. computeSelfCheck MUST return null (vector 001).
- `empty-checks-array` MUST — data.checks is []. Both lists are empty, so the function MUST return null.
- `empty-missingenv-array` MUST — a check with missingEnv: [] MUST be treated as having no missing env and MAY appear in issues if its state is not "ok" …
- `missing-env-on-an-ok-check` MUST — a check with state: "ok" and a non-empty missingEnv MUST still produce a non-null view with that name in missingEnv …
- `duplicate-names-within-one-check` MUST — a check with missingEnv: ["A", "A"] MUST yield ["A"], because deduplication covers the whole flattened list.
- `correlated-check-that-also-lists-missing-env` MUST — it MUST contribute its names to missingEnv, since missing-env selection does not look at correlated.
- `errored-cron-or-correlated-check-alone` MUST — MUST produce null and MUST NOT turn the bar red (vector 010).
- `missingenverror-implies-non-null` MUST — missingEnvError can only be true when missingEnv is non-empty, so a returned view with missingEnvError: true MUST have …

## Edge Cases

- **Undefined report**: `data` is `undefined` while the fetch is loading. `computeSelfCheck` MUST return `null` (vector 001).
- **Empty checks array**: `data.checks` is `[]`. Both lists are empty, so the function MUST return `null`.
- **Empty `missingEnv` array**: a check with `missingEnv: []` MUST be treated as having no missing env and MAY appear in `issues` if its state is not `"ok"` (vector 008).
- **Missing env on an ok check**: a check with `state: "ok"` and a non-empty `missingEnv` MUST still produce a non-null view with that name in `missingEnv` (vector 009).
- **Duplicate names within one check**: a check with `missingEnv: ["A", "A"]` MUST yield `["A"]`, because deduplication covers the whole flattened list.
- **Correlated check that also lists missing env**: it MUST contribute its names to `missingEnv`, since missing-env selection does not look at `correlated`.
- **Errored cron or correlated check alone**: MUST produce `null` and MUST NOT turn the bar red (vector 010).
- **`missingEnvError` implies non-null**: `missingEnvError` can only be `true` when `missingEnv` is non-empty, so a returned view with `missingEnvError: true` MUST have at least one name.
- **Malformed report**: a defined `data` without a `checks` array, or a `missingEnv` that is not an array, violates the typed precondition; the function performs no runtime check and a missing `checks` would throw a `TypeError` to the caller. This is a documented precondition (no-validation), not a handled path.
- **Network failure, timeout, offline**: not applicable to this function; it does no I/O. Fetch failures belong to useIntegrations, which passes `undefined` or the last good report.
- **Concurrent calls**: not applicable; the function is pure and synchronous in single-threaded JavaScript, so concurrent callers (the banner and the dashboard pill) always get the same result for the same report.
