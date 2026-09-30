<!-- leaf: implement-hub-domain-1/data--part-3 · source: hub-domain-data.md -->

# Hub Domain Data — continued (part 3)

**Rules** (cite as `implement-hub-domain-1/data--part-3#<slug>`):

- `resource-list-no-retry` MUST
- `resource-list-gc-time` MUST
- `resource-list-reload-identity-guard` MUST
- `resource-list-reload-rethrows` MUST
- `resource-list-set-items-writes-through` MUST
- `resource-list-is-fetching-derivation` MUST
- `resource-list-error-status-derivation` MUST
- `resource-list-error-message-fallback` MUST
- `make-entity-delete-handler-sequence` MUST
- `make-entity-delete-handler-del-not-caught` MUST
- `workspace-prefs-cache-key` MUST
- `read-cached-workspace-ssr-safe` MUST
- `write-cached-workspace-swallow` MUST
- `workspace-prefs-get-unwraps` MUST
- `workspace-prefs-put-full-replace` MUST
- `workspaces-query-key-constant` MUST
- `notify-workspaces-changed-dual-invalidate` MUST
- `notify-workspaces-changed-swallows` MUST
- `notify-workspaces-changed-dispatches-event` MUST
- `on-workspaces-changed-subscribe` MUST
- `check-workspace-slug-available` MUST
- `workspaces-api-list-drops-team-rows` MUST
- `workspaces-api-list-ordering` MUST
- `platform-i18n-layer-decide-design-choice-outside` MUST — Both occurrences are the same hardcoded English literal, with no lookup table, ICU message, or locale parameter …

