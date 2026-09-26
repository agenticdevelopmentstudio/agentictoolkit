---
id: f81157d7-766f-42c9-a98a-44df19698bea
title: 'Hub Domain: Customers'
domain: agentictoolkit://cookbook/hub/features/customers
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The Hub''s Customers domain: a data-access protocol and Codable models for
  an ecosystem''s end users, and the topic provider that lists, creates, edits, and
  deletes them.'
platforms:
- swift
- macos
- ios
tags:
- hub
- customers
- data-source
- forms
- crud
depends-on: []
related:
- agentictoolkit://cookbook/htdv
references:
- packages/apple/AgenticToolkit/Hub/Features/Customers/CustomersDataSource.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Customers/CustomersModels.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Customers/CustomersTopic.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitHubTests/CustomersTopicTests.swift
  (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Hub Domain: Customers

## Overview

The Customers domain is the Hub's management of an ecosystem's end users
(rows of `/customer/customers`). It is three cooperating pieces:

- **`CustomersDataSource`** (`CustomersDataSource.swift`) — the protocol
  through which the Customers topic reaches the server: list/get/create/
  update/delete, a single flat CRUD surface with no nested child resource.
- **The data shapes** (`CustomersModels.swift`) — `Customer` and
  `CustomerInput`, the `Codable` payloads the data source sends and
  receives.
- **`CustomersTopic`** (`CustomersTopic.swift`) — the `EcosystemTopicProvider`
  that renders this domain into the Hub's rail/detail (HTDV) navigation: a
  users list and the create/edit/delete form for a single user.
  `CustomersTopic` builds on the HTDV navigation and Forms types
  (`HTDVLevel`, `HTDVItem`, `HTDVChild`, `HTDVDetail`, `FormSpec`,
  `FormAction`, `FormDeleteAction`, and the rest) documented in the related
  HTDV Engine recipe; those types are not redescribed here.

`FormSheet`, `FormDetails`, `RailPath`, `HubError`, `HubText`,
`EcosystemTopicProvider`, `EcosystemRail`, and `Ecosystem` are Hub-wide
helpers `CustomersTopic` is built on but that are not among this recipe's
three given sources; they are described here only to the extent needed to
state what `CustomersTopic` itself does with them.

The rail label for this topic is "Users" (`entry.label`, and the list
level's own `title`), and its two user-facing action verbs are "New user"
and "Delete user" — but the type and protocol names throughout the three
given sources are `Customer`/`CustomerInput`/`CustomersDataSource`. This
recipe follows the source exactly: "customer" is used for the type- and
field-level vocabulary, and "user" only where the source's own string
literals themselves say "user."

## Behavioral Requirements

### CustomersDataSource.swift — server data-access contract

- **data-source-contract**: `CustomersDataSource` MUST be a `Sendable`,
  `AnyObject`-constrained protocol declaring five `async throws`
  operations: `list(ecosystemID:)`, `get(id:)`, `create(_:)`,
  `update(id:_:)`, and `delete(id:)`.
- **list-is-ecosystem-scoped**: `list(ecosystemID:)` MUST take an
  `ecosystemID` parameter; `create(_:)` instead carries the scope inside
  its `CustomerInput` payload's own `ecosystemId` field (see
  `customer-input-shape`).
- **get-update-delete-take-no-ecosystem-parameter**: `get(id:)`,
  `update(id:_:)`, and `delete(id:)` MUST each take only a bare
  `id: String` (plus, for `update`, a `CustomerInput`), with no
  `ecosystemID` parameter of their own — unlike `list(ecosystemID:)` and
  unlike `create(_:)`'s payload, none of these three operations names or
  carries the ecosystem it is scoped to at the protocol level (see the
  open question on `get-lacks-ecosystem-scope`).
- **data-source-is-class-bound**: `CustomersDataSource` MUST be
  constrained to `AnyObject`, so an implementation is a class or actor,
  never a value type; none of the given sources supplies a concrete
  implementation.

### CustomersModels.swift — data shapes

- **customer-shape**: `Customer` MUST be a `Codable`, `Hashable`,
  `Sendable`, `Identifiable` struct exposing `id: String`,
  `ecosystemId: String`, and seven optional `String?` fields — `email`,
  `displayName`, `externalId`, `slug`, `avatarUrl`, `createdAt`,
  `updatedAt` — with no custom `init(from:)`/`encode(to:)`, per the
  source's own doc comment "Every descriptive field is nullable on the
  wire."
- **customer-label-derivation**: `Customer.label` MUST return
  `HubText.nonBlank(displayName) ?? HubText.nonBlank(email) ?? "—"`, per
  the source's own doc comment: `displayName || email || "—"`, treating
  blank strings as missing.
- **customer-sublabel-derivation**: `Customer.sublabel` MUST return
  `HubText.nonBlank(email) ?? HubText.nonBlank(externalId) ?? "—"`, per
  the source's own doc comment: `email || externalId || "—"`.
- **customer-input-shape**: `CustomerInput` MUST be a `Codable`,
  `Hashable`, `Sendable` struct exposing non-optional `ecosystemId: String`
  and `email: String`, plus four optional `String?` fields —
  `displayName`, `externalId`, `slug`, `avatarUrl` — per the source's own
  doc comment: "Body for `POST /customer/customers` and
  `PUT /customer/customers/{id}`. Optional fields encode as absent, never
  `null`."
- **customer-input-field-asymmetry**: Unlike `Customer`, whose `email` is
  optional, `CustomerInput.email` MUST be non-optional — every input
  payload declares a concrete email string, never `nil` (see, further
  below, `email-is-trimmed-and-defaults-to-empty-string` and
  `other-four-fields-use-nonBlank`, the two `CustomersTopic` behaviors that
  populate this shape).

### CustomersTopic.swift — navigation, listing, and forms

- **topic-identity**: `CustomersTopic.entry` MUST be the static
  `EcosystemTopicEntry` with `id: "users"`, `label: "Users"`,
  `systemImage: "person.2"`, and `description: "The people who sign in to
  this product."`.
- **topic-actor-confinement**: `CustomersTopic` MUST be declared
  `@MainActor` and `final`, conforming to `EcosystemTopicProvider`, and
  holds a single stored `dataSource` supplied through its public
  `init(dataSource:)`.
- **email-pattern-and-message-are-shared-constants**:
  `CustomersTopic.emailPattern` MUST be the static string
  `"^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$"` and `CustomersTopic.emailMessage` MUST
  be the static string `"Enter a valid email address."`, both consumed by
  `fieldSpec(isRequiredEmail:)`'s `email` field.
- **field-spec-is-shared-and-ordered**:
  `CustomersTopic.fieldSpec(isRequiredEmail:)` MUST return exactly five
  fields in order — `email` (`.text`, label `"Email"`, placeholder
  `"person@example.com"`, `isRequired` set to the parameter,
  `pattern: emailPattern`, `patternMessage: emailMessage`), `displayName`
  (label `"Display name"`, placeholder `"Jane Doe"`), `externalId` (label
  `"External ID"`, placeholder `"auth0|abc123"`), `slug` (label `"Handle"`,
  placeholder `"jane"`), and `avatarUrl` (label `"Avatar URL"`, placeholder
  `"https://…"`) — per the source's own comment, "`isRequiredEmail` is
  always true today; the parameter keeps the create and detail specs
  literally shared."
- **create-spec-uses-first-two-shared-fields**: `createSpec(for:)` MUST
  build its `FormSpec` from `Array(fieldSpec(isRequiredEmail: true)
  .prefix(2))` — the `email` and `displayName` fields only — rather than
  declaring its own field list.
- **detail-spec-uses-all-five-shared-fields**: `detail(for:)` MUST build
  its `FormSpec` from the full, unsliced `fieldSpec(isRequiredEmail: true)`
  — all five fields.
- **child-dispatch-by-rail-path-presence**: `child(for:path:rail:)` MUST
  dispatch on whether `RailPath.id(at: 0, in: path)` is `nil`: when `nil`,
  it returns `.level(listLevel(for:))`; when non-`nil`, it treats that id
  as a customer id and calls `dataSource.get(id:)`.
- **missing-customer-yields-empty-not-error**: When `dataSource.get(id:)`
  throws `HubError.notFound` for the id at path index `0`, `child` MUST
  return `.empty`; any other error thrown by `get(id:)` MUST be re-thrown
  after `HubError.wrap`.
- **users-list-level-shape**: The root level MUST have
  `id: "users-list"`, `title: "Users"`, `emptyMessage: "No users yet."`,
  and one item per customer returned by `list(ecosystemID:)`, each item's
  `id` set to the customer's `id`, `label` set to the customer's `label`,
  `sublabel` set to the customer's `sublabel`, `systemImage: "person"`,
  and `leadsTo: .detail`; it MUST carry a `createAction` titled
  `"New user"` that presents `createSpec(for:)` through
  `FormSheet.present`.
- **list-level-errors-are-wrapped**: When `dataSource.list(ecosystemID:)`
  throws, `listLevel(for:)` MUST catch it and re-throw via
  `HubError.wrap`, so no raw non-`HubError` failure escapes this call.
- **input-builder-is-nonisolated-and-pure**: The private
  `CustomersTopic.input(from:ecosystemID:)` helper MUST be a
  `nonisolated static` function, so it is callable off the main actor from
  inside a `FormAction.perform` closure.
- **email-is-trimmed-and-defaults-to-empty-string**:
  `input(from:ecosystemID:)` MUST set `CustomerInput.email` to the
  `"email"` form value trimmed of leading/trailing whitespace and newlines
  via `.trimmingCharacters(in: .whitespacesAndNewlines)`, or the empty
  string `""` when the `"email"` key is absent from the given values —
  never `nil`, since `CustomerInput.email` is non-optional.
- **other-four-fields-use-nonBlank**: `input(from:ecosystemID:)` MUST set
  `displayName`, `externalId`, `slug`, and `avatarUrl` each via
  `HubText.nonBlank(values[key]?.stringValue)`, so a missing key, an empty
  string, or a whitespace-and-newline-only string all become `nil` on the
  resulting `CustomerInput` — an asymmetry with `email`'s own trim-only
  handling (see Design Decisions).
- **create-spec-precheck-rejects-case-insensitive-duplicate**:
  `createSpec(for:)`'s save action MUST fetch the ecosystem's current
  customer list via `list(ecosystemID:)` and throw
  `HubError.validation("A user with email \"<email>\" already exists.")`
  when an existing customer's `email` matches the built input's `email`
  case-insensitively (via `.caseInsensitiveCompare(_:) == .orderedSame`,
  treating a `nil` existing `email` as `""`) — before calling
  `dataSource.create(_:)`.
- **create-spec-conflict-fallback**: When the precheck passes but
  `dataSource.create(_:)` itself throws `HubError.conflict` (of any
  associated detail), the save action MUST catch it and throw the
  identical `"A user with email \"<email>\" already exists."` validation
  message rather than propagating the raw conflict detail (see **conflict-reason-discarded**
  and Design Decisions).
- **create-spec-other-errors-are-wrapped**: Any error from
  `list(ecosystemID:)` during the precheck, or any error from `create(_:)`
  other than `HubError.conflict`, MUST be re-thrown via `HubError.wrap`.
- **detail-shape-and-seed-values**: `detail(for:)` MUST build an
  `HTDVDetail` (via `FormDetails.form`) with `id: "customer:<customerID>"`,
  `title: "User"`, the five-field `FormSpec` from
  `fieldSpec(isRequiredEmail: true)`, and initial values for all five
  keys, each seeded from the customer's own field or the empty string when
  that field is `nil` (`customer.email ?? ""`, and likewise for the other
  four).
- **detail-save-conflict-fallback**: The detail save action MUST call
  `dataSource.update(id:_:)` directly, with no client-side duplicate
  lookup beforehand, and MUST catch a thrown `HubError.conflict` (of any
  associated detail) and re-throw it as
  `"A user with email \"<email>\" already exists."` — the same message
  `createSpec`'s save produces, but reached only through the server's
  conflict response, never a local list check (see Design Decisions).
- **detail-save-other-errors-are-wrapped**: Any error from
  `update(id:_:)` other than `HubError.conflict` MUST be re-thrown via
  `HubError.wrap`.
- **detail-delete-shape**: `detail(for:)`'s `FormSpec.actions.delete` MUST
  be a `FormDeleteAction` titled `"Delete user"` with
  `confirmationText: "Delete user \"<customer.label>\"? This cannot be
  undone."`, invoking `dataSource.delete(id: customer.id)`.
- **detail-delete-errors-are-wrapped**: When `dataSource.delete(id:)`
  throws, the delete action MUST catch it and re-throw via
  `HubError.wrap`.

## Appearance

Not applicable — this is the Customers domain's data-access protocol, data
shapes, and navigation/forms logic, not a visual component.

## States

Not applicable — this is the Customers domain's data-access protocol, data
shapes, and navigation/forms logic, not a visual component. The one
runtime distinction this file makes across list items and detail
fields — whether a customer's descriptive fields resolve to real text or
fall back to the placeholder "—" — is captured above as a requirement
(`customer-label-derivation`, `customer-sublabel-derivation`), not as a
visual-state table.

## Accessibility

Not applicable — this is the Customers domain's data-access protocol, data
shapes, and navigation/forms logic, not a visual component.
`CustomersDataSource`, `CustomersModels`, and `CustomersTopic` produce no
view, role, trait, or label of their own; any accessibility surface
belongs to the `FormViewController`/`AgenticToolkitHTDVViewController`
presentation layer that renders the `HTDVLevel`/`HTDVDetail`/`FormSpec`
values these sources build (out of this recipe's given sources; see the
related HTDV Engine recipe).

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hub-domain-customers-001 | customer-shape, customer-label-derivation, customer-sublabel-derivation | Decode a JSON customer payload with `email: null`, `displayName: null`, `externalId: "auth0|abc"`, `slug: null`, `avatarUrl: null` (`testDecodesCustomerWithNullFields`). | `customer.email` is `nil`; `customer.label == "—"`; `customer.sublabel == "auth0|abc"`. |
| hub-domain-customers-002 | customer-label-derivation | `Customer.fixture().label` / `.sublabel` (fixture's `displayName: "Jane Doe"`, `email: "jane@example.com"`) (`testLabelsPreferDisplayNameThenEmail`). | `label == "Jane Doe"`; `sublabel == "jane@example.com"`. |
| hub-domain-customers-003 | customer-label-derivation | `Customer.fixture(displayName: "").label` (`testLabelsPreferDisplayNameThenEmail`). | Returns `"jane@example.com"` — an empty `displayName` is treated as missing, not as the label itself. |
| hub-domain-customers-004 | customer-label-derivation, customer-sublabel-derivation | `Customer.fixture(email: nil, displayName: nil)` (`testLabelsPreferDisplayNameThenEmail`). | `.label == "—"`; `.sublabel == "—"`. |
| hub-domain-customers-005 | customer-label-derivation | `Customer.fixture(displayName: "\n").label` (`testLabelsPreferDisplayNameThenEmail`). | Returns `"jane@example.com"` — a newline-only display name is blank per `HubText.nonBlank`'s `.whitespacesAndNewlines` trim, not a label made of padding. |
| hub-domain-customers-006 | customer-label-derivation | `Customer.fixture(displayName: "  Jane  ").label` (`testLabelsPreferDisplayNameThenEmail`). | Returns `"Jane"` — leading/trailing whitespace is trimmed before use. |
| hub-domain-customers-007 | other-four-fields-use-nonBlank | Detail form for `Customer.fixture()`; set `slug` to `"\n"` and `externalId` to `"\n \n"`, then save (`testNewlineOnlyOptionalFieldIsOmittedNotEmptied`). | `save()` returns `true`; `source.updates[0].input.slug` and `.externalId` are both `nil`, not empty strings. |
| hub-domain-customers-008 | users-list-level-shape | `child([])` against three customers: two in ecosystem `"org.acme.shop"` (one with a `displayName`, one without) and one in ecosystem `"org.other"` (`testListShowsUsers`). | Returns a `.level` with `id == "users-list"`, `title == "Users"`, items labeled `["Jane Doe", "bob@example.com"]`, sublabels `["jane@example.com", "bob@example.com"]`, all `leadsTo == .detail`, `emptyMessage == "No users yet."`, `createAction?.title == "New user"`; the other-ecosystem customer does not appear. |
| hub-domain-customers-009 | create-spec-uses-first-two-shared-fields | `createSpec(for:)` (`testCreateFormValidatesEmailAndDuplicates`). | `spec.fields.map(\.key) == ["email", "displayName"]`. |
| hub-domain-customers-010 | field-spec-is-shared-and-ordered | The create save action with `email` set to `"not-an-email"` (`testCreateFormValidatesEmailAndDuplicates`). | `save()` returns `false`; `errors["email"] == "Enter a valid email address."`. |
| hub-domain-customers-011 | field-spec-is-shared-and-ordered (email `isRequired: true`) | The create save action with no `email` value set (`testCreateFormValidatesEmailAndDuplicates`). | `save()` returns `false`; `errors["email"] == "Email is required"` — the Forms subsystem's own generic required-field message (documented in the related HTDV Engine recipe), not one `CustomersTopic` itself produces. |
| hub-domain-customers-012 | create-spec-precheck-rejects-case-insensitive-duplicate | The create save action with `email` set to `"Jane@Example.com"` where a customer with `email: "jane@example.com"` already exists (`testCreateFormValidatesEmailAndDuplicates`). | `save()` returns `false`; `saveError == "A user with email \"Jane@Example.com\" already exists."`; `dataSource.create` is never called. |
| hub-domain-customers-013 | email-is-trimmed-and-defaults-to-empty-string, other-four-fields-use-nonBlank | The create save action with `email: "bob@example.com"`, `displayName: "Bob"`, no existing match (`testCreateFormValidatesEmailAndDuplicates`). | `save()` returns `true`; `dataSource.creates == [CustomerInput(ecosystemId: "org.acme.shop", email: "bob@example.com", displayName: "Bob")]` — `externalId`/`slug`/`avatarUrl` all `nil` since never set. |
| hub-domain-customers-014 | create-spec-conflict-fallback | The create save action with `source.createFailure = .conflict("dup")` and `email: "carol@example.com"` (no local duplicate) (`testCreateFormValidatesEmailAndDuplicates`). | `save()` returns `false`; `saveError == "A user with email \"carol@example.com\" already exists."`, not the raw `"dup"` conflict detail. |
| hub-domain-customers-015 | detail-shape-and-seed-values | `child(["c-jane"])` against `Customer.fixture()` (`slug: "jane"`, `externalId: nil`) (`testDetailFormShowsAllFieldsAndSaves`). | `detail.id == "customer:c-jane"`; `detail.title == "User"`; field keys `["email", "displayName", "externalId", "slug", "avatarUrl"]`; field labels `["Email", "Display name", "External ID", "Handle", "Avatar URL"]`; initial `email` value `.string("jane@example.com")`; initial `slug` value `.string("jane")`; initial `externalId` value `.string("")`. |
| hub-domain-customers-016 | detail-save-other-errors-are-wrapped, other-four-fields-use-nonBlank | Same detail form; set `externalId` to `"auth0|abc123"` and `slug` to `""`, then save (`testDetailFormShowsAllFieldsAndSaves`). | `save()` returns `true`; `source.updates.map(\.id) == ["c-jane"]`; `source.updates[0].input == CustomerInput(ecosystemId: "org.acme.shop", email: "jane@example.com", displayName: "Jane Doe", externalId: "auth0|abc123", slug: nil, avatarUrl: nil)`. |
| hub-domain-customers-017 | detail-delete-shape | Detail form for `Customer.fixture(displayName: nil)` (so `label` falls back to `"jane@example.com"`); invoke the delete action (`testDetailDeleteConfirmsWithLabel`). | `delete.title == "Delete user"`; `delete.confirmationText == "Delete user \"jane@example.com\"? This cannot be undone."`; `source.deletes == ["c-jane"]`. |
| hub-domain-customers-018 | missing-customer-yields-empty-not-error | `child(["nope"])` against a data source with no customers (`testUnknownUserIsEmpty`). | Returns `.empty`. |
| hub-domain-customers-019 | list-level-errors-are-wrapped | `child([])` where `dataSource.list`/`dataSource.get` throws `HubError.forbidden` (`testFailuresSurfaceAsHubError`). | The call throws `HubError.forbidden` unchanged — wrapped but not altered, since `HubError.wrap` returns an existing `HubError` as-is. |
| hub-domain-customers-020 | detail-save-conflict-fallback | Derived directly from `detail(for:)`'s save action's `catch HubError.conflict { throw HubError.validation(...) }` block; no test in `CustomersTopicTests.swift` sets a failure on `update(id:_:)` to exercise this branch. | A `HubError.conflict` thrown by `dataSource.update(id:_:)` would be caught and re-thrown as `"A user with email \"<email>\" already exists."`, not the raw conflict detail. |

## Edge Cases

- **Null and empty input**: An empty or whitespace-only `email` on create
  is rejected before this file's own save action runs, because
  `createSpec`'s `"email"` field is declared with `isRequired: true` (per
  `field-spec-is-shared-and-ordered`), and the Forms subsystem's own
  required-field validation (documented in the related HTDV Engine recipe)
  blocks `save()` from invoking the action at all — hence the missing-email
  case in `testCreateFormValidatesEmailAndDuplicates` surfaces the generic
  `"Email is required"` message, not one produced by `CustomersTopic`
  itself (MUST, by construction of the field). `detail(for:)` reuses the
  same required `email` field, so an existing customer's email can never
  be blanked out through this form either. The other four fields
  (`displayName`, `externalId`, `slug`, `avatarUrl`) are not required, and
  an empty string or a whitespace-and-newline-only string for any of them
  MUST become `nil` on the resulting `CustomerInput` rather than being
  posted as an empty string (MUST, see `other-four-fields-use-nonBlank`,
  `testNewlineOnlyOptionalFieldIsOmittedNotEmptied`).
- **Boundary values**: `email` itself receives no such blanking — it is
  only trimmed, never substituted with `nil`, because `CustomerInput.email`
  is non-optional (MUST, see `email-is-trimmed-and-defaults-to-empty-string`);
  an `email` value that is present but resolves to only whitespace after
  trimming becomes the empty string `""`, which then fails the shared
  `emailPattern` regex rather than being treated as absent. `emailPattern`
  itself (`"^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$"`) requires at least one
  non-`@`/non-whitespace character on each side of the `@` and a `.`
  after it, with no length bound of its own.
- **Concurrent access**: `CustomersTopic` is `@MainActor`-confined with no
  `Sendable` conformance of its own, so its own state (the single stored
  `dataSource` reference) is not mutated concurrently from another
  isolation domain. The data it depends on can still race across separate
  requests to the server: two overlapping "create user" calls for the
  same email can both pass this file's client-side duplicate precheck
  before either has landed, because the precheck lists existing state,
  then the create call happens later with no lock in between; this file's
  own defense is that a resulting server-side `HubError.conflict` is
  caught and re-thrown as the same duplicate-email validation message the
  precheck would have produced (MUST, see `create-spec-conflict-fallback`,
  and Design Decisions). `detail(for:)`'s save action runs no precheck at
  all and depends on this same conflict-to-validation mapping alone (MUST,
  see `detail-save-conflict-fallback`).
- **Error states**: Every operation in `CustomersDataSource` is `async
  throws`; `CustomersTopic` converts every error it does not specifically
  remap (`HubError.notFound` on `get(id:)`, `HubError.conflict` on the two
  save actions) into a `HubError` via `HubError.wrap` and re-throws it, so
  no failure is dropped silently (MUST, see
  `missing-customer-yields-empty-not-error`, `list-level-errors-are-wrapped`,
  `create-spec-other-errors-are-wrapped`, `detail-save-other-errors-are-wrapped`,
  `detail-delete-errors-are-wrapped`, `testFailuresSurfaceAsHubError`).
  `HTDVCreateAction.perform` (the closure passed to
  `HTDVLevel.createAction`) is non-throwing per its own declared signature
  (documented in the related HTDV Engine recipe), so a failure while
  presenting the "New user" sheet through `FormSheet.present` has no
  channel back into this file's own error handling — it is the sheet's own
  responsibility.
- **Offline or disconnected state**: None of the three given sources make
  a network call directly or define a timeout, retry, or
  connectivity-aware behavior of their own; every call to
  `CustomersDataSource` either succeeds or throws, and a thrown error
  surfaces exactly as described under Error states above (fact, not a
  gap — the failure is reported, not lost, just with no time bound or
  automatic retry defined at this layer).

- **get-lacks-ecosystem-scope**: NEEDS REVIEW: Not implemented in source. `CustomersDataSource.get(id:)` takes no `ecosystemID` parameter, and `CustomersTopic.child(for:path:rail:)` calls it with only the raw customer id taken from the rail path, never comparing the returned `Customer.ecosystemId` against the `ecosystem` parameter `child` was itself given before showing, editing (`update(id:_:)`), or deleting (`delete(id:)`) that customer; `list(ecosystemID:)` is the only one of the five operations that names an ecosystem at all, so nothing in these three sources stops a rail path holding a customer id from a different ecosystem from resolving, being edited, or being deleted — resolvable by inspecting whether the deployed `CustomersDataSource` implementation enforces this scoping server-side (not among the given sources), or by a decision from the Hub team on whether client-side scoping is also required.

- **conflict-reason-discarded**: both `createSpec(for:)`'s and `detail(for:)`'s save actions catch `HubError.conflict` by case alone and always re-throw the fixed message `"A user with email \"<email>\" already exists."`, discarding the associated `String` detail of the data source's `HubError.conflict(String)`. A `.conflict` raised for any other reason (for example, a uniqueness constraint on `slug` or `externalId`) is still reported as a failed save, but with the duplicate-email message.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `dataSource` (parameter to `CustomersTopic.init`) | `any CustomersDataSource` | none — required | The server access point this topic navigates and posts through; the host supplies its own implementation. |
| `ecosystem` (parameter to every `child(for:path:rail:)` call, and to `createSpec(for:)`) | `Ecosystem` | none — required | Supplies the `ecosystemId` value posted with every create/update call and, per `list-is-ecosystem-scoped`, the scope of `list(ecosystemID:)` reads; not among this recipe's given sources beyond its `id` field. |

None of the three given sources reads an environment variable or a named
settings key; every value `CustomersTopic` needs is supplied by its
`init` parameter, the `Ecosystem`/`Customer` values passed into its
methods, or the user's own form input.

## Deep Linking

Not applicable: none of the three given sources define a URL scheme,
route, or app-level navigation destination. `CustomersTopic`'s rail-path
id (a customer id) is an in-memory argument to `child(for:path:rail:)`,
consumed by the HTDV navigation state machine documented in the related
HTDV Engine recipe, not a deep-linkable URL.

## Localization

None of the three given sources reference a string-key or localization
table; every user-facing string `CustomersTopic` produces is a hardcoded
English literal composed inline:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal, no key) | `Users` | `CustomersTopic.entry.label` and the users-list level's `title`. |
| (none — literal, no key) | `The people who sign in to this product.` | `CustomersTopic.entry.description`. |
| (none — literal, no key) | `No users yet.` | Users list level's `emptyMessage`. |
| (none — literal, no key) | `New user` | The list level's `createAction.title`, reused as `FormSheet.present`'s dialog title. |
| (none — literal, no key) | `Enter a valid email address.` | `CustomersTopic.emailMessage`, the shared email field's pattern-mismatch message. |
| (none — literal, no key) | `A user with email "<email>" already exists.` | Create/detail save-action duplicate message (client precheck or server conflict). |
| (none — literal, no key) | `Delete user` | Detail form's delete action `title`. |
| (none — literal, no key) | `Delete user "<label>"? This cannot be undone.` | Detail form's delete confirmation text. |
| (none — literal, no key) | `User` | Detail's fixed `title`. |
| (none — literal, no key) | `Email`, `Display name`, `External ID`, `Handle`, `Avatar URL` | The five shared field labels from `fieldSpec(isRequiredEmail:)`. |

