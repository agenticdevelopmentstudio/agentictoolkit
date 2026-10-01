---
id: 65fbb2b1-ca41-499f-ac03-7ecc0e206dcc
title: Authentication Client
domain: agentictoolkit://cookbook/adh/hub/security/authentication-client
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: "The client-side contract for personal API tokens, storage tokens, and per-ecosystem bucket access lists: a root routing surface, a mint/reveal-once/revoke lifecycle for both token kinds, and a groups/members/grants tree for bucket access lists."
platforms:
- swift
- macos
- ios
tags:
- authentication
- api-tokens
- storage-tokens
- access-control
- hub
depends-on: []
related: []
references:
- packages/apple/AgenticToolkit/Hub/Features/Authentication/AccessListsTopic.swift
- packages/apple/AgenticToolkit/Hub/Features/Authentication/ApiTokensRail.swift
- packages/apple/AgenticToolkit/Hub/Features/Authentication/AuthenticationModels.swift
- packages/apple/AgenticToolkit/Hub/Features/Authentication/AuthenticationModule.swift
- packages/apple/AgenticToolkit/Hub/Features/EcosystemConfig/StorageTokensRail.swift
- packages/apple/AgenticToolkit/Hub/Features/EcosystemConfig/EcosystemConfigModels.swift
approved-by: ''
approved-date: ''
---

# Authentication Client

## Overview

Four independent roles, plus one sibling role, form the client-side contract for everything the Hub's
"Authentication" surface manages: a **root module** is the hierarchical-detail root — "Tokens" — that
routes to two child rails and an explainer; an **API tokens rail** mints, lists, reveals-once, and
revokes the caller's personal API tokens (`tmp_…`, scoped by REST path); a **storage tokens rail**
(shared with a separate ecosystem-configuration feature) does the same for storage tokens (`adh_…`,
each its own principal with one isolated bucket), parameterized by an optional ecosystem id so the
identical rail serves both the caller's own tokens (no ecosystem given) and a specific ecosystem's
tokens; and an **access lists topic** is a separate topic provider — the "Access" product-rail topic —
managing bucket access-control lists (groups), their members, and their create/read/update/delete
grants, nested three levels deep. A shared models file holds the wire types and the four data-source
contracts (for API tokens, bucket access, and storage tokens) that all four roles depend on but never
implement themselves — every network call is delegated to an injected data source, and every thrown
error is normalized to a single named error type before it reaches a caller. The access lists topic is
not reachable from the root module's tree — the two share vocabulary (the named error type, a shared
form specification shape, reveal-once secrets) but are wired into the app as two independent entry
points.

## Behavioral Requirements

**Root routing**

- **root-tokens-level**: The root level MUST be titled "Tokens" with exactly three items, in order:
  `"api"` ("API tokens"), `"storage"` ("Storage tokens", with a divider after it), and `"about"` ("About
  tokens"), and MUST set an empty list-empty message and no create action (the level itself offers no
  create action; creation happens one level down, inside each rail).
- **root-path-routing**: Routing a path MUST send a path whose first item's id is `"api"` to the API
  tokens rail with the remaining path, `"storage"` to the storage tokens rail with the remaining path
  and no ecosystem given, and `"about"` with an empty remaining path to a read-only notice detail
  showing the module's overview message; an empty path MUST return the root level itself.
- **root-unknown-routes-empty**: Routing a path MUST return an empty result for any first-item id other
  than `"api"`/`"storage"`/`"about"`, and for `"about"` with a non-empty remaining path.
- **root-storage-uses-personal-scope**: The root's `"storage"` route MUST always route into the storage
  tokens rail with no ecosystem given, so the root "Storage tokens" section lists only the caller's own
  (workspace) storage tokens, never an ecosystem's.

**Personal API tokens**

- **api-tokens-list-sorted-by-name**: The token list MUST be sorted by name using a case-insensitive,
  locale-aware comparison (ascending).
- **api-tokens-list-item-shape**: Each row's identifier MUST be the token's id, its label the token's
  name, its sublabel `"\(prefix)… · \(scopeLine)"`, its icon a key glyph, and it MUST lead to a detail
  view.
- **api-tokens-scope-line-legacy-fallback**: A token's scope line MUST be `"legacy"` when its scope is
  absent or empty, otherwise the scopes joined with `", "`.
- **api-tokens-catalogue-fetched-per-open**: The "New API token" create action MUST fetch the scope
  catalogue fresh every time the create form is opened; it MUST NOT reuse a catalogue fetched by an
  earlier open.
- **api-tokens-catalogue-unavailable-disables-create**: When fetching the scope catalogue fails, the
  create form MUST present exactly one read-only field (labeled "Scope catalogue") and no save action,
  so the form can display an explanatory message but cannot mint a token.
- **api-tokens-create-fields**: The create form MUST present, in order: a required `name` text field, a
  read-only scope-help field, one toggle field per catalogue prefix (labeled with the bare prefix), a
  "Read-only (GET/HEAD only)" toggle, and an expiration date field.
- **api-tokens-empty-scope-rejected**: The create action MUST reject with a validation error naming the
  "choose at least one scope" message when no scope toggle is selected, regardless of the read-only
  toggle's value, and MUST NOT proceed to create the token in that case.
- **api-tokens-scope-derivation**: The derived scope MUST include, in catalogue order, every prefix
  whose toggle is on, each suffixed `":read"` when the read-only toggle is on and left bare otherwise,
  and MUST be considered absent when no prefix toggle is on.
