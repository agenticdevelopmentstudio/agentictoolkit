<!-- leaf: implement-status-web-src-lib-1/auto-configure · source: status-web-src-lib-auto-configure.md -->

**Rules** (cite as `implement-status-web-src-lib-1/auto-configure#<slug>`):

- `port-shape` MUST
- `port-default-api` MUST
- `port-client-passthrough` MUST
- `port-create-methods-wired` MUST
- `endpoint-projection` MUST
- `opt-out-fold` MUST
- `site-projection` MUST
- `update-passthrough` MUST
- `create-site-projection` MUST
- `create-endpoint-projection` MUST
- `delete-passthrough` MUST
- `port-errors-propagate` MUST
- `match-only` MUST
- `injected-port-precedence` MUST
- `client-required` MUST
- `client-port` MUST
- `live-projects-forwarded` MUST
- `progress-forwarded` MUST
- `added-is-count` MUST
- `skipped-flattened` MUST
- `notes-flattened` MUST
- `sequential-execution` MUST
- `per-project-resilience` MUST
- `snapshot-failure-rejects` MUST
- `one-snapshot-per-run` MUST
- `match-write-shape` MUST
- `detail-line-limit` MUST
- `detail-empty` MUST
- `detail-leading-separator` MUST
- `detail-row-format` MUST
- `detail-cap` MUST
- `detail-remainder` MUST
- `detail-no-remainder` MUST
- `skip-header` MUST
- `note-header` MUST
- `detail-pure` MUST
- `no-cross-run-serialization` MUST
- `network-side-effects` MUST
- `no-timeout-or-retry` MUST

# Auto Configure Match Adapter

## Overview

`packages/web/packages/status-web/src/lib/auto-configure.ts` is the status dashboard's side of "Auto Configure". It does no matching of its own: the planner, classifier and runner belong to `@agentic-toolkit/deploy-platform/engine` (`runAutoConfigure`), the same code the Hono server runs behind `POST /auto-configure`. The file's header comment explains why: the app used to carry a hand-written copy of the planner, and "the browser and the server could canonicalize a host differently and file the same project under different sites depending on which button the operator pressed."

The module exports four things:

- `statusApi(client, api?)` — adapts the monitored-sites client onto the engine's I/O port, `StatusAddApi`.
- `runMatch(addable, opts)` — runs the engine **match-only** (it never passes `create`) and flattens the result to the `MatchRun` shape the dialogs render.
- `skipDetail(rows)` and `noteDetail(rows)` — build the "Left alone:" and "Also:" text blocks appended to the engine's `summarizeAutoConfigure` sentence, capped at `SKIP_DETAIL_LINES` (5) named projects.

Callers: `components/configure/PlatformProjects.tsx` calls `runMatch` for the per-platform "Match" and "Match all" buttons. `components/AutoConfigureProvider.tsx` appends `noteDetail` and `skipDetail` to the server-driven global "Auto Configure" summary. Site creation stays on the server, because only the server sees every site in one transaction-scoped snapshot.

## Behavioral Requirements

### Port adapter: `statusApi`

- **port-shape**: `statusApi(client, api)` MUST return an object implementing all six `StatusAddApi` methods: `listAllEndpoints`, `listSites`, `updateEndpoint`, `createSite`, `createEndpoint`, `deleteSite`.
- **port-default-api**: When `api` is omitted, `statusApi` MUST use the module's own monitored-sites client functions (`../api/monitored-sites`) as the backing implementation.
- **port-client-passthrough**: Every port method MUST forward the supplied `client` as the first argument of the matching monitored-sites function.
- **port-create-methods-wired**: `createSite`, `createEndpoint` and `deleteSite` MUST be fully wired to the client even though `runMatch` never reaches them. The doc comment says "an adapter that threw for half its port would be a trap for the next caller."
- **endpoint-projection**: `listAllEndpoints` MUST map each `EndpointView` to an `EndpointLite` holding exactly `id`, `siteId`, `url`, `kind`, `environment`, `platform`, `deployProject` and `ignoreProjectWarning`. The board's probe and monitoring fields (`expectedStatus`, `expectBody`, `dnsCheckA`, `dnsCheckAaaa`, `dnsCheckCname`, `checkIntervalSeconds`, `isActive`) MUST NOT appear in the output. This projection drops data deliberately.
- **opt-out-fold**: The projected `ignoreProjectWarning` MUST be `true` when the view's `ignoreProjectWarning === true`, or when its `isActive === false`, and `false` otherwise. This is `autoConfigureOptedOut` from `./config-status`, the same fold the server's adapter applies.
- **site-projection**: `listSites` MUST map each `SiteView` to exactly `{ id, slug, groupId }`. Every other field MUST be dropped.
- **update-passthrough**: `updateEndpoint(id, body)` MUST call the client's `updateEndpoint(client, id, body)` and resolve to what the client returns. The body is forwarded unchanged; the only check is a compile-time type cast.
- **create-site-projection**: `createSite(body)` MUST send only `name`, `slug` and `groupId` from `body`, and MUST resolve to `{ id }` taken from the created site.
- **create-endpoint-projection**: `createEndpoint(siteId, body)` MUST forward `body` unchanged and MUST resolve to the created endpoint passed through the same `EndpointLite` projection as `listAllEndpoints`.
- **delete-passthrough**: `deleteSite(id)` MUST call the client's `deleteSite(client, id)` and resolve when it resolves.
- **port-errors-propagate**: A rejection from any monitored-sites function MUST propagate unchanged out of the port method that called it. The adapter catches nothing.

### Match run: `runMatch`

