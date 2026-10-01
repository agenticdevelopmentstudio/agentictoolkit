---
id: 519d4419-8f80-478d-aa08-912b66bbe5cf
title: Hub Domain Applications
domain: agentictoolkit://cookbook/adh/hub/applications
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The client-side contract for the Hub''s Applications feature: CRUD/rename/grants/tokens
  operations, wire and domain data types for consumer kind and CRUD permission grants,
  and the feature''s rail navigation, identifier-rename/grant-rehoming sequence, and
  mint/reveal-once/revoke token lifecycle.'
platforms:
- swift
- macos
- ios
tags:
- hub
- applications
- access-control
- api-tokens
depends-on: []
related:
- agentictoolkit://cookbook/adh/hub/security/authentication-client
references:
- packages/apple/AgenticToolkit/Hub/Features/Applications/ApplicationsDataSource.swift
  (apple)
- packages/apple/AgenticToolkit/Hub/Features/Applications/ApplicationsModels.swift
  (apple)
- packages/apple/AgenticToolkit/Hub/Features/Applications/ApplicationsTopic.swift
  (apple)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitHubTests/ApplicationsTopicTests.swift
  (apple)
approved-by: ''
approved-date: ''
---

# Hub Domain Applications

## Overview

This is the client-side contract for the Hub's "Applications" product topic: an
applications data source is the interface every network call is delegated to; the
applications data model holds the wire types (application, application-create,
application-update, consumer kind, application token, application-token-created) plus
the domain-only, deliberately non-wire-serializable grant types (CRUD permissions,
table grant, schema grant); and the applications topic is the navigation controller
that resolves the rail path into list/detail panes for an application's Settings,
Bucket permissions, and Access tokens sections, using an injected buckets data source
to label and enumerate the buckets/tables a grant can target. Every thrown error is
normalized to the shared error type before it reaches a caller, and every token
secret this component ever holds is a transient, reveal-once-then-drop entry in an
in-memory dictionary — the same pattern the sibling Authentication feature
(`agentictoolkit://cookbook/adh/hub/security/authentication-client`) uses for its own
API and storage tokens.

## Behavioral Requirements

**Data source contract**

- **applications-listing**: The list operation MUST return the applications belonging
  to the given ecosystem, asynchronously, and MUST throw rather than return a partial
  or empty result on failure.
- **application-lookup**: The get operation MUST return the single application
  matching the given id, or throw (a not-found is signaled as an error, not an
  optional value).
- **application-creation**: The create operation MUST create and return a new
  application from an application-create body.
- **application-update**: The update operation MUST apply an application-update
  (each of whose `slug`/`displayName`/`consumerKind` fields is independently
  optional) and return the resulting application.
- **application-deletion**: The delete operation MUST remove the application
  identified by the given id.
- **identifier-rename**: The rename-identifier operation MUST issue a `PATCH
  /registry/identifiers/{current}` request with body `{rdid: next}` and MUST throw a
  conflict error when `next` is already taken by another identifier.
- **schema-grants-read**: The schema-grants operation MUST return the full current
  list of schema grants for that application.
- **schema-grants-write**: The set-schema-grants operation MUST replace the
  application's entire schema-grant list with the given array in one call (a
  whole-list write, not a per-grant patch).
- **token-listing**: The tokens operation MUST return the application's token rows
  (never including a plaintext secret).
- **token-creation**: The create-token operation MUST mint a new token and return a
  token-created result, whose `token` field carries the plaintext secret exactly
  once.
- **token-revocation**: The revoke-token operation MUST withdraw the token
  identified by the given token id.

**Data shapes**

- **application-identifier-shape**: An application's `id` MUST be a reverse-domain
  identifier of the form `app.<ecosystem>.<leaf>`; renaming the leaf through the
  rename-identifier operation MUST change this value.
- **application-identifier-prefix**: An application's identifier-prefix value MUST
  return everything up to and including the id's last `.` (e.g. `"app.acme.shop."`
  for `"app.acme.shop.web"`), and MUST return the empty string when the id contains
  no `.`.
- **consumer-kind-decoding**: Decoding a consumer kind MUST accept the wire's free
  `string` field (documented as `maxLength: 16`, no enum) and MUST narrow any value
  that is not `"staff"`/`"developer"`/`"customer"` to `"developer"` rather than
  failing the decode — this is what keeps one unrecognized row from failing the
  whole applications-list decode and blanking the rail.
- **consumer-kind-fallback-values**: when a `consumerKind` string cannot be parsed
  into a recognized consumer kind, the component MUST fall back to one of three
  different defaults depending on the call site: `"developer"` when decoding a wire
  application record, `"customer"` when the "New application" form's `consumerKind`
  value is unparsable, and the application's own current `consumerKind` when the
  "Settings" form's value is unparsable. Because the form's kind options are built
  from the full set of recognized consumer kinds, both form-side fallbacks are
  unreachable through the rendered UI and matter only if a value is missing or
  tampered with.
- **crud-permissions-wire-order**: A CRUD-permissions value's wire form MUST
  serialize to a comma-separated subset of `"C"`, `"R"`, `"U"`, `"D"` in that fixed
  order regardless of the order the flags were set in.
- **crud-permissions-parsing-tolerance**: Parsing a CRUD-permissions wire string MUST
  be case-insensitive, trimming whitespace around each token, and MUST treat any
  unrecognized token as simply absent rather than throwing.
