<!-- leaf: implement-hub-domain-2/teams · source: hub-domain-teams.md -->

# Hub Domain: Teams

## Overview

`hub-domain-teams` is the Teams domain of the hub: the non-UI web logic for
a *team* (a named group owned by an ecosystem) and its membership. There is
no Apple counterpart — this is a single, web-only reference implementation
(`packages/web/packages/data/src/teams/`, TypeScript), split across two
clients that sit on two different kinds of backend route:

- **`teams.ts`** — `teamsApi`, `toTeam`, and `validateTeamIdentifier`. The
  `Team` row itself is generic CRUD (`team.teams`), so this file's whole job
  is translating between the backend's column names and the UI's vocabulary
  and scoping every request to the calling workspace's owning ecosystem.
- **`team-members.ts`** — `teamMembersApi`. Membership is a hand-written
  backend route (`/api/team/members`, "OFF generic CRUD"), off the generated
  OpenAPI surface, because a member is one of two different kinds of thing —
  an existing customer added by email, or one of the caller's personas added
  by a grant-gated key — and no generic CRUD table models that choice.
- **`wire.ts`** — the backend row (`TeamRow`) and request-body
  (`TeamCreateBody`, `TeamPutBody`) shapes `teams.ts`'s mapper and call sites
  read and write; type-only, and deliberately narrower than the hub's
  generated `SuccessBody<...>`/`RequestBody<...>` wrappers so this client
  does not take on "adh product vocabulary a generic data client must not
  take on" (file header).
- **`index.ts`** — the public surface: both clients' exports.

Both clients share the transport and shaping conventions documented once
here: `authedJson`/`authedRequest` (`http.ts`, itself a re-export of
`@agentic-toolkit/auth/client`'s Bearer-token client) throw an `Error`
carrying the backend's message on failure, and every method here lets that
error propagate to the caller except `teamsApi.get`, which resolves to
`null` instead. `compact()` (`client-helpers.ts`) drops only `undefined`
keys from a PATCH/PUT body, preserving an explicit `null`.

