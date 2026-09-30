<!-- leaf: implement-general-1/api-toolkit--part-3 · source: api-toolkit.md -->

# ApiToolkit — continued (part 3)

**Rules** (cite as `implement-general-1/api-toolkit--part-3#<slug>`):

- `item-url-substitution` MUST
- `row-key-derivation` MUST
- `loading-vs-fetching` MUST
- `out-of-order-response-guard` MUST
- `loaded-for-tracking` MUST
- `query-composition-order` MUST
- `mutation-relist` MUST
- `delete-uses-authed-request` MUST
- `mutation-error-not-hook-state` MUST
- `stable-proxy-identity` MUST
- `presence-is-the-dirty-signal` MUST
- `proxy-reads-latest-guard` MUST
- `standalone-default` MUST
- `admin-derivation` MUST

### useCrudResource.ts

- **item-url-substitution**: `itemUrl(meta, row)` MUST substitute each
  `pkParams` value, URL-encoded, into `itemPath` to build the per-item URL.
- **row-key-derivation**: `rowKey(meta, row)` MUST join the row's escaped
  primary-key values, and MUST return the empty string when a single-pk row
  has no value for that key.
- **loading-vs-fetching**: `loading` MUST mean "nothing to show for the
  current list yet" and `fetching` MUST mean "a list call is currently open";
  the two MUST be able to diverge (e.g. a background re-list on an
  already-populated list has `fetching: true` but `loading: false`).
- **out-of-order-response-guard**: the hook MUST track a `listSeq` sequence
  number per list call and MUST discard the result of any list response
  whose sequence number is not the latest issued, so a slow, stale response
  MUST NOT overwrite state written by a newer, faster response.
- **loaded-for-tracking**: `loadedFor` MUST track which list identity's rows
  are currently on screen, and `loading` MUST be derived as
  `fetching && loadedFor.current !== listId` so switching to a not-yet-loaded
  list shows `loading`, while re-fetching an already-loaded list does not.
- **query-composition-order**: the `listQuery` string MUST place the
  `scopeEcosystemId`-derived `scopeQuery` before the `filterQuery` when both
  are present.
- **mutation-relist**: `create`, `update`, and `remove` MUST re-issue the list
  call after their underlying mutation succeeds; `createRow`, `updateRow`, and
  `removeRow` (the raw mutators they call) MUST NOT re-list on their own.
- **delete-uses-authed-request**: `removeRow` MUST call `authedRequest`
  (which discards the response body), not `authedJson`, because the DELETE
  endpoint answers `204 No Content` and `authedJson` throws on a `204`.
- **mutation-error-not-hook-state**: a failure from `createRow`, `updateRow`,
  or `removeRow` MUST propagate to the caller as a rejected promise, and MUST
  NOT be written into the hook's own `error` state.

### useExitGuardChannel.ts

- **stable-proxy-identity**: the `PaneExitGuard` proxy returned while a guard
  is registered MUST be the same object identity across re-registrations
  (built once via `useMemo` with an empty dependency array).
- **presence-is-the-dirty-signal**: the hook MUST expose the proxy (non-null)
  only while `present` is `true`, and MUST expose `null` once withdrawn;
  callers MUST treat the presence of a non-null guard, not merely a call to
  it, as part of the dirty signal.
- **proxy-reads-latest-guard**: the stable proxy's `isDirty()` MUST read
  through `guardRef` to the most recently registered guard rather than
  closing over a stale one.

### viewer.ts

- **standalone-default**: `useViewer()` MUST return the settled value
  `{ isAdmin: false, ready: true }` when no `AuthProvider` is mounted
  (`useOptionalAuth()` returns `null`), so the browser is usable standalone
  without ever reporting an unsettled/loading state.
- **admin-derivation**: when an `AuthProvider` is mounted, `isAdmin` MUST be
  derived from `isAdmin(auth.user)` and `ready` MUST be derived from
  `!auth.isLoading` — `ready` MUST distinguish "settled" from "still
  loading," never conflating the two.

## Configuration

- **`API_BASE`** (`buildRequest.ts`, `useCrudResource.ts`) — fixed constant
  `/api`; not caller- or environment-configurable in the given source.
- **`token`** (`buildRequest(meta, values, token?)`) — optional, caller-
  supplied bearer token forwarded as `Authorization: Bearer <token>`.
- **`PUBLIC_API_ORIGIN`** (`snippets.ts`) — fixed constant
  `https://api.agenticdeveloperhub.com` used only for generated snippet URLs,
  never for the same-origin requests `buildRequest` itself issues.
- **`EDITABLE_OVERRIDES`** (`editability.ts`) — a module-level object callers
  may hand-populate (outside test code) to force a non-relational,
  non-server-managed column's editability; empty by default.