- **api-tokens-name-trimmed**: The create action MUST trim leading/trailing whitespace from the `name`
  field before submitting the create request.
- **api-tokens-reveal-on-create**: On a successful create, the returned plaintext secret MUST be stored
  keyed by the new token's id, for one-time display.
- **api-tokens-reveal-once**: Resolving any path MUST first expire the previously revealed secret unless
  the requested detail's id equals the one currently shown; expiring MUST remove the revealed secret and
  clear the "currently revealed" marker, and MUST leave both untouched when the same detail is
  re-rendered.
- **api-tokens-detail-field-order**: The detail view MUST list read-only fields in the order `name`,
  `prefix`, `scope`, `created`, `lastUsed`, `expires`, followed by the secret and a notice field only
  when a revealed secret exists for that token.
- **api-tokens-detail-fallbacks**: The detail view MUST render `scope` as `"legacy (curated-only)"` when
  the token's scope is absent or empty (else the scopes joined by newlines), `lastUsed` as `"never
  used"` when absent, and `expires` as `"never"` when absent.
- **api-tokens-revoke**: The detail's delete action MUST be titled "Revoke token" with confirmation text
  `Revoke API token "{name}"? Anything using it will stop working.`, MUST revoke the token, and on
  success MUST clear its revealed secret.
- **api-tokens-unknown-path-empty**: Resolving a path MUST return an empty result when the path names
  exactly one segment and no token matches it, and for any path with more than one segment.
- **api-tokens-errors-wrapped**: Every call into the token data source MUST have its errors normalized
  to the single named error type (the create action's own two validation checks above already throw
  that type directly, since creating and revoking are the only throwing operations besides them).

**Storage tokens (shared with a separate ecosystem-configuration feature)**

- **storage-tokens-ecosystem-scoped**: Every storage-tokens operation (listing, level, create form,
  detail) MUST take an optional ecosystem identifier and pass it through unchanged to the underlying
  list/create/revoke calls; absent means the caller's own (workspace) tokens, present means that
  ecosystem's tokens.
- **storage-tokens-list-sorted-by-slug**: The token list MUST be sorted by a raw ordinal comparison on
  slug (NOT a locale-aware comparison, unlike the personal API tokens list's name sort).
- **storage-tokens-list-item-shape**: Each row's label MUST be the token's identifier or, when absent,
  its slug; sublabel `"\(prefix)… · \(bucketRdid ?? "no bucket")"`; icon a drive glyph; and it MUST lead
  to a detail view.
- **storage-tokens-about-varies-by-scope**: The explanatory "about" text MUST vary depending on whether
  an ecosystem was given: one variant when none was given, a different variant when one was; the create
  form's "about" value MUST come from this text.
- **storage-tokens-name-pattern**: The create form's `name` field MUST enforce the shared identifier
  pattern (see Configuration) with its associated violation message.
- **storage-tokens-create-body-shape**: The create action MUST trim the `name` field, MUST pass a
  non-blank version of the `description` field (absent when blank/missing), and MUST leave the request
  body's own `ecosystemId` field unset unconditionally — the actual ecosystem scope is conveyed
  exclusively through the separate ecosystem argument passed alongside the request, never through the
  body's own field.
- **storage-tokens-create-conflict-message**: The create action MUST catch a name-conflict error
  specifically and rethrow it as a validation error naming a "name already taken" message.
- **storage-tokens-create-error-tiering**: The create action MUST rethrow any other error from the named
  error type unchanged, and MUST convert any other kind of failure into an "unexpected" case of the
  named error type carrying a "creation failed" message — a three-way handling distinct from the single
  normalize-and-wrap pattern every other create/update/delete path in this component uses.
- **storage-tokens-reveal-on-create**: On success, the create action MUST store the returned plaintext
  secret keyed by the new token's id, mirroring `api-tokens-reveal-on-create`.
- **storage-tokens-reveal-once**: Resolving any path MUST first expire the previously revealed secret,
  with the same drop/keep semantics as `api-tokens-reveal-once`.
- **storage-tokens-detail-field-order**: The detail view MUST list read-only fields in the order `name`,
  `identifier`, `prefix`, `bucket`, `description`, `created`, `lastUsed`, `expires`, followed by the
  secret/notice fields only when a revealed secret exists.
- **storage-tokens-detail-fallbacks**: The detail view MUST render `name` as the token's slug (not its
  identifier), `identifier` as the token's identifier or an em dash when absent, `bucket` as the bucket
  identifier or `"no bucket"`, and `description` as an em dash when empty.
- **storage-tokens-revoke**: The detail's delete action MUST be titled "Revoke token" with confirmation
  text `Revoke storage token "{slug}"? Anything using it will lose access to its bucket.`, MUST revoke
  the token, and on success MUST clear its revealed secret.
- **storage-tokens-unknown-path-empty**: Resolving a path MUST return an empty result when the path
  names exactly one segment and no token matches, and for any path with more than one segment.

**Access lists**

- **access-topic-entry**: The access lists entry point MUST have identifier `"access"`, label
  `"Access"`, and a lock-shield icon.
- **access-groups-scoped-to-ecosystem**: Resolving any path within this topic MUST filter the fetched
  groups down to those belonging to the given ecosystem before building the list level or resolving the
  first path segment against it.
- **access-groups-sort-order**: The group list MUST be sorted first by the owning bucket's
  case-insensitive, locale-aware name (falling back to the raw bucket identifier when no bucket in the
  supplied bucket list matches), then by whether the group is the built-in "everyone" group (that group
  first within its bucket), then by the group's own case-insensitive, locale-aware name.
