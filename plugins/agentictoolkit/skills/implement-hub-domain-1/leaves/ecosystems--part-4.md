<!-- leaf: implement-hub-domain-1/ecosystems--part-4 · source: hub-domain-ecosystems.md -->

# Hub Domain: Ecosystems — continued (part 4)

**Rules** (cite as `implement-hub-domain-1/ecosystems--part-4#<slug>`):

- `eco-invitations-keys-namespaced-by-rdid` MUST
- `eco-invitations-list-hooks-map-rows` MUST
- `eco-invitations-notes-history-gated-on-subject` MUST
- `eco-invitations-save-notes-invalidates-notes-and-history` MUST
- `eco-invitations-send-invalidates-pending-and-invites` MUST
- `eco-invitations-add-pending-invalidates-pending` MUST
- `eco-invitations-delete-row-dispatch` MUST
- `features-bespoke-route` MUST
- `features-path-segments-encoded` MUST
- `features-catalog-order-preserved` MUST
- `features-catalog-entry-shape` MUST
- `features-subscription-tier-open-string` MUST
- `features-coming-soon-passthrough` MUST
- `features-list-all-states` MUST
- `features-provisioned-shape` MUST
- `features-provision-one-request` MUST
- `features-provision-returns-full-list` MUST
- `features-remove-single-delete` MUST
- `features-remove-404-is-success` MUST
- `features-remove-rethrows-other-errors` MUST
- `features-query-keys` MUST
- `features-catalog-stale-time` MUST
- `features-provisioned-query-gated` MUST
- `features-hooks-context-client` MUST
- `features-provision-writes-cache-then-invalidates` MUST
- `features-remove-hook-invalidates` MUST
- `features-apply-adds-first` MUST
- `features-apply-skips-empty-add` MUST
- `features-apply-removals-all-settled` MUST
- `features-apply-names-failed-keys` MUST
- `features-apply-404-removal-succeeds` MUST
- `features-apply-invalidates-on-settle` MUST
- `features-no-client-dedupe` MUST

### Web — Invitations topic hooks (`ecosystem-invitations.ts`)

- **eco-invitations-keys-namespaced-by-rdid**: every query key in `KEYS`
  MUST include the ecosystem's `rdid` as its second element, so two
  ecosystems' Invitations caches never collide
  (`ecosystem-invitations.ts`).
- **eco-invitations-list-hooks-map-rows**: `useEcoInvitationRequests`,
  `useEcoPendingUsers`, and `useEcoInvites` MUST fetch from
  `ecosystemInvitationEndpoints(rdid)`'s corresponding endpoint and map
  every row through the shared `toRequest`/`toPendingUser`/`toInvite`
  mappers before returning them (`ecosystem-invitations.ts`).
- **eco-invitations-notes-history-gated-on-subject**: `useEcoRowNotes` and
  `useEcoRowHistory` MUST be `enabled: !!subjectId` — neither query MUST
  run for an empty subject id (`ecosystem-invitations.ts`).
- **eco-invitations-save-notes-invalidates-notes-and-history**:
  `useEcoSaveNotes`'s mutation, on success, MUST invalidate both the
  matching notes key and the matching history key for the same
  `(subjectTable, subjectId)` (`ecosystem-invitations.ts`).
- **eco-invitations-send-invalidates-pending-and-invites**:
  `useEcoSendInvitations`'s mutation, on success, MUST invalidate both
  the pending-users key and the invites key for the ecosystem
  (`ecosystem-invitations.ts`).
- **eco-invitations-add-pending-invalidates-pending**:
  `useEcoAddPendingUsers`'s mutation, on success, MUST invalidate the
  pending-users key (`ecosystem-invitations.ts`).
- **eco-invitations-delete-row-dispatch**: `useEcoDeleteRow(rdid, kind)`
  MUST select the DELETE endpoint (`requestItem`, `pendingUserItem`, or
  `invitationItem`) by `kind`, and on success MUST invalidate exactly the
  one list query key matching that same `kind` (`ecosystem-invitations.ts`).

### Web — feature picker data (`ecosystem-features.ts`)

