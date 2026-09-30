<!-- leaf: implement-hub-domain-1/ecosystems--test-vectors-part-2 · source: hub-domain-ecosystems.md -->

# Hub Domain: Ecosystems — Conformance Test Vectors (part 2)

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hub-domain-ecosystems-040 | features-apply-removals-all-settled, features-apply-names-failed-keys, features-apply-skips-empty-add | `useApplyFeatureChange("eco-1").mutate({add: [], remove: ["a","b","c"]})`; DELETE for `b` rejects 500, `a` and `c` resolve | Exactly 3 DELETEs issued, no POST; mutation status `error`; error message `"Couldn't remove: b"` (`ecosystem-features.test.tsx`) |
| hub-domain-ecosystems-041 | features-apply-404-removal-succeeds | Same mutation; `b` rejects 404, `a` and `c` resolve | Mutation status `success`; no error (`ecosystem-features.test.tsx`) |
| hub-domain-ecosystems-042 | features-provision-one-request, features-provision-returns-full-list | `provision("org.acme.shop", ["storage","users"])`; server answers `{features: [storage, users, research]}` | One POST to `/api/ecosystem/features/org.acme.shop`, `Content-Type: application/json`, body `{"keys":["storage","users"]}`; resolves the 3-row list (`ecosystem-features.ts`) |
| hub-domain-ecosystems-043 | features-catalog-order-preserved, features-coming-soon-passthrough | `catalog()`; server answers `{features: [zeta, alpha(comingSoon:true)]}` | Resolves `[zeta, alpha]` in that order, `alpha` still present with `comingSoon: true` (`ecosystem-features.ts`) |
| hub-domain-ecosystems-044 | features-list-all-states | `list("eco-1")`; server answers rows in states `active`, `provisioning`, `removed` | All three rows returned unfiltered (`ecosystem-features.ts`) |
| hub-domain-ecosystems-045 | features-provisioned-query-gated, features-query-keys | Render `useProvisionedFeatures(null)` | No request issued; query key `["eco-features", ""]` (`ecosystem-features.ts`) |
| hub-domain-ecosystems-046 | features-provision-writes-cache-then-invalidates | `useProvisionFeatures("eco-1").mutate(["storage"])`; POST returns list `L` | Cache for `["eco-features","eco-1"]` equals `L` immediately on success, then that key is invalidated (`ecosystem-features.ts`) |
| hub-domain-ecosystems-047 | features-apply-adds-first, features-apply-invalidates-on-settle | `useApplyFeatureChange("eco-1").mutate({add:["storage"], remove:["users"]})`; POST rejects 500 | Mutation rejects with the POST's error; no DELETE sent; `["eco-features","eco-1"]` still invalidated (`ecosystem-features.ts`) |
| hub-domain-ecosystems-048 | features-catalog-stale-time, features-query-keys | Render `useFeatureCatalog()` twice within 30 minutes | Query key `["eco-features","catalog"]`; one catalog fetch, second mount served from cache (`staleTime` 1,800,000 ms) (`ecosystem-features.ts`) |
| hub-domain-ecosystems-049 | features-path-segments-encoded | `remove("eco 1", "a/b")` | DELETE URL `/api/ecosystem/features/eco%201/a%2Fb` (`ecosystem-features.ts`) |
| hub-domain-ecosystems-050 | features-remove-hook-invalidates | `useRemoveFeature("eco-1").mutate("storage")`; DELETE resolves | `["eco-features","eco-1"]` invalidated; no `setQueryData` write (`ecosystem-features.ts`) |
| hub-domain-ecosystems-051 | ecosystem-id-for-slug-ownership-first | `ecosystemIdForSlug("fishlamp")` where the workspace lookup resolves `null` (empty array) | Falls back to the raw base-route scan (`ecosystems.ts`) |