- **crud-permissions-summary-text**: A CRUD-permissions value's summary text MUST
  return `"No access"` when every flag is `false`, and otherwise the enabled flags'
  words (`"Create"`, `"Read"`, `"Update"`, `"Delete"`) joined with `", "` in that
  fixed order.
- **crud-permissions-ceiling-check**: A CRUD-permissions ceiling check MUST return
  `true` only when every flag that is `true` on the value being checked is also
  `true` on the given ceiling.
- **grant-types-are-domain-only**: Table-grant and schema-grant values MUST NOT be
  wire-serializable; this is deliberate — the wire shape (`{schemaId, crud, tables:
  [{tableId, crud}]}`) lives in an adapter outside the domain layer, so it is
  impossible to serialize these domain types onto the API by accident.
- **table-grant-level-is-ui-only**: A table grant's `level` field MUST carry no wire
  counterpart (`"table"` vs. the not-yet-supported `"row"` is a UI-only concept) and
  MUST never be sent to the server.
- **schema-grant-table-keying**: A schema grant's `tables` map MUST be keyed by a
  table's `id` (the wire's `tableId`), never by its `sqlTableName`.
- **application-token-shape**: An application token MUST expose `id`, `name`,
  `prefix`, and an optional `createdAt`, and MUST NOT carry a secret field.
- **application-token-created-shape**: A created-token result (the response to
  minting a token) MUST expose the same fields as an application token plus a
  `token` field holding the plaintext secret.

**Navigation**

- **rail-path-resolution**: The rail path resolver MUST resolve the path in order —
  an application id at position 0, then a section id (`"settings"`, `"grants"`, or
  `"tokens"`) at position 1, then any remaining segments handed to that section's own
  resolver — and MUST return the top-level listing when the path is empty.
- **missing-application-returns-empty**: when looking up the application by id in
  the path throws a not-found error, the rail path resolver MUST return an empty
  result, not propagate the error.
- **errors-wrapped-and-propagated**: any error other than a not-found error from the
  get, list, or any other data-source call MUST be passed through the shared
  error-wrapping step and rethrown — never swallowed.
- **unknown-section-returns-empty**: a section id other than `"settings"`,
  `"grants"`, or `"tokens"` MUST resolve to an empty result.
- **secret-expiry-on-navigation**: every call to the rail path resolver MUST run the
  secret-expiry check first, passing the token id from the path only when the path is
  presently inside that same token's detail (the section id at position 1 is
  `"tokens"` gives the token id at position 2, else none); that check MUST drop the
  currently revealed secret and clear the on-screen-token marker whenever the
  resolved token id differs from it, and MUST leave both untouched when it matches (a
  re-render of the same detail).

**Applications list and create**

- **applications-list-item-mapping**: the applications listing MUST map each
  application to a list item with `id` = the application's `id`, `label` =
  `displayName`, `sublabel` = `id`, an icon keyed by `consumerKind`, and leading to a
  list.
- **create-application-fields**: the "New application" form MUST present, in order,
  a required `displayName` text field, a required `slug` text field validated
  against the shared slug-format rule, and a required `consumerKind` select field
  offering every recognized consumer kind.
- **create-application-slug-lowercased**: the create save action MUST lowercase the
  submitted `slug` before constructing the create body, and MUST trim
  leading/trailing whitespace from `displayName`.
- **create-conflict-messaging**: when creating throws a conflict error, the save
  action MUST throw a validation error reading `An application with identifier
  "{slug}" already exists.` instead of the raw conflict; any other error MUST pass
  through the shared error-wrapping step.

**Application level and settings**

