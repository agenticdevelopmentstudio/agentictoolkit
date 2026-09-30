<!-- leaf: implement-hub-domain-1/data · source: hub-domain-data.md -->

# Hub Domain Data

## Overview

The `hub-domain-data` ingredient is the web SPA's cross-cutting data
substrate: nine dependency-light TypeScript modules at
`@agentic-toolkit/data`'s package root
(`packages/web/packages/data/src/client-helpers.ts`, `config.ts`,
`ftd-storage.ts`, `http.ts`, `tenant.ts`, `use-resource-item.ts`,
`use-resource-list.ts`, `workspace-prefs.ts`, `workspaces.ts`) that together
give every per-domain feature module in the package (the subpath exports the
package's own root file describes as the hub's per-domain modules, not part
of this contract) a shared tenant-scoped resource cache built on
`@tanstack/react-query`, browser-persisted FTD state (which id a collection
last showed, and whether it renders as cards or a list), a cached
workspace-prefs round-trip, and workspace listing/switching. It builds
directly on the Bearer-authed fetch layer, token/subject reading, and
base64url decoding that `@agentic-toolkit/auth/client` exports — documented
separately as the `auth-client` recipe (`depends-on`) — and re-exports
several of those functions unchanged rather than re-implementing them. It has
no visual surface of its own: every list, detail pane, and workspace switcher
in the app is a consumer of this contract, not part of it.