- **features-bespoke-route**: every `ecosystemFeaturesApi` call MUST target
  the hand-written `/api/ecosystem/features` base route (`catalog`,
  `<ecosystemId>`, `<ecosystemId>/<featureKey>`), never the generic
  ecosystems CRUD base, because provisioning a feature has server-side side
  effects (its storage bucket, child ecosystem and roles are created when
  the feature is added and at no other time) (`ecosystem-features.ts`,
  header comment).
- **features-path-segments-encoded**: `list`, `provision` and `remove` MUST
  URL-encode `ecosystemId` (an rdid or uuid) and `featureKey` via `enc`
  (`encodeURIComponent`) before placing them in the path
  (`ecosystem-features.ts`).
- **features-catalog-order-preserved**: `ecosystemFeaturesApi.catalog()`
  MUST GET `/api/ecosystem/features/catalog` and return the response's
  `features` array unchanged, in the backend's own order — the client
  MUST NOT sort or filter it (alphabetising by `label` is the picker's and
  the rail's job) (`ecosystem-features.ts`).
- **features-catalog-entry-shape**: a `CatalogFeature` MUST carry `key`
  (stable, permanent; what a provisioned row is keyed by), `label`,
  `description`, `subscriptionTier`, and the optional flags `featureSite`
  and `comingSoon` (`ecosystem-features.ts`).
- **features-subscription-tier-open-string**: `FeatureSubscriptionTier`
  MUST be typed as a plain `string`, not a closed union, so a tier the
  backend adds later renders instead of failing to parse; the client MUST
  only display it, never branch on it (`ecosystem-features.ts`, doc
  comment on `FeatureSubscriptionTier`).
- **features-coming-soon-passthrough**: a catalog entry with
  `comingSoon: true` MUST be returned by `catalog()` like any other entry —
  this client MUST NOT filter it out; it is listed so the owner can see it
  is coming, the picker shows it under "Coming soon" with its checkbox
  disabled, and the backend refuses to provision it
  (`ecosystem-features.ts`, doc comment on `comingSoon`).
- **features-list-all-states**: `ecosystemFeaturesApi.list(ecosystemId)`
  MUST GET `/api/ecosystem/features/<ecosystemId>` and return every
  `ProvisionedFeature` in every `FeatureState` (`provisioning`, `active`,
  `removed`) unfiltered — callers filter (`ecosystem-features.ts`).
- **features-provisioned-shape**: a `ProvisionedFeature` MUST carry
  `featureKey`, `state: FeatureState`, `provisionedAt`,
  `provisionedBy: string | null`, and `updatedAt`
  (`ecosystem-features.ts`).
- **features-provision-one-request**: `ecosystemFeaturesApi.provision
  (ecosystemId, keys)` MUST send exactly one POST to
  `/api/ecosystem/features/<ecosystemId>` with header
  `Content-Type: application/json` and body `{ "keys": [...] }` carrying
  the whole batch, never one request per key (`ecosystem-features.ts`).
- **features-provision-returns-full-list**: `provision` MUST resolve to the
  response's `features` array — the ecosystem's FULL provisioned list after
  the add, not only the added rows (`ecosystem-features.ts`).
- **features-remove-single-delete**: `ecosystemFeaturesApi.remove
  (ecosystemId, featureKey)` MUST send one DELETE to
  `/api/ecosystem/features/<ecosystemId>/<featureKey>` with no body and
  resolve to `void` (`ecosystem-features.ts`; pinned by "resolves normally
  when the DELETE succeeds outright" in `ecosystem-features.test.tsx`).
- **features-remove-404-is-success**: `remove` MUST resolve (not throw) when
  the DELETE fails with `isNotFound` (404), because the row is already
  gone (`ecosystem-features.ts`; pinned by "treats a 404 as success" in
  `ecosystem-features.test.tsx`).
- **features-remove-rethrows-other-errors**: `remove` MUST rethrow every
  non-404 failure unchanged (`ecosystem-features.ts`; pinned by "still
  throws on a real failure" in `ecosystem-features.test.tsx`).
- **features-query-keys**: the catalog query key MUST be
  `["eco-features", "catalog"]` (no ecosystem id — the catalog is a
  property of the server build, shared by every ecosystem), and the
  provisioned query key MUST be `["eco-features", ecosystemId ?? ""]`
  (`ecosystem-features.ts`).
- **features-catalog-stale-time**: `useFeatureCatalog()` MUST configure
  `staleTime` as 30 minutes (1,800,000 ms) so opening the picker again
  within that window does not refetch the catalog
  (`ecosystem-features.ts`).
- **features-provisioned-query-gated**: `useProvisionedFeatures(ecosystemId)`
  MUST be `enabled: Boolean(ecosystemId)` — no request MUST run while the
  id is `null`, `undefined`, or `""` (`ecosystem-features.ts`).
- **features-hooks-context-client**: the feature hooks MUST use the query
  client from React context (`useQuery` without an explicit client,
  `useQueryClient()` in the mutations) — unlike
  `useWorkspaceDefaultEcosystemId`, which passes the module singleton
  explicitly (`ecosystem-features.ts`).
- **features-provision-writes-cache-then-invalidates**:
  `useProvisionFeatures`'s mutation, on success, MUST first write the
  returned full list into the provisioned query's cache via `setQueryData`
  and then invalidate that same key, so the rail redraws on the same tick
  and still picks up a concurrent session's changes
  (`ecosystem-features.ts`).
- **features-remove-hook-invalidates**: `useRemoveFeature`'s mutation, on
  success, MUST invalidate the provisioned query key and MUST NOT write the
  cache (the DELETE returns no list) (`ecosystem-features.ts`).
- **features-apply-adds-first**: `useApplyFeatureChange`'s mutation MUST
  await the single `provision` POST for `add` before issuing any removal,
  so a failed removal never costs the owner the features just added; a
  failed POST MUST reject the mutation before any DELETE is sent
  (`ecosystem-features.ts`).
- **features-apply-skips-empty-add**: `useApplyFeatureChange` MUST NOT send
  a POST when `add` is empty (`ecosystem-features.ts`).
- **features-apply-removals-all-settled**: `useApplyFeatureChange` MUST
  issue one `remove` per key in `remove` concurrently and wait for all of
  them via `Promise.allSettled`, so one rejected removal MUST NOT prevent
  the others from being attempted (`ecosystem-features.ts`; pinned by
  "runs every removal even when one fails" in
  `ecosystem-features.test.tsx`).
- **features-apply-names-failed-keys**: when one or more removals reject,
  `useApplyFeatureChange` MUST reject with an `Error` whose message is
  `Couldn't remove: ` followed by the failed keys, in `remove` order,
  joined by `, ` (`ecosystem-features.ts`; pinned by the
  `"Couldn't remove: b"` assertion in `ecosystem-features.test.tsx`).
- **features-apply-404-removal-succeeds**: a removal that 404s MUST count
  as success, so a change whose only removal failures are 404s MUST
  resolve (`ecosystem-features.ts`; pinned by "succeeds when every removal
  succeeds (or is a 404, already-gone)").
- **features-apply-invalidates-on-settle**: `useApplyFeatureChange` MUST
  invalidate the provisioned query key in `onSettled` — after success AND
  after failure, since a failure partway still changed part of the list
  (`ecosystem-features.ts`).
- **features-no-client-dedupe**: `useApplyFeatureChange` MUST pass `add`
  and `remove` through as given — it does not deduplicate keys or reject a
  key present in both lists; because adds run first, such a key is
  provisioned and then removed (`ecosystem-features.ts`).
- **features-mutation-null-id**: NEEDS REVIEW: Not implemented in source. `useProvisionFeatures`, `useRemoveFeature` and `useApplyFeatureChange` accept `ecosystemId: string | null | undefined` but cast it `as string` without a guard, so a mutation fired before the id resolves sends a request to a path segment of `null`/`undefined` (encoded as that literal text) instead of failing fast client-side; a guard (or a non-nullable parameter type) in `ecosystem-features.ts` would settle it.

