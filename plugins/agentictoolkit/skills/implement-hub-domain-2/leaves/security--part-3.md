<!-- leaf: implement-hub-domain-2/security--part-3 · source: hub-domain-security.md -->

# Hub Domain Security Client — continued (part 3)

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `BASE` (`tokensApi`) | module constant, `"/api/auth/tokens"` | fixed | Not injectable; every `tokensApi` request path is built as `${BASE}/...`. |
| `GROUPS` (`bucketAccessApi`) | module constant, `"/api/bucket/access-groups"` | fixed | Not injectable; the base path for group/member/grant operations by `groupId`. |
| `BUCKETS` (`bucketAccessApi`) | module constant, `"/api/bucket/buckets"` | fixed | Not injectable; used only by `createGroup`'s `${BUCKETS}/{bucketId}/access-groups` path. |
| `body` (`mint`) | `MintTokenBody` (`{ name, expiresAt?, scope? }`) | none — required | Sent verbatim as the `POST` body; `expiresAt`/`scope` are omitted from the wire body entirely when left `undefined` by `JSON.stringify`. |
| `id` (`revoke`) | `string` (caller parameter) | none — required | The token's `id`; percent-encoded via the global `encodeURIComponent` before being placed in the URL. |
| `bucketId` (`createGroup`) | `string` (caller parameter) | none — required | The owning bucket; percent-encoded via `enc`. |
| `groupId` (most `bucketAccessApi` methods) | `string` (caller parameter) | none — required | The access group's `id`; percent-encoded via `enc`. |
| `input` (`createGroup`) | `{ name: string; description?: string }` | none — required | `name` is trimmed before send; `description` is sent only when truthy. |
| `patch` (`updateGroup`) | `{ name?: string; description?: string }` | none — required | Each key is sent only when the caller supplies it (checked via `!== undefined`, not truthiness). |
| `input` (`addMember`) | `{ memberType: MemberType; memberId: string }` | none — required | Sent verbatim as the `POST` body. |
| `memberRowId` (`removeMember`) | `string` (caller parameter) | none — required | The `AccessGroupMember.id` of the membership row, not the principal's id. |
| `input` (`upsertGrant`) | `{ targetType: GrantTargetType; targetId: string; crud: string }` | none — required | Sent verbatim as the `PUT` body; `crud` is not validated client-side. |
| `grantId` (`deleteGrant`) | `string` (caller parameter) | none — required | The grant's `id`; percent-encoded via `enc`. |

## Localization

`bucket-access.ts` is the one place in this domain that authors its own English strings, rather than
relaying one from the backend:

| String Key | Default (en) | Context |
|-----------|---------------|---------|
| — | `An access list named "<name>" already exists.` | Thrown by `createGroup` on a name conflict, via `rethrowConflict` |
| — | `An access list named "<name>" already exists.` | Thrown by `updateGroup` on a name conflict, via `rethrowConflict` |
| — | `That member is already in this access list.` | Thrown by `addMember` on a member-uniqueness conflict, via `rethrowConflict` |

There is no localization mechanism in this domain (no catalog, no key, no `i18n` call) — the three
strings above are hardcoded literals, stated as fact per the non-UI component guidance rather than as
a gap. Every other error message a caller can observe from `tokensApi` or `bucketAccessApi` originates
in the backend's response body and is extracted by `extractErrorMessage` in `auth/src/client.ts`, not
authored in these two files.

## Privacy

- **Data collected**: `tokensApi` originates and returns personal API token records — `id`, `name`,
  `prefix` ("non-secret leading chars, for display"), `createdAt`, `expiresAt`, `lastUsedAt`, `scope`
  — and, on `mint` only, the raw secret `token` value, documented as "shown exactly once."
  `bucketAccessApi` reads and writes access-group, member, and grant records identifying which
  principals (`user`/`organization`/`persona`/`app`/`token`) hold which CRUD grants at which targets.
  The token secret is credential material; the access-group records are access-control records, not
  end-user PII.
- **Storage**: none within these files. Both clients are stateless per-call request builders (per
  `stateless-module`); neither holds the minted secret, a session token, or any access-control record
  in memory or on disk beyond the lifetime of a single call.
- **Transmission**: yes. Every call carries a bearer session credential attached by
  `@agentic-toolkit/auth/client` (`auth-delegated-to-shared-client`), not by these modules; `mint`
  additionally receives a freshly issued raw secret token in its response body. Whatever transport
  security the deployment provides is outside the scope of these files.
