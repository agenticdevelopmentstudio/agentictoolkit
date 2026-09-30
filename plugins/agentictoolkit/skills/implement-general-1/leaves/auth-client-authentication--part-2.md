<!-- leaf: implement-general-1/auth-client-authentication--part-2 · source: auth-client-authentication.md -->

# Authentication Client — continued (part 2)

**Rules** (cite as `implement-general-1/auth-client-authentication--part-2#<slug>`):

- `root-tokens-level` MUST
- `root-path-routing` MUST
- `root-unknown-routes-empty` MUST
- `root-storage-uses-personal-scope` MUST
- `api-tokens-list-sorted-by-name` MUST
- `api-tokens-list-item-shape` MUST
- `api-tokens-scope-line-legacy-fallback` MUST
- `api-tokens-catalogue-fetched-per-open` MUST
- `api-tokens-catalogue-unavailable-disables-create` MUST
- `api-tokens-create-fields` MUST
- `api-tokens-empty-scope-rejected` MUST
- `api-tokens-scope-derivation` MUST
- `api-tokens-name-trimmed` MUST
- `api-tokens-reveal-on-create` MUST
- `api-tokens-reveal-once` MUST
- `api-tokens-detail-field-order` MUST
- `api-tokens-detail-fallbacks` MUST
- `api-tokens-revoke` MUST
- `api-tokens-unknown-path-empty` MUST
- `api-tokens-errors-wrapped` MUST
- `storage-tokens-ecosystem-scoped` MUST
- `storage-tokens-list-sorted-by-slug` MUST
- `storage-tokens-list-item-shape` MUST
- `storage-tokens-about-varies-by-scope` MUST
- `storage-tokens-name-pattern` MUST
- `storage-tokens-create-body-shape` MUST
- `storage-tokens-create-conflict-message` MUST
- `storage-tokens-create-error-tiering` MUST
- `storage-tokens-reveal-on-create` MUST
- `storage-tokens-reveal-once` MUST
- `storage-tokens-detail-field-order` MUST
- `storage-tokens-detail-fallbacks` MUST
- `storage-tokens-revoke` MUST
- `storage-tokens-unknown-path-empty` MUST

## Behavioral Requirements

**Root module (`AuthenticationModule`)**

- **root-tokens-level**: `rootLevel()` MUST return an `HTDVLevel` titled "Tokens" with exactly three
  items, in order: `"api"` ("API tokens"), `"storage"` ("Storage tokens", `dividerAfter: true`), and
  `"about"` ("About tokens"), and MUST set `emptyMessage: ""` and `createAction: nil` (the level itself
  offers no create action; creation happens one level down, inside each rail).
- **root-path-routing**: `child(for:)` MUST route a path whose first item's `id` is `"api"` to
  `apiTokens.child(path:)` with the remaining path, `"storage"` to
  `storageTokens.child(path:ecosystemID:levelID:title:)` with the remaining path and
  `ecosystemID: nil`, and `"about"` with an empty remaining path to a read-only notice detail showing
  `AuthenticationModule.overviewMessage`; an empty path MUST return `.level(rootLevel())`.
- **root-unknown-routes-empty**: `child(for:)` MUST return `.empty` for any first-item id other than
  `"api"`/`"storage"`/`"about"`, and for `"about"` with a non-empty remaining path.
- **root-storage-uses-personal-scope**: the root's `"storage"` route MUST always call
  `storageTokens.child(...)` with `ecosystemID: nil`, so the root "Storage tokens" section lists only
  the caller's own (workspace) storage tokens, never an ecosystem's.

**Personal API tokens (`ApiTokensRail`)**

- **api-tokens-list-sorted-by-name**: `level(tokens:)` MUST sort tokens by `name` using
  `localizedCaseInsensitiveCompare` (ascending).
- **api-tokens-list-item-shape**: each row's `id` MUST be the token's `id`, `label` its `name`,
  `sublabel` `"\(prefix)… · \(scopeLine)"`, `systemImage` `"key"`, and `leadsTo` `.detail`.
