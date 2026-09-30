<!-- leaf: implement-hub-domain-1/buckets--edge-cases · source: hub-domain-buckets.md -->

# Hub Domain: Buckets

**Rules** (cite as `implement-hub-domain-1/buckets--edge-cases#<slug>`):

- `null-and-empty-input` MUST — An empty or whitespace-only bucket name on create or settings-save is rejected before this file's own save action runs, …
- `boundary-values` MUST — A table count of exactly 1 MUST use the singular "1 table"; every other count, including 0, MUST use the plural form …
- `concurrent-access` MUST — BucketsTopic is @MainActor-confined with no Sendable conformance of its own, so its own state (the single stored …
- `error-states` MUST — Every operation in BucketsDataSource is async throws; BucketsTopic converts every error it does not specifically remap …

## Edge Cases

- **Null and empty input**: An empty or whitespace-only bucket `name` on
  create or settings-save is rejected before this file's own save action
  runs, because `createSpec`/`settingsDetail` both mark the `"name"` field
  `isRequired: true`, and the Forms subsystem's own required-field
  validation (documented in the related HTDV Engine recipe) blocks `save()`
  from invoking the action at all (MUST, by construction of the field). An
  empty or whitespace-only table `name`, by contrast, MUST be caught by
  this file's own save action with `"Every table needs a name."`, because
  `createTableSpec`/`tableDetail` deliberately mark that field
  `isRequired: false` (MUST, see `create-table-requires-a-non-empty-trimmed-name`,
  `table-detail-save-updates-name-only`). An exactly-empty description MUST
  post `nil` metadata; a whitespace-only description is non-empty by this
  check and MUST post as literal whitespace (MUST, see
  `create-bucket-empty-description-becomes-nil-metadata`).
- **Boundary values**: A table count of exactly `1` MUST use the singular
  `"1 table"`; every other count, including `0`, MUST use the plural form
  (MUST, see `table-count-pluralization`). A name that is non-empty after
  trimming but derives an empty SQL identifier — every character stripped —
  MUST be rejected with the dedicated "no letters or digits" message rather
  than silently producing an empty `sqlTableName` (MUST, see
  `table-name-of-unusable-input-is-empty-string`,
  `create-table-rejects-a-name-with-no-usable-characters`).
- **Concurrent access**: `BucketsTopic` is `@MainActor`-confined with no
  `Sendable` conformance of its own, so its own state (the single stored
  `dataSource` reference) is not mutated concurrently from another
  isolation domain. The data it depends on can still race across separate
  requests to the server: two overlapping "create bucket" (or "create
  table") calls can both pass this file's client-side duplicate precheck
  before either has landed, because the precheck lists existing state,
  then the create call happens later with no lock in between; this file's
  own defense is that a resulting server-side `HubError.conflict` is caught
  and re-thrown as the same duplicate-name validation message the precheck
  would have produced (MUST, see `create-bucket-conflict-fallback`,
  `create-table-conflict-fallback`, and Design Decisions). `settingsDetail`'s
  save action runs no precheck at all and depends on this same
  conflict-to-validation mapping alone (MUST, see
  `settings-form-conflict-fallback-without-a-precheck`).
- **Error states**: Every operation in `BucketsDataSource` is `async
  throws`; `BucketsTopic` converts every error it does not specifically
  remap (`HubError.notFound` on `get(id:)`, `HubError.conflict` on the
  three create/update save actions) into a `HubError` via `HubError.wrap`
  and re-throws it, so no failure is dropped silently (MUST, see
  `missing-bucket-yields-empty-not-error`,
  `every-other-thrown-error-is-wrapped-not-swallowed`,
  `testFailuresSurfaceAsHubError`). `HTDVCreateAction.perform` (the
  closures passed to `HTDVLevel.createAction`) is non-throwing per its own
  declared signature (documented in the related HTDV Engine recipe), so a
  failure while presenting the "New bucket"/"New table" sheet through
  `FormSheet.present` has no channel back into this file's own error
  handling — it is the sheet's own responsibility.
- **Offline or disconnected state**: None of the three given sources make
  a network call directly or define a timeout, retry, or connectivity-aware
  behavior of their own; every call to `BucketsDataSource` either succeeds
  or throws, and a thrown error surfaces exactly as described under Error
  states above (fact, not a gap — the failure is reported, not lost, just
  with no time bound or automatic retry defined at this layer).

- **table-name-length-bound**: NEEDS REVIEW: Not implemented in source. `tableName(from:)` strips a table name down to its ASCII letters, digits, and single-underscore separators with no maximum length enforced anywhere in either `tableName(from:)` or `createTableSpec`'s save action, even though deriving a valid SQL identifier is the explicit purpose of this function; most SQL engines cap identifier length (for example, 63 bytes on PostgreSQL), so a sufficiently long table name could produce a `sqlTableName` some downstream schema-creation step truncates or rejects unpredictably, and nothing in these three sources says which system is responsible for that bound — resolvable by inspecting whichever `BucketsDataSource` implementation and server-side schema-creation code consume `sqlTableName` (not among the given sources), or by a decision from the Hub team on where the length limit belongs.

- **bucket-ecosystem-scoping**: NEEDS REVIEW: Not implemented in source. `child(for:path:rail:)` fetches a bucket by `dataSource.get(id: bucketID)` using only the raw bucket id taken from the rail path, and never compares the returned `bucket.ecosystemId` against the `ecosystem` parameter `child` was itself given before proceeding to `get`/`update(id:_:)`/`delete(id:)`/`createTable`/`updateTable(id:_:)`/`deleteTable(id:)`; `list(ecosystemID:)` is documented as ecosystem-scoped in its own doc comment, but none of the id-only operations carries or checks an ecosystem, so nothing in these three sources stops a rail path holding a bucket or table id from a different ecosystem from resolving and mutating it — resolvable by inspecting whether the deployed `BucketsDataSource` implementation enforces this scoping server-side (not among the given sources), or by a decision from the Hub team on whether client-side scoping is also required.
