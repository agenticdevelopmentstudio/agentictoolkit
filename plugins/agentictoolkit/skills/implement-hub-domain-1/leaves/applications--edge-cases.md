<!-- leaf: implement-hub-domain-1/applications--edge-cases · source: hub-domain-applications.md -->

# Hub Domain Applications

**Rules** (cite as `implement-hub-domain-1/applications--edge-cases#<slug>`):

- `empty-applications-list` MUST — an empty [Application] result MUST render listLevel's emptyMessage ("No applications yet.") rather than an error (MUST).
- `no-schemas-to-grant` MUST — when the ecosystem has no ungranted buckets, "Add schema" MUST fail with ApplicationsTopic.noSchemasMessage rather than …
- `deleted-bucket-still-referenced-by-a-grant` MUST — a SchemaGrant whose schemaId no longer matches any bucket MUST still list and remain editable/removable, labeled …
- `boundary-table-permissions-exactly-at-the-schema-ceiling` MUST — a table's submitted permissions equal to the schema grant's own permissions MUST be accepted (isWithin is inclusive of …
- `boundary-table-permissions-exceeding-the-ceiling-by-one-flag` MUST — MUST be rejected with the table-grant-ceiling-enforcement message even when only one extra flag is set (MUST).
- `malformed-garbage-crud-wire-string` MUST — CrudPermissions(wire:) MUST NOT throw on an unrecognized token (e.g. "x,y,z"); it parses to a fully-false, isEmpty == …
- `identifier-rename-racing-a-settings-save-s-other-field-changes` MUST — settingsDetail's save action performs the rename, the grant re-home, and the field update as three sequential awaited …
- `concurrent-schema-grant-writers` MUST — see the open question on grants-write-concurrency — two overlapping setSchemaGrants calls for the same application MUST …
- `cancellation` MUST — every ApplicationsDataSource/BucketsDataSource call is a plain try await with no explicit cancellation handling in …
- `offline-or-unreachable-backend` MUST — HubError.offline/.transport(...) thrown by the injected data source MUST propagate unchanged through HubError.wrap(_:); …
- `empty-blank-required-text-fields` MUST — displayName and the "New token" name field are marked isRequired: true on their FormTextField, so blank submission is …

## Edge Cases

- **Empty applications list**: an empty `[Application]` result MUST render `listLevel`'s
  `emptyMessage` ("No applications yet.") rather than an error (MUST).
- **No schemas to grant**: when the ecosystem has no ungranted buckets, "Add schema" MUST fail with
  `ApplicationsTopic.noSchemasMessage` rather than presenting an empty, unusable picker (MUST).
- **Deleted bucket still referenced by a grant**: a `SchemaGrant` whose `schemaId` no longer
  matches any bucket MUST still list and remain editable/removable, labeled
  `ApplicationsTopic.deletedSchemaLabel` (MUST).
- **Boundary: table permissions exactly at the schema ceiling**: a table's submitted permissions
  equal to the schema grant's own permissions MUST be accepted (`isWithin` is inclusive of
  equality) (MUST).
- **Boundary: table permissions exceeding the ceiling by one flag**: MUST be rejected with the
  `table-grant-ceiling-enforcement` message even when only one extra flag is set (MUST).
- **Malformed/garbage CRUD wire string**: `CrudPermissions(wire:)` MUST NOT throw on an
  unrecognized token (e.g. `"x,y,z"`); it parses to a fully-`false`, `isEmpty == true` value,
  because parsing is a case-insensitive substring match against `{"C","R","U","D"}` with no
  validation that every token is recognized (MUST).
- **Identifier rename racing a settings save's other field changes**: `settingsDetail`'s save
  action performs the rename, the grant re-home, and the field update as three sequential awaited
  calls with no rollback of an earlier step if a later one fails — a failed `update(id:_:)` call
  after a successful rename and grant re-home leaves the application renamed and re-homed but with
  its display name/consumer kind unchanged; the source's own comment on the grant-write ordering
  acknowledges there is "no compensating write" for the grant step specifically, and the same is
  true, undocumented, for the trailing `update` call (MUST NOT roll back — matches source; NEEDS
  REVIEW below covers the concurrent-writer variant, this line covers the single-writer partial-
  failure sequence).
- **Concurrent schema-grant writers**: see the open question on grants-write-concurrency — two
  overlapping `setSchemaGrants` calls for the same application MUST NOT be assumed to compose; the
  last writer's full-array write wins and silently discards the other's change (SHOULD be
  addressed before this component is relied on for multi-writer scenarios; currently undefined).
- **Cancellation**: every `ApplicationsDataSource`/`BucketsDataSource` call is a plain `try await`
  with no explicit cancellation handling in these files; Swift's structured concurrency propagates
  a surrounding task's cancellation as a thrown `CancellationError` through the same `try await`
  path that any other error takes, so it is passed through `HubError.wrap(_:)` like any other
  failure — no code in `ApplicationsTopic` distinguishes cancellation from a network failure
  (MUST — this is what the language guarantees with no extra code, not a gap).
- **Offline or unreachable backend**: `HubError.offline`/`.transport(...)` thrown by the injected
  data source MUST propagate unchanged through `HubError.wrap(_:)`; none of these three files
  retries, queues, or caches a request to paper over the failure — a failed call simply throws and
  the caller decides whether to retry (MUST).
- **Empty/blank required text fields**: `displayName` and the "New token" `name` field are marked
  `isRequired: true` on their `FormTextField`, so blank submission is rejected by the shared form
  validator (documented in the `htdv-engine` recipe) before `ApplicationsTopic`'s own save closures
  ever run; slug format (not blankness) is the one constraint `ApplicationsTopic` itself enforces
  via `Slug.pattern` (MUST — enforcement is delegated, not absent).