- **`meta` / `filter` / `scopeEcosystemId`** (`useCrudResource(meta, filter?,
  scopeEcosystemId?)`) — `meta` (the table's `CrudTableMeta`) is required;
  `filter` is an optional caller-supplied query object serialized into
  `listQuery`; `scopeEcosystemId` is an optional caller-supplied scope value
  that precedes `filter` in the query string and rides every verb, not just
  the list call.
- **`isAdminViewer`** (`exposure.ts`'s `canReadTable`/`canWriteTable`/
  `readableTables`) — caller-supplied boolean, typically sourced from
  `useViewer()`'s `isAdmin`.

## Deep Linking

`slug.ts` exists specifically to make each API endpoint reachable by a
crawlable, collision-checked URL slug: `endpointSlug(meta)` projects an
endpoint to a slug (path segments with `{param}` braces stripped, plus the
lower-cased method appended), and `endpointForSlug(slug)` reverses that
projection for routing, returning `undefined` on a miss rather than throwing.
This is the deep-linking contract for the whole recipe; no other given source
file participates in deep linking.

## Localization

None of the given sources externalize strings into a localization resource
system; the following are hardcoded, English-only strings that are facts
about the current implementation, not gaps:

- `snippets.ts`'s `TOKEN_PLACEHOLDER` (`'YOUR_TOKEN'`) is embedded verbatim,
  in English, in every generated cURL/JavaScript snippet.
- `slug.ts`'s collision message (`api-explorer: endpoint slug collision on
  "${slug}"...`) is a hardcoded English developer-facing error string.
- `useCrudResource`'s reliance on the auth package's hardcoded English error
  message for an unexpected `204` response (see Platform Notes) is inherited,
  not produced, by this recipe's own sources.

## Privacy

- `buildRequest`'s `token` parameter is forwarded as an `Authorization`
  header and is never persisted, cached, or logged by any given source; the
  caller owns the token's lifecycle.
- `snippets.ts` deliberately substitutes `TOKEN_PLACEHOLDER` for any real
  token so that copying a generated snippet to the clipboard can never leak a
  live credential — a privacy-motivated design decision (see Design
  Decisions).
- `exposure.ts`'s tier gate (`canReadTable`/`canWriteTable`) is presentation
  data-minimization only: it narrows which tables the UI *offers* to a
  non-admin viewer, but it is explicitly documented as not a security or
  privacy boundary — the server independently decides what data is actually
  returned.
- None of the given sources persist personally identifiable information to
  local storage, a database, or any other durable store.

## Platform Notes

- **Web (source platform)**: `fetch`, `AbortController`, `URLSearchParams`,
  and `Promise` are the native browser primitives this recipe's TypeScript
  is written against; `shiki` (via dynamic `import()`) is the only
  third-party runtime dependency among the given sources.
- **Apple (Swift, not in source)**: `URLSession` (with `URLRequest`) is the
  equivalent of `buildRequest`/`executeRequest`; `Codable` is the equivalent
  of the JSON-Schema-driven `schemaToExample`/`describeFields` derivation
  (though Codable is compile-time-typed, so a dynamic JSON-Schema-to-example
  projection has no direct one-to-one match); `Task`/`async`/`await` replace
  the Promise-based flow; a stable `AnyObject` proxy under `@MainActor`
  would replace `useExitGuardChannel`'s `useMemo`-stabilized proxy.
- **Android (Kotlin, not in source)**: `OkHttp` or `Retrofit` plus
  `kotlinx.serialization` (or Moshi) replace `buildRequest`/`executeRequest`
  and the schema-derived example/field logic respectively; Kotlin
  `Flow`/`StateFlow` replace the `loading`/`fetching` state pair exposed by
  `useCrudResource`; a `Mutex`-guarded sequence counter would replace the
  `listSeq` out-of-order-response guard.
- **WinUI 3 (Windows, not in source)**: `HttpClient` replaces `buildRequest`/
  `executeRequest`; `System.Text.Json` replaces the JSON-Schema example/field
  derivation in `schema.ts` (again, statically-typed deserialization has no
  exact analogue to the dynamic example synthesis in `schemaToExample`);
  `Windows.Storage` has no counterpart here since no given source persists
  data locally; `Task`/`async`/`await` replace the Promise-based flow;
  `ObservableCollection<T>` plus `INotifyPropertyChanged` replace the
  `rows`/`loading`/`fetching` state that `useCrudResource` exposes to a React
  render; a WinUI 3 port would need its own out-of-order-response guard
  (e.g. a monotonically increasing request-token field checked before
  applying a completed request's result) since `HttpClient` provides no
  built-in equivalent to `listSeq`.
- **Python (not in source)**: `httpx` (or `requests`) replaces
  `buildRequest`/`executeRequest`; `dataclasses` or `pydantic` models replace
  the JSON-Schema example/field derivation; there is no direct Python
  analogue to the React-hook state machine in `useCrudResource` since Python
  is not paired with a UI render loop in this codebase — a port would need to
  re-derive the `loading`/`fetching` distinction against whatever calling
  convention it adopts (a callback, an async generator, or similar).

