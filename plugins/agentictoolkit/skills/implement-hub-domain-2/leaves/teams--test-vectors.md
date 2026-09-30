<!-- leaf: implement-hub-domain-2/teams--test-vectors · source: hub-domain-teams.md -->

# Hub Domain: Teams

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| hub-domain-teams-001 | identifier-validation-shape | `validateTeamIdentifier("com.acme.platform")` | `null` (`teams.test.ts`: "accepts reverse-domain identifiers") |
| hub-domain-teams-002 | identifier-validation-empty-refused | `validateTeamIdentifier("")` | Matches `/required/i` (`teams.test.ts`: "rejects an empty identifier") |
| hub-domain-teams-003 | identifier-validation-shape | `validateTeamIdentifier("platform")` | Matches `/reverse-domain/i` (`teams.test.ts`: "rejects a single-label identifier") |
| hub-domain-teams-004 | team-vocabulary-mapping | `toTeam({id:"1", name:"Platform", slug:"com.acme.platform", createdAt:"c", updatedAt:"u"})` | `t.displayName === "Platform"`, `t.identifier === "com.acme.platform"` (`teams.test.ts`: "renames name→displayName and slug→identifier") |
| hub-domain-teams-005 | team-update-partial-via-compact | `teamsApi.update("1", {displayName: "Renamed", identifier: undefined})` | PUT body `{"name":"Renamed"}` — `slug` key absent, not sent as `undefined` (`teamsApi.update`, `compact`) |
| hub-domain-teams-006 | team-create-conflict-rethrown-friendly | `teamsApi.create({displayName:"X", identifier:"com.acme.x"}, "eco1")` when the backend throws `Error("... already exists")` | Rethrown `Error('A team with identifier "com.acme.x" already exists.')` (`rethrowConflict`) |
| hub-domain-teams-007 | team-list-scoped-to-ecosystem, team-list-sorted-by-display-name | `teamsApi.list("eco1")` over backend rows named `["Beta","Alpha"]` | GET `/api/team/teams?ecosystemId=eco1`; result names `["Alpha","Beta"]` (`teamsApi.list`, `sortByText`) |
| hub-domain-teams-008 | team-get-resolves-null-on-thrown-error | `teamsApi.get("missing")` when the request throws | Resolves to `null`, does not rethrow (`teamsApi.get`) |
| hub-domain-teams-009 | team-delete-issues-delete | `teamsApi.delete("t/1")` | `DELETE /api/team/teams/t%2F1` (`teamsApi.delete`, `enc`) |
| hub-domain-teams-010 | member-list-tolerates-missing-members-key | `teamMembersApi.list("t1")` when the response body is `{}` | Resolves to `[]`, no thrown error (`teamMembersApi.list`) |
| hub-domain-teams-011 | member-list-query-scoped-by-team | `teamMembersApi.list("t1")` | GET `/api/team/members?teamId=t1` (`teamMembersApi.list`) |
| hub-domain-teams-012 | member-counts-maps-team-to-count | `teamMembersApi.counts()` over `{counts:[{teamId:"t1",count:3}]}` | `Map` with `get("t1") === 3` (`teamMembersApi.counts`) |
| hub-domain-teams-013 | member-add-by-email-resolves-existing-customer | `teamMembersApi.add("t1", "a@b.com")` | POST `/api/team/members` with body `{"teamId":"t1","email":"a@b.com"}` (`teamMembersApi.add`) |
| hub-domain-teams-014 | member-add-persona-gated-by-may-act | `teamMembersApi.addPersona("t1", "sales-bot")` | POST `/api/team/members/personas` with body `{"teamId":"t1","personaKey":"sales-bot"}` (`teamMembersApi.addPersona`) |
| hub-domain-teams-015 | member-remove-addresses-member-row | `teamMembersApi.remove("m/1")` | `DELETE /api/team/members/m%2F1` (`teamMembersApi.remove`, `enc`) |
| hub-domain-teams-016 | member-kind-discriminates-customer-vs-persona | A GET row with `memberKind: "elevated"` (an unrecognized value) | Per the type's own doc comment, a consumer MUST treat it as `"customer"`, never as `"persona"` (`TeamMember.memberKind` doc comment) |
