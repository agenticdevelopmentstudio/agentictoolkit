<!-- leaf: implement-status-web-src-lib-1/board-types · source: status-web-src-lib-board-types.md -->

**Rules** (cite as `implement-status-web-src-lib-1/board-types#<slug>`):

- `type-only-module` MUST
- `no-runtime-validation` MUST
- `issue-source-reuse` MUST
- `server-parity` MUST
- `wire-subset-only` MUST
- `activity-kind-members` MUST
- `activity-tone-members` MUST
- `activity-tone-stale-meaning` MUST
- `activity-tone-matches-row-tone` MUST
- `indicator-members` MUST
- `problem-fields` MUST
- `problem-target-deploy` MUST
- `problem-target-endpoint` MUST
- `problem-target-platform` MUST
- `problem-name-human` MUST
- `problem-state-vocabulary` MUST
- `problem-branch-raw` MUST
- `problem-error-text` MUST
- `problem-since` MUST
- `activity-row-fields` MUST
- `activity-row-id-deploy-format` MUST
- `activity-row-id-issue-format` MUST
- `activity-row-id-stable` MUST
- `deploy-row-id-excludes-mutable` MUST
- `activity-row-step` MUST
- `activity-row-source-spelling` MUST
- `activity-row-tone-direction` MUST
- `activity-row-verb-server-owned` MUST
- `activity-row-branch-error-null-on-issue` MUST
- `activity-row-at` MUST
- `board-fields` MUST
- `board-generated-at` MUST
- `board-data-as-of` MUST
- `board-data-as-of-distinct` MUST
- `board-probe-interval` MUST
- `board-activity-from` MUST
- `board-monitored-targets` MUST
- `cursor-pair` MUST
- `page-order` MUST
- `page-next-cursor` MUST
- `no-side-effects` MUST

# Board Wire Types

## Overview

`packages/web/packages/status-web/src/lib/board-types.ts` is the status dashboard's wire contract for `GET /api/board` and for the activity feed's paging protocol (`/api/activity`). Per its header comment it is "hand-mirrored from src/board/types.ts (the server tree, which the web app cannot import at runtime)" and is "Pinned by board-types-parity.test.ts's mutual-assignability check; keep the two in lockstep."

The module is type-only: it exports three string unions (`ActivityKind`, `ActivityTone`, `Indicator`) and five interfaces (`Problem`, `ActivityRow`, `Board`, `ActivityCursor`, `ActivityPage`) and emits no runtime code. It re-uses `IssueSource` from `./issue-sources`. It mirrors only the wire shapes: the server file additionally declares its input facts (`RosterEntry`, `DeployFact`, `BoardFacts`, and others) and constants (`ACTIVITY_WINDOW_MS`, `MAX_ACTIVITY_ROWS`, `DEGRADED_CONFIRM_MS`), none of which cross the wire and none of which appear here.

Use it wherever client code reads a board or an activity page: `useBoard` types the `/board` response as `Board`, `useActivityHistory` reads `/api/activity` as `ActivityPage` and builds its query from `ActivityCursor`, and `overview.ts`, `row-model.ts`, `KpiStrip`, `GlobalPanel` and `OverviewTab` consume `Problem`, `ActivityRow` and `Indicator`. A port reproduces these shapes exactly, because the server is the owner of every value in them.

## Behavioral Requirements

### Module shape