- **application-level-items**: the application-level listing MUST return exactly
  three items, in order: `"settings"` ("Settings", leads to a detail view),
  `"grants"` ("Bucket permissions", leads to a list), and `"tokens"` ("Access
  tokens", leads to a list).
- **settings-form-fields**: the settings detail MUST present `displayName`, `slug`,
  a read-only `identifier`, and `consumerKind`, pre-filled from the current
  application.
- **settings-save-without-rename**: when the submitted `slug` equals the
  application's current `slug`, the save action MUST call the update operation with
  the application's existing id and MUST NOT call the rename-identifier operation.
- **settings-save-with-rename**: when the submitted `slug` differs from the current
  `slug`, the save action MUST call the rename-identifier operation (renaming to the
  identifier prefix plus the new slug) before calling the update operation, and MUST
  target the update at the new id.
- **rename-conflict-messaging**: when the rename-identifier operation throws a
  conflict error, the save action MUST throw a validation error reading `The
  identifier "{next}" is already in use.`.
- **grant-rehoming-write-order**: on a successful rename, the save action MUST read
  the old id's schema grants, write them to the new id, and only then clear the old
  id's grants (write-new, then-clear-old) — never the reverse order, and never a
  single combined write.
- **delete-clears-grants-then-deletes**: the "Delete application" action MUST call
  the set-schema-grants operation with an empty list before calling the delete
  operation.
- **delete-confirmation-text**: the delete action's confirmation text MUST be
  exactly `Delete application "{displayName}"? This cannot be undone.`.

**Bucket permission grants**

- **grants-list-item-mapping**: the schema-grants listing MUST map each schema grant
  to an item labeled with the matching bucket's `name`, or the deleted-schema label
  (`"(deleted schema)"`) when no bucket with that `schemaId` exists among the
  ecosystem's buckets, with `sublabel` set to that grant's permissions summary.
- **add-schema-options-exclude-granted**: the "Add schema" form MUST offer only
  buckets whose id is not already present among the application's current schema
  grants' `schemaId`s.
- **add-schema-default-permissions**: a newly added grant MUST start with read-only
  permissions (`"R"`) and an empty `tables` map.
- **add-schema-requires-selection**: when no ungranted bucket exists, the "Add
  schema" save action MUST throw a validation error reading `No schemas defined yet.
  Create one in the Buckets section first.` without calling the set-schema-grants
  operation.
- **grant-level-item-composition**: the grant-level listing MUST list a `"schema"`
  item ("Schema permissions", divider after, leads to a detail view) followed by one
  item per table in that schema, each labeled with the table's `name` and sublabeled
  with that table's grant summary or `"No access"` when the table has no grant
  entry.
- **schema-detail-fields**: the schema permissions detail MUST present a read-only
  `schema` field plus four toggle fields (`create`, `read`, `update`, `delete`),
  pre-filled from the grant's permissions.
- **schema-detail-deleted-bucket-notice**: when the grant's bucket no longer exists,
  the `schema` field's value MUST append ` — This schema no longer exists. Remove
  the grant, or recreate the bucket.` to the deleted-schema label.
- **schema-save-rewrites-whole-list**: saving the schema detail MUST recompute
  `permissions` from the four toggles, then rewrite the application's entire grants
  list (remove the prior entry for that `schemaId`, append the replacement, call the
  set-schema-grants operation with the full array) — never a partial or per-field
  update.
- **schema-remove-grant**: the schema detail's "Remove grant" action MUST drop that
  schema's grant entirely (the same whole-list rewrite with no replacement) with
  confirmation text `Remove the "{label}" grant? This application will lose access
  to its tables.`.
- **table-grant-ceiling-enforcement**: saving a table's permissions MUST throw a
  validation error reading `"{table.name}" can't exceed the schema's permissions.`
  when the submitted permissions are not within the schema grant's own permissions
  (every enabled flag on the submission must also be enabled on the ceiling).
- **table-grant-row-level-rejected**: selecting `"row"` as the permission level MUST
  cause the save action to throw a validation error reading `Per-row permissions are
  coming soon. Choose "Table".` without persisting anything.
- **table-grant-empty-removes-entry**: when the submitted permissions are empty, saving
  MUST remove that table's entry from the schema grant's `tables` map rather than
  storing an empty-permission table grant.
- **table-grant-level-constant**: every table grant this component persists MUST have
  `level == "table"` — `"row"` is rejected before it can be saved
  (**table-grant-row-level-rejected**) and there is no other path that writes a
  table grant.
- **grants-write-concurrency**: NEEDS REVIEW: Not implemented. The grant-rewrite
  logic and the "Add schema" save action both read the application's full list of
  schema grants, mutate an in-memory copy, and write the whole array back with no
  version token, ETag, or compare-and-swap; two overlapping writers (two devices,
  tabs, or concurrent form submissions against the same application) can each read
  the same snapshot and the second set-schema-grants call silently discards the
  first writer's change. Settling this needs either a server-side optimistic-lock
  primitive this contract does not expose, or evidence that the backend itself
  serializes set-schema-grants calls per application (neither is currently known).

**Access tokens**

- **tokens-list-item-mapping**: the tokens listing MUST map each token to an item
  with `label` = `name` and `sublabel` = `"{prefix}… · {formatted createdAt}"`.
- **token-creation-mints-and-reveals-secret**: the "New token" save action MUST call
  the create-token operation and, on success, MUST store the returned token-created
  result's `token` value into the revealed-secrets store, keyed by the created
  token's id.
- **token-reveal-while-current**: the token detail MUST include a read-only `token`
  field (the plaintext secret) and a read-only `notice` field ("Copy this token now
  — you won't be able to see it again.") only while the revealed-secrets store holds
  a value for that token, and MUST set the on-screen-token marker to that token's id
  whenever it does.
- **token-secret-expires-on-navigation**: resolving any path other than that same
  token's detail MUST remove its entry from the revealed-secrets store, so
  navigating to a sibling token or anywhere else and back MUST NOT re-show the
  plaintext secret.
- **token-revoke-clears-secret-and-list**: the "Revoke token" action MUST call the
  revoke-token operation and, on success, MUST remove that token's entry from the
  revealed-secrets store.
- **token-revoke-confirmation-text**: the revoke action's confirmation text MUST be
  exactly `Revoke token "{name}"? Applications using it will lose access.`.

**Authorization errors**

- **authorization-errors-propagate**: an unauthorized or forbidden error thrown by
  the applications or buckets data source MUST propagate unchanged to the caller
  through the shared error-wrapping step rather than being caught, retried, or
  downgraded locally.

## Appearance

Not applicable — this is the client-side Applications data-source contract and
rail-navigation logic, not a visual component.

## States

Not applicable — this is the client-side Applications data-source contract and
rail-navigation logic, not a visual component; the level/detail/form values it
returns are consumed by a separate presentation layer that owns any
loading/error/empty visual state.

## Accessibility

Not applicable — this is the client-side Applications data-source contract and
rail-navigation logic, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hub-apps-001 | applications-listing, applications-list-item-mapping | The applications listing resolved against two applications | Items in insertion order with label/sublabel/icon matching displayName/id/consumerKind; the configured empty-list message is "No applications yet." |
| hub-apps-002 | consumer-kind-decoding | Decoding a list of applications where one row's `consumerKind` is "service" (unrecognized) and a sibling's is "customer" | Both rows decode; the unrecognized row's `consumerKind` becomes "developer", the sibling's stays "customer" |
| hub-apps-003 | crud-permissions-wire-order, crud-permissions-parsing-tolerance | Parsing the CRUD-permissions wire string "R, D,C" and re-serializing it | "C,R,D" |
| hub-apps-004 | crud-permissions-summary-text | The summary text for an empty CRUD-permissions value and for one with every flag set | "No access" and "Create, Read, Update, Delete" |
| hub-apps-005 | application-identifier-prefix | The identifier-prefix value for an application whose `id` is "app.acme.shop.web" | "app.acme.shop." |
| hub-apps-006 | create-application-slug-lowercased, create-conflict-messaging | The create form's save action invoked with `slug: "mobile"`, then again after the data source is set to fail creation with a conflict error ("dup") | First call: the create body recorded by the data source has the given fields; second call: save fails and the error message reads "An application with identifier \"mobile\" already exists." |
| hub-apps-007 | application-level-items | The application-level listing for "app.acme.shop.web" | Item ids are ["settings", "grants", "tokens"]; resolving an unknown application id returns an empty result |
| hub-apps-008 | settings-save-without-rename | Settings form saved with `slug` unchanged | No rename is recorded; one update is recorded, targeting the existing id |
| hub-apps-009 | settings-save-with-rename, grant-rehoming-write-order | Settings form saved with `slug` changed from "web" to "store", the application already having one schema grant | A rename from "app.acme.shop.web" to "app.acme.shop.store" is recorded; the grant writes recorded are, in order, the grant written to the new id, then an empty list written to the old id |
| hub-apps-010 | rename-conflict-messaging | The rename-identifier operation fails with a conflict error ("dup") for a submitted rename | Save fails with the error message "The identifier \"app.acme.shop.web\" is already in use." |
| hub-apps-011 | grant-rehoming-write-order | Rename succeeds but the SECOND grant write (clearing the old id) fails | Save reports failure, but both the new and old id's grants still hold the original grant — no data loss |
| hub-apps-012 | delete-clears-grants-then-deletes, delete-confirmation-text | Delete action invoked for "Web Storefront" | The confirmation text reads "Delete application \"Web Storefront\"? This cannot be undone."; an empty-grants write for the application is recorded before the deletion is recorded |
| hub-apps-013 | grants-list-item-mapping | The schema-grants listing with one grant for an existing bucket and one for a schema id with no matching bucket | Items' labels are the bucket's name and "(deleted schema)" respectively |
| hub-apps-014 | add-schema-options-exclude-granted, add-schema-default-permissions | The "Add schema" form with one bucket already granted and one ungranted, then saved | The select field offers only the ungranted bucket; after save, the new grant's permissions are "R" and its `tables` map is empty |
| hub-apps-015 | add-schema-requires-selection | The "Add schema" form invoked with no ungranted buckets available, then saved | Throws a validation error with message "No schemas defined yet. Create one in the Buckets section first." |
| hub-apps-016 | grant-level-item-composition | The grant-level listing for a grant with two tables, one having a table grant and one not | Items are ["schema", <table with a grant>, <table without>]; the table without a grant sublabels "No access" |
| hub-apps-017 | schema-save-rewrites-whole-list, schema-remove-grant | Schema detail saved with `delete` toggled on, then its "Remove grant" action invoked | After save, the grant's permissions include "D"; after remove, the application's grants are empty |
| hub-apps-018 | table-grant-ceiling-enforcement | Table detail saved with `update: true` while the schema grant's permissions are "C,R" | Throws a validation error reading "\"{table.name}\" can't exceed the schema's permissions."; the application's grants are unchanged |
| hub-apps-019 | table-grant-row-level-rejected | Table detail saved with `level: "row"` | Throws a validation error reading "Per-row permissions are coming soon. Choose \"Table\"."; the application's grants are unchanged |
| hub-apps-020 | table-grant-empty-removes-entry | Table detail saved with every CRUD toggle `false` after previously having `read: true` | The schema grant's `tables` map no longer contains an entry for that table id |
| hub-apps-021 | tokens-list-item-mapping, token-creation-mints-and-reveals-secret | "New token" saved with `name: "CI deploy"` | A token creation with that name is recorded; the revealed-secrets store holds the created token's plaintext secret keyed by its id |
| hub-apps-022 | token-reveal-while-current, token-secret-expires-on-navigation | After creating a token, resolve that token's detail, then a sibling token's detail, then the original token's detail again | First resolution shows the `token`/`notice` fields; after visiting the sibling, the revealed-secrets store no longer holds the original token's secret; the return visit's field list omits `token`/`notice` |
| hub-apps-023 | token-revoke-clears-secret-and-list, token-revoke-confirmation-text | Revoke action invoked for a token whose secret is not currently revealed | The confirmation text reads "Revoke token \"{name}\"? Applications using it will lose access."; the revocation is recorded |
| hub-apps-024 | errors-wrapped-and-propagated | The data source is set to fail with an unauthorized error; the rail path resolver is invoked with an empty path | Throws the unauthorized error unchanged (not swallowed, not downgraded) |
| hub-apps-025 | missing-application-returns-empty | Looking up the application by id throws a not-found error for the requested application id | The rail path resolver returns an empty result, no error propagates |

## Edge Cases

- **Empty applications list**: an empty applications result MUST render the
  applications listing's configured empty message ("No applications yet.") rather
  than an error (MUST).
- **No schemas to grant**: when the ecosystem has no ungranted buckets, "Add schema"
  MUST fail with the configured no-schemas message rather than presenting an empty,
  unusable picker (MUST).
- **Deleted bucket still referenced by a grant**: a schema grant whose `schemaId` no
  longer matches any bucket MUST still list and remain editable/removable, labeled
  with the configured deleted-schema label (MUST).
- **Boundary: table permissions exactly at the schema ceiling**: a table's submitted
  permissions equal to the schema grant's own permissions MUST be accepted (the
  ceiling check is inclusive of equality) (MUST).
- **Boundary: table permissions exceeding the ceiling by one flag**: MUST be
  rejected with the **table-grant-ceiling-enforcement** message even when only one
  extra flag is set (MUST).
- **Malformed/garbage CRUD wire string**: parsing a CRUD-permissions wire string MUST
  NOT throw on an unrecognized token (e.g. `"x,y,z"`); it parses to a fully-`false`,
  empty value, because parsing is a case-insensitive substring match against
  `{"C","R","U","D"}` with no validation that every token is recognized (MUST).
- **Identifier rename racing a settings save's other field changes**: the settings
  save action performs the rename, the grant re-home, and the field update as three
  sequential awaited calls with no rollback of an earlier step if a later one fails
  — a failed update call after a successful rename and grant re-home leaves the
  application renamed and re-homed but with its display name/consumer kind
  unchanged; the grant-write ordering acknowledges there is "no compensating write"
  for the grant step specifically, and the same is true, undocumented, for the
  trailing update call (MUST NOT roll back — matches the implementation; NEEDS
  REVIEW below covers the concurrent-writer variant, this line covers the
  single-writer partial-failure sequence).
- **Concurrent schema-grant writers**: see the open question on
  grants-write-concurrency — two overlapping set-schema-grants calls for the same
  application MUST NOT be assumed to compose; the last writer's full-array write
  wins and silently discards the other's change (SHOULD be addressed before this
  component is relied on for multi-writer scenarios; currently undefined).
- **Cancellation**: this component performs no explicit cancellation handling of its
  own; if the underlying platform's concurrency primitives cancel an in-flight call,
  that cancellation is expected to surface through the same error path as any other
  failure — no code in the applications topic distinguishes cancellation from a
  network failure (MUST — this is what the underlying concurrency model guarantees
  with no extra code, not a gap).
- **Offline or unreachable backend**: an offline or transport error thrown by the
  injected data source MUST propagate unchanged through the shared error-wrapping
  step; this component does not retry, queue, or cache a request to paper over the
  failure — a failed call simply throws and the caller decides whether to retry
  (MUST).
- **Empty/blank required text fields**: `displayName` and the "New token" `name`
  field are marked required on their form field, so blank submission is rejected by
  the shared form validator (documented in the `htdv-engine` recipe) before this
  component's own save actions ever run; slug format (not blankness) is the one
  constraint this component itself enforces via the shared slug-format rule (MUST —
  enforcement is delegated, not absent).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `dataSource` | the applications data source | none (required) | Backs the list/get/create/update/delete/rename-identifier/schema-grants/set-schema-grants/tokens/create-token/revoke-token operations. |
| `buckets` | the buckets data source | none (required) | Supplies the ecosystem's bucket list and bucket-table list this topic uses to label and enumerate schema/table grants; owned by the separate Buckets feature. |
| Consumer kind values | enumerated string | decode fallback "developer" | The three consumer kinds (staff, developer, customer) a caller can assign to an application. |
| Slug format rule | string pattern + message | fixed | Shared identifier rule enforced on both the create form's and the settings form's `slug` field. |
| Default grant permissions | CRUD-permissions value | `"R"` (read-only) | Starting permission set for a schema grant created by the "Add schema" save action. |

## Deep Linking

Not applicable: this component registers no URL scheme, universal link, or
app-continuation activity of its own; navigation is entirely through path arrays
supplied by the presentation layer that hosts this topic.

## Localization

This component contains no localization mechanism — every user-facing string below
is a hardcoded English literal, stated here as fact rather than as a gap:

| String Key | Default (en) | Context |
|-----------|---------------|---------|
| — | `No applications yet.` | Applications listing's empty-list message |
| — | `An application with identifier "{slug}" already exists.` | Create-form conflict message |
| — | `The identifier "{next}" is already in use.` | Settings-save rename-conflict message |
| — | `Delete application "{displayName}"? This cannot be undone.` | Settings delete confirmation |
| — | `No schemas defined yet. Create one in the Buckets section first.` | "Add schema" no-schemas message |
| — | `Remove the "{label}" grant? This application will lose access to its tables.` | Schema detail remove confirmation |
| — | `Per-row permissions are coming soon. Choose "Table".` | Table detail row-level-rejected message |
| — | `"{table.name}" can't exceed the schema's permissions.` | Table detail ceiling-violation message |
| — | `Copy this token now — you won't be able to see it again.` | Token reveal notice |
| — | `Revoke token "{name}"? Applications using it will lose access.` | Token revoke confirmation |

(This is a representative sample of the roughly two dozen literals across the
implementation, not the full set — every one follows the same pattern: a plain
string with no key, no catalog entry, and no pluralization rule beyond ad hoc string
interpolation.)

## Accessibility Options

Not applicable: this is a data-source contract and rail-navigation controller with no
UI of its own, so it responds to no Reduce Motion, Increase Contrast, or
Differentiate Without Color setting.

## Feature Flags

Not applicable: this component reads no feature-flag key and contains no conditional
feature-gating logic.

## Analytics

Not applicable: this component contains no analytics/event-emission call.

## Privacy

- **Data collected**: a plaintext bearer secret (the created-token result's `token`
  field) is returned exactly once, in the response to a successful create-token
  operation.
- **Storage**: the applications topic never persists the secret; the revealed-secrets
  store is an in-memory key-value map on the topic instance, with no file,
  user-defaults, or keychain write anywhere in this component.
- **Transmission**: this component never transmits the secret itself — it receives it
  once from the create-token response and places it into a read-only form field for
  on-screen display; actual network transmission is the injected data source's
  concern, out of scope of this component.
- **Retention**: bounded by two independent mechanisms — the reveal-once rule
  (**token-secret-expires-on-navigation**), which drops the secret from the
  revealed-secrets store the moment navigation moves away from that token's detail,
  and the applications topic instance's own lifetime (the store holds nothing once
  the instance is deallocated).
