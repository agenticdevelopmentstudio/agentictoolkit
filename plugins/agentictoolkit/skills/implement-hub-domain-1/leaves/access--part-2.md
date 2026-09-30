<!-- leaf: implement-hub-domain-1/access--part-2 · source: hub-domain-access.md -->

# Hub Domain Access Client — continued (part 2)

**Rules** (cite as `implement-hub-domain-1/access--part-2#<slug>`):

- `decision` MUST — restrictItem/restoreItem call authedJson rather than authedRequest, even though both are declared Promise<void>. …

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `workspace` | `string` (caller parameter) | none — required on every call | The workspace slug (personal customer slug or org slug) every `accessApi` call is scoped to; percent-encoded via `enc` before being placed in the URL. |
| `scope` (`listAssignments`) | `{ feature: string; itemId: string }` (optional) | omitted → workspace-wide listing | When given, narrows the assignments list to one item; omitted, lists workspace-wide assignments. |
| `input` (`createRole`) | `AccessRoleInput` | none — required | `{ slug, name, description?, defaultFor?, grants }`, sent verbatim as the `POST` body. |
| `patch` (`updateRole`) | `Partial<Omit<AccessRoleInput,"slug">>` | none — required | Any subset of `name`/`description`/`defaultFor`/`grants`; `slug` is excluded from the type. |
| `input` (`putAssignment`) | `AccessAssignmentInput` | none — required | `{ subjectKind, subjectId, feature?, itemId?, roleId }`, sent verbatim as the `PUT` body. |
| `q` (`effective`) | `{ feature, subjectKind, subjectId, itemId? }` | none — required | `itemId` is appended to the query string only when provided. |
| `BASE` | module constant, `"/api/access"` | fixed | Not injectable or configurable; every request path is built as `${BASE}/...`. |
| `ACCESS_FEATURES` | module constant, `ReadonlyArray<AccessFeatureRow>` | fixed two-entry array | The fallback a caller may use when `listFeatures` fails against a backend that predates `/access/features`; not applied automatically by this module. |

## Localization

`listFeatures` is the one place this module authors its own English string, rather than relaying one
from the backend:

| String Key | Default (en) | Context |
|-----------|---------------|---------|
| — | `GET /access/features returned a malformed feature list` | Thrown by `listFeatures` when the response fails `feature-row-shape-validated`'s runtime shape check |

There is no localization mechanism in this module (no catalog, no key, no `i18n` call) — the string
above is a hardcoded literal, stated as fact per the non-UI component guidance rather than as a gap.
Every other error message a caller can observe from `accessApi` originates in the backend's response
body and is extracted by `extractErrorMessage` in `auth/src/client.ts`, not authored here.

## Privacy

- **Data collected**: this module originates no data of its own; it reads and writes role, grant, and
  assignment records identifying which subjects (`customer`/`persona`/`team`) hold which roles at which
  scopes. These are access-control records, not end-user PII.
- **Storage**: none. `accessApi` is a stateless per-call request builder; it holds nothing in memory or
  on disk beyond the lifetime of a single call, per `no-client-side-cache` and `stateless-module`.
- **Transmission**: yes. Every call carries a bearer credential attached by `@agentic-toolkit/auth/client`
  (`auth-delegated-to-shared-client`), not by this module; whatever transport security the deployment
  provides is outside the scope of these two files.
- **Retention**: none. Nothing this module handles is retained after the response it produced is
  returned to the caller.

## Platform Notes

- **React/Web** (source platform): `packages/web/packages/data/src/access/access.ts` and `wire.ts`
  hold the client; `accessApi` is built entirely on `authedJson`/`authedRequest` from
  `@agentic-toolkit/auth/client` (re-exported through `./http`) and `enc` (`encodeURIComponent`) from
  `./client-helpers`; `index.ts` re-exports both files as the package's public surface for the rest of
  the web app.
- **SwiftUI**: a Swift port would model `AccessFeatureRow`/`AccessGrantRow`/`AccessRoleRow`/
  `AccessAssignmentRow`/`EffectiveAccessRow` as `Codable, Hashable, Sendable` structs, mirroring the
  pattern the sibling Hub authentication recipe's `AuthenticationModels.swift` already uses, and
  `accessApi` as an `actor` or `@MainActor final class` exposing `async throws` functions built on
  `URLSession`, with a dedicated error type carrying the HTTP status and an optional machine code in
  place of `AuthHttpError`.
- **AppKit / UIKit**: no direct UI dependency exists in this module; a macOS/iOS Hub feature would
  consume the ported client through an injected data-source protocol — the same pattern
  `ApiTokensRail`/`AccessListsTopic` already use for their own data sources — rather than calling
  `URLSession` from the view layer.
- **Compose**: model the five wire rows as Kotlin `data class`es annotated `@Serializable`, and
  `accessApi` as a class exposing `suspend fun` equivalents built on Ktor or OkHttp, with a sealed
  error type carrying the HTTP status and optional code.
- **WinUI 3**: a .NET port would model the wire rows as `record`s attributed for `System.Text.Json`,
  and `accessApi` as a class exposing `Task<T>`-returning methods built on `HttpClient`, attaching
  `Authorization: Bearer <token>` the way this module's `authedFetch` does, refreshing on a `401` the
  same one-retry way, and defining an `AccessApiException` (status, code) parallel to `AuthHttpError`
  — this is the platform with the least existing prior art in this repo for that refresh-and-retry
  contract, so the WinUI 3 port would need to build the equivalent of `authedFetch` itself, not only
  `accessApi`.

## Design Decisions

**Decision**: `ACCESS_FEATURES` is exported as a plain constant but never consulted from inside
`listFeatures` itself.
**Rationale**: the source's own comment frames it as a degraded path for "a backend that predates
`/access/features`," and the authoritative registry is per-deployment and server-refined — so
`listFeatures` staying strict (throw on anything it can't validate) and leaving the fallback decision
to the caller keeps this module from silently masking a real backend/response mismatch as an old-backend
case.
**Approved**: pending

**Decision**: `restrictItem`/`restoreItem` call `authedJson` rather than `authedRequest`, even though
both are declared `Promise<void>`.
**Rationale**: this is recorded as observed source behavior, not smoothed into the declared type — a
204 response from either endpoint throws today, per `item-restrict-restore-parse-body`; a port MUST
preserve this exact behavior rather than "fixing" it to `authedRequest`'s discard-the-body semantics,
since the current backend's actual response shape for these two routes is not available in this
checkout to confirm which is correct.
**Approved**: pending

**Decision**: only `listFeatures` validates its response shape at runtime; `listRoles`, `listAssignments`,
and `effective` trust the generic `authedJson<T>` cast.
**Rationale**: the source's own `isAccessFeatureRow` comment explains this guard was added after a
bare cast on `/access/features` let a malformed response reach every consumer looking like real data;
no equivalent comment or fix exists for the other reads, so this recipe records the current asymmetry
as a fact of the source rather than projecting the same guard onto endpoints that don't have it.
**Approved**: pending