- **match-only**: `runMatch` MUST call `runAutoConfigure` without a `create` option. A project that no existing endpoint monitors MUST therefore be skipped with the engine's reason `no site monitors this domain yet`, and MUST NOT cause any `createSite` or `createEndpoint` call.
- **injected-port-precedence**: When `opts.api` is supplied, `runMatch` MUST use it as the engine's port and MUST NOT construct one from `opts.client`.
- **client-required**: When `opts.api` is absent and `opts.client` is `undefined`, `runMatch` MUST reject with an `Error` whose message is `runMatch: opts.client is required when opts.api is not supplied`. It MUST NOT fall back to a default network client.
- **client-port**: When `opts.api` is absent and `opts.client` is supplied, `runMatch` MUST use `statusApi(opts.client)` as the port.
- **live-projects-forwarded**: `runMatch` MUST forward `opts.liveProjects` to the engine unchanged. The engine uses it to tell stale wiring apart from a live conflict.
- **progress-forwarded**: `runMatch` MUST forward `opts.onProgress` to the engine unchanged. The engine calls it as `(done, total)` once per project, after that project settles.
- **added-is-count**: `MatchRun.added` MUST equal the number of projects the engine reported in `added`. The engine's `created` list MUST NOT be counted; it is empty by construction because `create` is never passed.
- **skipped-flattened**: `MatchRun.skipped` MUST list one `{ project, reason }` per engine skip, in the engine's order. `project` MUST be the skipped project's `projectName` and `reason` MUST be the engine's reason text, unchanged.
- **notes-flattened**: `MatchRun.notes` MUST list one `{ project, note }` per engine note, in the engine's order. `project` MUST be the project's `projectName` and `note` MUST be the engine's note text, unchanged.
- **sequential-execution**: Projects MUST be applied strictly one after another, never in parallel, so that each match sees the wiring written by the previous one. This ordering is enforced by the engine's `applySequentially`, and `runMatch` MUST NOT reorder or batch `addable`.
- **per-project-resilience**: A project whose apply throws MUST be recorded in `skipped`, with the error's `message` as its reason (or `String(e)` for a non-`Error`), and MUST NOT stop the rest of the batch. The engine provides this behavior.
- **snapshot-failure-rejects**: When the engine's initial `listAllEndpoints` or `listSites` call rejects, `runMatch` MUST reject with that error. No partial `MatchRun` is returned.
- **one-snapshot-per-run**: Each `runMatch` call MUST read endpoints and sites once, at the start, and MUST plan every project against that snapshot as updated by the run's own writes. Other runs, whether in the browser or on the server, are not seen.
- **match-write-shape**: Each successful match MUST issue one `updateEndpoint` call whose body sets `platform`, `deployProject` and `environment`. The engine builds this body; `runMatch` does not alter it.

### Detail blocks: `skipDetail`, `noteDetail`

- **detail-line-limit**: `SKIP_DETAIL_LINES` MUST equal `5`, and both blocks MUST use it as their cap.
- **detail-empty**: `skipDetail` and `noteDetail` MUST return the empty string `""`, with no header, when their input is `undefined` or an empty array.
- **detail-leading-separator**: A non-empty block MUST start with two newlines (`"\n\n"`) and then its header line.
- **detail-row-format**: Each named row MUST read `• <project>: <why>` on its own line, in input order.
- **detail-cap**: A block MUST name at most the first `SKIP_DETAIL_LINES` rows.
- **detail-remainder**: When the input has more rows than `SKIP_DETAIL_LINES`, the block MUST end with a final line `…and <N> more`, where `N` is the input length minus the number of rows shown, not the total.
- **detail-no-remainder**: When the input has `SKIP_DETAIL_LINES` rows or fewer, the block MUST NOT contain a `…and` line.
- **skip-header**: `skipDetail` MUST use the header `Left alone:` and MUST take each row's `why` from `reason`.
- **note-header**: `noteDetail` MUST use the neutral header `Also:` and MUST take each row's `why` from `note`.
- **detail-pure**: `skipDetail` and `noteDetail` MUST be pure and synchronous, with no I/O and no mutation of their input.

### Concurrency and side effects

- **single-threaded**: All calls run on the browser's single JavaScript thread. Within one run, port calls are awaited one at a time, except for the engine's first read, which issues `listAllEndpoints` and `listSites` together via `Promise.all`.
- **no-cross-run-serialization**: `runMatch` MUST NOT serialize itself against other concurrent `runMatch` calls. Callers own that guard: `PlatformProjects` uses an `addingRef` so each platform panel runs one match at a time.
- **network-side-effects**: The only side effects of `runMatch` MUST be the port's HTTP calls through the supplied client: two reads, then one `updateEndpoint` per matched project.
- **no-timeout-or-retry**: `runMatch` MUST NOT add a timeout, retry or cancellation of its own. A hung request holds the run until the client's own transport settles. There is no `AbortSignal` parameter.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `statusApi` `client` | `StatusApiClient` | none (required) | Client forwarded to every monitored-sites call |
| `statusApi` `api` | `typeof import("../api/monitored-sites")` | the real `monitored-sites` module | Backing functions; tests inject a fake module |
| `runMatch` `addable` | `ProjectLite[]` | none (required) | Projects to match, applied in array order |
| `runMatch` `opts.api` | `StatusAddApi` | `statusApi(opts.client)` | Injected engine port; takes precedence over `client` |
| `runMatch` `opts.client` | `StatusApiClient` | none | Required when `opts.api` is absent; no hidden default |
| `runMatch` `opts.liveProjects` | `PlanOpts["liveProjects"]` | `undefined` | Live-project index forwarded to the planner |
| `runMatch` `opts.onProgress` | `(done: number, total: number) => void` | `undefined` | Per-project progress callback |
| `SKIP_DETAIL_LINES` | `number` constant | `5` | Row cap shared by `skipDetail` and `noteDetail` |

No environment variables or settings keys are read.