- **api-tokens-scope-line-legacy-fallback**: `ApiToken.scopeLine` MUST be `"legacy"` when `scope` is
  `nil` or empty, otherwise the scopes joined with `", "`.
- **api-tokens-catalogue-fetched-per-open**: the "New API token" create action MUST call
  `dataSource.scopes()` fresh every time the sheet is opened; it MUST NOT reuse a catalogue fetched by
  an earlier open.
- **api-tokens-catalogue-unavailable-disables-create**: when `scopes()` throws, `createSpec(scopes:
  nil)` MUST return a form with exactly one read-only field (key `"notice"`, label "Scope catalogue")
  and `FormActions()` with no save action, so the sheet can display
  `ApiTokensRail.catalogueUnavailableMessage` but cannot mint a token.
- **api-tokens-create-fields**: `createSpec(scopes:)` with a non-nil catalogue MUST build, in order:
  a required `name` text field, a read-only `scopeHelp` field, one toggle field per catalogue prefix
  (key `"scope:" + prefix`, label the bare prefix), a `readOnly` toggle ("Read-only (GET/HEAD only)"),
  and an `expiresAt` date field.
- **api-tokens-empty-scope-rejected**: the create save action MUST throw
  `HubError.validation(ApiTokensRail.noScopeSelectedMessage)` when `ApiTokensRail.scope(from:prefixes:)`
  returns `nil` (no scope toggle selected), regardless of the `readOnly` toggle's value, and MUST NOT
  call `dataSource.create(_:)` in that case.
- **api-tokens-scope-derivation**: `ApiTokensRail.scope(from:prefixes:)` MUST return, in catalogue
  order, every prefix whose toggle is `true`, each suffixed `":read"` when the `readOnly` toggle is
  `true` and left bare otherwise, and MUST return `nil` when no prefix toggle is `true`.
- **api-tokens-name-trimmed**: the create save action MUST trim leading/trailing whitespace from the
  `name` field before constructing `ApiTokenCreate`.
- **api-tokens-reveal-on-create**: on a successful `dataSource.create(_:)`, the save action MUST store
  the returned `created.token` into `revealedSecrets[created.id]`.
- **api-tokens-reveal-once**: `child(path:)` MUST call `expireRevealedSecret(unless: path.first?.id)`
  before doing anything else on every call; that call MUST remove the currently-revealed secret from
  `revealedSecrets` and clear `revealedOnScreen` whenever the requested path's first id differs from
  `revealedOnScreen`, and MUST leave both untouched when the first id equals `revealedOnScreen` (a
  re-render of the same detail).
- **api-tokens-detail-field-order**: `detail(for:)` MUST list read-only fields in the order `name`,
  `prefix`, `scope`, `created`, `lastUsed`, `expires`, followed by `token` and `notice` only when a
  revealed secret exists for that token.
- **api-tokens-detail-fallbacks**: `detail(for:)` MUST render `scope` as `"legacy (curated-only)"` when
  `token.scope` is `nil` or empty (else the scopes joined by `"\n"`), `lastUsed` as `"never used"` when
  `lastUsedAt` is `nil`, and `expires` as `"never"` when `expiresAt` is `nil`.
- **api-tokens-revoke**: the detail's delete action MUST be titled "Revoke token" with confirmation
  text `Revoke API token "{name}"? Anything using it will stop working.`, MUST call
  `dataSource.revoke(id:)`, and on success MUST clear `revealedSecrets[token.id]`.
- **api-tokens-unknown-path-empty**: `child(path:)` MUST return `.empty` when `path.count == 1` and no
  token matches `path[0].id`, and MUST return `.empty` for any `path.count` other than `0` or `1`.
- **api-tokens-errors-wrapped**: every call into `dataSource` MUST be routed through `HubError.wrap`
  (directly, or via the create save action's own `try await`, which only ever surfaces `HubError` since
  `create(_:)` and `revoke(id:)`'s calls are the only throwing operations besides the two validation
  checks above, both of which already throw `HubError.validation`).

**Storage tokens (`StorageTokensRail`, shared with `EcosystemConfig`)**

