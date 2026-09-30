<!-- leaf: implement-hub-domain-1/ecosystems--part-5 · source: hub-domain-ecosystems.md -->

# Hub Domain: Ecosystems — continued (part 5)

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `topics` | `[any EcosystemTopicProvider]` (Apple, `EcosystemsModule.init`) | none — required | The ordered set of topic providers a product's rail exposes; `EcosystemsModule` imposes no fixed order or fixed membership |
| `parent` | `Ecosystem?` (Apple, `EcosystemCreateForm.init`) | `nil` | When set, the new ecosystem is created as a child of this ecosystem; when `nil`, the prefix comes from `dataSource.infrastructureID()` |
| `EcosystemCreateForm.slugMaxLength` | `Int` constant (Apple) | `64` | Client-side slug length ceiling enforced before any network call |
| `workspaceSlug` | `string \| undefined` (web, `workspaceDefaultEcosystemId`/the hook) | `undefined` | Selects the workspace principal's infrastructure row; omitted resolves the caller's own |
| `opts.parent` / `opts.workspace` | `string \| undefined` (web, `ecosystemsApi.create`) | both `undefined` | Scope a create to a parent ecosystem or a workspace's principal; `parent` wins if both are given |
| `BASE` (`/api/ecosystem/ecosystems`) | internal constant (web, `ecosystems.ts`) | fixed | Base route for every generic-CRUD ecosystems call |
| `BASE` (`/api/registry/identifiers`) | internal constant (web, `identifiers.ts`) | fixed | Base route for rdid rename/availability |
| `BASE` (`/api/ecosystem/features`) | internal constant (web, `ecosystem-features.ts`) | fixed | Base route for the feature catalog, provisioned list, add and remove |
| `ecosystemId` | `string \| null \| undefined` (web, feature hooks) | none — required | The ecosystem (rdid or uuid) whose features are listed or changed; the list query is disabled while it is falsy |
| `keys` | `string[]` (web, `provision`/`useProvisionFeatures`) | none — required | Catalog `key`s to add in one batch |
| `FeatureChange` `{ add, remove }` | `string[]` each (web, `useApplyFeatureChange`) | none — required | One picker visit: keys to add (one POST), provisioned keys to remove (one DELETE each) |
| catalog `staleTime` | internal constant (web, `useFeatureCatalog`) | `30 * 60 * 1000` ms | How long the session-wide catalog is served from cache before a refetch |

## Localization

