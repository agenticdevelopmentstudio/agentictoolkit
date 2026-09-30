<!-- leaf: implement-hub-domain-1/data--edge-cases · source: hub-domain-data.md -->

# Hub Domain Data

**Rules** (cite as `implement-hub-domain-1/data--edge-cases#<slug>`):

- `null-empty-input` MUST — tenantIdFromToken(null) and decodeJwtClaims('') MUST return null (hub-domain-data-032, hub-domain-data-037). …
- `boundary-malformed-values` MUST — A JWT with no dot, one dot, or a payload that is not valid base64url/JSON MUST all decode to null via decodeJwtClaims …
- `concurrent-access` MUST — A prefetch (useResourceItemPrefetch) racing a mount's own read of the same item MUST NOT let the prefetch's failure …
- `error-states` MUST — Every hook's query function (useResourceItemQuery, useResourceList) MUST rethrow whatever its load/del callback throws …
- `storage-unavailable` MUST (private browsing, disabled storage — a web-specific edge case with no native-platform analog) — every FTD function (readLastId, writeLastId, clearLastId, readViewMode, writeViewMode) and the workspace-slug cache …

## Edge Cases

- **Null/empty input**: `tenantIdFromToken(null)` and `decodeJwtClaims('')`
  MUST return `null` (hub-domain-data-032, hub-domain-data-037).
  `workspaceQuery(undefined)` MUST return `''` (hub-domain-data-008).
  `readLastId(basePath)` with nothing stored MUST return `null`
  (hub-domain-data-012).
- **Boundary/malformed values**: A JWT with no dot, one dot, or a payload
  that is not valid base64url/JSON MUST all decode to `null` via
  `decodeJwtClaims` (hub-domain-data-032, hub-domain-data-034), relying
  entirely on `decodeBase64UrlJson`'s own contract (see `auth-client`) —
  this component adds no additional payload validation of its own. A stored
  FTD view-mode value that is neither `'cards'` nor `'list'` MUST be
  rejected back to the `'cards'` default rather than passed through
  (hub-domain-data-017).
- **Concurrent access**: A prefetch (`useResourceItemPrefetch`) racing a
  mount's own read of the same item MUST NOT let the prefetch's failure
  cleanup remove data a concurrent success has since written
  (hub-domain-data-055). Two renders of `useResourceList` with the same
  `load` identity MUST NOT cancel/refetch, but a changed `load` identity
  (with `cacheKey`/tenant unchanged) MUST (hub-domain-data-061,
  hub-domain-data-062) — this guard exists specifically because a naive
  effect keyed only on mount would otherwise refetch on every render.
- **Error states**: Every hook's query function (`useResourceItemQuery`,
  `useResourceList`) MUST rethrow whatever its `load`/`del` callback throws
  after optionally reporting it, never swallowing a primary read/write
  failure (resource-item-error-reporting-gated,
  resource-list-error-reporting-gated); the one deliberate exception is
  `makeEntityDeleteHandler`'s post-delete `reload()`, whose failure is
  swallowed because the delete itself already succeeded (see Design
  Decisions).
- **Offline/disconnected state**: Neither `use-resource-item.ts` nor
  `use-resource-list.ts` defines its own retry policy for a network-level
  failure — both explicitly set `retry: false` (resource-item-no-retry,
  resource-list-no-retry), so a caller that wants offline resilience must
  layer it on `load`/`del` itself; this component's own contract is to
  surface the failure promptly, not to mask it behind hidden retries.
- **Storage unavailable** (private browsing, disabled storage — a
  web-specific edge case with no native-platform analog): every FTD
  function (`readLastId`, `writeLastId`, `clearLastId`, `readViewMode`,
  `writeViewMode`) and the workspace-slug cache (`readCachedWorkspace`,
  `writeCachedWorkspace`) MUST swallow a thrown storage exception rather
  than propagate it, degrading to the documented default (`null`/`'cards'`)
  rather than crashing a render.
