<!-- leaf: implement-status-web-src-lib-1/auto-configure--test-vectors · source: status-web-src-lib-auto-configure.md -->

# Auto Configure Match Adapter

## Conformance Test Vectors

Derived from `src/lib/auto-configure.test.ts` unless noted.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| autocfg-001 | endpoint-projection | `statusApi(client, fake)` where `listAllEndpoints` returns one `EndpointView` `{id:"e1", siteId:"s1", url:"https://a.com", kind:"frontend", environment:"production", platform:"vercel", deployProject:"p", ignoreProjectWarning:false, expectedStatus:200, isActive:true, …}` | `listAllEndpoints()` resolves to exactly `[{id:"e1", siteId:"s1", url:"https://a.com", kind:"frontend", environment:"production", platform:"vercel", deployProject:"p", ignoreProjectWarning:false}]` |
| autocfg-002 | opt-out-fold | Three views: `ignored` (`ignoreProjectWarning:true`), `paused` (`isActive:false`), `live` (neither) | Projected flags: `ignored → true`, `paused → true`, `live → false` |
| autocfg-003 | site-projection | `listSites` returns `{id:"s1", slug:"alpha", groupId:"g1", name:"Alpha", extra:"ignored"}` | `listSites()` resolves to `[{id:"s1", slug:"alpha", groupId:"g1"}]` |
| autocfg-004 | match-only | No endpoints or sites. `runMatch([{platform:"vercel", projectName:"help-production", domain:"agenticdeveloperhelp.com"}], {api})` | `createSite` and `createEndpoint` are never called. `added === 0`. `skipped[0]` is `{project:"help-production", reason}` with `reason` containing `no site monitors this domain` |
| autocfg-005 | added-is-count, skipped-flattened, match-write-shape | One endpoint `e1` on `https://a.com` (production). `runMatch` over `a-production` (a.com) and `b-production` (b.com) | `added === 1`. `skipped` equals `[{project:"b-production", reason:<string>}]`. One `updateEndpoint("e1", …)` call |
| autocfg-006 | client-required | `runMatch([], {})`, with no `api` and no `client` (derived from `requireClient`) | Rejects with `Error("runMatch: opts.client is required when opts.api is not supplied")` |
| autocfg-007 | injected-port-precedence | `runMatch(list, {api: fake, client: undefined})` (derived from `requireClient` being reached only when `api` is absent) | Resolves normally, and the fake port's methods are the ones called |
| autocfg-008 | detail-empty | `skipDetail(undefined)`, `skipDetail([])`, `noteDetail(undefined)`, `noteDetail([])` | Each returns `""` |
| autocfg-009 | skip-header, detail-row-format, detail-leading-separator | `skipDetail([{project:"p1", reason:"r1"}, {project:"p2", reason:"r2"}])` | `"\n\nLeft alone:\n• p1: r1\n• p2: r2"` |
| autocfg-010 | detail-no-remainder | `skipDetail` with exactly 5 rows | Splitting on `"\n• "` yields 6 parts, and the output does not contain `more` |
| autocfg-011 | detail-cap, detail-remainder | `skipDetail` with 7 rows p1..p7 | Contains `• p5: r5`, does not contain `• p6: r6`, and contains `…and 2 more` |
| autocfg-012 | note-header | `noteDetail([{project:"p1", note:"n1"}, {project:"p2", note:"n2"}])` | `"\n\nAlso:\n• p1: n1\n• p2: n2"` |
| autocfg-013 | detail-line-limit | `noteDetail` with 7 rows | Splitting on `"\n• "` yields 6 parts, and the output contains `…and 2 more` |
| autocfg-014 | per-project-resilience | Port where `updateEndpoint` rejects with `Error("boom")` for the first matching project, and a second project matches normally (derived from the engine's `applySequentially`) | First project is in `skipped` with reason `boom`. `added === 1` for the second |
| autocfg-015 | snapshot-failure-rejects | Port whose `listAllEndpoints` rejects with `Error("down")` (derived from `runAutoConfigure`) | `runMatch` rejects with `down`, and no `updateEndpoint` call is made |
| autocfg-016 | progress-forwarded | `runMatch` over 2 projects with `onProgress` spy (derived from `applySequentially`) | Spy called with `(1, 2)` and then `(2, 2)` |
| autocfg-017 | notes-flattened | Engine plan for project `x` wires an endpoint that `replaces` retired project `old` on `vercel` (derived from `executeAdd`) | `notes` equals `[{project:"x", note:"took over the monitor wired to old, which vercel no longer has"}]`, and `added === 1` |