- **Disclosure safeguard**: the created-token result — the one type that carries a
  raw plaintext secret in its `token` field — has no custom string-description
  override, so its default, naive description would include the secret in full if
  ever logged or printed. The applications topic never logs or prints a created-token
  value; it stores only its `token` field into the revealed-secrets store. A port
  MUST NOT log this value.

## Logging

Not applicable: this component contains no logging call of any kind.

## Platform Notes

- **SwiftUI**: not applicable to these files directly — the applications topic
  returns level/detail/form values consumed by the shared form/HTDV presentation
  layer; a SwiftUI-based presenter would consume the same values unchanged, since
  `ApplicationsTopic.swift` imports no SwiftUI and performs no rendering itself.
- **AppKit / UIKit**: this is the source. `ApplicationsDataSource.swift`,
  `ApplicationsModels.swift`, and `ApplicationsTopic.swift` live in the `Hub` module
  shared between the `AgenticToolkitHub-macOS` and `AgenticToolkitHub-iOS` targets
  (both declared in `project.yml`, one source set). None of the three files imports
  `AppKit` or `UIKit` directly — each is plain `Foundation` (`ApplicationsTopic.swift`
  also imports `AgenticToolkitHTDV`), with the platform-specific
  `NSViewController`/`UIViewController` split handled entirely inside
  `FormViewController`, one layer below where these types operate.

  `ApplicationsDataSource` is declared `AnyObject, Sendable` and exposes:
  `list(ecosystemID:)`, `get(id:)`, `create(_:)`, `update(id:_:)`, `delete(id:)`,
  `renameIdentifier(_:to:)`, `schemaGrants(applicationID:)`,
  `setSchemaGrants(applicationID:_:)`, `tokens(applicationID:)`,
  `createToken(applicationID:name:)`, and `revokeToken(applicationID:tokenID:)`.
  `BucketsDataSource` is likewise `AnyObject, Sendable`. `ApplicationsModels.swift`
  holds the `Codable`/`Sendable` wire types `Application`, `ApplicationCreate`,
  `ApplicationUpdate`, `ConsumerKind`, `ApplicationToken`, `ApplicationTokenCreated`,
  plus the domain-only, deliberately non-`Codable` grant types `CrudPermissions`,
  `TableGrant`, `SchemaGrant` (kept off the wire per
  **grant-types-are-domain-only**). `ConsumerKind.init(from:)` implements the
  unrecognized-value fallback (**consumer-kind-decoding**); the two form-side
  fallbacks live in `ApplicationsTopic.createSpec`'s save action and
  `settingsDetail`'s save action, and `Self.kindOptions` is built from
  `ConsumerKind.allCases`. `CrudPermissions.wire`, `CrudPermissions.init(wire:)`,
  `CrudPermissions.summary`, and `CrudPermissions.isWithin(_:)` implement the
  wire-order, parsing-tolerance, summary-text, and ceiling-check requirements
  respectively. `Slug.pattern`/`Slug.patternMessage` back the shared slug-format
  rule, and `CrudPermissions.readOnly` is the default grant permission set.

  `ApplicationsTopic` is declared `@MainActor final class` conforming to
  `EcosystemTopicProvider`; every thrown error is normalized via `HubError.wrap(_:)`,
  with specific mappings to `HubError.conflict`/`.notFound`/`.validation` where the
  requirements above call for a distinct message. `child(for:path:rail:)` is the
  rail path resolver; `RailPath.id(at: 1, in: path)` reads the section id.
  `revealedSecrets` (`[String: String]`) and `revealedOnScreen` (`String?`) are the
  topic's own `@MainActor`-isolated stored state; `expireRevealedSecret(unless:)`
  implements the secret-expiry check. `listLevel(for:)`, `applicationLevel(for:)`,
  `grantsLevel(_:ecosystem:)`, and `grantLevel(_:grant:)` implement the four
  listings; `createSpec(for:)`, `settingsDetail`, and `addSchemaSpec` implement the
  three forms; `rewriteGrant` implements the schema/table grant whole-list rewrite.
  `ApplicationsTopic.deletedSchemaLabel`, `.noSchemasMessage`, `.rowLevelMessage`,
  and `.revealMessage` hold the four named message constants.

  Three requirements exist only because of Swift's concurrency model and apply to
  this platform alone: `ApplicationsTopic` MUST be declared `@MainActor final
  class`, with its stored state (`revealedSecrets`, `revealedOnScreen`) and every
  method running only on the main actor, so no lock, queue, or other synchronization
  primitive is needed to serialize reads and writes of that state within a process.
  `ApplicationsDataSource` and `BucketsDataSource` MUST be declared `AnyObject,
  Sendable`, so a conforming instance can be safely injected into and called from
  the `@MainActor`-isolated `ApplicationsTopic` while performing its own network
  work off the main actor. Because `FormAction.perform` is a plain `@Sendable async
  throws -> Void` closure, not `@MainActor`-isolated, a save action that mutates
  `revealedSecrets` (the "New token" create action) MUST hop that mutation onto the
  main actor explicitly via `await MainActor.run { ... }` — it cannot write the
  `@MainActor`-isolated property directly from the closure's own execution context.

  Cancellation: every `ApplicationsDataSource`/`BucketsDataSource` call is a plain
  `try await` with no explicit cancellation handling in these files; Swift's
  structured concurrency propagates a surrounding task's cancellation as a thrown
  `CancellationError` through the same `try await` path that any other error takes,
  so it is passed through `HubError.wrap(_:)` like any other failure.

  The test suite (`ApplicationsTopicTests.swift`) exercises every operation against
  a fake data source whose spy properties are named `creates`, `renames`,
  `grantWrites`, `grants`, `deletes`, `tokenCreates`, `tokenRevokes`, and
  `createFailure`/`failure`/`grantWriteFailureIndex`; fixtures use
  `Application.fixture()`.

  Deep linking: none of these three files registers a `URL` scheme, universal link,
  or `NSUserActivity`; navigation is entirely through `HTDVItem`/`HTDVChild` path
  arrays. Localization: no `String(localized:)`, `.strings`/`.xcstrings` catalog, or
  `NSLocalizedString` call appears; every literal is a plain Swift `String`.
  Logging: no `os_log`, `Logger`, or `print` call appears. `ApplicationTokenCreated`
  declares no `CustomStringConvertible`/`CustomDebugStringConvertible` override, so
  its synthesized default description includes the secret in full;
  `ApplicationsTopic.swift` never logs or prints a `created` value.
