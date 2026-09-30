<!-- leaf: implement-hub-domain-2/security · source: hub-domain-security.md -->

# Hub Domain Security Client

## Overview

`tokens.ts` and `bucket-access.ts`, re-exported by `index.ts`, are the public surface of the security
data domain: two independent, unrelated-at-runtime clients that happen to share one folder because
both guard access to backend resources. `tokensApi` (`tokens.ts`) mints, lists, and revokes the
caller's own personal API tokens against `/api/auth/tokens`. `bucketAccessApi` (`bucket-access.ts`)
is, per its own top-of-file comment, "wired to the real backend access-group routes
(`websites/backend/src/routes/bucketGroups.ts`)": CRUD for bucket-scoped access lists (a named group
of principals plus CRUD grants per target), their members, and their grants, against
`/api/bucket/access-groups` and `/api/bucket/buckets/{bucketId}/access-groups`. `wire.ts` holds the
wire shapes for both; its own header comment states it is a package-local mirror of the
OpenAPI-generated shapes the hub previously imported from `@agentic-toolkit/adh-api-types` (for
`/auth/tokens` and `/bucket/{access-groups,buckets}/*`), carrying full backend-schema fidelity so the
toolkit stays decoupled from the hub's generated types. Both clients are thin request builders over
the shared `authedJson`/`authedRequest` helpers from `@agentic-toolkit/auth/client` (re-exported
through `./http`), plus `enc`/`compact` from `./client-helpers`. Neither client is a visual surface —
this is a headless **logic** module, so this recipe marks Appearance, States, and Accessibility not
applicable and carries the runtime contract entirely in Behavioral Requirements, per the non-UI
component guidance this recipe was authored under.

