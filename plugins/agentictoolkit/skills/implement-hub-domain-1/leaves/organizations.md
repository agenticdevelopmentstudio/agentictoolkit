<!-- leaf: implement-hub-domain-1/organizations · source: hub-domain-organizations.md -->

# Hub Domain: Organizations

## Overview

`hub-domain-organizations` is the Organizations domain of the hub: the non-UI logic that lists,
resolves, creates, renames, archives, and restores an *organization* — a workspace-owned record
whose creation provisions an ownership chain (a namespace, an admin team, and a default ecosystem)
and mints a reverse-domain identifier (rdid) — plus a companion client for an organization
workspace's member roster. Both live in
`packages/web/packages/data/src/organizations/`: `organizations.ts` (`organizationsApi` — six
methods, plus the `ORGANIZATIONS_QUERY_KEY` react-query cache-key prefix), `members.ts`
(`workspaceMembersApi.list`), and `wire.ts` (the backend row and request-body shapes both clients
read and send, transcribed from the backend's own OpenAPI-documented component schemas).
`index.ts` re-exports both files as `@agentic-toolkit/data/organizations`'s public surface.

The module's own top-of-file comment frames its central fact: creating an organization is a
hand-written backend operation, *not* generic CRUD — it provisions state beyond the organization
row itself — and its authorization is split two ways that this recipe documents precisely:
`create` is gated by the *workspace kind* the caller creates from (open in a personal workspace,
admin-of-the-org required from an org workspace), while `rename` is gated by *which field* is
being changed (name/description need org-team-admin; a slug change needs site-admin, because it
re-mints the organization's global rdid tree). `organizationsApi.list` is deliberately
workspace-scoped rather than a pure membership listing, for the same reason the sibling Ecosystems
domain's list is workspace-scoped: an unscoped "the caller's organizations" list answered a
membership question that stayed identical no matter which workspace was open, silently misplacing
an organization inside the wrong workspace's own rail.