The generic `"<label> is required"` message a blank required field
produces (for example, a blank `email`) belongs to the Forms subsystem's
own validation, documented in the related HTDV Engine recipe, not to any
of this recipe's three given sources.

## Accessibility Options

Not applicable: none of the three given sources present any UI of their
own, so none responds to Reduce Motion, Increase Contrast, or
Differentiate Without Color; any such handling belongs to the
presentation layer that renders the `HTDVLevel`/`HTDVDetail`/`FormSpec`
values this file builds.

## Feature Flags

Not applicable: none of the three given sources read a feature-flag or an
on/off settings key. Every behavior described above is unconditional
given its inputs (the data source's responses and the user's form
entries), with no flag gating any of it.

## Analytics

Not applicable: none of the three given sources contain an analytics or
event-tracking call.

## Privacy

- **Data collected**: `CustomersTopic` and `CustomersDataSource` handle
  whatever `email`, `displayName`, `externalId`, `slug`, and `avatarUrl`
  the user types into the create/detail forms, plus the server-assigned
  `id`, `ecosystemId`, `createdAt`, and `updatedAt` values `Customer`
  decodes; `email` and `externalId` in particular are personally
  identifying, though none of it is inherently distinguished as sensitive
  by these sources.
- **Storage**: None of the three given sources persist anything to disk,
  a database, or `UserDefaults`; `Customer` values and the `FormState`
  values built from them (documented in the related HTDV Engine recipe)
  exist only in memory for the lifetime of the loaded level/detail.
