<!-- leaf: implement-hub-domain-1/customers--part-2 · source: hub-domain-customers.md -->

# Hub Domain: Customers — continued (part 2)

**Rules** (cite as `implement-hub-domain-1/customers--part-2#<slug>`):

- `data-source-contract` MUST
- `list-is-ecosystem-scoped` MUST
- `get-update-delete-take-no-ecosystem-parameter` MUST
- `data-source-is-class-bound` MUST
- `customer-shape` MUST
- `customer-label-derivation` MUST
- `customer-sublabel-derivation` MUST
- `customer-input-shape` MUST
- `customer-input-field-asymmetry` MUST
- `topic-identity` MUST
- `topic-actor-confinement` MUST
- `email-pattern-and-message-are-shared-constants` MUST
- `field-spec-is-shared-and-ordered` MUST
- `create-spec-uses-first-two-shared-fields` MUST
- `detail-spec-uses-all-five-shared-fields` MUST
- `child-dispatch-by-rail-path-presence` MUST
- `missing-customer-yields-empty-not-error` MUST
- `users-list-level-shape` MUST
- `list-level-errors-are-wrapped` MUST
- `input-builder-is-nonisolated-and-pure` MUST
- `email-is-trimmed-and-defaults-to-empty-string` MUST
- `other-four-fields-use-nonblank` MUST — input(from:ecosystemID:) MUST set displayName, externalId, slug, and avatarUrl each via …
- `create-spec-precheck-rejects-case-insensitive-duplicate` MUST
- `create-spec-conflict-fallback` MUST
- `create-spec-other-errors-are-wrapped` MUST
- `detail-shape-and-seed-values` MUST
- `detail-save-conflict-fallback` MUST
- `detail-save-other-errors-are-wrapped` MUST
- `detail-delete-shape` MUST
- `detail-delete-errors-are-wrapped` MUST

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

