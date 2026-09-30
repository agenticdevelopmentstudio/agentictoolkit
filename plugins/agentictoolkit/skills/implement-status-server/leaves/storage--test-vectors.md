<!-- leaf: implement-status-server/storage--test-vectors · source: status-server-storage.md -->

# Status Server Storage Boundary

## Conformance Test Vectors

| ID | Requirement | Input | Expected Output | Notes |
|----|-------------|-------|-----------------|-------|
| storage-001 | list-site-groups | (none) | Array of all GroupRow entries, possibly empty | empty array when no groups created |
| storage-002 | create-group | `{ name: "Production", slug: "prod" }` | GroupRow with generated id, createdAt, updatedAt | slug and name persisted verbatim |
| storage-003 | create-endpoint | `{ siteId: "site1", url: "https://example.com", expectedStatus: 200 }` | EndpointRow with all fields, defaults applied to omitted optional fields | isActive defaults to true |
| storage-004 | list-active-endpoints | (none) | ConfiguredEndpoint[] with only isActive: true rows, flattened with group and site names | empty if no active endpoints |
| storage-005 | find-user-by-email | email string "User@Example.com" | UserRecord stored as "user@example.com" if exists, undefined if not | input lowercased before lookup; createUser stores lowercased |
| storage-006 | create-user | `{ email: "new@example.com", displayName: "New User", role: "pending" }` | UserRecord with generated id and createdAt | role is typed UserRole |
| storage-007 | mint-api-token | `{ name: "CLI", role: "user", createdBy: "admin1" }` | `{ meta: ApiTokenMeta, raw: string }` where raw starts with "sts_" | raw shown exactly once; hash only persisted |
| storage-008 | validate-api-token | valid raw token string | TokenPrincipal with id, name, role, expiresAt | lastUsedAt is bumped on success |
| storage-009 | validate-api-token | revoked or expired token | null | does not throw; returns null |
| storage-010 | record-checks | `[{ serviceSlug: "api", status: "up", responseTimeMs: 150, statusCode: 200, ... }]` | (void) | health_checks row persisted |
| storage-011 | latest-checks | `["api", "web"]` | LatestCheckRow[] with most recent per slug | checked_at in epoch SECONDS |
| storage-012 | upsert-deployments | `[{ id: "d1", platform: "vercel", projectName: "proj", deployPhase: "building", ... }]` | (void) | deployment row upserted by id |
| storage-013 | list-open | (none) | IssueRow[] sorted oldest-first by openedAt then id | empty if no open issues |
| storage-014 | insert-issue | IssueInsert for a target that already has an open issue | (void), no new row | insert-or-ignore on the one-open-issue-per-target index |
| storage-015 | purge-endpoint-history | `["endpoint1"]` | (void) | health_checks and metrics_hourly deleted; open issues resolved as unmonitored |
| storage-016 | role-for-email | "BOSS@example.com" with the admin in ADMIN_EMAILS | 'admin' | from auth-store.int.test.ts |
| storage-017 | role-for-email | "rando@x.com" | 'pending' | from auth-store.int.test.ts |
| storage-018 | redact-peer | `{ id: "p1", token: "" }` | `{ id: "p1", hasToken: false }` | empty string counts as no token |
| storage-019 | is-unique-violation | Error whose `.cause` message is "UNIQUE constraint failed: users.email" | true | walks the cause chain |
| storage-020 | delete-user-guarded | unknown id | false | not undefined |
