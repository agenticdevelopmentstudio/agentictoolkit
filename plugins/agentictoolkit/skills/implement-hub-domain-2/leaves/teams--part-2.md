<!-- leaf: implement-hub-domain-2/teams--part-2 · source: hub-domain-teams.md -->

# Hub Domain: Teams — continued (part 2)

**Rules** (cite as `implement-hub-domain-2/teams--part-2#<slug>`):

- `team-vocabulary-mapping` MUST
- `team-identifier-is-reverse-domain` MUST
- `identifier-validation-empty-refused` MUST
- `identifier-validation-shape` MUST
- `team-list-scoped-to-ecosystem` MUST
- `team-list-sorted-by-display-name` MUST
- `team-get-resolves-null-on-thrown-error` MUST
- `team-create-no-pre-read-relies-on-backend-constraint` MUST
- `team-create-scopes-into-ecosystem` MUST
- `team-create-conflict-rethrown-friendly` MUST
- `team-update-partial-via-compact` MUST
- `team-update-conflict-rethrown-friendly` MUST
- `team-delete-issues-delete` MUST
- `team-row-id-is-opaque` MUST
- `member-kind-discriminates-customer-vs-persona` MUST
- `member-email-null-outside-ecosystem` MUST
- `member-persona-fields-null-for-customers` MUST
- `member-list-tolerates-missing-members-key` MUST
- `member-list-query-scoped-by-team` MUST
- `member-counts-maps-team-to-count` MUST
- `member-counts-is-unreferenced-but-retained` MUST
- `member-add-by-email-resolves-existing-customer` MUST
- `member-add-persona-gated-by-may-act` MUST
- `member-remove-addresses-member-row` MUST
- `member-errors-propagate-with-backend-message` MUST
- `member-add-duplicate-is-conflict` MUST
- `member-types-hand-declared-off-openapi` MUST
- `wire-types-mirror-call-sites-only` MUST
- `team-put-body-is-fully-partial` MUST

## Behavioral Requirements

### teams.ts — `teamsApi`

