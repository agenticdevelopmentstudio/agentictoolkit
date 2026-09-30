<!-- leaf: implement-hub-domain-1/markdown--test-vectors · source: hub-domain-markdown.md -->

# Hub Domain Markdown Client

## Conformance Test Vectors

| ID | Input | Expected Output / Effect | Source |
|----|-------|---------------------------|--------|
| HDM-001 | `withTags({id: "d1", title: "Doc"})` (no `tags` field) | `{id: "d1", title: "Doc", tags: []}` | markdown.test.ts, "defaults a missing tags field to []" |
| HDM-002 | `withTags({id: "d1", tags: null})` | `.tags` resolves to `[]` | markdown.test.ts, "defaults a null tags field to []" |
| HDM-003 | `withTags({id: "d1", tags: ["a", "b"]})` | returns the exact same object reference, unmodified | markdown.test.ts, "passes a real array through unchanged" |
| HDM-004 | `categoryNodes({items: ["Meetings"], nodes: [{id: "c1", name: "Meetings", parentIds: [], sortOrder: 0}]})` | returns the exact same `nodes` array reference | markdown.test.ts, "passes real nodes through unchanged" |
| HDM-005 | `categoryNodes({items: [], nodes: []})` | `[]` (does not rebuild from empty `items`) | markdown.test.ts, "prefers nodes even when they are EMPTY" |
| HDM-006 | `categoryNodes({items: ["Admin", "Meetings", "Reading"]})` (no `nodes`) | `[{id: "Admin", name: "Admin", parentIds: [], sortOrder: 0}, {id: "Meetings", ...sortOrder: 1}, {id: "Reading", ...sortOrder: 2}]` | markdown.test.ts, "rebuilds an older backend's flat names as roots" |
| HDM-007 | `categoryNodes({})` (neither field present) | `[]`, does not throw | markdown.test.ts, "yields [] when NEITHER field is an array" |
| HDM-008 | `tagNodes({items: ["alpha", "beta"]})` (no `nodes`) | `[{id: "alpha", label: "alpha"}, {id: "beta", label: "beta"}]` | markdown.test.ts, "rebuilds an older backend's flat labels" |
| HDM-009 | `markdownApi.routeAvailable("doc 1", "a/b", {workspace: "acme"})` | issues `GET /api/content/markdown/doc%201/route-available/a%2Fb?workspace=acme` | markdown.test.ts, "asks the author-scoped endpoint with both segments encoded" |
| HDM-010 | backend resolves `routeAvailable` with `{available: false, reason: "reserved"}` | `markdownApi.routeAvailable` resolves with that object unchanged | markdown.test.ts, "returns the backend's verdict unchanged" |
| HDM-011 | `markdownApi.publish(id, route)` where the POST throws a conflict (`isConflict`) | throws `Error('The route "<route>" is already used by one of your papers.')`, discarding the original error | markdown.ts, `publish`'s catch block (no dedicated test exercises this branch) |
| HDM-012 | `markdownApi.createCategory({name})` where the POST throws a conflict | throws `Error('A category named "<name>" already exists somewhere else.')` | markdown.ts, `createCategory`'s catch block (no dedicated test) |
| HDM-013 | `schemasApi.create({tables: [{name: "Contacts"}, {name: "contacts"}], ...}, ecosystemId)` | throws `Error('Duplicate table name "contacts" in this bucket.')` before any network request is issued | schemas.ts, `assertUniqueTableNames` (no test file exists for schemas.ts) |
| HDM-014 | `schemasApi.create` succeeds on the parent bucket but the second table's POST throws | calls `rollbackSchema` (deletes the first created table, then the bucket, via `Promise.allSettled`), then rethrows the table-creation error unchanged | schemas.ts, `create`'s catch block (no test file) |
| HDM-015 | `schemasApi.get(id)` where the underlying GET throws any error (404, 500, or a network failure) | resolves `null` in every case, with no way to distinguish which occurred | schemas.ts, `get`'s bare `catch { return null }` — see the open question on schemas-get-swallows-errors |
| HDM-016 | `schemasApi.list(ecosystemId)` with buckets belonging to several ecosystems | resolves only the buckets whose `ecosystemId` matches, sorted alphabetically by name | schemas.ts, `list` (`scopeByOwner` + `sortByText`, no test file) |
| HDM-017 | `taxonomyApi.removeCategoryParent(childId, parentId)` called when no edge with that `parentId` exists for `childId` | resolves with zero DELETE calls issued | taxonomy.ts, `removeCategoryParent`'s own doc comment (no test file exists for taxonomy.ts) |
| HDM-018 | `markdownApi.list({}, {noted: false, doc: false})` | request query string omits both `noted` and `doc` entirely (not sent as `false`) | markdown.ts, `listQuery` |
