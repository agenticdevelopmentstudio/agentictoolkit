<!-- leaf: implement-status-server-monitor-2/webhook-events--part-2 · source: status-server-monitor-webhook-events.md -->

# Status Server Monitor Webhook Events — continued (part 2)

**Rules** (cite as `implement-status-server-monitor-2/webhook-events--part-2#<slug>`):

- `map-vercel-signature` MUST
- `map-railway-signature` MUST
- `pure-no-io` MUST
- `no-throw` MUST
- `vercel-state-table` MUST
- `vercel-unmapped-type-null` MUST
- `vercel-created-queued` MUST
- `vercel-build-requested-building` MUST
- `vercel-succeeded-ready-built` MUST
- `vercel-promoted-built-promoted` MUST
- `vercel-error-failed` MUST
- `vercel-canceled` MUST
- `vercel-missing-deployment-null` MUST
- `vercel-id-prefix` MUST
- `vercel-platform-literal` MUST
- `vercel-project-name` MUST
- `vercel-provider-project-id` MUST
- `vercel-phases-delegated` MUST
- `vercel-environment` MUST
- `vercel-commit-hash` MUST
- `vercel-commit-message` MUST
- `vercel-branch` MUST
- `vercel-commit-repo` MUST
- `vercel-url` MUST
- `vercel-created-at` MUST
- `railway-status-from-type` MUST
- `railway-status-precedence` MUST
- `railway-missing-required-null` MUST
- `railway-id-prefix` MUST
- `railway-platform-literal` MUST
- `railway-project-name` MUST
- `railway-provider-project-id` MUST
- `railway-phases-delegated` MUST
- `railway-environment` MUST
- `railway-commit-hash` MUST
- `railway-commit-message` MUST
- `railway-branch` MUST
- `railway-commit-repo` MUST
- `railway-url` MUST
- `railway-created-at` MUST

## Behavioral Requirements

### Signature and Purity

- **map-vercel-signature**: `mapVercelDeployEvent` MUST accept one `event: unknown` argument and MUST return either a `ProviderDeploy` object or `null`, synchronously.
- **map-railway-signature**: `mapRailwayDeployEvent` MUST accept one `event: unknown` argument and MUST return either a `ProviderDeploy` object or `null`, synchronously.
- **pure-no-io**: Neither `mapVercelDeployEvent` nor `mapRailwayDeployEvent` MUST perform a network call, a database read or write, or any logging; both functions' only observable effect is their return value.
- **no-throw**: Neither function MUST throw for any `event` value, including `undefined`, `null`, an empty object `{}`, or a value whose nested fields are the wrong type — each function casts its argument to its own event interface and reads fields through optional chaining, so an absent or mistyped field flows into a `null`/`undefined` local rather than a thrown `TypeError`.

### Vercel Event-Type Lookup

- **vercel-state-table**: `mapVercelDeployEvent` MUST look up `event.type` in the fixed table `VERCEL_STATE`, which maps exactly the event-type strings `` deployment.created ``, `` deployment.build-requested ``, `` deployment.succeeded ``, `` deployment.ready ``, `` deployment.promoted ``, `` deployment.error ``, and `` deployment.canceled `` to a `{ readyState, readySubstate }` pair; every other event-type string, and an absent `type`, MUST fail the lookup.
- **vercel-unmapped-type-null**: When `event.type` is absent or does not appear in `VERCEL_STATE`, `mapVercelDeployEvent` MUST return `null` without inspecting `event.payload` at all.
- **vercel-created-queued**: `mapVercelDeployEvent` MUST map `` deployment.created `` to `{ readyState: "QUEUED", readySubstate: null }`. Per the table's own comment, `` created `` is the deployment ENTERING the queue, not a build starting — with Vercel admitting builds only as concurrency slots free, a fleet-wide push can leave a `` created `` deployment queued for minutes to hours.
- **vercel-build-requested-building**: `mapVercelDeployEvent` MUST map `` deployment.build-requested `` to `{ readyState: "BUILDING", readySubstate: null }`. Per the table's own comment, this is the transition OUT of the queue — the moment a build slot frees and the build actually starts; the comment records that this event type was previously absent from the table, so the mapper returned `null` and the ingest route silently dropped every queued-to-building transition even though the account's webhook subscription had always included it.
- **vercel-succeeded-ready-built**: `mapVercelDeployEvent` MUST map both `` deployment.succeeded `` and `` deployment.ready `` to `{ readyState: "READY", readySubstate: null }`.
- **vercel-promoted-built-promoted**: `mapVercelDeployEvent` MUST map `` deployment.promoted `` to `{ readyState: "READY", readySubstate: "PROMOTED" }`.
- **vercel-error-failed**: `mapVercelDeployEvent` MUST map `` deployment.error `` to `{ readyState: "ERROR", readySubstate: null }`.
- **vercel-canceled**: `mapVercelDeployEvent` MUST map `` deployment.canceled `` to `{ readyState: "CANCELED", readySubstate: null }`.