- **Transmission**: `CustomersDataSource`'s five operations transmit
  whatever a concrete implementation does internally (not among the given
  sources); none of the three given sources performs a network call
  directly or applies any encryption, redaction, or transformation to the
  values before handing them to `dataSource`.
- **Retention**: Not applicable at this layer — how long a customer or
  their descriptive fields are retained is a server-side policy outside
  these three sources; nothing here defines a client-side expiry or
  cache.

## Logging

Not applicable: none of the three given sources make a logging call (no
`import os`, no `Logger`, no `print` appears in any of them). A failure
surfaces only as a thrown `HubError` as described under Behavioral
Requirements and Edge Cases; if a host wants to log it, that logging
happens outside these sources.

## Platform Notes

- **SwiftUI**: A SwiftUI host would keep `CustomersDataSource`,
  `CustomersModels`, and `CustomersTopic`'s pure static helpers
  (`fieldSpec(isRequiredEmail:)`, `input(from:ecosystemID:)`) unchanged,
  since none of them depends on AppKit/UIKit or on `CustomersTopic`'s own
  `@MainActor` class, and would drive `createSpec`/`detail`'s `FormSpec`
  values through the same `FormState` bridge described in the related
  HTDV Engine recipe's SwiftUI note, presenting the "New user" form with
  `.sheet` in place of `FormSheet.present`.