- **Retention**: none within these files. Whatever the backend retains — token metadata rows, access
  group/member/grant rows — is outside the scope of `tokens.ts`, `bucket-access.ts`, and `wire.ts`.

## Platform Notes

- **React/Web** (source platform): `packages/web/packages/data/src/security/tokens.ts` and
  `bucket-access.ts` hold the two clients; `wire.ts` holds their shared wire shapes; `index.ts`
  re-exports all three as the package's public surface. Both clients are built entirely on
  `authedJson`/`authedRequest` from `@agentic-toolkit/auth/client` (re-exported through `./http`) and
  `enc` (`encodeURIComponent`) from `./client-helpers`; `tokens.ts` alone calls the global
  `encodeURIComponent` directly rather than the `enc` alias, per `token-revoke-request-shape`.
- **SwiftUI**: a Swift port already exists for this exact backend surface —
  `packages/apple/AgenticToolkit/Hub/Features/Authentication/ApiTokensRail.swift` and
  `AccessListsTopic.swift` (documented in the sibling `auth-client-authentication` recipe) — and models
  the wire rows as `Codable, Sendable` structs and each client as an `@MainActor final class` exposing
  `async throws` methods over an injected data-source protocol, with a `HubError` in place of
  `AuthHttpError`. A fresh port of these two TypeScript files specifically should follow that existing
  pattern rather than introduce a second one.
- **AppKit / UIKit**: no direct UI dependency exists in either TypeScript file; consuming code reaches
  the ported client through an injected data-source protocol (`ApiTokensDataSource`,
  `BucketAccessDataSource` in the existing Swift port), never by calling `URLSession` from the view
  layer directly.
- **Compose**: model the six wire rows (`ApiToken`, `ApiTokenCreated`, `AccessGroup`,
  `AccessGroupMember`, `AccessGrant`, `AccessGroupDetail`) as Kotlin `data class`es annotated
  `@Serializable`, and each client as a class exposing `suspend fun` equivalents built on Ktor or
  OkHttp, with a sealed error type carrying the HTTP status and optional code in place of
  `AuthHttpError`.
- **WinUI 3**: a .NET port would model the wire rows as `record`s attributed for
  `System.Text.Json`, and `TokensApi`/`BucketAccessApi` as classes exposing `Task<T>`-returning methods
  built on `HttpClient`, attaching `Authorization: Bearer <token>` the way `authedFetch` does and
  refreshing on a `401` the same one-retry way, with an `ApiException` (status, code) parallel to
  `AuthHttpError`. This is the platform with the least existing prior art in this repo for that
  refresh-and-retry contract — as with the sibling `hub-domain-access` recipe's `accessApi`, a WinUI 3
  port would need to build the equivalent of `authedFetch` itself before either client can be ported,
  including its own single-refresh-then-retry-on-401 waterfall.

## Design Decisions

**Decision**: `deleteGroup` and `upsertGrant` wrap their call in no `try`/`catch`, while
`createGroup`, `updateGroup`, and `addMember` each catch and pass the error through `rethrowConflict`.
**Rationale**: `rethrowConflict` rewrites an error only when its message matches `/already exists/i`
— a naming or uniqueness collision the caller caused by picking a value that collided with an
existing row. `deleteGroup`'s `409` (the seeded "everyone" group refusing deletion) and any `upsertGrant`
failure are not naming collisions, so wrapping either in `rethrowConflict` would be a no-op even if
added: the regex would never match, and the original error would pass through unchanged regardless.
**Approved**: pending

**Decision**: `tokens.ts`'s `revoke` percent-encodes its path segment with the global
`encodeURIComponent`, while every `bucket-access.ts` method uses the `enc` alias
(`client-helpers.ts`'s re-export of the identical function) for the same purpose.
**Rationale**: not explained in either source file; recorded here as an observed naming inconsistency
between two sibling files in the same domain folder, not a functional difference — both names resolve
to the same built-in function, so `hub-domain-security-021`'s behavior is identical either way. A port
to another platform should use one consistent name for this operation rather than carrying the
inconsistency forward.
**Approved**: pending

**Decision**: `wire.ts`'s types are declared as a package-local mirror of the OpenAPI-generated shapes
in `@agentic-toolkit/adh-api-types`, rather than importing them directly.
**Rationale**: per `wire.ts`'s own header comment, this keeps the toolkit decoupled from the hub's
generated types "without narrowing what a caller can rely on" — the mirrored interfaces carry full
backend-schema fidelity (every field the backend's OpenAPI schema declares), not only the subset
`tokens.ts`/`bucket-access.ts` happen to read or write today.
**Approved**: pending
