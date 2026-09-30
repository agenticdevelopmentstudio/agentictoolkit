<!-- leaf: implement-hub-domain-2/teams--part-3 · source: hub-domain-teams.md -->

# Hub Domain: Teams — continued (part 3)

## Localization

- **Hardcoded English strings**: `validateTeamIdentifier`'s two messages —
  `"Identifier is required."` and `"Use reverse-domain form, e.g.
  com.example.platform."` — and `teamsApi.create`/`update`'s
  `rethrowConflict` message, `A team with identifier "<identifier>" already
  exists.`, are fixed English literals in `teams.ts`.

No file in this domain defines an i18n key, a lookup table, or a locale
parameter — every user-facing string above is plain, fixed English. This is
a plain, honestly-reported fact about the current source, not a hidden gap
(see Compliance).

## Privacy

- **Data collected**: Team administrative metadata (`displayName`,
  `identifier`) and per-member data — a member's `role`, `addedAt`, and,
  for a customer member, `email`/`displayName` resolved from that
  customer's own row; for a persona member, `personaSlug`/`personaName`.
  `email` is the one field here that directly identifies a person outside
  the platform's own naming.
- **Storage**: This client holds no cache of its own — every call is a
  live round trip through `authedJson`/`authedRequest`. Whatever caching a
  consumer layers on top is outside this domain's files.
- **Transmission**: Every call travels through `authedJson`/
  `authedRequest` (`http.ts`, re-exporting `@agentic-toolkit/auth/client`'s
  Bearer-token client); this domain itself attaches no credential and reads
  no cookie.
- **Retention**: This domain retains nothing between calls; it is a
  stateless set of functions over the network. A removed member
  (`teamMembersApi.remove`) or a deleted team (`teamsApi.delete`) leaves no
  trace in this client — retention of the underlying rows is a backend
  concern this domain's files do not describe.

## Platform Notes

- **SwiftUI / AppKit / UIKit**: Not applicable — no Swift declaration
  exists in this domain; there is no Apple-side Teams implementation to
  note concurrency behavior for.
- **React/Web**: This is the sole reference implementation. Both clients
  (`teamsApi`, `teamMembersApi`) are plain objects of `async` functions
  over `fetch` (via `authedJson`/`authedRequest`); neither exports a React
  hook, unlike `hub-domain-ecosystems`'s
  `use-workspace-default-ecosystem.ts` — every export here is
  framework-agnostic and usable from a plain script or a test.
- **Windows / WinUI 3**: No WinUI 3 implementation exists in this domain. A
  port would model `Team`/`TeamMember` as plain records (or `record`
  types), route every call through a shared `HttpClient` with a Bearer
  token attached (the equivalent of `authedJson`/`authedRequest`), use
  `System.Text.Json` for the request/response bodies (mirroring
  `compact`'s undefined-vs-null distinction by only serializing properties
  actually set, e.g. via `JsonIgnoreCondition.WhenWritingNull` combined with
  nullable value types rather than omission), and reproduce
  `teamsApi.get`'s null-on-404 contract with an explicit
  `HttpStatusCode.NotFound` check rather than a bare `catch` — closing the
  gap this recipe flags in the web source
  (team-get-swallows-any-error-as-not-found). `async`/`Task` maps directly
  from this domain's `Promise`-returning methods; no `ObservableCollection`
  or `INotifyPropertyChanged` is needed, since nothing here is observed
  state — every call returns a fresh value.
- **Android**: No Android implementation exists in this domain. A Kotlin
  port would face the identical 404-vs-any-error distinction as WinUI 3
  above (checking the HTTP response code explicitly, e.g. via Retrofit/
  OkHttp, rather than catching every `IOException` alike), and would model
  `compact`'s undefined-vs-null distinction with a `Map<String, Any?>` (or
  a sealed "patch" type) rather than a Kotlin `data class`'s all-or-nothing
  field set, since a `data class` cannot distinguish "not set" from "set to
  null" the way this domain's `Partial<TeamInput>` does.
- **Python**: No Python implementation exists in this domain. A port would
  route calls through a shared `httpx`/`requests` session carrying the
  Bearer token, model `Team`/`TeamMember` as `dataclass`es or Pydantic
  models, and reproduce `compact` with a helper that drops keys whose value
  is a sentinel "unset" (not Python's own `None`, which — as in the
  TypeScript source — must remain sendable as an explicit clear).

## Design Decisions

**Decision**: Membership by an existing customer (`add`, by email) and
membership by one of the caller's own personas (`addPersona`, by key) are
two separate methods on two separate routes, rather than one method
branching on a `kind` argument.
**Rationale**: The two paths differ in both lookup (an email resolved
against the caller's ecosystem vs. a key resolved against the caller's own
personas) and authorization (an ordinary team-scope check vs. the
persona's own `may_act` `'team'` grant); collapsing them into one signature
would hide which check applies to a given call (file header: "added by
EMAIL, resolved to a customer in the ecosystem — 404 if none... or one of
the caller's personas (added by key, gated on the persona's may_act 'team'
grant)").
**Approved**: pending

**Decision**: `teams.ts` (generic CRUD) maps through a `wire.ts` row type
and a `toTeam` mapper; `team-members.ts` (a hand-written route) declares
`TeamMember` directly, with no separate wire row or mapper.
**Rationale**: The generic-CRUD backend's column names (`name`, `slug`)
differ from the UI's vocabulary (`displayName`, `identifier`), so `teams.ts`
needs a translation layer. The hand-written `/api/team/members` route "is
off the generated OpenAPI surface" and was written to match the UI's
vocabulary directly, so there is no generated row to diverge from and
nothing to translate (file headers of both files).
**Approved**: pending

**Decision**: `teamsApi.create`/`update` perform no pre-read for a
duplicate identifier before writing; the backend's unique `(owner, slug)`
constraint is the only guard, translated to a friendly message via
`rethrowConflict` only after the backend rejects the write.
**Rationale**: A pre-read is racy under concurrent writers and "can't see a
soft-deleted row still holding the slug" — the database constraint is the
one place that can answer "is this slug free" correctly (`teamsApi.create`
inline comment).
**Approved**: pending

**Decision**: `ecosystemId` is a required argument on `teamsApi.list`/
`create`, resolved by the caller (via `hub-domain-ecosystems`'s
`ecosystemIdForSlug`), rather than looked up inside this domain.
**Rationale**: A team's owning ecosystem is "the workspace's ecosystem",
and the slug-to-id resolution is `hub-domain-ecosystems`'s own concern; had
`teams.ts` performed that lookup itself, it would take on a dependency on
another domain's data shape instead of accepting the id its caller already
has (file header: "The caller resolves the id with
`ecosystemsApi.ecosystemIdForSlug(slug)`").
**Approved**: pending