- **team-vocabulary-mapping**: `toTeam` MUST map the backend row's `name`
  column to `Team.displayName` and `slug` to `Team.identifier`, passing
  `id`, `createdAt`, and `updatedAt` through unchanged (`toTeam`; file
  header mapping table: "UI displayName <-> backend name", "UI identifier
  <-> backend slug").
- **team-identifier-is-reverse-domain**: `Team.identifier` MUST be a
  reverse-domain string, e.g. `com.example.platform` (`Team.identifier` doc
  comment).
- **identifier-validation-empty-refused**: `validateTeamIdentifier` MUST
  return `"Identifier is required."` for an empty identifier, checked
  before the shape rule (`validateTeamIdentifier`, confirmed by
  `hub-domain-teams-002`).
- **identifier-validation-shape**: `validateTeamIdentifier` MUST return
  `"Use reverse-domain form, e.g. com.example.platform."` for a non-empty
  identifier that fails the pattern one lowercase-alphanumeric label
  followed by one or more dot-separated lowercase-alphanumeric-or-hyphen
  labels, and MUST return `null` when the identifier passes
  (`validateTeamIdentifier`, confirmed by `hub-domain-teams-001`/`003`).
- **team-list-scoped-to-ecosystem**: `teamsApi.list(ecosystemId)` MUST GET
  `/api/team/teams?ecosystemId=<encoded ecosystemId>`; the backend then
  returns ONLY that ecosystem's teams, enforced even for an admin caller
  (file header: "`?ecosystemId=` ... list then returns ONLY that
  ecosystem's teams (enforced for admins too)").
- **team-list-sorted-by-display-name**: `teamsApi.list` MUST return teams
  sorted by `displayName` via `sortByText` (locale-aware `localeCompare`),
  never in the backend's raw row order (`teamsApi.list`).
- **team-get-resolves-null-on-thrown-error**: `teamsApi.get(id)` MUST
  resolve to `null` rather than rethrow when the underlying request throws
  — "the backend 404s with a thrown error; the UI contract is
  null-for-missing" (`teamsApi.get`).
- **team-get-swallows-any-error-as-not-found**: NEEDS REVIEW: Not implemented in source. `teamsApi.get`'s catch block returns `null` for ANY thrown error, not only the backend's documented 404, so a network failure or a 500 is indistinguishable from a team that genuinely does not exist, and no signal (a rethrow, a log call) reaches the caller to tell the two apart; settled by narrowing the catch to `httpStatus(err) === 404` (`http.ts`) and rethrowing everything else, or by an operator-visible log of the swallowed error.
- **team-create-no-pre-read-relies-on-backend-constraint**: `teamsApi.create`
  MUST NOT pre-read for a duplicate identifier before POSTing — the
  backend's unique `(owner, slug)` constraint is the sole guard, because a
  pre-read "can't see a soft-deleted row still holding the slug"
  (`teamsApi.create` inline comment).
- **team-create-scopes-into-ecosystem**: `teamsApi.create(input,
  ecosystemId)` MUST POST to `/api/team/teams?ecosystemId=<encoded
  ecosystemId>`, stamping the new team into that ecosystem so it lands in —
  and is visible under — the workspace it was created in (`teamsApi.create`
  inline comment).
- **team-create-conflict-rethrown-friendly**: On a 409 whose message
  matches "already exists" (case-insensitive), `teamsApi.create` MUST
  rethrow via `rethrowConflict` as `A team with identifier "<identifier>"
  already exists.`; any other error MUST rethrow unchanged
  (`rethrowConflict`, `teamsApi.create` catch block, confirmed by
  `hub-domain-teams-004`).
- **team-update-partial-via-compact**: `teamsApi.update(id, input)` MUST
  send only the defined optional keys of `{name, slug}` through `compact` —
  an omitted (`undefined`) field MUST be dropped from the PUT body
  (`teamsApi.update`, confirmed by `hub-domain-teams-005`).
- **team-update-conflict-rethrown-friendly**: `teamsApi.update` MUST
  rethrow a 409 slug collision via `rethrowConflict` with the same
  friendly-message shape as `create`, because "a slug rename can collide
  with the unique `(owner, slug)` index" (`teamsApi.update` inline comment).
- **team-delete-issues-delete**: `teamsApi.delete(id)` MUST issue `DELETE
  /api/team/teams/<encoded id>` and resolve to `void` on success
  (`teamsApi.delete`).
- **team-row-id-is-opaque**: `Team.id` MUST be treated as an opaque,
  server-generated identifier, never derived or parsed by this client (file
  header: "UI id <-> backend id (opaque server-generated UUID)").

### team-members.ts — `teamMembersApi`

- **member-kind-discriminates-customer-vs-persona**: `TeamMember.memberKind`
  MUST be read as `"customer"` for any value other than the literal
  `"persona"` — "present on every GET row; treat anything other than
  'persona' as a customer (robust to the api-types field still being
  optional)" (`TeamMember.memberKind` doc comment).
- **member-email-null-outside-ecosystem**: `TeamMember.email` MUST be
  `null` when the member's customer row lies outside the caller's
  ecosystem, and MUST be non-null only when resolved from a customer row
  within it (`TeamMember.email` doc comment: "resolved from the member's
  customer row; null if outside the caller's ecosystem").
- **member-persona-fields-null-for-customers**: `TeamMember.personaSlug`
  and `TeamMember.personaName` MUST be set only for a persona member and
  MUST be `null` for a customer member (`TeamMember.personaSlug`/
  `personaName` doc comments: "set only for persona members (null for
  customers)").
- **member-list-tolerates-missing-members-key**: `teamMembersApi.list`
  MUST return an empty array when the response body carries no `members`
  key, rather than dereferencing `undefined.length` — "tolerate a body
  without `members` (the route always sends it, but a proxy/error page
  might not)" (`teamMembersApi.list`).
- **member-list-query-scoped-by-team**: `teamMembersApi.list(teamId)` MUST
  GET `/api/team/members?teamId=<encoded teamId>` (`teamMembersApi.list`).
- **member-counts-maps-team-to-count**: `teamMembersApi.counts()` MUST
  return a `Map` keyed by `teamId` to that team's member count within the
  caller's scope, built from `GET /api/team/members/counts`, and MUST
  default to an empty `Map` when the response carries no `counts` array
  (`teamMembersApi.counts`).
- **member-counts-is-unreferenced-but-retained**: `teamMembersApi.counts`
  MUST remain in this client even though "nothing in the fleet calls it
  now" — the backend route it wraps is live, and this client mirrors "the
  backend's surface, not the current callers'"; it MUST be deleted only
  together with the route it wraps, never before (`teamMembersApi.counts`
  doc comment).
- **member-add-by-email-resolves-existing-customer**: `add(teamId, email)`
  MUST POST `{teamId, email}` to `/api/team/members`, adding an EXISTING
  customer resolved by email within the caller's ecosystem — never
  creating a new customer; the backend 404s when none resolves (file
  header: "added by EMAIL, resolved to a customer in the ecosystem — 404 if
  none").
- **member-add-persona-gated-by-may-act**: `addPersona(teamId, personaKey)`
  MUST POST `{teamId, personaKey}` to `/api/team/members/personas`, and the
  backend MUST refuse the call (403) unless the named persona has been
  granted `may_act` `'team'` (file header: "gated on the persona's may_act
  'team' grant").
- **member-remove-addresses-member-row**: `remove(memberId)` MUST issue
  `DELETE /api/team/members/<encoded memberId>`, addressing the MEMBER
  row's own id — not the team id, nor the underlying user's or persona's id
  (`teamMembersApi.remove`).
- **member-errors-propagate-with-backend-message**: `list`, `counts`,
  `add`, `addPersona`, and `remove` MUST NOT catch or transform a thrown
  error — `authedJson`/`authedRequest` throw an `Error` carrying the
  backend's message verbatim, and every method here lets it propagate
  unchanged so "callers surface `e.message` inline" (file header).
- **member-add-duplicate-is-conflict**: Adding a member already on the
  team MUST surface as a thrown error from a backend 409 — "the backend
  ... guards duplicates (409)" (file header); `teamMembersApi` performs no
  client-side pre-check for this, unlike `teamsApi.create`/`update`'s
  `rethrowConflict` friendly-message mapping.
- **member-types-hand-declared-off-openapi**: `TeamMember` and its request
  bodies MUST be maintained by hand in `team-members.ts` rather than
  generated, because `/api/team/members` "is off the generated OpenAPI
  surface" (file header).

### wire.ts

- **wire-types-mirror-call-sites-only**: `TeamRow`/`TeamCreateBody`/
  `TeamPutBody` MUST carry exactly the fields `teams.ts`'s mappers and call
  sites touch, replacing the hub's generated `SuccessBody<...>`/
  `RequestBody<...>` wrappers so this client does not inherit "adh product
  vocabulary a generic data client must not take on" (file header).
- **team-put-body-is-fully-partial**: `TeamPutBody`'s `name` and `slug`
  MUST both be optional, matching the generic-CRUD backend's
  `createInsertSchema().partial()` PUT contract (`TeamPutBody` comment,
  `teamsApi.update`).

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ecosystemId` (`teamsApi.list`/`create`) | `string` | required, no default | Scopes the op to that ecosystem's own teams via `?ecosystemId=` |
| `id` (`teamsApi.get`/`update`/`delete`) | `string` | required, no default | The team row's opaque server-generated id |
| `input.displayName`/`input.identifier` (`teamsApi.create`) | `string`/`string` | required, no default | Sent as backend `name`/`slug` |
| `input` (`teamsApi.update`) | `Partial<TeamInput>` | `{}` (all fields optional) | Only defined keys are sent, via `compact` |
| `teamId` (`teamMembersApi.list`/`add`/`addPersona`) | `string` | required, no default | The team a member list is read from or added to |
| `email` (`teamMembersApi.add`) | `string` | required, no default | Resolved to an existing customer within the caller's ecosystem |
| `personaKey` (`teamMembersApi.addPersona`) | `string` | required, no default | One of the caller's own personas; gated on its `may_act` `'team'` grant |
| `memberId` (`teamMembersApi.remove`) | `string` | required, no default | The membership row's own id |