- **storage-tokens-ecosystem-scoped**: every `StorageTokensRail` operation (`child`, `level`,
  `createSpec`, `detail`) MUST take an `ecosystemID: String?` and pass it through unchanged to
  `dataSource.list(ecosystemID:)`, `dataSource.create(ecosystemID:_:)`, and
  `dataSource.revoke(ecosystemID:id:)`; `nil` means the caller's own (workspace) tokens, a non-nil value
  means that ecosystem's tokens.
- **storage-tokens-list-sorted-by-slug**: `level(tokens:...)` MUST sort tokens by the raw `<` operator
  on `slug` (NOT `localizedCaseInsensitiveCompare`, unlike `ApiTokensRail`'s name sort).
- **storage-tokens-list-item-shape**: each row's `label` MUST be `token.rdid ?? token.slug`, `sublabel`
  `"\(prefix)… · \(bucketRdid ?? "no bucket")"`, `systemImage` `"externaldrive"`, `leadsTo` `.detail`.
- **storage-tokens-about-varies-by-scope**: `StorageTokensRail.aboutText(ecosystemID:)` MUST return
  `aboutWithoutEcosystem` when `ecosystemID` is `nil` and `aboutWithEcosystem` otherwise; the create
  sheet's `"about"` value MUST come from this function.
- **storage-tokens-name-pattern**: the create form's `name` field MUST enforce `Slug.pattern` with
  `Slug.patternMessage` as its violation message.
- **storage-tokens-create-body-shape**: the create save action MUST trim the `name` field, MUST pass
  `HubText.nonBlank(...)` of the `description` field (nil when blank/missing), and MUST construct
  `StorageTokenCreate` with `ecosystemId: nil` unconditionally — the actual ecosystem scope is conveyed
  exclusively through `dataSource.create(ecosystemID:_:)`'s separate `ecosystemID` argument, never
  through the request body's own `ecosystemId` field.
- **storage-tokens-create-conflict-message**: the create save action MUST catch `HubError.conflict`
  specifically and rethrow `HubError.validation(StorageTokensRail.nameTakenMessage)`.
- **storage-tokens-create-error-tiering**: the create save action MUST rethrow any other `HubError`
  case unchanged, and MUST convert any non-`HubError` throw into
  `HubError.unexpected(StorageTokensRail.createFailedMessage)` — a three-way catch chain distinct from
  the single `HubError.wrap(_:)` pattern every other create/update/delete path in this component uses.
- **storage-tokens-reveal-on-create**: on success, the save action MUST store `created.token` into
  `revealedSecrets[created.id]`, mirroring `api-tokens-reveal-on-create`.
- **storage-tokens-reveal-once**: `child(path:ecosystemID:levelID:title:)` MUST call
  `expireRevealedSecret(unless: path.first?.id)` first on every call, with the same drop/keep semantics
  as `api-tokens-reveal-once`.
- **storage-tokens-detail-field-order**: `detail(for:ecosystemID:)` MUST list read-only fields in the
  order `name`, `identifier`, `prefix`, `bucket`, `description`, `created`, `lastUsed`, `expires`,
  followed by `token`/`notice` only when a revealed secret exists.
- **storage-tokens-detail-fallbacks**: `detail(for:)` MUST render `name` as `token.slug` (not `rdid`),
  `identifier` as `token.rdid ?? "—"`, `bucket` as `token.bucketRdid ?? "no bucket"`, and `description`
  as `"—"` when `token.description.isEmpty`.
- **storage-tokens-revoke**: the detail's delete action MUST be titled "Revoke token" with confirmation
  text `Revoke storage token "{slug}"? Anything using it will lose access to its bucket.`, MUST call
  `dataSource.revoke(ecosystemID:id:)`, and on success MUST clear `revealedSecrets[token.id]`.
- **storage-tokens-unknown-path-empty**: `child(path:...)` MUST return `.empty` when `path.count == 1`
  and no token matches, and for any `path.count` other than `0` or `1`.

**Access lists (`AccessListsTopic`)**
