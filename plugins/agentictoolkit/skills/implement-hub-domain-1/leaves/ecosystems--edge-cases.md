<!-- leaf: implement-hub-domain-1/ecosystems--edge-cases · source: hub-domain-ecosystems.md -->

# Hub Domain: Ecosystems

**Rules** (cite as `implement-hub-domain-1/ecosystems--edge-cases#<slug>`):

- `null-empty-input` MUST — A slug of "" after lowercasing — Slug.pattern requires at least one leading/trailing alphanumeric, so both …
- `boundary-malformed-values` MUST — A slug at exactly 64 characters — MUST be accepted; at 65 — MUST be rejected with the fixed message …
- `manageability-authorization` MUST — An ecosystem whose canManage is explicitly false — the Apple rail MUST refuse to resolve ANY topic under it, including …
- `feature-removal-already-done` MUST — a remove whose DELETE 404s (a double-click, a stale list, a second tab racing the same removal) MUST resolve as …
- `feature-batch-partial-failure` MUST — a useApplyFeatureChange whose adds succeed but some removals fail with a non-404 error MUST keep the adds, still …
- `empty-feature-change` MUST — useApplyFeatureChange with add: [] MUST send no POST; with remove: [] it MUST send no DELETE and resolve (an allSettled …
- `feature-hooks-with-no-ecosystem-id` MUST — useProvisionedFeatures MUST NOT fetch while the id is null/undefined/""; the mutation hooks do not guard it (see the …

## Edge Cases

- **Null/empty input**: A slug of `""` after lowercasing — `Slug.pattern`
  requires at least one leading/trailing alphanumeric, so both
  `FormValidator`'s pattern check and `Slug.isValid` reject it before any
  network call. `workspaceDefaultEcosystemId` with an empty result array
  MUST resolve to `null`, never `undefined` or a thrown error
  (hub-domain-ecosystems-031); `ecosystemIdForSlug` then falls back to the
  raw scan, and MUST resolve to `null` only when that scan is also empty
  (hub-domain-ecosystems-051).
- **Boundary/malformed values**: A slug at exactly 64 characters — MUST be
  accepted; at 65 — MUST be rejected with the fixed message
  (hub-domain-ecosystems-015). A non-rdid `identifier` passed to
  `ecosystemsApi.create`/`update` (no `.` at all) — the client MUST pass
  its whole value through as `slug` unmodified via `addressLeaf`'s
  `lastIndexOf` fallback, deliberately letting the SERVER reject the
  malformed address rather than fabricating a different-looking error
  client-side (`"passes a non-rdid identifier through untouched"`,
  `ecosystems.ts`).
- **Concurrent access**: Two closely-timed `EcosystemCreateForm` saves for
  the same slug — the client-side `identifierExists` probe (Apple) is a
  courtesy check only; a probe that returns `false` right before a
  competing create lands is a real race the backend's own unique
  constraint resolves via a `409`, which both the Apple form and the web
  `create()` map to a friendly "already exists" message
  (create-form-conflict-mapping, create-conflict-mapping) — the probe
  narrows the window, it does not close it.
- **Error states**: Every `EcosystemsDataSource`/`ecosystemsApi` call that
  can fail surfaces a typed error to its caller — `HubError` on Apple
  (never a raw `Error` reaching a topic or the module), an `Error` with a
  numeric `.status` (`AuthHttpError`-shaped) on web. `HubError.notFound`
  is the one case multiple call sites treat as a structural, non-error
  outcome (`.empty` on Apple; `null` from `ecosystemsApi.get`) rather than
  a failure to surface.
- **Manageability / authorization**: An ecosystem whose `canManage` is
  explicitly `false` — the Apple rail MUST refuse to resolve ANY topic
  under it, including `child-ecosystems` and `settings`, returning only
  the not-manageable notice (child-manageability-gate-first). The web
  side carries the equivalent `canManage` through `toEcosystem` and
  `workspaceDefaultEcosystemId`, but enforcing it against a pane is each
  host's own responsibility — this component only reports the flag.
- **Identifier drift (handle vs. derived address)**: A row whose stored
  `id`/`identifier` (handle) and `slug` column have diverged — because
  something renamed the handle without moving the slug (the deprecated
  `identifiers.rename`/`registry.identifiers` PATCH path, or an old
  ancestor-cascade bug) — derives to a DIFFERENT address than its own
  handle claims. `ecosystemsApi.update` heals this specific case: sending
  the handle's own current value as the new `identifier` is a genuine
  slug change (`chosen` → `adh`, matching the stale handle) that a naive
  diff-against-`id` would have silently skipped
  (update-slug-sent-on-presence, hub-domain-ecosystems-026).
- **Feature removal already done**: a `remove` whose DELETE 404s (a
  double-click, a stale list, a second tab racing the same removal) MUST
  resolve as success, and inside `useApplyFeatureChange` it MUST count as
  a successful removal (hub-domain-ecosystems-037, -041).
- **Feature batch partial failure**: a `useApplyFeatureChange` whose adds
  succeed but some removals fail with a non-404 error MUST keep the adds,
  still attempt every other removal, reject naming only the failed keys,
  and invalidate the provisioned list (hub-domain-ecosystems-040). A
  failed add POST MUST reject before any removal is sent
  (hub-domain-ecosystems-047); whether the backend's batch transaction
  rolls back whole is the backend's contract, which this client relies on
  and does not verify.
- **Empty feature change**: `useApplyFeatureChange` with `add: []` MUST send
  no POST; with `remove: []` it MUST send no DELETE and resolve (an
  `allSettled` over zero promises). With both empty it sends nothing and
  still invalidates the provisioned list. `useProvisionFeatures` has no
  such guard: `mutate([])` MUST send a POST with `{"keys": []}`.
- **Already-active or stale feature keys**: provisioning a key that is
  already `active` is a backend no-op, not a conflict — the client sends it
  unchanged and surfaces whatever the backend answers; a `provisioning`-state
  row is the picker's concern to show as already taken.
- **Coming-soon feature submitted**: `provision` sends a `comingSoon` key
  unchanged if a caller supplies one; the backend refuses it and the
  rejection surfaces unchanged to the caller — this client performs no
  client-side refusal.
- **Feature hooks with no ecosystem id**: `useProvisionedFeatures` MUST NOT
  fetch while the id is `null`/`undefined`/`""`; the mutation hooks do not
  guard it (see the open question on features-mutation-null-id).
- **Concurrent feature changes**: the removals inside one
  `useApplyFeatureChange` run in parallel; they touch distinct keys, so
  their completion order does not affect the result, and the list is
  re-read once on settle. Two sessions changing the same ecosystem are
  reconciled only by the post-mutation invalidation re-reading the
  server's list.