- **Compose**: Model `CustomersDataSource` as a suspend-function interface
  and `Customer`/`CustomerInput` as `@Serializable` Kotlin data classes
  with every descriptive field nullable, matching the source's own "every
  descriptive field is nullable on the wire" contract; reimplement
  `input(from:ecosystemID:)`'s asymmetry exactly — trim-only for `email`,
  blank-to-`null` for the other four — and present the "New user" form as
  a `ModalBottomSheet`/`AlertDialog` in place of `FormSheet.present`.
- **React/Web**: Model `CustomersDataSource` as an async client interface
  returning the same shapes, with a TypeScript `Customer` type whose
  descriptive fields are `string | null` and a `CustomerInput` type whose
  `email` is a required `string` and the other four are optional;
  reimplement the email-pattern check with the same regex literal
  (`emailPattern`) rather than a browser's native email input validation,
  so the user-facing message stays `"Enter a valid email address."` on
  every platform. Present the create/edit forms as a modal dialog in place
  of `FormSheet.present`, and keep the same precheck-then-server-conflict
  double guard for duplicate emails.
- **AppKit / UIKit**: This is the source: `CustomersDataSource.swift`,
  `CustomersModels.swift`, and `CustomersTopic.swift` hold no AppKit/UIKit
  import of their own — `CustomersTopic` depends only on `Foundation` and
  the `AgenticToolkitHTDV` module (`HTDVItem`, `HTDVLevel`, `HTDVChild`,
  `HTDVCreateAction`, `HTDVDetail`,
  `FormSpec`/`FormSection`/`FormAction`/`FormDeleteAction`/`FormActions`),
  and presents its create sheet through the shared `FormSheet.present`
  rather than any AppKit/UIKit API of its own.
