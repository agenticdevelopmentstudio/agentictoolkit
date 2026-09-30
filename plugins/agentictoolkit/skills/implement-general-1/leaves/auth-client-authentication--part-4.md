<!-- leaf: implement-general-1/auth-client-authentication--part-4 · source: auth-client-authentication.md -->

# Authentication Client — continued (part 4)

**Rules** (cite as `implement-general-1/auth-client-authentication--part-4#<slug>`):

- `security-secret-not-persisted` MUST
- `security-secret-single-source` MUST
- `security-unauthorized-propagates` MUST
- `security-revocation-is-the-response` MUST
- `disclosure-safeguard` MUST — ApiTokenCreated and StorageTokenCreated — the two types that carry a raw plaintext secret in their token field — …

- **security-secret-not-persisted**: `ApiTokensRail`/`StorageTokensRail` MUST NOT write a revealed
  plaintext secret to disk, `UserDefaults`, or the Keychain; `revealedSecrets` is a plain in-memory
  dictionary with no backing store.
- **security-secret-single-source**: the plaintext secret MUST be obtainable only from the response of
  `dataSource.create(_:)`/`create(ecosystemID:_:)`; no operation in this contract re-fetches or
  re-derives a previously issued secret once its reveal has expired (`api-tokens-reveal-once` /
  `storage-tokens-reveal-once`).
- **security-unauthorized-propagates**: `HubError.unauthorized`/`.forbidden` thrown by any data source
  MUST propagate unchanged to the caller through `HubError.wrap(_:)` rather than being caught, retried,
  or downgraded locally.
- **security-revocation-is-the-response**: the only way this component withdraws a previously granted
  credential or permission is outright removal — `revoke(id:)`/`revoke(ecosystemID:id:)` for tokens,
  `removeMember(groupID:memberRowID:)`/`removeGrant(groupID:grantID:)` for access — MUST NOT offer any
  "soft-disable" or partial-trust intermediate state.
## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `apiTokens` | `ApiTokensDataSource` | none (required) | `AuthenticationModule`'s collaborator for personal API tokens; wrapped internally into an `ApiTokensRail`. |
| `storageTokens` | `StorageTokensDataSource` | none (required) | `AuthenticationModule`'s collaborator for storage tokens; wrapped internally into a `StorageTokensRail`. |
| `dataSource` (`ApiTokensRail.init`) | `ApiTokensDataSource` | none (required) | Backs `list()`, `scopes()`, `create(_:)`, `revoke(id:)`. |
| `dataSource` (`StorageTokensRail.init`) | `any StorageTokensDataSource` | none (required) | Backs `list(ecosystemID:)`, `create(ecosystemID:_:)`, `revoke(ecosystemID:id:)`. |
| `dataSource` (`AccessListsTopic.init`) | `BucketAccessDataSource` | none (required) | Backs `groups()`, `detail(id:)`, `create/update/delete`, `addMember`/`removeMember`, `upsertGrant`/`removeGrant`. |
| `buckets` (`AccessListsTopic.init`) | `BucketsDataSource` | none (required) | Supplies the bucket list/names and bucket-table list this topic renders alongside access lists; owned by the separate Buckets feature. |
| `ecosystemID` (`StorageTokensRail` calls) | `String?` | caller-supplied per call | `nil` selects the caller's own (workspace) tokens; non-nil selects that ecosystem's tokens. |
| `scopes` (`ApiTokensRail.createSpec`) | `[String]?` | caller-supplied per call | The scope catalogue for this create sheet; `nil` disables the save action entirely. |
| Row id length limit | `Int` literal `36` | fixed | Inline bound in `AccessListsTopic`'s grant save action; not a named constant or injectable configuration. |
| `Slug.pattern` / `Slug.patternMessage` | `String` constants | fixed | Shared identifier rule (`Slug.pattern`: one lowercase letter or digit, optionally followed by lowercase letters, digits, or hyphens and ending in a letter or digit) enforced on `StorageTokensRail`'s `name` field. |

## Localization

The source contains no localization mechanism (no `String(localized:)`, no `.strings`/`.xcstrings`
catalog, no `NSLocalizedString`) — every user-facing string below is a hardcoded English literal, per
Extra Rule 14 stated here as fact rather than as a gap:

| String Key | Default (en) | Context |
|-----------|---------------|---------|
| — | `Choose at least one scope. An empty selection mints a broad legacy token, not the scoped one you intended.` | `ApiTokensRail.noScopeSelectedMessage` |
| — | `Couldn't load the scope catalogue. Token creation is disabled until it loads — otherwise an empty selection would silently mint a broad legacy token instead of the scoped one you intended.` | `ApiTokensRail.catalogueUnavailableMessage` |
| — | `Revoke API token "{name}"? Anything using it will stop working.` | `ApiTokensRail` revoke confirmation |
| — | `That name is already in use. Token names stay reserved even after revoke — pick a different one.` | `StorageTokensRail.nameTakenMessage` |
| — | `Revoke storage token "{slug}"? Anything using it will lose access to its bucket.` | `StorageTokensRail` revoke confirmation |
| — | `An access list named "{name}" already exists in that bucket.` | `AccessListsTopic` create validation |
| — | `The built-in "everyone" list applies to every principal and can't be renamed.` | `AccessListsTopic.everyoneNameHelp` |
| — | `That member is already in this access list.` | `AccessListsTopic` member-add conflict |
| — | `Row id must be 36 characters or fewer.` | `AccessListsTopic` grant validation |
| — | `Choose at least one permission.` | `AccessListsTopic` grant validation (create and save) |

(This is a representative sample of the roughly two dozen literals across the four files, not the full
set; every one of them follows the same pattern — a plain `String` with no key, no catalog entry, and
no pluralization/formatting rule beyond ad hoc string interpolation.)

## Privacy

- **Data collected**: a plaintext bearer secret (`ApiTokenCreated.token` / `StorageTokenCreated.token`)
  is returned exactly once, in the response to a successful create call.
- **Storage**: none of the four types persists the secret; `revealedSecrets` is an in-memory
  `[String: String]` on the `@MainActor`-isolated rail instance, with no file, `UserDefaults`, or
  Keychain write anywhere in this component.
- **Transmission**: this component never transmits the secret itself — it receives it once from
  `create(_:)`'s/`create(ecosystemID:_:)`'s response and places it into a `FormDetails.form`'s read-only
  field for on-screen display; actual network transmission is the injected data source's concern, out
  of scope of these files.
- **Retention**: bounded by two independent mechanisms — the reveal-once rule
  (`security-secret-single-source`), which drops a secret from `revealedSecrets` the moment navigation
  moves away from its detail, and the rail instance's own lifetime (the dictionary holds nothing once
  the instance is deallocated, e.g. on app relaunch).
- **Disclosure safeguard**: `ApiTokenCreated` and `StorageTokenCreated` — the two types that
  carry a raw plaintext secret in their `token` field — declare no
  `CustomStringConvertible`/`CustomDebugStringConvertible` override, so their synthesized default
  description includes the secret in full. Neither `ApiTokensRail.swift` nor `StorageTokensRail.swift`
  logs or prints a `created` value; both store only its `token` into `revealedSecrets`. A port MUST NOT
  log these values.

