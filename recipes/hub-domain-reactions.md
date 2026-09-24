---
id: 5e7bafd6-fb7e-45fc-a1de-31e34edf5431
title: 'Hub Domain: Reactions'
domain: agentictoolkit://recipes/hub-domain-reactions
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Web data client (reactionsApi, tally, byTarget) and wire types for emoji
  reactions on any (targetKind, targetId) subject.
platforms:
- typescript
- web
tags:
- hub
- reactions
- emoji
- tally
- crud
depends-on: []
related:
- agenticdevelopertoolkit://recipes/reaction-bar
references:
- packages/web/packages/data/src/reactions/reactions.ts (agentictoolkit)
- packages/web/packages/data/src/reactions/wire.ts (agentictoolkit)
- packages/web/packages/data/src/reactions/__tests__/reactions.test.ts (agentictoolkit)
- packages/web/packages/data/src/http.ts (agentictoolkit)
- packages/web/packages/data/src/client-helpers.ts (agentictoolkit)
- packages/web/packages/auth/src/client.ts (agentictoolkit)
- packages/web/packages/auth/src/tokens.ts (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Hub Domain: Reactions

## Overview

This component is `reactionsApi` (three methods: `list`, `add`, `remove`) plus the pure
folding helpers `tally` and `byTarget` and the mapper `toReaction`, all in `reactions.ts`,
with their wire shapes in `wire.ts`. It is the one client for emoji reactions on ANY
subject in the product: the backend store names a reaction's subject as a free
`(targetKind, targetId)` pair rather than a foreign key into one table, so a comment, a
discussion post and a research document all reach the same `/api/content/reactions`
surface through the same three calls — a new kind of thing to react to needs only a new
`targetKind` string, never a new table, route, or client. This is a **logic** component:
`reactions.ts` and `wire.ts` render nothing — they are a plain fetch-based client, two pure
array-folding functions, and type-only wire shapes, consumed by presentational UI (the
sibling `ReactionBar` component, not part of this component's given sources) that owns no
reaction state of its own.

## Behavioral Requirements

### Module-wide

- **wire-types-own-transcription**: `ReactionRow` and `ReactionCreateBody` MUST come from this module's own `./wire`, hand-narrowed from the backend's OpenAPI `Reaction` schema rather than imported from `@agentic-toolkit/adh-api-types`, per `wire.ts`'s own comment ("a generic data client must not take on" adh's product vocabulary).
- **api-proxy-path-prefix**: every request `reactionsApi` issues MUST address the fixed `BASE` path `/api/content/reactions`, or an id-suffixed path under it.
- **path-segment-encoding**: every dynamic value interpolated into a request path (`targetKind`, the joined `targetIds` batch, `reactionId`) MUST be passed through `enc` (`encodeURIComponent`) first.
- **stateless-module**: `reactionsApi` MUST hold no instance- or module-level mutable state between calls; every method's request MUST be built solely from the arguments passed to that call. `MAX_TARGET_IDS` is a fixed constant, not per-call state.
- **no-response-caching**: none of `list`, `add`, or `remove` MUST cache a prior response; every call MUST issue a fresh `authedJson`/`authedRequest` request.
- **error-propagation-unmodified**: none of `list`, `add`, or `remove` MUST catch, transform, or discard a rejection from `authedJson`/`authedRequest`; each method's returned promise MUST reject with whatever error that call throws, unmodified — no method body contains a `try`/`catch`.

### Reading

- **list-target-id-cap**: `list(targetKind, targetIds)` MUST split its de-duplicated, non-empty `targetIds` into batches of at most `MAX_TARGET_IDS` (200) before requesting, per its own comment describing this as "the backend's cap on one batched read."
- **list-empty-input-short-circuits**: `list` MUST resolve to `[]` without issuing any request when, after filtering falsy entries and de-duplicating, zero target ids remain — per its own comment, "the backend requires at least one, and a pane whose list has not arrived yet should not send a call it knows is a 400."
- **list-deduplicates-target-ids**: `list` MUST de-duplicate `targetIds` (via `new Set`) and MUST drop any falsy entry (via `.filter(Boolean)`) before batching.
- **list-chunks-issued-concurrently**: when `targetIds` spans more than one batch, `list` MUST issue all batches' requests concurrently (`Promise.all`), not sequentially.
- **list-merges-chunks-in-order**: `list` MUST return the merged rows in batch order (`pages.flatMap`), regardless of which batch's request settles first over the network.
- **list-scope-is-ecosystem-public**: `list` MUST NOT filter its result to the calling actor's own reactions; per the module's own top-of-file comment, "the list is PUBLIC within the ecosystem (everyone sees who reacted); only writes are scoped to the actor."
- **to-reaction-field-projection**: `toReaction` MUST map a `ReactionRow` to a `Reaction` carrying exactly `id`, `customerId`, `targetKind`, `targetId`, `emoji`, and `createdAt`; it MUST NOT carry the row's `ecosystemId` or `deletedAt` fields into the mapped `Reaction`.

### Writing

- **add-idempotent-on-repeat**: `add(targetKind, targetId, emoji)` MUST always resolve with a `Reaction` for a POST to `BASE` with `{ targetKind, targetId, emoji }`; per the module's own top-of-file comment, "ADDING is idempotent on (actor, target, emoji) — a repeat POST returns the existing row rather than a 409, so a double-click is not an error to handle."
- **remove-addressed-by-reaction-id**: `remove(reactionId)` MUST issue a DELETE to `` `${BASE}/${enc(reactionId)}` ``, addressing the caller's own reaction by ITS id, never by emoji or by subject — per the module's own comment, this is "which is why `tally` hands back the caller's own reaction id rather than a bare boolean."

### Folding

- **tally-counts-per-emoji**: `tally(reactions, viewerId)` MUST return exactly one `ReactionTally` per distinct emoji present in `reactions`, whose `count` equals the number of `reactions` entries carrying that emoji.
- **tally-mine-identifies-viewers-own-reaction**: for each `ReactionTally`, `mine` MUST be the `id` of the one entry in `reactions` whose `emoji` matches and whose `customerId` equals `viewerId`, or `null` when no such entry exists.
- **tally-sort-order**: `tally`'s returned array MUST be sorted by `count` descending; two emoji with equal counts MUST keep the order in which the emoji first appeared in `reactions`, per the function's own comment ("ties keep the order the emoji first appeared, so a bar does not reshuffle as counts even up").
- **tally-null-viewer-honest-rendering**: `tally` MUST accept `viewerId: string | null`; when `viewerId` is falsy (`null` or `""`), every returned `ReactionTally.mine` MUST be `null` rather than a guess, per the function's own comment ("pass null when unknown and every tally reads as not-mine — the honest rendering rather than a wrong one").
- **by-target-groups-preserving-order**: `byTarget(reactions)` MUST return a `Map<string, Reaction[]>` keyed by `targetId`, where each bucket's entries appear in the same relative order they held in the input `reactions` array.
- **by-target-omits-empty-targets**: `byTarget` MUST NOT create an entry for a `targetId` that no reaction in the input names; such a target MUST simply be absent from the returned `Map` rather than mapped to an empty array.

## Appearance

Not applicable — this is a data client, not a visual component.

## States

Not applicable — this is a data client, not a visual component. `reactionsApi` holds no runtime state machine of its own; see `stateless-module` under Behavioral Requirements.

## Accessibility

Not applicable — this is a data client, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| reactions-001 | wire-types-own-transcription | Read the import statement at the top of `reactions.ts` | Imports `ReactionCreateBody`/`ReactionRow` only from `./wire`; no import from `@agentic-toolkit/adh-api-types` |
| reactions-002 | api-proxy-path-prefix, path-segment-encoding | `reactionsApi.list("project.comments", ["c1", "c2"])` | `authedJson` called once with `"/api/content/reactions?targetKind=project.comments&targetIds=c1%2Cc2"` (per `reactions.test.ts`, "reads MANY subjects in one request") |
| reactions-003 | list-empty-input-short-circuits | `reactionsApi.list("project.comments", [])` | Resolves to `[]`; `authedJson` is never called (per `reactions.test.ts`, "issues NO request for an empty subject list") |
| reactions-004 | list-deduplicates-target-ids | `reactionsApi.list("project.comments", ["c1", "c1", "c2"])` | `authedJson` called with `targetIds=c1%2Cc2` — `"c1"` appears once (per `reactions.test.ts`, "de-duplicates subjects before asking") |
| reactions-005 | list-target-id-cap, list-chunks-issued-concurrently | `reactionsApi.list("project.comments", <201 distinct ids>)` | `authedJson` called exactly twice; the first call's `targetIds` has 200 entries, the second has 1 (per `reactions.test.ts`, "chunks past the backend's cap") |
| reactions-006 | list-merges-chunks-in-order | Same 201-id call, with the two chunk responses mocked to resolve `{items:[row("r1")]}` then `{items:[row("r2")]}` | Resolved array is `[r1, r2]`, in that order (per `reactions.test.ts`, "merges every chunk's rows into one list") |
| reactions-007 | add-idempotent-on-repeat | `reactionsApi.add("project.comments", "c1", "👍")` with `authedJson` mocked to resolve a `ReactionRow` | POST to `/api/content/reactions` with body `{"targetKind":"project.comments","targetId":"c1","emoji":"👍"}`; resolves with the mapped `Reaction` (per `reactions.test.ts`, "add POSTs the whole subject") |
| reactions-008 | remove-addressed-by-reaction-id | `reactionsApi.remove("r1")` | `authedRequest` called with `"/api/content/reactions/r1"` and `{ method: "DELETE" }` (per `reactions.test.ts`, "remove addresses the REACTION's id") |
| reactions-009 | tally-counts-per-emoji, tally-mine-identifies-viewers-own-reaction | `tally([r1(👍,cust-1), r2(👍,cust-2), r3(🎉,cust-2)], "cust-1")` | `[{emoji:"👍",count:2,mine:"r1"},{emoji:"🎉",count:1,mine:null}]` (per `reactions.test.ts`, "counts per emoji and hands back the VIEWER's own reaction id") |
| reactions-010 | tally-null-viewer-honest-rendering | `tally([r1(👍), r2(🎉)], null)` | Every returned `ReactionTally.mine` is `null` (per `reactions.test.ts`, "claims nothing when the viewer is unknown") |
| reactions-011 | tally-sort-order | `tally([r1(🎉), r2(👍), r3(👀), r4(👀)], null)` | Emoji order `["👀","🎉","👍"]` — 👀 first on count (2), then 🎉 before 👍 on first-appearance (per `reactions.test.ts`, "orders by count, and a tie keeps the order the emoji first appeared") |
| reactions-012 | by-target-groups-preserving-order, by-target-omits-empty-targets | `byTarget([r1(c1), r2(c2), r3(c1)])`, then read `.get("c9")` | Keys in order `["c1","c2"]`; `groups.get("c1")` is `[r1,r3]`; `groups.get("c9")` is `undefined` (per `reactions.test.ts`, "unpacks a batched read back into one bucket per subject") |
| reactions-013 | to-reaction-field-projection | `toReaction({id:"r1",customerId:"cust-1",ecosystemId:"eco-1",targetKind:"project.comments",targetId:"c1",emoji:"👍",createdAt:"t-r1",deletedAt:null})` | Returned `Reaction` has exactly `{id,customerId,targetKind,targetId,emoji,createdAt}`; no `ecosystemId` or `deletedAt` key present |
| reactions-014 | error-propagation-unmodified | `authedJson` mocked to reject with an `AuthHttpError(503, "no worker registered")` for `reactionsApi.add` | The returned promise rejects with that same error, unmodified |
| reactions-015 | list-scope-is-ecosystem-public | Read `reactionsApi.list`'s implementation | No filter, `.filter`, or comparison against a caller/actor id anywhere in the method body |

## Edge Cases

- **Empty `targetIds` array**: `list` resolves `[]` with no request issued. MUST (`list-empty-input-short-circuits`).
- **All-falsy `targetIds` (e.g. `["", "", ""]`)**: `.filter(Boolean)` removes every entry, leaving an empty set, so the same no-request short-circuit applies as an all-empty array. MUST.
- **Empty `emoji` string passed to `add`**: `reactions.ts` performs no client-side check of `emoji`'s shape or non-emptiness before POSTing; the value is sent to the backend verbatim, and any rejection (documented or not) surfaces unmodified per `error-propagation-unmodified`. MUST.
- **`viewerId` as an empty string**: `tally`'s guard is `viewerId && ...`, so `""` is treated exactly like `null` — every `mine` comes back `null`, not merely "no match found." MUST (`tally-null-viewer-honest-rendering`).
- **Exactly `MAX_TARGET_IDS` (200) target ids**: `list` issues exactly one request; the boundary case one id below the cap must not trigger a second chunk. MUST.
- **One id past the cap (201)**: `list` issues exactly two requests, 200 ids then 1, per `reactions-005`. MUST.
- **Concurrent calls to `list`, `add`, or `remove`**: `reactionsApi` holds no shared state between calls (`stateless-module`); two concurrent calls — even the same operation against the same subject — MUST NOT be serialized, deduplicated, or coalesced by this module; each fires its own independent request whose relative completion order depends on the network, not this file. MUST.
- **One chunk of a multi-chunk `list` rejects**: `Promise.all` rejects as soon as any one chunk's `authedJson` call rejects; the rows from any OTHER chunk that already resolved are discarded — `list` never returns a partial result, per `error-propagation-unmodified`. MUST.
- **Network unreachable**: a `fetch` failure (no connectivity) rejects before any `Response` exists; per `error-propagation-unmodified`, the calling method's promise rejects with that same underlying error, uncaught. MUST.
- **Non-2xx response**: per `authedFetch` (in `@agentic-toolkit/auth/client.ts`, outside these two given files but read to resolve this contract), a non-ok response becomes an `AuthHttpError` carrying the response's status and an extracted message; exactly one `401` triggers one token-refresh-and-retry before this conversion. MUST.
- **Offline or disconnected mid-request**: none of `list`, `add`, or `remove` registers a retry, timeout, or an abort signal of its own; a request that never settles leaves the returned promise pending for as long as the underlying `fetch` call takes to settle. MUST.
- **Malformed `list` response body (missing `items` key)**: `list` calls `p.items.map(toReaction)` unconditionally on each resolved page; a page missing `items` throws a `TypeError` from inside the `.then`/`await` chain, rejecting `list`'s promise rather than being caught. MUST.
- **`add` called twice with the same `(actor, target, emoji)`**: per the module's own comment, the second call resolves with the SAME existing reaction row rather than rejecting with a 409 — this is the documented idempotency contract, not a race. MUST.
- **repeat-remove-behavior**: a repeat `remove` against an already-removed id issues another `DELETE content/reactions/:id` exactly like the first; the client adds no de-duplication, and whatever the backend returns (success or an error status) surfaces to the caller unchanged. Unlike `add`, no comment documents a repeat `remove` as idempotent.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `targetKind` | `string` | none (required) | The subject's kind (e.g. `"project.comments"`); passed to `list` and `add`, URL-encoded via `enc()` for `list`'s query string and sent verbatim in `add`'s JSON body. |
| `targetIds` | `string[]` | none (required) | Subject ids to batch-read via `list`; de-duplicated, filtered of falsy entries, and chunked at `MAX_TARGET_IDS`. |
| `targetId` | `string` | none (required) | The single subject id passed to `add`, sent verbatim in the JSON body (not URL-encoded, since it travels in the body, not the path). |
| `emoji` | `string` | none (required) | The reaction glyph passed to `add`; no client-side format or length check. |
| `reactionId` | `string` | none (required) | The reaction's own id passed to `remove`, URL-encoded via `enc()` into the DELETE path. |
| `viewerId` | `string \| null` | none (required parameter of `tally`) | The reader's own user id (typically from `readTokenSubject()`, outside these given sources); `null`/`""` makes every `ReactionTally.mine` read as not-mine. |
| `MAX_TARGET_IDS` | `number` (module constant) | `200` | The backend's cap on one batched `list` read; fixed in `reactions.ts`, not caller-configurable — changing it requires editing the source. |
| Bearer access token | implicit environment dependency | none | Attached to every request by `authedJson`/`authedRequest`/`authedFetch` (in `@agentic-toolkit/auth/client.ts`, outside these two given files) via `readAccessToken()`; not a parameter of any `reactionsApi` method. |
| Request base path | implicit environment dependency | `/api/content/reactions` (relative) | Every path is relative, resolved against the current page origin through the host's `/api/:path*` BFF proxy; no base-URL environment variable appears in `reactions.ts`. |

## Deep Linking

Not applicable: neither `reactions.ts` nor `wire.ts` defines a URL scheme, route table, or navigation handler. Every path this module builds is an outbound API request path, not an inbound deep link.

## Localization

Not applicable: `reactions.ts` and `wire.ts` contain no user-facing string literal — no `throw new Error("...")`, no display text, and no i18n library call. The only string literals in either file are the fixed `BASE` path and HTTP method names — data values and request shapes, not display copy.

## Accessibility Options

Not applicable: these files render nothing and read no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color, VoiceOver).

## Feature Flags

Not applicable: no given source gates any of its own behavior behind a feature flag.

## Analytics

Not applicable: no given source calls an analytics or event-emission API of any kind.

## Privacy

- **Data collected**: this component transports reaction rows — each carrying a `customerId` (the user who reacted), a `targetKind`/`targetId` (the subject reacted to), and an `emoji` — none of which this module collects itself; it only reads and writes rows the backend already stores. Per the module's own top-of-file comment, this read is not actor-scoped: "the list is PUBLIC within the ecosystem (everyone sees who reacted)."
- **Storage**: not applicable — `reactions.ts`/`wire.ts` persist nothing themselves; every method is a stateless fetch call.
- **Transmission**: every request travels over whatever transport `authedJson`/`authedRequest` use (outside these given sources); this component configures no TLS or transport-level behavior itself.
- **Retention**: not applicable — this component defines no retention policy of its own; retention of reaction rows (including the soft-delete `deletedAt` field the read routes already filter out, per `wire.ts`) is entirely the backend's concern.

## Logging

Not applicable: neither `reactions.ts` nor `wire.ts` calls `console.log`, `Logger`, or any other logging API.

## Platform Notes

- **SwiftUI**: not applicable to these sources directly — this is a web-only component with no Apple counterpart given. A Swift port's networking/model layer (see AppKit/UIKit below) is the same regardless of whether the consuming UI is SwiftUI or AppKit; SwiftUI itself adds nothing beyond that shared layer.
- **AppKit / UIKit**: model `reactionsApi` as a small `struct`/`enum` namespace of three `async throws` functions built on `URLSession`, mirroring `list`/`add`/`remove` 1:1 (including `list`'s de-dupe, `MAX_TARGET_IDS`-chunking, and `TaskGroup`-based concurrent chunk fetch with `flatMap`-in-order merge); model `Reaction`, `ReactionRow`, and `ReactionCreateBody` as `Codable, Hashable` structs. Model `tally` and `byTarget` as free functions over `[Reaction]`; since Swift's `Dictionary` gives no iteration-order guarantee, build the per-emoji fold with an explicit ordered structure — e.g. an array of `(emoji, ReactionTally)` pairs alongside a lookup — so a `sort(by:)` on `count` (Swift's `sort` is not guaranteed stable) is followed by an explicit tiebreak on each emoji's first-seen index, reproducing the source's "ties keep first-appearance order" guarantee that a bare `Dictionary` cannot.
- **React / Web**: this is the source platform. `reactions.ts` (`reactionsApi`, `tally`, `byTarget`, `toReaction`) and `wire.ts` (the wire types, "Type-only file" per its own header comment) live under `packages/web/packages/data/src/reactions/`; TypeScript's structural typing means the `ReactionCreateBody`/`ReactionRow` shapes are checked only at compile time and by the backend at request time, never by this module at runtime.
- **Compose**: model each of the three operations as a `suspend fun` on a `ReactionsApi` interface returning the Kotlin equivalent data class (`kotlinx.serialization.Serializable`); model `tally`'s per-emoji fold with a `LinkedHashMap<String, ReactionTally>` rather than a plain `HashMap`, since `LinkedHashMap` preserves insertion order — the direct Kotlin analog of the source's JS `Map`-based fold — before sorting by `count` with a stable `sortedByDescending`.
- **WinUI 3**: model `reactionsApi` as a C# class whose three methods return `Task<T>`/`Task` over `HttpClient`, using `System.Text.Json` with `JsonNamingPolicy.CamelCase` for the `Reaction`/`ReactionRow`/`ReactionCreateBody` records, and `Task.WhenAll` for `list`'s concurrent chunk fetch (mirroring `Promise.all`) followed by an in-order `SelectMany` merge (mirroring `pages.flatMap`). The distinctive porting problem this recipe exists to flag: `tally`'s tie-break relies on the JS `Map`'s guaranteed insertion-order iteration, but `System.Collections.Generic.Dictionary<TKey,TValue>`'s enumeration order is explicitly UNDOCUMENTED and must never be relied on for this — a WinUI 3 port needs to track first-seen order itself (e.g. a separate `List<string>` of emoji keys appended to as each is first encountered, or an `OrderedDictionary`) and use that list, not `Dictionary` enumeration, as the tiebreak key before a stable `OrderBy(t => -t.Count).ThenBy(firstSeenIndex)`. A tally exposed to a bound `ItemsControl` is a plain `IReadOnlyList<ReactionTally>` rebuilt on each fold, not an `ObservableCollection` the source never mutates in place.

## Design Decisions

**Decision**: `reactions.ts` transcribes its own wire types into `wire.ts` by hand from the backend's OpenAPI `Reaction` schema, rather than importing generated types from `@agentic-toolkit/adh-api-types`.
**Rationale**: `wire.ts`'s own comment states this directly — the toolkit's generic data client "must not take on" adh's product vocabulary. This keeps the `packages/data` layer product-agnostic at the cost of a second, hand-maintained copy of the backend's `Reaction` schema that must be kept in sync by hand, per the same comment ("the cost is that a backend contract change is caught by keeping this in sync, not by the build").
**Approved**: pending

**Decision**: `add` is documented as idempotent on `(actor, target, emoji)` (a repeat POST returns the existing row, not a 409), while `remove` carries no equivalent documented guarantee for a repeat call against an already-removed id.
**Rationale**: the module's own top-of-file comment calls out idempotent `add` and id-addressed `remove` as two of the "three things the surface does that a caller must not re-derive," but says nothing about repeating a `remove`. The asymmetry is recorded rather than resolved; see `repeat-remove-behavior` under Edge Cases.
**Approved**: pending

**Decision**: this component owns no reaction UI state — no toggle logic, no optimistic update, no re-fetch-after-write. `add`/`remove` resolve once and return; the caller decides when and how to re-read.
**Rationale**: `tally` and `byTarget` are pure folds over whatever `Reaction[]` a caller already has; the module comment frames the batched `list` read as the caller's job "rendering a pane," not this client's. The sibling presentational component [ReactionBar](agenticdevelopertoolkit://recipes/reaction-bar) is built on exactly this split — it is stateless itself and calls back with an emoji, leaving the write and the re-read to its consumer — the same division this data client assumes.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | partial | Reliability |
| [error-response-handling](agenticdevelopercookbook://compliance/access-patterns#error-response-handling) | partial | Access Patterns |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | partial | Security |

`separation-of-concerns` passes: `reactions.ts`/`wire.ts` contain no UI-rendering import and no business logic beyond building a path, choosing an HTTP verb, shaping a body, and folding an already-fetched array — a clean, single-purpose data-access layer consumed by a separate presentational package. `unit-test-coverage` passes: `reactions.test.ts` exercises every one of `list`'s branches (empty input, de-dupe, chunking, chunk-merge), both writes, and all three folding-function behaviors (`tally`'s count/mine/order/null-viewer, `byTarget`'s grouping). `explicit-error-handling` passes: every method lets `authedJson`/`authedRequest`'s rejection propagate untouched — there is no `catch` anywhere in either file to silently swallow one. `idempotent-operations` is partial: `add` is documented and (per the module comment) backend-enforced as idempotent on `(actor, target, emoji)`, but `remove`'s repeat-call behavior is undocumented in the given sources — see `repeat-remove-behavior` under Edge Cases and the second Design Decision above. `error-response-handling` is partial: every rejection from `authedJson`/`authedRequest` propagates to the caller unmodified, so no documented status code (404, 409, 503, etc.) is ever translated into a friendlier, entity-named message by this module itself — a caller must inspect the raw error (e.g. via `httpStatus`/`isConflict`/`isServiceUnavailable` in `http.ts`, outside these two given files) to act on a specific status. `input-sanitization` is partial: `enc()` (`encodeURIComponent`) sanitizes every dynamic URL segment against path injection, but no field-level validation of `emoji`'s shape, `targetKind`'s membership in a known set, or `targetId`'s format happens in this module — every one of those constraints, if any exist, is enforced only by the backend's response.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
