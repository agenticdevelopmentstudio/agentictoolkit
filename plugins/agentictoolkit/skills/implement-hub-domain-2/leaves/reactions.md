<!-- leaf: implement-hub-domain-2/reactions · source: hub-domain-reactions.md -->

**Rules** (cite as `implement-hub-domain-2/reactions#<slug>`):

- `wire-types-own-transcription` MUST
- `api-proxy-path-prefix` MUST
- `path-segment-encoding` MUST
- `stateless-module` MUST
- `no-response-caching` MUST
- `error-propagation-unmodified` MUST
- `list-target-id-cap` MUST
- `list-empty-input-short-circuits` MUST
- `list-deduplicates-target-ids` MUST
- `list-chunks-issued-concurrently` MUST
- `list-merges-chunks-in-order` MUST
- `list-scope-is-ecosystem-public` MUST
- `to-reaction-field-projection` MUST
- `add-idempotent-on-repeat` MUST
- `remove-addressed-by-reaction-id` MUST
- `tally-counts-per-emoji` MUST
- `tally-mine-identifies-viewers-own-reaction` MUST
- `tally-sort-order` MUST
- `tally-null-viewer-honest-rendering` MUST
- `by-target-groups-preserving-order` MUST
- `by-target-omits-empty-targets` MUST

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

## Privacy

- **Data collected**: this component transports reaction rows — each carrying a `customerId` (the user who reacted), a `targetKind`/`targetId` (the subject reacted to), and an `emoji` — none of which this module collects itself; it only reads and writes rows the backend already stores. Per the module's own top-of-file comment, this read is not actor-scoped: "the list is PUBLIC within the ecosystem (everyone sees who reacted)."
- **Storage**: not applicable — `reactions.ts`/`wire.ts` persist nothing themselves; every method is a stateless fetch call.
- **Transmission**: every request travels over whatever transport `authedJson`/`authedRequest` use (outside these given sources); this component configures no TLS or transport-level behavior itself.
- **Retention**: not applicable — this component defines no retention policy of its own; retention of reaction rows (including the soft-delete `deletedAt` field the read routes already filter out, per `wire.ts`) is entirely the backend's concern.