### Vercel Row Construction

- **vercel-missing-deployment-null**: After a successful `VERCEL_STATE` lookup, when `event.payload.deployment.id` or `event.payload.deployment.name` is falsy, `mapVercelDeployEvent` MUST return `null`.
- **vercel-id-prefix**: A returned Vercel row's `id` field MUST be the literal string `` vc_ `` concatenated with `event.payload.deployment.id`.
- **vercel-platform-literal**: A returned Vercel row's `platform` field MUST be the literal string `"vercel"`.
- **vercel-project-name**: A returned Vercel row's `projectName` field MUST be `event.payload.deployment.name`.
- **vercel-provider-project-id**: A returned Vercel row's `providerProjectId` field MUST be `event.payload.project.id` when present, otherwise `null`. Per the source's own comment, this is "the identity the board keys on, exactly as the poller records it" (`fetch-vercel-projects.ts`, external) and as `mapRailwayDeployEvent` also does below; without it a webhook-created row is matchable only by project NAME, so a project renamed upstream owns no board target until the next full poll overwrites the row, and because `upsertDeployments` (external) COALESCEs this column, a `null` here can never erase an id an earlier poll already learned for the same deployment.
- **vercel-phases-delegated**: A returned Vercel row's `buildPhase` and `deployPhase` fields MUST be the two properties of the object returned by `vercelPhases(state.readyState, state.readySubstate, target)`, where `target` is `event.payload.target ?? null` — spread directly into the row with no additional transformation in this file. See the Status Server Monitor Deploy Status recipe for `vercelPhases`'s own mapping contract.
- **vercel-environment**: A returned Vercel row's `environment` field MUST be `event.payload.target ?? null` — the same value passed as `vercelPhases`'s `target` argument.
- **vercel-commit-hash**: A returned Vercel row's `commitHash` field MUST be `shortSha(meta.githubCommitSha)`, where `meta` is `event.payload.deployment.meta ?? {}`.
- **vercel-commit-message**: A returned Vercel row's `commitMessage` field MUST be `commitFullMessage(meta.githubCommitMessage)`.
- **vercel-branch**: A returned Vercel row's `branch` field MUST be `meta.githubCommitRef ?? null`.
- **vercel-commit-repo**: A returned Vercel row's `commitRepo` field MUST be the string `` <githubCommitOrg>/<githubCommitRepo> `` when both `meta.githubCommitOrg` and `meta.githubCommitRepo` are truthy, otherwise `null`.
- **vercel-url**: A returned Vercel row's `url` field MUST be `event.payload.links.deployment` when present, otherwise, when `event.payload.deployment.url` is present, MUST be that value prefixed with the literal `` https:// ``, otherwise MUST be `null`.
- **vercel-created-at**: A returned Vercel row's `createdAt` field MUST be `toValidDate(event.createdAt) ?? new Date()` — the current wall-clock time (the webhook's receipt time) whenever `event.createdAt` is absent or does not parse to a finite `Date` via `toValidDate` (`./provider-deploy`, agentictoolkit://recipes/status-server-monitor-provider-deploy). Per the source's own comment, "a webhook is often the only witness of a terminal state, so approximate time beats a dropped event (and an Invalid Date must never leave this boundary)."

### Railway Status Derivation

- **railway-status-from-type**: The module-private `railwayStatusFromType` helper MUST return `undefined` when its `type` argument is falsy, and otherwise MUST return the substring of `type` after its last `.` character, uppercased — e.g. `` Deployment.crashed `` becomes `` CRASHED ``.
- **railway-status-precedence**: `mapRailwayDeployEvent` MUST derive its working `status` as `event.status ?? railwayStatusFromType(event.type)` — a present `event.status` field always wins over deriving one from `event.type`.

### Railway Row Construction

- **railway-missing-required-null**: `mapRailwayDeployEvent` MUST return `null` when any of the derived `status`, `event.id`, or `event.project.name` is falsy.
- **railway-id-prefix**: A returned Railway row's `id` field MUST be the literal string `` ry_ `` concatenated with `event.id`.
- **railway-platform-literal**: A returned Railway row's `platform` field MUST be the literal string `"railway"`.
- **railway-project-name**: A returned Railway row's `projectName` field MUST be `event.project.name`.
- **railway-provider-project-id**: A returned Railway row's `providerProjectId` field MUST be `event.project.id` when present, otherwise `null` — the same identity-preservation contract as vercel-provider-project-id, for the same reason.
- **railway-phases-delegated**: A returned Railway row's `buildPhase` and `deployPhase` fields MUST be the two properties of the object returned by `railwayPhases(status)`, spread directly into the row with no additional transformation in this file. See the Status Server Monitor Deploy Status recipe for `railwayPhases`'s own mapping contract.
- **railway-environment**: A returned Railway row's `environment` field MUST be `event.environment.name` when present, otherwise `null`.
- **railway-commit-hash**: A returned Railway row's `commitHash` field MUST be `shortSha(event.commitHash)` when `event.commitHash` is a `string`, otherwise `null` — a non-string `commitHash` (including `undefined`) is never passed to `shortSha`.
- **railway-commit-message**: A returned Railway row's `commitMessage` field MUST be `commitFullMessage(event.commitMessage)` when `event.commitMessage` is a `string`, otherwise `null`.
- **railway-branch**: A returned Railway row's `branch` field MUST be `event.branch` when it is a `string`, otherwise `null`.
- **railway-commit-repo**: A returned Railway row's `commitRepo` field MUST be `event.repo` when it is a `string` containing a `` / `` character, otherwise `null`.
- **railway-url**: A returned Railway row's `url` field MUST be the string `` https://railway.com/project/<event.project.id> `` when `event.project.id` is present, otherwise `null`.
- **railway-created-at**: A returned Railway row's `createdAt` field MUST be `toValidDate(event.timestamp) ?? new Date()`, with the identical receipt-time fallback contract as vercel-created-at. The source's own inline comment marks this as "the same fallback contract as the Vercel mapper."

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `event` (parameter to `mapVercelDeployEvent`) | `unknown`, cast to the module-private `VercelEvent` shape | none — caller-supplied per call | The already-JSON-parsed Vercel webhook request body, handed in by `routes/hooks.ts` (external) after HMAC-SHA1 signature verification (`webhook-verify.ts`, external). |
| `event` (parameter to `mapRailwayDeployEvent`) | `unknown`, cast to the module-private `RailwayEvent` shape | none — caller-supplied per call | The already-JSON-parsed Railway webhook request body, handed in by `routes/hooks.ts` (external) after shared-secret verification. |
| `VERCEL_STATE` (module constant) | `Record<string, { readyState: string; readySubstate: string \| null }>` | the fixed 7-entry table under Vercel Event-Type Lookup | Not exposed to the caller or the environment; the sole source of the mapping from a Vercel event `type` string to a `readyState`/`readySubstate` pair. |

