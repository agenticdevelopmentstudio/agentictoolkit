<!-- leaf: implement-general-1/api-toolkit · source: api-toolkit.md -->

# ApiToolkit

## Overview

`ApiToolkit` is the headless, non-UI logic shared by two sibling packages:
`@agentic-toolkit/api-explorer` (`packages/web/packages/api-explorer/src/`) and
`@agentic-toolkit/crud` (`packages/web/packages/crud/src/`). Neither package
exports a component named `ApiToolkit`; this recipe is the umbrella
specification for their pure `lib/` functions and headless hooks — the parts
with no JSX and no DOM access — so that the request-building, endpoint-lookup,
schema-derivation, slugging, snippet-generation, and generic-CRUD contracts
are documented once instead of being re-derived by every UI recipe that
consumes them (`CrudTable`, `CrudRecordForm`, and any `ApiBrowser`/
`ApiEndpointReference` consumer).

`api-explorer`'s logic builds and executes same-origin `/api` BFF requests
from generated OpenAPI endpoint metadata (`buildRequest.ts`, `getEndpoint.ts`),
derives cycle-safe JSON-Schema examples and field descriptions
(`schema.ts`), highlights code with a dual-theme, lazily-cached shiki
instance (`highlight.ts`), projects endpoints to crawlable, collision-checked
URL slugs (`slug.ts`), generates cURL/JavaScript request snippets with a
deliberate non-live token placeholder (`snippets.ts`), and maps HTTP
method/status to a fixed presentation "tone" (`tone.ts`). `server.ts` is a
server-only entry (no `'use client'`) that re-exports the non-interactive
pieces; `index.ts` is the client barrel and deliberately excludes the large
generated endpoint metadata so importing a button component never pulls it
into the initial bundle.

`crud`'s logic derives per-column editability from a fixed precedence
(`editability.ts`), tracks staged, dirty, mergeable row edits
(`edits.ts`), gates table visibility by a presentation-only authorization
tier (`exposure.ts`), exposes the generated CRUD schema allowlist
(`schemas.ts`), defines the shared CRUD metadata shapes (`types.ts`), runs
list/create/update/remove against the same `/api` BFF through a headless hook
with an out-of-order-response guard (`useCrudResource.ts`), bridges an
imperative unsaved-changes guard into a stable proxy object
(`useExitGuardChannel.ts`), and exposes the current viewer's admin capability
and readiness (`viewer.ts`).