- **Compose**: a Kotlin port would model `Application`/`ApplicationCreate`/`ApplicationUpdate`/
  `ApplicationToken`/`ApplicationTokenCreated` as immutable `data class`es, `ConsumerKind` as a
  Kotlin `enum class` with a custom deserializer mirroring the `.developer` fallback,
  `CrudPermissions`/`TableGrant`/`SchemaGrant` as plain (non-`@Serializable`) domain classes kept
  out of the wire-decoding path on purpose, and `ApplicationsTopic` as a class exposing a
  `suspend fun child(...)` returning a sealed `HtdvChild`; `revealedSecrets` becomes a
  `MutableMap<String, String>` confined to a single `Dispatchers.Main`-bound coroutine scope,
  mirroring `@MainActor`.
- **React/Web**: a TypeScript port would use `readonly`-field interfaces for the wire types, a
  runtime narrowing function for `ConsumerKind` (mirroring the `.developer` fallback instead of
  `zod`'s default throw-on-mismatch behavior), plain objects (not classes) for
  `CrudPermissions`/`TableGrant`/`SchemaGrant` kept out of any `JSON.stringify` path that reaches
  the network, and `async` functions returning `Promise<HtdvChild>` for `child(...)`; the
  reveal-once mechanic needs an explicit teardown (a router's route-leave hook keyed by the
  outgoing path's token id) to reproduce `expireRevealedSecret(unless:)`'s "same detail re-renders,
  anything else expires" rule — JavaScript's single-threaded event loop already gives the map
  mutation itself the safety `@MainActor` provides in Swift, so no extra confinement primitive is
  needed for that part.
- **WinUI 3**: a .NET port would model `Application`, `ApplicationCreate`, `ApplicationUpdate`,
  `ApplicationToken`, and `ApplicationTokenCreated` as `record`s (free structural equality,
  mirroring the Swift `Hashable` conformances), `ConsumerKind` as an `enum` with a custom
  `JsonConverter` that narrows an unrecognized `System.Text.Json` string to `Developer` instead of
  throwing, and `CrudPermissions`/`TableGrant`/`SchemaGrant` as plain classes with no
  `[JsonPropertyName]`/serialization attributes at all — kept deliberately unreachable from
  `System.Text.Json.JsonSerializer` the same way the Swift types are kept off `Codable`.
  `IApplicationsDataSource` would expose `Task<Application[]> ListAsync(string ecosystemId)`,
  `Task<ApplicationTokenCreated> CreateTokenAsync(string applicationId, string name)`, etc., backed
  by `HttpClient` + `System.Text.Json`. `ApplicationsTopic`'s equivalent would be a view-model class
  with `async Task<HtdvChild> ChildAsync(...)`; `revealedSecrets` becomes a
  `Dictionary<string, string>` field on a view model instantiated per-window/per-`ContentDialog`,
  with the one-shot expiry implemented in the page's `OnNavigatedFrom` override (or the view
  model's `Dispose`) rather than a `@MainActor`-checked property, and UI-bound lists
  (`ObservableCollection<T>`) rebuilt wholesale on every re-fetch rather than incrementally patched,
  mirroring the whole-list-rewrite pattern in `schema-save-rewrites-whole-list`.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Hub/Features/Applications/` |

## Design Decisions

**Decision**: the settings save action re-homes an application's schema grants by writing
them to the new identifier BEFORE clearing them from the old one, rather than clearing first or
writing both in one call.
**Rationale**: there is no compensating write if the second call
fails; ordering the writes this way means a transient failure on the second (clearing) call merely
leaves a harmless duplicate of the grants under the now-stale old id, whereas the reverse order
would let a transient failure on the second (writing) call lose the grants outright.
**Approved**: pending

**Decision**: a token's plaintext secret is retained in the revealed-secrets store only until
navigation departs from the detail screen currently showing it, enforced by running the
secret-expiry check at the top of every navigation resolution rather than on a timer or a
view-disappear callback.
**Rationale**: retaining the secret for the whole session "made the
notice a lie" — the reveal notice promises the secret disappears once the reader
has navigated away. Tying the check to the navigation path itself, rather than a lifecycle event a
presentation layer would have to remember to call, means the guarantee holds regardless of which
presentation layer drives it.
**Approved**: pending

**Decision**: CRUD-permissions, table-grant, and schema-grant values are kept out of wire
serialization entirely, with the wire shape's translation left to an adapter outside these domain
types.
**Platform**: AppKit/UIKit.
**Rationale**: this makes it impossible to serialize these domain
types onto the API by accident — a caller reaching for Swift's `JSONEncoder` on a `SchemaGrant`
fails to compile rather than silently producing the wrong wire shape (`{schemaId, crud, tables:
[{tableId, crud}]}` is not what the struct's stored properties would naively encode to).
**Approved**: pending

**Decision**: a table's permissions are rejected outright (not clamped or silently ignored) when
they exceed the schema grant's own ceiling, and selecting `"row"` as the permission level is
rejected outright rather than silently treated as `"table"`.
**Rationale**: both are explicit validation errors with user-facing messages
(**table-grant-ceiling-enforcement**, **table-grant-row-level-rejected**) rather than a quiet
downgrade, so the caller always knows why a save did not take effect instead of discovering a
narrower grant than requested only by inspecting it afterward.
**Approved**: pending

**Decision**: schema and table grant edits are persisted by rewriting the application's entire
list of schema grants on every save, rather than a per-field or per-grant PATCH.
**Platform**: AppKit/UIKit.
**Rationale**: this keeps the write path uniform — one shape of call
(`setSchemaGrants(applicationID:_:)`) handles add, edit, and remove for both schema- and
table-level grants — at the cost of the concurrency exposure covered by the open question on
grants-write-concurrency; it is not documented whether this tradeoff was made knowingly or
because the backend has historically been treated as single-writer-per-application.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [secure-storage](agenticdevelopercookbook://compliance/security#secure-storage) | passed | Security |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [error-recovery](agenticdevelopercookbook://compliance/reliability#error-recovery) | failed | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |

`separation-of-concerns` passes: `ApplicationsDataSource` isolates every network call behind a
protocol `ApplicationsTopic` depends on but never implements, and the wire/domain model split
(`ApplicationsModels.swift`'s `Codable` types vs. the non-`Codable` `CrudPermissions`/
`TableGrant`/`SchemaGrant`) keeps the API's exact shape out of the domain layer. `unit-test-coverage`
passes: `ApplicationsTopicTests.swift` exercises every operation with a fake data source, including
the rename/re-home sequence, the reveal-once/expiry mechanic, and multiple failure paths.
`explicit-error-handling` passes: every throwing path in `ApplicationsTopic` routes through
`HubError.wrap(_:)` or a specific `catch HubError.conflict`/`.notFound` mapping — nothing is
silently discarded. `secure-storage` passes: no plaintext token secret is ever written to disk,
`UserDefaults`, or the Keychain — `revealedSecrets` is transient, in-memory, and actively
self-expiring. `no-hardcoded-strings` fails outright — see Localization; there is no localization
mechanism anywhere in these three files. `error-recovery` fails: none of the three files retries,
backs off, or queues a failed call — every `ApplicationsDataSource`/`BucketsDataSource` invocation
is a single `try await` that throws straight through to the caller on any failure, transient or
not. `data-integrity` is `partial`: individual writes are internally consistent (each
`setSchemaGrants` call replaces the array atomically from the caller's point of view, and
`table-grant-ceiling-enforcement` validates cross-field consistency before a save), but see the
open question on grants-write-concurrency — the whole-list read-modify-write pattern has no
protection against two overlapping writers silently discarding one another's changes.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to adh/hub/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