- **WinUI 3**: Model `CustomersDataSource` as a C# interface with five
  `Task`-returning methods, backed by `HttpClient` and `System.Text.Json`
  for a concrete implementation (not among the given sources). Model
  `Customer` as a C# record with `[JsonPropertyName]` attributes and
  nullable reference types for every descriptive field, and expose
  `Label`/`Sublabel` as computed read-only properties exactly mirroring
  `Customer.label`/`sublabel`'s fallback chain, including that a
  whitespace-only value is treated as missing. Model `CustomerInput` as a
  record whose `Email` is a non-nullable `string` and whose other four
  properties are nullable, serialized with
  `JsonIgnoreCondition.WhenWritingNull` to reproduce "optional fields
  encode as absent, never `null`." Use a `ContentDialog` (or a
  `TeachingTip`-hosted form) in place of `FormSheet.present` for the
  "New user" flow, and compare emails with
  `string.Equals(a, b, StringComparison.OrdinalIgnoreCase)` in place of
  `caseInsensitiveCompare`, keeping the same
  precheck-then-server-conflict double guard.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Hub/Features/Customers/` |

## Design Decisions

**Decision**: `createSpec(for:)`'s save action checks for a duplicate
email against a freshly fetched customer list *before* calling
`create(_:)`, and also catches an `HubError.conflict` the create call
itself might throw, re-throwing it as the identical duplicate-email
message either way; `detail(for:)`'s save action skips the precheck and
relies on the conflict catch alone.
**Rationale**: The precheck-then-create sequence has an unavoidable
check-then-act window — nothing in these three sources locks the
ecosystem between the list read and the create write — so a second,
concurrent create for the same email can still reach the server after the
precheck passed. Catching the server's own conflict response and
re-mapping it to the same user-facing message means a caller sees one
consistent duplicate-email error regardless of which guard actually
caught it. The source does not explain why `detail`'s save skips the
precheck the create path performs; the observable effect is that renaming
an existing user's email to one already in use is caught only by the
server's response, one round trip later than the create path's own local
check.
**Approved**: pending

**Decision**: `input(from:ecosystemID:)` trims `email` but never
substitutes `nil` for it, while trimming-and-nil-substituting
(`HubText.nonBlank`) the other four fields.
**Rationale**: `CustomerInput.email` is declared non-optional, so there is
no `nil` to substitute — an absent or blank email becomes the empty
string `""`, which the shared `emailPattern` regex then rejects rather
than the Forms-required-field check rejecting it outright (since
`email`'s own `isRequired: true` already blocks an empty submission
before this function runs at all). The other four fields are genuinely
optional on the wire, so a blank value legitimately means "no value,"
which `HubText.nonBlank` expresses as `nil` rather than posting an empty
string.
**Approved**: pending

**Decision**: `fieldSpec(isRequiredEmail:)` takes a Boolean parameter that
both `createSpec` and `detail` always pass as `true`, per the source's own
comment that the parameter "keeps the create and detail specs literally
shared."
**Rationale**: Sharing one field-building function guarantees the
"email" field's label, placeholder, pattern, and pattern message stay
identical between the create dialog and the detail form without a second
field literal to drift out of sync; the parameter exists as a documented
seam for a future caller that might need an optional-email variant, even
though no such caller exists among these three sources today.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [error-recovery](agenticdevelopercookbook://compliance/reliability#error-recovery) | failed | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | passed | Reliability |
| [error-response-handling](agenticdevelopercookbook://compliance/access-patterns#error-response-handling) | passed | Access Patterns |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | partial | Security |

Notes: unit-test-coverage passes because `CustomersTopicTests.swift`
carries meaningful, behavior-specific assertions for every requirement
described above — 9 test methods, including the decode/label-fallback,
newline-trim, duplicate-rejection, and delete-confirmation paths — though
the detail-form `HubError.conflict` fallback (`detail-save-conflict-fallback`)
is exercised only by inspection of the source's `catch` block, not by a
dedicated test, per Conformance Test Vector 020. separation-of-concerns
passes because all three given sources import only `Foundation` (plus
`AgenticToolkitHTDV` for the HTDV/Forms types) and hold no AppKit/UIKit
dependency of their own. explicit-error-handling passes because every
`throws` boundary in these three sources is caught and converted into an
explicit `HubError` — via a specific re-mapping (`notFound`, `conflict`)
or `HubError.wrap` — with no path that drops a failure silently, per
Edge Cases' Error states. error-recovery fails because none of the three
given sources retries a failed operation or backs off — a failed
`list`/`get`/`create`/`update`/`delete` call is reported once and left to
whatever caller invoked `child`/a save action to decide what happens
next. data-integrity passes because both the create and detail save
actions validate before writing — an email-format check, a
case-insensitive duplicate-email precheck on create, and a
required-email check — before ever calling `create`/`update`.
error-response-handling passes because `CustomersTopic` explicitly
branches on the two `HubError` cases it can act on (`notFound`,
`conflict`) and uniformly wraps every other case for the caller to
display via `HubError.message` (out of these given sources), rather than
leaving any case unhandled. no-hardcoded-strings fails because every
user-facing string these sources produce — labels, field labels,
validation messages, and delete confirmation text — is a hardcoded
English literal with no localization key, per Localization above.
input-sanitization is partial: `email` receives real format validation
(the shared `emailPattern` regex, enforced both in the field spec and
implicitly by the duplicate-email comparison), but the other four fields
(`displayName`, `externalId`, `slug`, `avatarUrl`) receive no validation
or character-set restriction at all beyond the blank-to-`nil` collapse in
`other-four-fields-use-nonBlank` — `avatarUrl` in particular is never
checked to be a well-formed URL despite its name and placeholder.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation |
