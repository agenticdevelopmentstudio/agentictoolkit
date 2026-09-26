---
id: 15c61cfc-543c-493d-b686-c605b773be83
title: Board Wire Types
domain: agentictoolkit://cookbook/status-web/lib/board-types
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Type-only wire contract for GET /api/board and the activity paging protocol,
  hand-mirrored from the status server's board types.
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://cookbook/status-web/hooks/use-board
- agentictoolkit://cookbook/status-web/hooks/use-activity-history
- agentictoolkit://cookbook/status-web/api
references: []
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a type-only wire contract, not a visual component.

## States

Not applicable — this is a type-only wire contract, not a visual component.

## Accessibility

Not applicable — this is a type-only wire contract, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| board-types-001 | server-parity | Compile `Exact<server.Board, web.Board>` (and the same for `Problem`, `ActivityRow`, `ActivityTone`, `ActivityKind`, `Indicator`, `ActivityCursor`, `ActivityPage`) where `Exact<A, B>` is true only under mutual assignability | Every check resolves to `true` and the file typechecks; renaming a field, widening a nullability or adding a union member on one side makes it fail to compile |
| board-types-002 | indicator-members | Keys of the client's `INDICATOR_STATE` map, sorted | Exactly `["degraded", "operational", "outage"]` |
| board-types-003 | problem-fields, issue-source-reuse | A `Problem` literal with `target: "vercel\|example"`, `source: "vercel"`, `name: "example"`, `severity: "minor"`, `state: "failed"`, `since: "2026-06-30T00:00:00.000Z"` and every nullable field `null` | Typechecks; omitting any field, or setting `source: "cloudflare"`, fails to typecheck |
| board-types-004 | indicator-members, problem-fields | Empty `Problem[]` passed to the client's `indicatorFromProblems` and to the server's `indicatorFor` | Client result equals `{ state: INDICATOR_STATE[indicatorFor([])], count: 0 }` |
| board-types-005 | problem-fields | `[minor, minor]` problems | Client result equals `{ state: INDICATOR_STATE[indicatorFor(problems)], count: 2 }` |
| board-types-006 | problem-fields | `[major, minor]` problems | Client result equals `{ state: INDICATOR_STATE[indicatorFor(problems)], count: 2 }` |
| board-types-007 | problem-fields | `[minor, major, critical]` problems | Client result equals `{ state: INDICATOR_STATE[indicatorFor(problems)], count: 3 }` |
| board-types-008 | activity-kind-members, activity-tone-members | Assign `"deploy"`, `"probe"`, `"platform"` to `ActivityKind`; assign `"good"`, `"bad"`, `"progress"`, `"neutral"`, `"stale"` to `ActivityTone` | All typecheck; `"issue"` as `ActivityKind` or `"warning"` as `ActivityTone` fails |
| board-types-009 | activity-row-id-deploy-format, activity-row-step | Deployment `abc` that reached the deploy step | Two rows with ids `deploy:abc:build` (`step: "build"`) and `deploy:abc:deploy` (`step: "deploy"`), no target or timestamp in either id |
| board-types-010 | cursor-pair, page-next-cursor | `ActivityPage` with `nextCursor: { atMs: 1719705600000, id: "deploy:abc:build" }`, then one with `nextCursor: null` | Both typecheck; `nextCursor: 1719705600000` (a bare number) fails; the null page means history is exhausted |
| board-types-011 | board-fields, board-data-as-of | `Board` with `dataAsOfMs: null`, empty `problems`, `activity` and `monitoredTargets` | Typechecks; omitting `probeIntervalMs` or `activityFromMs` fails |
| board-types-012 | type-only-module, no-side-effects | Import the module and inspect its runtime exports | No runtime values are exported |

## Edge Cases

- **Empty board**: `problems`, `activity` and `monitoredTargets` MAY each be empty arrays; the type allows it and `indicatorFor([])` yields the operational indicator (test vector board-types-004). MUST.
- **No observations**: `dataAsOfMs` MUST be `null` when the board rests on no observations; consumers MUST treat that as distinct from a fresh board (`useBoard` folds it into a `no-data` reason). MUST.
- **Unknown source at runtime**: A server that emits an `IssueSource` the client does not know is not caught by this module (no runtime validation); per `issue-sources.ts` the client then renders `undefined` in the filter and badge. The parity test is the guard against this, at compile time only. MUST (fact of the contract).
- **Out-of-vocabulary state**: `Problem.state` is a free `string`; a value outside the documented list MUST still typecheck and be carried through unchanged. MUST.
- **Shared timestamp**: A deployment's build and deploy rows share one `createdAtMs`; paging MUST use the `(atMs, id)` pair so neither row is repeated or skipped across pages. MUST.
- **Corrected deploy metadata**: When `deployments.created_at`, `project_name` or `branch` is corrected after first render, the row `id` MUST NOT change. MUST.
- **Exhausted history**: `nextCursor: null` MUST mean no older page exists. MUST.
- **Drift under test runs**: `pnpm test` transpiles without typechecking, so drift is caught only by `pnpm typecheck` in this package and by the dashboard host's `web` typecheck, which names the parity test under `files`. SHOULD run both in CI; a test-only run cannot detect drift.
- **Malformed payload**: A response that does not match `Board` is not detected by this module; behavior is owned by the consumer that parses it (see [useBoard](agentictoolkit://cookbook/status-web/hooks/use-board)). MUST (fact of the contract).
- **Concurrency, network, offline, cancellation, timeouts**: Not applicable; the module has no runtime behavior.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| — | — | — | None. The module takes no parameters, environment variables or injected dependencies; it depends only on the `IssueSource` type from `./issue-sources`. |

## Deep Linking

Not applicable: the module declares data types and handles no URLs or routes.

## Localization

Not applicable: the module holds no strings; `ActivityRow.verb` and `Problem.name` are server-supplied values rendered verbatim, and localizing them is the server's concern.

## Accessibility Options

Not applicable: the module has no visual output.

## Feature Flags

Not applicable: the module reads no flags.

## Analytics

Not applicable: the module emits no events.

## Privacy

Not applicable: the module stores and transmits nothing; the fields it types (project names, commit metadata, URLs) carry no credentials or personal data by declaration.

## Logging

Not applicable: the module has no runtime code and logs nothing.

## Platform Notes

- **SwiftUI**: Model each interface as a `struct` conforming to `Codable, Sendable, Hashable`; each union as a `String`-raw-value `enum` conforming to `Codable`. Nullable fields become optionals, decoded with `JSONDecoder` (keys already camelCase). Unlike TypeScript, decoding validates at runtime: an unknown `IssueSource` or `state` member fails decode, so decide per field whether to add an `unknown` fallback case. `ActivityRow.id` is the natural `Identifiable.id`.
- **Compose**: Kotlin `@Serializable data class` per interface with `kotlinx.serialization`; unions as `enum class` with `@SerialName` for hyphenated members (`"cloudflare-pages"`). Set `Json { ignoreUnknownKeys = true }` if the server may add fields; an unknown enum value throws unless `coerceInputValues` or a custom serializer handles it.
- **React/Web**: Source platform. `src/lib/board-types.ts` is the type-only mirror; `src/lib/board-types-parity.test.ts` holds the `Exact<A, B>` mutual-assignability guard against `@agentic-toolkit/status-server/board` plus the `indicatorFromProblems` versus `indicatorFor` agreement tests. Types are erased, so a port that wants runtime safety adds a schema (for example zod) at the fetch site.
- **AppKit / UIKit**: Same `Codable` structs as the SwiftUI note, in a UI-free module shared by both; no framework types are involved.
- **WinUI 3**: Declare C# `record` types (`public sealed record Problem(...)`) with `string?`/`int?`/`long?` for nullable fields and `IReadOnlyList<T>` for arrays, deserialized with `System.Text.Json` (`JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase }`). Map unions to C# `enum`s with `JsonStringEnumConverter` plus `[JsonStringEnumMemberName("cloudflare-pages")]` (.NET 9) for hyphenated members, or keep them `string` to mirror TypeScript's lenient behavior. Epoch-ms fields (`dataAsOfMs`, `atMs`, `probeIntervalMs`, `activityFromMs`) are `long`; ISO fields may be `DateTimeOffset`, but keep `ActivityRow.id` a `string`. For binding, project `Board.problems` and `Board.activity` into an `ObservableCollection<T>` keyed by `target` / `id` in a view model that implements `INotifyPropertyChanged`. There is no compile-time parity check against the server; a shared contract assembly or a JSON-schema test replaces `board-types-parity.test.ts`.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/lib/board-types.ts` |

## Design Decisions

**Decision**: Hand-mirror the server's board types instead of importing them.
**Rationale**: The header comment states the web app "cannot import at runtime" the server tree; there is no shared package between the backend and its embedded web app. Drift is caught by the parity test's `Exact<A, B>` checks, compiled by two typechecks.
**Approved**: pending

**Decision**: Carry `tone` and `verb` on the wire instead of deriving them in the client.
**Rationale**: "the server owns what a row SAYS, exactly as it owns whether the row exists"; `ActivityTone` matches `RowTone` one-for-one so the pane renders it directly, and `kind` is never recomputed from `tone` (the doc comment cites that exact mistake as defect #1 in the spec).
**Approved**: pending

**Decision**: Platform-health targets use two segments, `platform-health|<source>`, not `boardTargetKey()` output.
**Rationale**: That spelling already exists in the `issues` table; "a provider is not a deploy target, and giving it a third segment would orphan every live platform-health row for no gain."
**Approved**: pending

**Decision**: Deploy row ids exclude target and timestamp.
**Rationale**: Those deployment fields are corrected after first render, and the client cannot distinguish a renamed row from a replaced one, so ids must use only immutable components.
**Approved**: pending

**Decision**: Paging cursor is the `(atMs, id)` pair.
**Rationale**: Build and deploy rows of one deployment share a `createdAtMs`; a time-only cursor would re-serve or skip one of them.
**Approved**: pending

**Decision**: `Board` carries `probeIntervalMs`, `activityFromMs` and `monitoredTargets`.
**Rationale**: The cadence previously arrived only on the SSE stream and was null for non-stream consumers; the activity boundary is read rather than re-derived; `monitoredTargets` replaces `/live`'s `deployTargets` so the ledger writer can tell recovery from de-configuration, since `resolveIssue` alerts on the first and stays silent on the second.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | best-practices |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | reliability |

The module contains only the wire contract, with fetching, derivation and rendering in other modules, so separation-of-concerns passes. `board-types-parity.test.ts` pins every exported type to the server by mutual assignability and checks the indicator mapping, so unit-test-coverage passes. Data-integrity is partial: the parity guard runs at compile time only, `pnpm test` transpiles without typechecking, and no runtime check rejects a payload that does not match the types, so an unknown union member reaches the UI unchecked.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial recipe extracted from `board-types.ts` and `board-types-parity.test.ts` |