- **type-only-module**: The module MUST export only types; importing it MUST produce no runtime value or side effect.
- **no-runtime-validation**: The module MUST NOT validate a payload at runtime; a response typed as `Board` or `ActivityPage` is trusted as-is by the consumer that casts it (the validation owner, if any, is the fetching consumer such as `useBoard`'s `fetchBoard`, which returns `res.json()` unchecked).
- **issue-source-reuse**: `Problem.source` and `ActivityRow.source` MUST use the `IssueSource` union from `issue-sources.ts` (`"dns" | "http" | "glitchtip" | "vercel" | "cloudflare-pages" | "railway" | "crunchy"`), not a type of their own.
- **server-parity**: Every exported type MUST be mutually assignable with the same-named type exported by the status server's board module (`Board`, `Problem`, `ActivityRow`, `ActivityTone`, `ActivityKind`, `Indicator`, `ActivityCursor`, `ActivityPage`), as pinned by the `Exact<A, B>` checks in `board-types-parity.test.ts`.
- **wire-subset-only**: The module MUST NOT declare the server's fact types or server-side constants; it carries only what the server sends.

### Unions

- **activity-kind-members**: `ActivityKind` MUST be exactly `"deploy" | "probe" | "platform"`.
- **activity-tone-members**: `ActivityTone` MUST be exactly `"good" | "bad" | "progress" | "neutral" | "stale"`.
- **activity-tone-stale-meaning**: The `stale` tone MUST mean "the row's claim could not be re-confirmed (an `unknown` phase)", distinct from `progress` and from a verdict tone.
- **activity-tone-matches-row-tone**: `ActivityTone` MUST match the client's `RowTone` one-for-one so the pane renders the wire value directly instead of re-deriving it.
- **indicator-members**: `Indicator` MUST be exactly `"operational" | "degraded" | "outage"`.

### Problem

- **problem-fields**: `Problem` MUST carry exactly these fields: `target: string`, `source: IssueSource`, `name: string`, `environment: string | null`, `severity: "critical" | "major" | "minor"`, `state: string`, `statusCode: number | null`, `detail: string | null`, `sourceUrl: string | null`, `liveUrl: string | null`, `commitHash: string | null`, `commitMessage: string | null`, `commitRepo: string | null`, `branch: string | null`, `errorText: string | null`, `since: string`.
- **problem-target-deploy**: For a deploy target, `Problem.target` MUST be the output of the server's `boardTargetKey()`.
- **problem-target-endpoint**: For an endpoint, `Problem.target` MUST be the endpoint's bare id, unwrapped, because consumers tell endpoint problems apart by testing `serviceSlugs.has(target)`.
- **problem-target-platform**: For platform health, `Problem.target` MUST be `platform-health|<source>` with exactly two segments and no trailing pipe, matching the spelling already stored in the server's `issues` table.
- **problem-name-human**: `Problem.name` MUST be the human name (project or site name), never the id.
- **problem-state-vocabulary**: `Problem.state` is typed `string`; its documented values are `failed`, `stuck`, `down`, `degraded`, `stale`, `unreachable`, and the type MUST NOT be narrowed to that list without a matching server change.
- **problem-branch-raw**: `Problem.branch` MUST be the raw git ref the deploy was built from; a stale-production problem MUST carry the project's configured production branch; every non-deploy problem MUST carry `null`.
- **problem-error-text**: `Problem.errorText` MUST be the provider's own failure text, or `null` where no provider text exists.
- **problem-since**: `Problem.since` MUST be an ISO time the problem began: from the ledger when known, else the first observation.

### ActivityRow

- **activity-row-fields**: `ActivityRow` MUST carry exactly these fields: `id: string`, `kind: ActivityKind`, `step: "build" | "deploy" | null`, `source: IssueSource | null`, `tone: ActivityTone`, `verb: string`, `target: string`, `name: string`, `environment: string | null`, `detail: string | null`, `sourceUrl: string | null`, `liveUrl: string | null`, `commitHash: string | null`, `commitMessage: string | null`, `commitRepo: string | null`, `branch: string | null`, `errorText: string | null`, `at: string`.
- **activity-row-id-deploy-format**: A deployment row's `id` MUST have the form `deploy:<deploymentId>:<step>`.
- **activity-row-id-issue-format**: An issue row's `id` MUST have the form `issue:<target>:opened|resolved:<atMs>:<issueId>` (the literal `opened` or `resolved` in the third segment).
- **activity-row-id-stable**: Every component of `ActivityRow.id` MUST be immutable for the life of the fact; the client keys history by this string and cannot tell a renamed row from a withdrawn-and-replaced one.
- **deploy-row-id-excludes-mutable**: A deploy row's `id` MUST NOT include the target or a timestamp, because `deployments.created_at`, `project_name` and `branch` are corrected after the row first renders.
- **activity-row-step**: A deployment MUST emit a `build` row and, when it got that far, a separate `deploy` row; `step` MUST be `null` on probe and platform rows.
- **activity-row-source-spelling**: `ActivityRow.source` MUST use the same `IssueSource` spelling as `Problem.source` (`"cloudflare-pages"`, never `"cloudflare"`), and MUST be `null` only when genuinely unknown.
- **activity-row-tone-direction**: `tone` MUST be derived from the event; `kind` MUST NOT be recomputed from `tone`.
- **activity-row-verb-server-owned**: `verb` MUST be the rendered status word (for example `"building"`, `"build failed"`, `"deployed"`, `"[down] resolved"`); the client copies it into `Row.statusWord` and MUST NOT keep a second verb table for this pane.
- **activity-row-branch-error-null-on-issue**: `ActivityRow.branch` and `ActivityRow.errorText` MUST be `null` on an issue row.
- **activity-row-at**: `ActivityRow.at` MUST be the ISO time the event happened.

### Board

- **board-fields**: `Board` MUST carry exactly these fields: `generatedAt: string`, `dataAsOfMs: number | null`, `probeIntervalMs: number`, `activityFromMs: number`, `problems: Problem[]`, `activity: ActivityRow[]`, `indicator: Indicator`, `monitoredTargets: string[]`.
- **board-generated-at**: `generatedAt` MUST be the ISO server clock at derivation and is the client's only time reference.
- **board-data-as-of**: `dataAsOfMs` MUST be the epoch ms of the newest observation the board was derived from, or `null` when the board rests on no observations.
- **board-data-as-of-distinct**: `dataAsOfMs` MUST NOT be treated as equivalent to `generatedAt`; a wedged monitor keeps minting a fresh `generatedAt` over frozen data.
- **board-probe-interval**: `probeIntervalMs` MUST be the monitor's probe cadence in ms, carried on the board itself so consumers that never open the SSE stream still receive it.
- **board-activity-from**: `activityFromMs` MUST be the epoch ms of the oldest event `activity` can contain; consumers counting or captioning activity rows MUST read the boundary from this field instead of re-deriving a window.
- **board-monitored-targets**: `monitoredTargets` MUST list every target the board is currently watching, whether or not it has a problem, so a ledger writer can tell "recovered" from "no longer monitored".

### Activity paging

- **cursor-pair**: `ActivityCursor` MUST be the pair `{ atMs: number; id: string }`, never a timestamp alone, because a deployment's build and deploy rows share one `createdAtMs`.
- **page-order**: `ActivityPage.rows` MUST be oldest-first, like the feed itself.
- **page-next-cursor**: `ActivityPage.nextCursor` MUST point to where the next (older) page starts, or be `null` when the facts are exhausted.

### Concurrency and side effects

- **no-side-effects**: The module MUST perform no I/O, hold no state and have no ordering or concurrency behavior; it is erased at compile time.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| — | — | — | None. The module takes no parameters, environment variables or injected dependencies; it depends only on the `IssueSource` type from `./issue-sources`. |

