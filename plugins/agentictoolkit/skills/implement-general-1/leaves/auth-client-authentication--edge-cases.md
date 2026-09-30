<!-- leaf: implement-general-1/auth-client-authentication--edge-cases · source: auth-client-authentication.md -->

# Authentication Client

**Rules** (cite as `implement-general-1/auth-client-authentication--edge-cases#<slug>`):

- `empty-lists` MUST — an empty [ApiToken]/[StorageToken]/[AccessGroup] result MUST render the rail's emptyMessage ("No API tokens yet.", "No …
- `row-id-exactly-at-the-boundary` MUST — a trimmed grant row id of exactly 36 characters MUST be accepted; 37 characters MUST be rejected …
- `all-crud-false-on-create-vs-on-an-existing-grant` MUST — both paths MUST reject identically (access-grant-permission-required); the existing-grant path additionally MUST NOT …
- `scope-catalogue-unavailable-at-create-time` MUST — ApiTokensRail MUST disable create entirely (api-tokens-catalogue-unavailable-disables-create) rather than falling back …
- `scope-catalogue-available-but-nothing-selected` MUST — MUST be rejected the same way as an unavailable catalogue (api-tokens-empty-scope-rejected) — for the same reason: an …
- `accesscrud-init-with-garbage-input` MUST — an input string like "x,y,z" (no recognized letters) MUST NOT throw; it parses to a fully-false AccessCRUD (isEmpty == …
- `accessmembertype-from-an-unrecognized-membertype-string` MUST — AccessGroupMember.type MUST be nil and typeTitle MUST fall back to the raw memberType string; membersLevel's row falls …
- `accessgrant-with-an-unrecognized-targettype` MUST — AccessGrant.target MUST be nil; targetLabel(_:tables:) falls back to the bare targetId, and grantDetail's own target …

## Edge Cases

- **Empty lists**: an empty `[ApiToken]`/`[StorageToken]`/`[AccessGroup]` result MUST render the rail's
  `emptyMessage` ("No API tokens yet.", "No tokens yet.", "No access lists yet.") rather than an error.
- **Row id exactly at the boundary**: a trimmed grant row id of exactly 36 characters MUST be accepted;
  37 characters MUST be rejected (`access-grant-row-id-length-limit`).
- **All-CRUD-false on create vs. on an existing grant**: both paths MUST reject identically
  (`access-grant-permission-required`); the existing-grant path additionally MUST NOT treat the
  all-false state as an implicit delete (`access-grant-save-never-deletes`) — a fixed regression the
  source's own comment documents ("Save with every toggle off used to DELETE the grant, silently and
  with no confirmation").
- **Scope catalogue unavailable at create time**: `ApiTokensRail` MUST disable create entirely
  (`api-tokens-catalogue-unavailable-disables-create`) rather than falling back to an unscoped/legacy
  token, because a `nil` scope selection is itself the broad-legacy-token footgun the disable exists to
  prevent.
- **Scope catalogue available but nothing selected**: MUST be rejected the same way as an unavailable
  catalogue (`api-tokens-empty-scope-rejected`) — for the same reason: an empty selection would silently
  mint the broadest possible token.
- **Concurrent duplicate-name creation (two clients, same bucket)**: `access-create-rejects-duplicate-name-client-side`'s
  pre-check only sees the `existing` list snapshot the caller supplied when it built the form; two
  concurrent creates racing past that check both reach `dataSource.create(bucketID:_:)`, and the loser
  is caught by `access-create-conflict-message`'s server-side `HubError.conflict` handling — the
  client-side check is an early UX shortcut, not the actual concurrency guard.
- **Everyone group protections apply narrowly**: only `name` (rename) and delete are blocked for the
  everyone group (`access-everyone-name-locked`, `access-everyone-delete-blocked`); its `description`
  remains editable, and its grants/members-viewing (but not members-editing,
  `access-everyone-members-is-notice`) remain reachable like any other group.
- **`lastUsed`/`expires` double fallback**: when the field itself is `nil`, both rails show
  `"never used"`/`"never"`; when the field is a non-nil but unparseable ISO string, `HubDates.display`'s
  own internal fallback (`"—"`) applies instead — two different fallback strings reachable from the
  same UI field depending on which condition holds.
- **`AccessCRUD.init(crud:)` with garbage input**: an input string like `"x,y,z"` (no recognized
  letters) MUST NOT throw; it parses to a fully-`false` `AccessCRUD` (`isEmpty == true`), since parsing
  is a case-insensitive substring match against `{"C","R","U","D"}` with no validation that every token
  is recognized.
- **`AccessMemberType` from an unrecognized `memberType` string**: `AccessGroupMember.type` MUST be
  `nil` and `typeTitle` MUST fall back to the raw `memberType` string; `membersLevel`'s row falls back to
  `"questionmark.circle"` for `systemImage`.
- **`AccessGrant` with an unrecognized `targetType`**: `AccessGrant.target` MUST be `nil`;
  `targetLabel(_:tables:)` falls back to the bare `targetId`, and `grantDetail`'s own target line falls
  back to `"{targetType} · {targetId}"` — a different fallback string from `targetLabel`'s, since the
  two format the unknown case independently. Saving that grant MUST throw
  `access-grant-unknown-target-blocked-on-save`'s error rather than silently upserting with a
  meaningless `targetType`.
- **Member id / row id with no client-side format validation**: `memberSpec`'s `memberId` field accepts
  any non-blank, trimmed string with no pattern check (unlike `StorageTokensRail`'s `Slug`-validated
  `name`); member identifiers are caller-supplied external ids (user/org/persona/app/token ids), not a
  slug this component mints.
- **Offline or transport failure from any data source**: every operation propagates the resulting
  `HubError.offline`/`.transport(...)` unchanged (through `HubError.wrap`, or, for
  `StorageTokensRail`'s create path, through the "any other `HubError`" branch of
  `storage-tokens-create-error-tiering`); none of the four types retries, queues, or caches a request to
  paper over a failure — a failed `child(...)` call simply throws, and the caller decides whether to
  retry.
