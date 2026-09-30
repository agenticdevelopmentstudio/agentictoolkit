<!-- leaf: implement-hub-domain-1/customers--edge-cases · source: hub-domain-customers.md -->

# Hub Domain: Customers

**Rules** (cite as `implement-hub-domain-1/customers--edge-cases#<slug>`):

- `null-and-empty-input` MUST — An empty or whitespace-only email on create is rejected before this file's own save action runs, because createSpec's …
- `boundary-values` MUST — email itself receives no such blanking — it is only trimmed, never substituted with nil, because CustomerInput.email is …
- `concurrent-access` MUST — CustomersTopic is @MainActor-confined with no Sendable conformance of its own, so its own state (the single stored …
- `error-states` MUST — Every operation in CustomersDataSource is async throws; CustomersTopic converts every error it does not specifically …

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