- **Apple hardcoded strings**: `"Products"`, `"No products yet."`,
  `"New Product"`, `"Child Ecosystems"`, `"No child ecosystems yet."`,
  `"New Ecosystem"`, `"Settings"`, `"Delete Product"`,
  `EcosystemSettingsTopic.deleteWarning` ("Deleting a product deletes all
  the data associated with the product, including applications, buckets,
  and users. Do you wish to proceed?"), `EcosystemsModule.notManageableTitle`/
  `notManageableMessage`, `EcosystemCreateForm.slugTooLongMessage`
  ("Slug must be 64 characters or fewer."), every field label
  (`"Display Name"`, `"Slug"`, `"Identifier"`, `"Description"`,
  `"Geographic Region"`), and every "already in use"/"already exists"
  validation message this recipe's requirements quote.
- **Web hardcoded strings**: every thrown-error friendly message
  (`rethrowConflict`'s "An ecosystem with identifier ... already exists.",
  "The identifier ... is already in use."), and `useApplyFeatureChange`'s
  `Couldn't remove: <keys>` error. Catalog `label`/`description`/
  `subscriptionTier` text is served by the backend and passed through
  untranslated.

Neither implementation has a lookup table, i18n key, or locale parameter
anywhere in these files — every user-facing string above is fixed English.
This is a plain, honestly-reported fact about the current source, not a
hidden gap (see Compliance).

## Privacy

- **Data collected**: Ecosystem administrative metadata only — `name`,
  `slug`/`identifier`, `description`, `region`, `primaryDomain`/`domain`,
  timestamps, and the caller's own `canManage` flag. None of these fields
  are personal data about an end user; they describe a product/ecosystem
  record, not a person.
- **Storage**: Apple holds no cache of its own — every `EcosystemsModule`/
  topic call is a live `async throws` round-trip to whatever
  `EcosystemsDataSource` adapter the app supplies. Web holds the results
  in the shared react-query client's in-memory cache, keyed as documented
  under each hook/query above; nothing in this component writes to
  `localStorage`/`sessionStorage`/`IndexedDB`.
- **Transmission**: All calls travel through the injected data source
  (Apple) or `authedJson`/`authedRequest` (web, `@agentic-toolkit/auth`'s
  Bearer-token client — see `auth-client`); this component itself attaches
  no credentials and reads no cookies.
- **Retention**: Apple retains nothing between calls. Web's react-query
  cache entries persist per their query key until invalidated by the
  matching mutation (as documented per hook above) or garbage-collected by
  react-query's own cache lifetime; the only custom cache settings are the
  workspace-default hook's `retry: false` and the feature catalog's
  30-minute `staleTime`, and no `gcTime` is set anywhere. Provisioned
  feature rows carry `provisionedBy` (a principal id or `null`), held only
  in that in-memory cache.

## Platform Notes

- **SwiftUI / AppKit / UIKit**: This is one of the two reference
  implementations. `EcosystemsModule`/topics are `@MainActor` and
  `Sendable`-safe under Swift 6 strict concurrency; the same `FormSpec`
  values these topics build are rendered by both the macOS `FormSheet`/
  `FormViewController` (`HTDV/Views/macOS/`) and the iOS
  `FormSheet+UIKit`/`FormViewController+UIKit` (`HTDV/Views/iOS/`)
  presenters, so this domain logic is genuinely shared, unmodified,
  across macOS and iOS — only the presenting view layer differs.
- **React/Web**: This is the other reference implementation.
  `ecosystemsApi`/`identifiersApi` are plain async functions over `fetch`
  (via `authedJson`/`authedRequest`); `useWorkspaceDefaultEcosystemId` and
  the Invitations and feature hooks are `@tanstack/react-query` wrappers
  around them. Only `useWorkspaceDefaultEcosystemId` passes the module
  query-client singleton explicitly; the Invitations and feature hooks read
  the client from context. `ecosystem-features.ts` (with its test
  `ecosystem-features.test.tsx`) is web-only: the Apple Hub has no feature
  picker data source in these sources, so a port of the picker starts from
  the web contract.
- **Compose / Android**: `OkHttp`/`Ktor` (or `Retrofit`) would replace
  `fetch`/`URLSession` for the web/Apple network calls respectively; a
  `ViewModel` exposing a `StateFlow`/`LiveData` of the resolved ecosystem
  list is the idiomatic equivalent of both `EcosystemsModule.rootLevel()`
  and the react-query list hooks. `androidx.lifecycle.SavedStateHandle` or
  a `Room`-backed repository would be where a native Android port adds a
  local cache neither reference implementation currently has. For the
  feature picker, `coroutineScope { keys.map { async { runCatching {
  remove(it) } } }.awaitAll() }` is the equivalent of `Promise.allSettled`,
  run after the provision call returns.
- **WinUI 3**: `HttpClient` with `System.Text.Json` replaces both
  `fetch` and `URLSession` for every ecosystems/identifiers request this
  recipe documents. A `NavigationView`/`TreeView` with a
  `TreeViewNode`-backed hierarchy is the idiomatic equivalent of the
  Apple rail's recursive `HTDVLevel`/`HTDVChild` model (products → topics
  → child ecosystems, recursing arbitrarily deep per
  child-ecosystems-recurse-via-rail); a `ContentDialog` hosting a form
  built from `Microsoft.UI.Xaml.Controls` (`TextBox` for `name`/`slug`,
  a read-only `TextBlock` for `id`, a multi-line `TextBox` for
  `description`) is the equivalent of `FormSheet`'s create dialog, and a
  second `ContentDialog` with a destructive-styled primary button is the
  equivalent of `FormDeleteAction`'s confirmation flow. `Task`/`async`-
  `await` replaces every `Promise`/Swift `async throws` call; a custom
  `HubError`-equivalent exception hierarchy (or a `Result<T, HubError>`)
  should carry the same `notFound`/`conflict`/`validation` distinctions
  this recipe's error-mapping requirements rely on, since WinUI has no
  built-in typed-error convention of its own to inherit. For the feature
  picker: a `FeaturesClient` over `HttpClient` exposes `GetCatalogAsync`
  (deserialize `{ features }` with `System.Text.Json`, keep server order),
  `ListAsync`, `ProvisionAsync` (one `PostAsJsonAsync` with
  `{ keys }`, returning the full list) and `RemoveAsync` (`DeleteAsync`,
  treating `HttpStatusCode.NotFound` as success), with path segments
  escaped by `Uri.EscapeDataString`. The picker is a `ContentDialog`
  hosting a `ListView` of `CheckBox` items bound to an
  `ObservableCollection<FeatureRow>` whose rows implement
  `INotifyPropertyChanged`; a `comingSoon` row goes in a separate
  "Coming soon" group (a `CollectionViewSource` with `IsSourceGrouped`) with
  `IsEnabled="False"`, and a `provisioning` row shows as already checked.
  Applying a change awaits `ProvisionAsync` first, then
  `Task.WhenAll` over per-key tasks that each catch their own exception
  and return a success flag (plain `Task.WhenAll` throws on the first
  fault, unlike `Promise.allSettled`), then throws
  `Couldn't remove: <keys>` for the failures and always re-reads the list
  in a `finally`. The 30-minute catalog cache has no built-in equivalent:
  keep the catalog and a fetched-at `DateTimeOffset` in a
  session-lifetime service.