- **resource-list-no-retry**: `useResourceList`'s query MUST set `retry:
  false` (`use-resource-list.ts`).
- **resource-list-gc-time**: `useResourceList`'s query MUST set `gcTime:
  RESOURCE_GC_TIME` (30 minutes) (`use-resource-list.ts`).
- **resource-list-reload-identity-guard**: `useResourceList`'s effect MUST
  cancel the in-flight request and refetch only when `load`'s identity has
  changed AND `cacheKey`/`tenantId` have stayed the same
  (`use-resource-list.ts`).
- **resource-list-reload-rethrows**: the returned `reload()` MUST call
  `refetch()` and MUST rethrow whatever error that resolves with
  (`use-resource-list.ts`).
- **resource-list-set-items-writes-through**: the returned `setItems` MUST
  write through `client.setQueryData` (`use-resource-list.ts`).
- **resource-list-is-fetching-derivation**: the returned `isFetching` MUST
  be `query.isFetching || query.isPending` (`use-resource-list.ts`).
- **resource-list-error-status-derivation**: the returned `errorStatus` MUST
  be `httpStatus(err) ?? null` (`use-resource-list.ts`).
- **resource-list-error-message-fallback**: the returned `error` MUST be
  `null` when there is no error, `err.message` when the error is an
  `Error`, and the literal string `'Failed to load.'` otherwise
  (`use-resource-list.ts`).
- **make-entity-delete-handler-sequence**: `makeEntityDeleteHandler(opts)`'s
  returned handler MUST, in order: await `del(id)`; when `readLastId(basePath)
  === id`, call `clearLastId(basePath)`; call `router.push(\`${basePath}/all\`,
  { scroll: false })`; then call `reload()`, swallowing any error `reload()`
  throws (`use-resource-list.ts`).
- **make-entity-delete-handler-del-not-caught**: a rejection thrown by
  `del(id)` itself MUST NOT be caught by this handler — only the subsequent
  `reload()` call's rejection is swallowed (`use-resource-list.ts`).
- **workspace-prefs-cache-key**: the cached workspace slug MUST be stored
  under `` `${dataConfig().storageKeyPrefix}:home:workspace` ``
  (`workspace-prefs.ts`).
- **read-cached-workspace-ssr-safe**: `readCachedWorkspace()` MUST return a
  safe empty result (no thrown exception) both off-browser and when reading
  storage throws (`workspace-prefs.ts`).
- **write-cached-workspace-swallow**: `writeCachedWorkspace(slug)` MUST
  swallow any exception thrown while writing storage (`workspace-prefs.ts`).
- **workspace-prefs-get-unwraps**: `workspacePrefsApi.get()` MUST issue `GET
  /api/me/workspace-prefs`, unwrap the response's `{ prefs }` field, and MUST
  default to `{}` rather than surface a 404 (`workspace-prefs.ts`).
- **workspace-prefs-put-full-replace**: `workspacePrefsApi.put(prefs)` MUST
  issue `PUT /api/me/workspace-prefs` with the full `prefs` object,
  replacing the stored preferences rather than merging into them
  (`workspace-prefs.ts`).
- **workspaces-query-key-constant**: `WORKSPACES_QUERY_KEY` MUST be
  `['workspaces']` (`workspaces.ts`).
- **notify-workspaces-changed-dual-invalidate**:
  `notifyWorkspacesChanged()` MUST invalidate the `WORKSPACES_QUERY_KEY`
  cache entry directly, AND MUST invalidate, via `revalidateResources`,
  every `resource-list` cache entry whose cache key is `'workspaces'`
  (`workspaces.ts`).
- **notify-workspaces-changed-swallows**: both invalidations
  `notifyWorkspacesChanged()` performs MUST swallow any rejection they
  produce (`workspaces.ts`).
- **notify-workspaces-changed-dispatches-event**:
  `notifyWorkspacesChanged()` MUST dispatch a `CustomEvent` named by
  `WORKSPACES_CHANGED_EVENT` (`'adh:workspaces-changed'`) on `window`, and
  MUST be a no-op off-browser (`workspaces.ts`).
- **on-workspaces-changed-subscribe**: `onWorkspacesChanged(listener)` MUST
  subscribe `listener` to that event and MUST return an unsubscribe
  function; both MUST be no-ops off-browser (`workspaces.ts`).
- **check-workspace-slug-available**: `checkWorkspaceSlugAvailable(slug)`
  MUST issue `GET` to
  `` `/api/auth/slug-available/${encodeURIComponent(slug)}` `` and return a
  `SlugAvailability` (`workspaces.ts`).
- **workspaces-api-list-drops-team-rows**: `workspacesApi.list()` MUST
  exclude any row whose `type` is `'team'` (`workspaces.ts`).
- **workspaces-api-list-ordering**: `workspacesApi.list()` MUST order its
  caller's own individual workspace first, followed by every organization
  sorted by name via `sortByText` (`workspaces.ts`).
## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `storageKeyPrefix` | `string` (via `configureData`) | `'adh'` | Prefix for every FTD key (`` `${prefix}:ftd:...` ``) and the cached-workspace key (`` `${prefix}:home:workspace` ``) |
| `WORKSPACES_QUERY_KEY` | exported constant | `['workspaces']` | react-query key the workspace switcher's own list is cached under |
| `WORKSPACES_CHANGED_EVENT` | exported constant | `'adh:workspaces-changed'` | Name of the `CustomEvent` `notifyWorkspacesChanged` dispatches on `window` |
| `RESOURCE_GC_TIME` | imported constant (`query/index.tsx`, not one of this component's own files) | `1,800,000` ms (30 min) | `gcTime` every `resource-list`/`resource-item` entry this component mints uses |
| `opts.reportErrors` | caller-supplied option, per call to `useResourceItemQuery`/`useResourceList` | `true` | Gates whether a load failure is sent to `reportUnexpectedAuthError` |
| `opts.seedFrom` | caller-supplied option, per call to `useResourceItemQuery` | `undefined` | Supplies `placeholderData` (never `initialData`) while the real read is in flight |

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `resourceItem.loadFailedFallback` | Failed to load. | `useResourceItemQuery`'s returned `error` when the underlying rejection is not an `Error` instance (`use-resource-item.ts`) |
| `resourceList.loadFailedFallback` | Failed to load. | `useResourceList`'s returned `error` when the underlying rejection is not an `Error` instance (`use-resource-list.ts`) |

Both occurrences are the same hardcoded English literal, with no lookup
table, ICU message, or locale parameter anywhere in these nine files — there
is no localization mechanism in this component at all. This is a plain fact
about the source, not a gap: a port to a platform with an i18n layer MUST
decide, as a design choice outside this contract, whether and how to route
this string through it.

## Privacy

- **Data collected**: This component collects no new personal data of its
  own. It caches, in memory (react-query) or `localStorage`, whatever rows
  and preference objects its callers already fetched: resource lists/items
  keyed by an opaque `tenantId` (`ecosystem_id`/`tenant_id`/`project_id`,
  read via `useTenantId`, never re-derived or stored separately by this
  module), a last-selected id and view-mode string per collection (FTD), and
  a cached workspace slug.
- **Storage**: The FTD last-id/view-mode values and the cached workspace
  slug live in `localStorage` under `` `${storageKeyPrefix}:ftd:...` `` and
  `` `${storageKeyPrefix}:home:workspace` `` as plaintext — readable by any
  script running on the page, the same SPA localStorage tradeoff
  `auth-client`'s own Privacy section documents for the access token; none
  of these values is itself a credential. Resource lists/items live only in
  the in-memory `@tanstack/react-query` cache (`getToolkitQueryClient()`),
  never written to `localStorage`.
- **Transmission**: Every network call this component makes (`authedJson`,
  `authedRequest`, and the plain `fetch` calls in `workspace-prefs.ts`/
  `workspaces.ts`) goes through the Bearer-authed fetch layer `http.ts`
  re-exports from `auth-client`; this module adds no transmission channel
  of its own.
- **Retention**: `resource-list`/`resource-item` cache entries persist in
  memory for `RESOURCE_GC_TIME` (30 minutes) after their last observer
  unmounts, and the whole cache is cleared the moment the signed-in
  principal changes (`watchSession()` in `query/index.tsx`, not one of this
  component's own files, but the mechanism that keeps a tenant-keyed cache
  entry from surviving a sign-out/sign-in on a shared machine). FTD and
  workspace-slug `localStorage` entries persist until explicitly overwritten
  or the browser's own storage is cleared; this component enforces no TTL
  on them.