- **access-create-requires-bucket**: The "New access list" action MUST reject with a validation error
  (`"Choose a bucket."`) when no bucket is selected.
- **access-create-rejects-duplicate-name-client-side**: The create action MUST reject, before submitting
  the create request, a trimmed name that case-insensitively matches an existing group's name within the
  same bucket, with `An access list named "{name}" already exists in that bucket.`.
- **access-create-conflict-message**: The create action MUST catch a name-conflict error from the create
  request and rethrow it as a validation error (`An access list named "{name}" already exists.`); any
  other error MUST be normalized through the shared error-wrapping.
- **access-group-level-composition**: A group's detail level MUST contain exactly three items —
  `settings` (leads to a detail view), `members` (leads to a list view, sublabel "Applies to everyone"
  for the everyone group else "{N} member(s)"), `grants` (leads to a list view, sublabel "{N}
  grant(s)") — and MUST set an empty list-empty message and no create action.
- **access-everyone-name-locked**: The settings detail MUST render `name` as a non-editable read-only
  field (plus a read-only help note explaining that the built-in "everyone" list applies to every
  principal and can't be renamed) for the everyone group, and as an editable required text field
  otherwise.
- **access-everyone-delete-blocked**: The settings detail MUST omit the delete action and instead append
  a read-only note field explaining that the everyone group can't be deleted, for the everyone group.
- **access-settings-save-name**: The settings save action MUST leave `name` unset when saving the
  everyone group, and otherwise send the trimmed `name` field's value.
- **access-settings-delete**: For a non-everyone group, the delete action MUST be titled "Delete access
  list" with confirmation text `Delete access list "{name}"? Its members and grants will be removed.`
  and MUST delete the group.
- **access-everyone-members-is-notice**: Resolving the `"members"` segment under the everyone group MUST
  return a read-only notice explaining that its membership can't be edited, never the editable members
  level.
- **access-members-list-item-shape**: Each member row's identifier MUST be the member row's id, label
  the member's identifier, sublabel the member type's title, and icon the member type's glyph or a
  question-mark glyph when the type is unrecognized.
- **access-member-type-options**: The "Add member" form's type field MUST offer exactly the member-type
  options, in a fixed order (`user`, `organization`, `persona`, `application`, `token`), each option's
  value being that type's wire value — including `application`, whose wire value is the literal string
  `"app"`, not `"application"`.
- **access-member-add-required-fields**: The "Add member" action MUST reject with a validation error
  (`"Choose a type."`) when the type field doesn't decode to a recognized member type, and MUST trim the
  member-identifier field before submitting.
- **access-member-add-conflict-message**: The add-member action MUST catch a conflict error and rethrow
  it as a validation error (`"That member is already in this access list."`).
- **access-member-remove**: The member detail's delete action MUST be titled "Remove member" with
  confirmation text `Remove {typeTitle} "{memberId}" from this access list?` and MUST remove the member.
- **access-grants-list-item-shape**: Each grant row's label MUST be the resolved target label, and its
  sublabel the grant's permission summary.
- **access-grant-target-label**: The target label MUST be `"Whole bucket"` for a bucket-wide target, the
  matching table's name (or the bare target identifier when no table matches its id) for a bucket-type
  target, `"Row {targetId}"` for a row target, and the bare target identifier when the target is
  unrecognized.
- **access-grant-target-options-shrink**: The "Add grant" form's target field MUST offer `"Whole
  bucket"` only while no existing grant targets the whole bucket; MUST offer `"Bucket type"` only while
  at least one table has no existing grant targeting it; and MUST always offer `"Row"`.
- **access-grant-target-required**: The "Add grant" action MUST reject with a validation error
  (`"Choose a target."`) when the target field doesn't decode to a recognized target type.
- **access-grant-bucket-type-required**: When the target is a bucket type, the action MUST reject with a
  validation error (`"Choose a bucket type."`) when the bucket-type field is blank.
- **access-grant-row-id-required**: When the target is a row, the action MUST trim the row-id field and
  reject with a validation error (`"Enter a row id."`) when the trimmed value is blank.
- **access-grant-row-id-length-limit**: When the target is a row, the action MUST reject with a
  validation error (`"Row id must be 36 characters or fewer."`) when the trimmed row id's length
  (counted in user-perceived characters, not bytes) exceeds 36; a length of exactly 36 MUST be accepted.
- **access-grant-permission-required**: Both the "Add grant" action and an existing grant's "Save"
  action MUST reject with a validation error (`"Choose at least one permission."`) when every
  create/read/update/delete toggle is off.
- **access-grant-save-never-deletes**: Saving an existing grant with every permission toggle off MUST
  NOT delete the grant (MUST reject with `access-grant-permission-required`'s error instead); a grant
  MUST be removable only through its own "Remove grant" action.
- **access-grant-remove**: The grant detail's delete action MUST be titled "Remove grant" with
  confirmation text `Remove the grant for {label}?` and MUST remove the grant.
- **access-grant-unknown-target-blocked-on-save**: Saving an existing grant whose target is unrecognized
  MUST reject with a validation error (`Unknown grant target "{targetType}".`) rather than attempting to
  save it.
- **access-crud-serialization**: The permission set MUST serialize as a comma-separated, upper-case
  subset of `"C"`,`"R"`,`"U"`,`"D"` in that fixed order (only the granted permissions present, `""` when
  none); parsing MUST read a comma-separated string case-insensitively, trimming whitespace around each
  token.
- **access-unknown-path-empty**: Resolving a path MUST return an empty result for any group id, second
  path segment, or member/grant row id that doesn't match the currently fetched
  groups/detail/members/grants.
- **access-detail-refetches-every-call**: Resolving a path MUST re-fetch the bucket list, the group
  list, and — whenever the path is non-empty — the group detail and bucket-table list on every call;
  none of the four MUST be cached across calls.

**Shared across all four roles**

- **error-domain-is-hub-error**: Every one of the four roles MUST surface only the shared named error
  type to its caller; the root module, API tokens rail, and access lists topic achieve this by
  normalizing every data-source error through the shared error-wrapping helper, while the storage tokens
  rail's create path uses the three-way handling in `storage-tokens-create-error-tiering` instead — that
  divergence is intentional and MUST be preserved, not unified, when this component is ported or
  refactored.

**Security**

- **security-secret-not-persisted**: Neither rail MUST write a revealed plaintext secret to disk, to a
  settings store, or to a secure credential store; the revealed-secrets store is a plain in-memory
  mapping with no backing store.
- **security-secret-single-source**: The plaintext secret MUST be obtainable only from the response of
  the create call; no operation in this contract re-fetches or re-derives a previously issued secret
  once its reveal has expired (`api-tokens-reveal-once` / `storage-tokens-reveal-once`).
- **security-unauthorized-propagates**: An unauthorized or forbidden error thrown by any data source
  MUST propagate unchanged to the caller through the shared error-wrapping helper rather than being
  caught, retried, or downgraded locally.
- **security-revocation-is-the-response**: The only way this component withdraws a previously granted
  credential or permission is outright removal — revoking a token, or removing a member/grant for
  access — MUST NOT offer any "soft-disable" or partial-trust intermediate state.

## Appearance

Not applicable — this is the client-side token/access-list management contract (the root module, API
tokens rail, storage tokens rail, and access lists topic together), not a visual component.

## States

Not applicable — this is the client-side token/access-list management contract, not a visual component;
the level/detail values it returns are consumed by a separate presentation layer that owns any
loading/error/empty visual state.

## Accessibility

Not applicable — this is the client-side token/access-list management contract, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| auth-client-001 | root-tokens-level, root-path-routing | Resolving an empty path on the root module | A level titled "Tokens" with items `api`, `storage`, `about` in that order |
| auth-client-002 | root-storage-uses-personal-scope | Resolving the `storage` path segment against a data source that records calls | The list call is observed with no ecosystem given |
| auth-client-003 | root-unknown-routes-empty | Resolving a path whose first segment is `bogus` | An empty result |
| auth-client-004 | api-tokens-empty-scope-rejected | Invoking the create action with every scope toggle off and the read-only toggle on | Throws a validation error naming the "choose at least one scope" message; the create request is never sent |
| auth-client-005 | api-tokens-scope-derivation | The same create action with the `read` scope toggle on and the read-only toggle on | The derived scope is `["read:read"]` |
| auth-client-006 | api-tokens-catalogue-unavailable-disables-create | The scope catalogue fetch fails; the create form is built anyway | The returned form has one read-only notice field and no save action |
| auth-client-007 | api-tokens-reveal-on-create, api-tokens-detail-field-order | A create succeeds returning secret `"tmp_abc"`, then its detail is rendered | Detail includes the secret `"tmp_abc"` and a reveal notice |
| auth-client-008 | api-tokens-reveal-once | After 007, a different token's detail is resolved | The revealed secret for the created token is removed; a later rendering of its detail shows no secret/notice field |
| auth-client-009 | api-tokens-reveal-once | After 007, the same token's detail is resolved again | The revealed secret is unchanged; the secret is still shown |
| auth-client-010 | api-tokens-revoke | The delete action is invoked for a token whose secret is currently revealed | The token is revoked; its revealed secret is cleared afterward |
| auth-client-011 | storage-tokens-name-pattern | The create form's `name` field validated with input `"My Token!"` | Field rejected with the shared pattern's violation message |
| auth-client-012 | storage-tokens-create-conflict-message | The create request fails with a name-conflict error | The create action throws a validation error naming the "name already taken" message |
| auth-client-013 | storage-tokens-create-error-tiering | The create request fails with an unrelated, non-domain error | The create action throws an "unexpected" error naming a "creation failed" message |
| auth-client-014 | storage-tokens-list-sorted-by-slug | Tokens with slugs `["zeta", "alpha"]` and names that would sort oppositely under a locale-aware comparison | The list appears in raw slug order: `alpha`, `zeta` |
| auth-client-015 | storage-tokens-about-varies-by-scope | The "about" text requested with no ecosystem given, versus with ecosystem `"eco-1"` given | The "no ecosystem" variant versus the "with ecosystem" variant respectively |
| auth-client-016 | storage-tokens-create-body-shape | The create action invoked with ecosystem `"eco-1"` given and a description of only whitespace | The request body's `description` is absent; its `ecosystemId` field is unset; the create call is still made with `"eco-1"` as the separate ecosystem argument |
| auth-client-017 | access-groups-scoped-to-ecosystem | Groups fetched for two ecosystems; resolving an empty path scoped to ecosystem A | The resulting list includes only ecosystem A's groups |
| auth-client-018 | access-groups-sort-order | Two groups in the same bucket, one the everyone group and one a custom group, both alphabetically after other-bucket groups | The everyone group's row precedes the custom group's row within that bucket |
| auth-client-019 | access-create-rejects-duplicate-name-client-side | The create action invoked with name `"Editors"` while an existing group named `"editors"` (different case) already exists in the same bucket | Throws a validation error with the "already exists in that bucket" message; the create request is never sent |
| auth-client-020 | access-everyone-name-locked, access-everyone-delete-blocked | The settings detail rendered for the everyone group | The `name` field is read-only; no delete action is present; a note field explains the group can't be deleted |
| auth-client-021 | access-everyone-members-is-notice | Resolving the `"members"` segment under the everyone group | A read-only notice explaining membership can't be edited, with no save/delete actions |
| auth-client-022 | access-member-type-options | The "Add member" form's type field options | Values in order: `"user"`, `"organization"`, `"persona"`, `"app"`, `"token"` |
| auth-client-023 | access-member-add-conflict-message | Adding a member fails with a conflict error | The add action throws a validation error (`"That member is already in this access list."`) |
| auth-client-024 | access-grant-target-options-shrink | Existing grants already include a whole-bucket grant and a bucket-type grant for every table | The "Add grant" form's target options contain only `"Row"` |
| auth-client-025 | access-grant-row-id-length-limit | The action invoked with target `"row"` and a trimmed row id of exactly 36 characters, then 37 characters | The 36-character id is accepted (the save proceeds); the 37-character id throws a validation error (`"Row id must be 36 characters or fewer."`) |
| auth-client-026 | access-grant-permission-required, access-grant-save-never-deletes | An existing grant's "Save" action invoked with all four permission toggles off | Throws a validation error (`"Choose at least one permission."`); the grant is neither saved nor removed |
| auth-client-027 | access-crud-serialization | Serializing a permission set with create and update granted, read and delete not; parsing the string `" r , c "` | Serializes to `"C,U"`; parsing yields a permission set with read and create granted, update and delete not |
| auth-client-028 | access-grant-target-label | Resolving the target label for a bucket-type grant with an unrecognized target identifier against an empty table list | Returns the bare target identifier (no table matched) |
| auth-client-029 | access-detail-refetches-every-call | Two consecutive resolutions of the same group's path against a data source that changes its detail response between calls | The second call's group level reflects the changed response, proving no caching |

## Edge Cases

- **Empty lists**: an empty list of tokens or access lists MUST render the rail's empty message ("No
  API tokens yet.", "No tokens yet.", "No access lists yet.") rather than an error.
- **Row id exactly at the boundary**: a trimmed grant row id of exactly 36 characters MUST be accepted;
  37 characters MUST be rejected (`access-grant-row-id-length-limit`).
- **All-CRUD-false on create vs. on an existing grant**: both paths MUST reject identically
  (`access-grant-permission-required`); the existing-grant path additionally MUST NOT treat the
  all-false state as an implicit delete (`access-grant-save-never-deletes`) — a fixed regression the
  source's own comment documents ("Save with every toggle off used to DELETE the grant, silently and
  with no confirmation").
- **Scope catalogue unavailable at create time**: the API tokens rail MUST disable create entirely
  (`api-tokens-catalogue-unavailable-disables-create`) rather than falling back to an unscoped/legacy
  token, because an absent scope selection is itself the broad-legacy-token footgun the disable exists
  to prevent.
- **Scope catalogue available but nothing selected**: MUST be rejected the same way as an unavailable
  catalogue (`api-tokens-empty-scope-rejected`) — for the same reason: an empty selection would silently
  mint the broadest possible token.
- **Concurrent duplicate-name creation (two clients, same bucket)**:
  `access-create-rejects-duplicate-name-client-side`'s pre-check only sees the snapshot of existing
  groups the caller supplied when it built the form; two concurrent creates racing past that check both
  reach the create request, and the loser is caught by `access-create-conflict-message`'s server-side
  conflict handling — the client-side check is an early UX shortcut, not the actual concurrency guard.
- **Everyone group protections apply narrowly**: only `name` (rename) and delete are blocked for the
  everyone group (`access-everyone-name-locked`, `access-everyone-delete-blocked`); its `description`
  remains editable, and its grants/members-viewing (but not members-editing,
  `access-everyone-members-is-notice`) remain reachable like any other group.
- **`lastUsed`/`expires` double fallback**: when the field itself is absent, both rails show "never
  used"/"never"; when the field is present but an unparseable date string, the shared date-formatting
  fallback ("—") applies instead — two different fallback strings reachable from the same field
  depending on which condition holds.
- **Parsing a permission string with garbage input**: an input string like `"x,y,z"` (no recognized
  letters) MUST NOT throw; it parses to a fully-ungranted permission set, since parsing is a
  case-insensitive substring match against `{"C","R","U","D"}` with no validation that every token is
  recognized.
- **A member with an unrecognized type string**: the member's type MUST resolve to an unrecognized type,
  falling back to the raw string for its title; its row falls back to a question-mark glyph.
- **A grant with an unrecognized target type**: the grant's target MUST resolve to an unrecognized
  target; the target label falls back to the bare target identifier, and the grant detail's own target
  line falls back to `"{targetType} · {targetId}"` — a different fallback string from the list label's,
  since the two format the unknown case independently. Saving that grant MUST throw
  `access-grant-unknown-target-blocked-on-save`'s error rather than silently saving it.
- **Member id / row id with no client-side format validation**: the "Add member" form's identifier
  field accepts any non-blank, trimmed string with no pattern check (unlike the storage tokens rail's
  pattern-validated `name`); member identifiers are caller-supplied external ids (user/org/persona/app/
  token ids), not an identifier this component mints.
- **Offline or transport failure from any data source**: every operation propagates the resulting
  offline or transport failure unchanged (through the shared error-wrapping helper, or, for the storage
  tokens rail's create path, through the "any other error" branch of
  `storage-tokens-create-error-tiering`); none of the four roles retries, queues, or caches a request to
  paper over a failure — a failed resolution simply throws, and the caller decides whether to retry.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| API tokens collaborator | injected data source | none (required) | The root module's collaborator for personal API tokens; wrapped internally into the API tokens rail. |
| Storage tokens collaborator | injected data source | none (required) | The root module's collaborator for storage tokens; wrapped internally into the storage tokens rail. |
| API tokens rail's data source | injected data source | none (required) | Backs listing, fetching the scope catalogue, creating, and revoking personal API tokens. |
| Storage tokens rail's data source | injected data source | none (required) | Backs listing, creating, and revoking storage tokens, each call scoped by the given ecosystem. |
| Access lists topic's data source | injected data source | none (required) | Backs listing/fetching groups, create/update/delete, add/remove member, and upsert/remove grant. |
| Access lists topic's buckets collaborator | injected data source | none (required) | Supplies the bucket list/names and bucket-table list this topic renders alongside access lists; owned by the separate Buckets feature. |
| Ecosystem scope (storage tokens calls) | optional identifier | caller-supplied per call | Absent selects the caller's own (workspace) tokens; present selects that ecosystem's tokens. |
| Scope catalogue (create form) | list of strings, optional | caller-supplied per call | The scope catalogue for this create form; absent disables the save action entirely. |
| Row id length limit | integer literal `36` | fixed | Inline bound in the access lists topic's grant save action; not a named constant or injectable configuration. |
| Shared identifier pattern | string constants | fixed | Shared identifier rule (one lowercase letter or digit, optionally followed by lowercase letters, digits, or hyphens and ending in a letter or digit) plus its violation message, enforced on the storage tokens rail's `name` field. |

## Deep Linking

Not applicable: none of the four roles registers a URL scheme, universal link, or platform-level
user-activity record; navigation is entirely through path arrays supplied by the presentation layer.

## Localization

The source contains no localization mechanism (no string-catalog lookup, no resource-bundle strings
file, no localized-string macro) — every user-facing string below is a hardcoded English literal, per
Extra Rule 14 stated here as fact rather than as a gap:

| String Key | Default (en) | Context |
|-----------|---------------|---------|
| — | `Choose at least one scope. An empty selection mints a broad legacy token, not the scoped one you intended.` | API tokens rail: no-scope-selected message |
| — | `Couldn't load the scope catalogue. Token creation is disabled until it loads — otherwise an empty selection would silently mint a broad legacy token instead of the scoped one you intended.` | API tokens rail: catalogue-unavailable message |
| — | `Revoke API token "{name}"? Anything using it will stop working.` | API tokens rail: revoke confirmation |
| — | `That name is already in use. Token names stay reserved even after revoke — pick a different one.` | Storage tokens rail: name-taken message |
| — | `Revoke storage token "{slug}"? Anything using it will lose access to its bucket.` | Storage tokens rail: revoke confirmation |
| — | `An access list named "{name}" already exists in that bucket.` | Access lists topic: create validation |
| — | `The built-in "everyone" list applies to every principal and can't be renamed.` | Access lists topic: everyone-group name help |
| — | `That member is already in this access list.` | Access lists topic: member-add conflict |
| — | `Row id must be 36 characters or fewer.` | Access lists topic: grant validation |
| — | `Choose at least one permission.` | Access lists topic: grant validation (create and save) |

(This is a representative sample of the roughly two dozen literals across the underlying source, not the
full set; every one of them follows the same pattern — a plain string with no key, no catalog entry, and
no pluralization/formatting rule beyond ad hoc string interpolation.)

## Accessibility Options

Not applicable: this is the client-side token/access-list management contract with no UI of its own, so
it responds to no reduced-motion, increased-contrast, or color-differentiation setting.

## Feature Flags

Not applicable: none of the four roles reads a feature-flag key or contains conditional feature-gating
logic (a sibling feature-flags collaborator manages a *different* ecosystem-level feature — flags an
admin configures — and is not consulted by, or related to, this component).

## Analytics

Not applicable: the source contains no analytics/event-emission call.

## Privacy

- **Data collected**: a plaintext bearer secret is returned exactly once, in the response to a
  successful create call.
- **Storage**: none of the four roles persists the secret; the revealed-secrets store is an in-memory
  mapping owned by the rail instance, with no file, settings-store, or secure-credential-store write
  anywhere in this component.
- **Transmission**: this component never transmits the secret itself — it receives it once from the
  create response and places it into a read-only field for on-screen display; actual network
  transmission is the injected data source's concern, out of scope of these roles.
- **Retention**: bounded by two independent mechanisms — the reveal-once rule
  (`security-secret-single-source`), which drops a secret from the revealed-secrets store the moment
  navigation moves away from its detail, and the instance's own lifetime (the store holds nothing once
  the instance goes away, e.g. on app relaunch).
- **Disclosure safeguard**: the two wire shapes that carry a raw plaintext secret in their `token`
  field declare no custom string-conversion override, so their default description includes the secret
  in full. Neither rail logs or prints the create-response value; both store only its secret into the
  revealed-secrets map. A port MUST NOT log these values.

## Logging

Not applicable: the source contains no logging call of any kind.

## Platform Notes

- **SwiftUI**: not applicable to these files directly — all four types return `HTDVLevel`/`HTDVDetail`/
  `FormSpec` values consumed by the shared `FormViewController`/HTDV presentation layer; a SwiftUI-based
  presenter would consume the same values unchanged, since none of the four imports SwiftUI or performs
  any rendering itself.
- **AppKit / UIKit**: this is the source. `AuthenticationModule.swift`, `ApiTokensRail.swift`,
  `AuthenticationModels.swift`, and `AccessListsTopic.swift` live in the `Hub` module of the
  `AgenticToolkitHub-macOS`/`AgenticToolkitHub-iOS` targets (both declared in `project.yml`, sharing one
  source set); `StorageTokensRail.swift` lives in the sibling `EcosystemConfig` feature folder of the
  same module. None of the five files imports `AppKit` or `UIKit` directly — each is plain
  `AgenticToolkitHTDV` + `Foundation`, with the platform-specific `NSViewController`/`UIViewController`
  split handled entirely inside `FormViewController` (a different file), one level below where these
  types operate. All four roles (`AuthenticationModule`, `ApiTokensRail`, `StorageTokensRail`,
  `AccessListsTopic`) are declared `@MainActor final class`: every stored property (`revealedSecrets`,
  `revealedOnScreen`) and method is read and written only on the main actor, and none declares any lock,
  queue, or other synchronization primitive because none is needed under that isolation (confirmed by
  source declaration — no runtime test needed; this is a compile-time fact, not a Conformance Test
  Vector). Every wire model in `AuthenticationModels.swift` and the storage-token types in
  `EcosystemConfigModels.swift` (`ApiToken`, `ApiTokenCreated`, `ApiTokenCreate`, `AccessGroup`,
  `AccessGroupMember`, `AccessGrant`, `AccessGroupDetail`, `AccessCRUD`, `StorageToken`,
  `StorageTokenCreated`, `StorageTokenCreate`, etc.) is a `Codable, Hashable, Sendable` value type, so an
  instance MAY cross actor-isolation boundaries freely; the four `*DataSource` protocols
  (`ApiTokensDataSource`, `BucketAccessDataSource`, `StorageTokensDataSource`) are `AnyObject, Sendable`,
  so any conforming implementation MUST itself be safe to invoke from the main actor while doing its own
  work off it. Because `FormAction.perform`/`FormDeleteAction.perform` are plain `@Sendable ... async
  throws -> Void` closures (not `@MainActor`), every message constant a save or delete closure reads
  (`noScopeSelectedMessage`, `nameTakenMessage`, `createFailedMessage`) is declared `nonisolated`, and any
  mutation those closures make to a rail's `@MainActor`-isolated state (e.g., `revealedSecrets`) is
  hopped back onto the main actor explicitly (each of `ApiTokensRail` and `StorageTokensRail` does this
  with `await MainActor.run { self?.revealedSecrets[...] = ... }`).
- **Compose**: a Kotlin port would model each `Codable` struct (`ApiToken`, `AccessGroup`,
  `AccessGrant`, `StorageToken`, etc.) as an immutable `data class`; the four rails/topics as classes
  exposing `suspend fun` equivalents of `child(...)` returning a sealed `HtdvChild` class
  (`Level`/`Detail`/`Empty`); `HubError` as a Kotlin `sealed class` with the same eight cases, each
  computing its own `message`; `revealedSecrets` as a `MutableMap<String, String>` guarded by
  confinement to a single `Dispatchers.Main`-bound coroutine scope, mirroring `@MainActor`.
- **React/Web**: a TypeScript port would use `readonly`-field interfaces for the wire types, a
  discriminated-union `HubError` type (`{kind: "conflict", detail: string} | ...`) with a
  `hubErrorMessage()` helper mirroring `HubError.message`, and plain `async` functions returning
  `Promise<HtdvChild>` for each `child(...)`/`level(...)`/`detail(...)` equivalent; the reveal-once
  mechanic would need an explicit teardown (e.g., a router's `onBeforeRouteLeave`/`useEffect` cleanup
  keyed by the outgoing route's first path segment) to reproduce `expireRevealedSecret(unless:)`'s
  "same detail re-renders, anything else expires" rule, since there is no `@MainActor`-style confinement
  to lean on for correctness — the map mutation itself would need to happen on the same thread
  (JavaScript's single-threaded event loop already guarantees this, unlike a truly concurrent runtime).
- **WinUI 3**: a .NET port would model the wire types as `record`s (free structural equality, mirroring
  the Swift `Hashable` conformances) and the four rails/topics as classes with `async Task<HtdvChild>`
  methods, backed by an `HttpClient` + `System.Text.Json` implementation of each `*DataSource` protocol
  (`IApiTokensDataSource`, `IBucketAccessDataSource`, `IStorageTokensDataSource`) with method shapes
  matching the Swift protocols one-to-one (`Task<ApiToken[]> ListAsync()`,
  `Task<ApiTokenCreated> CreateAsync(ApiTokenCreate body)`, etc.); `revealedSecrets` as a
  `Dictionary<string, string>` field on a class instantiated per-window/per-`ContentDialog`, with the
  one-shot expiry implemented in the page's `OnNavigatedFrom` override (or the view model's disposal)
  rather than a `@MainActor`-checked property; `Slug.pattern`/`Slug.patternMessage` port directly to a
  `System.Text.RegularExpressions.Regex` constant plus a `TextBox` validation error string; UI-bound
  collections (the token/group/member/grant lists) become `ObservableCollection<T>` wrapped in a view
  model implementing `INotifyPropertyChanged`, with each list rebuilt (not incrementally patched) on
  every re-fetch, mirroring `access-detail-refetches-every-call`'s "no caching" rule.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Hub/Features/Authentication/` |

## Design Decisions

**Decision**: `StorageTokensRail` is a single class parameterized by an optional `ecosystemID`, shared
verbatim between `AuthenticationModule`'s "the caller's own tokens" use (`ecosystemID: nil`) and the
separate `EcosystemConfig` feature's "this ecosystem's tokens" use, rather than two separate types.
**Rationale**: the list/create/detail/revoke logic is identical in both cases — only the value passed to
`dataSource.list/create/revoke` and the `about`/level title text differ — so a shared class with the
`ecosystemID` threaded through every call avoids duplicating the reveal-once mechanic and the
create-error-tiering logic in two places.
**Approved**: pending

**Decision**: a token's plaintext secret is retained in `revealedSecrets` only until navigation departs
from the detail screen currently showing it, enforced by calling `expireRevealedSecret(unless:)` at the
top of every `child(...)` call rather than, say, on a timer or on view-disappear.
**Rationale**: per the source's own comment, retaining the secret "for the session made the notice a
lie" — the copy-once affordance (`ApplicationsTopic.revealMessage`) promises the secret disappears once
the reader has navigated away; tying the check to the navigation path itself (rather than a lifecycle
event the presentation layer would have to remember to call) means the guarantee holds regardless of
which presentation layer drives it.
**Approved**: pending

**Decision**: `ApiTokensRail.createSpec(scopes:)` disables its own save action entirely (a notice-only
form) when the scope catalogue fails to load, and separately rejects an empty scope selection when the
catalogue *did* load, rather than falling back to an unscoped ("legacy") token in either case.
**Rationale**: a `nil`/empty scope selection mints the *broadest* token this system can issue, not the
narrowest — the source's own comment calls this out explicitly as a footgun that was once unguarded when
the catalogue loaded successfully. Both guards exist to make the failure mode "creation is blocked" for
a reason the caller can see, rather than "a wide-open token was minted silently."
**Approved**: pending

**Decision**: saving an existing access grant with every CRUD toggle cleared is rejected with a
validation error, not treated as an implicit delete; a grant is removable only through its own explicit
"Remove grant" action.
**Rationale**: the source's own comment documents this as a fixed regression — the previous behavior
made a destructive action ("delete the grant") reachable through a button labelled "Save" with no
confirmation, "behind clearing the last checkbox." The current contract makes "no permissions selected"
an error identical to the one the create form already throws, and reserves actual deletion for the
button whose label and confirmation text say so.
**Approved**: pending

**Decision**: `StorageTokensRail`'s create path uses a three-way `catch` (rethrow a specific
`HubError.conflict` as a friendlier validation message, rethrow any other `HubError` unchanged, and
convert anything else into a fixed `HubError.unexpected(createFailedMessage)`) instead of the single
`HubError.wrap(_:)` call every other create/update/delete path in this component uses; `StorageTokensRail`
also sorts its list by raw `slug` rather than `localizedCaseInsensitiveCompare`d name, unlike
`ApiTokensRail`.
**Rationale**: both divergences are observed, deliberate facts of the current source, not oversights to
be silently unified — `slug` is a `Slug`-pattern-constrained ASCII identifier, so a locale-aware compare
buys nothing there, while a token's display `name` in `ApiTokensRail` is free-form caller text where
locale-aware ordering matters. This recipe states both divergences as requirements
(`storage-tokens-list-sorted-by-slug`, `storage-tokens-create-error-tiering`) rather than smoothing them
into the other rail's pattern.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [secure-storage](agenticdevelopercookbook://compliance/security#secure-storage) | passed | Security |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | partial | Security |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | partial | Privacy and Data |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |

`secure-storage` passes: no plaintext secret is ever written to disk, `UserDefaults`, or the Keychain by
this component — `revealedSecrets` is transient, in-memory, and actively self-expiring
(`security-secret-not-persisted`). `input-sanitization` is `partial`: the fields whose shape actually
matters downstream are validated (`Slug.pattern` on storage-token names, the 36-character row-id bound,
the required-field checks on every create/add form), but free-text fields like a group's or token's
`description` and a member's `memberId` are only trimmed, not pattern- or length-checked, leaving that
enforcement to the server. `explicit-error-handling` passes: every throwing path surfaces only
`HubError`, with the one intentional, documented divergence in `StorageTokensRail`'s create path
(covered above) rather than a silently swallowed exception. `no-hardcoded-strings` fails outright — see
Localization; there is no localization mechanism anywhere in these five files. `data-minimization` is
`partial`: `revealedSecrets` can hold more than one plaintext secret at once (every token created in a
session without its detail ever being opened keeps accumulating), and neither `ApiTokenCreated` nor
`StorageTokenCreated` carries a redaction safeguard against being logged or printed whole (the
Disclosure safeguard under Privacy). `idempotent-operations` passes for the one operation named that way in the
source: `upsertGrant(groupID:_:)` — calling it twice with the same `target`/`crud` body produces the
same end state each time, by design (`AccessGrantUpsert` is explicitly an upsert, not an append).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to adh/hub/security/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
