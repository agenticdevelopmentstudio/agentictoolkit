<!-- leaf: implement-hub-domain-1/organizations--part-3 · source: hub-domain-organizations.md -->

# Hub Domain: Organizations — continued (part 3)

**Rules** (cite as `implement-hub-domain-1/organizations--part-3#<slug>`):

- `auth-delegated-to-shared-client` MUST
- `session-refresh-waterfall` MUST
- `errors-carry-status-and-code` MUST
- `authorization-enforced-server-side` MUST
- `winui-3` MUST — HttpClient with System.Text.Json replaces fetch/URLSession for every organizations/roster request this recipe …

### Security

This is a security-relevant recipe: `create`, `rename`, `archive`, and the roster read are all
gated by organization- and workspace-level authorization roles. It carries no secret of its own —
the bearer credential lives in `@agentic-toolkit/auth/client`, which this module composes rather
than reimplements.

- **auth-delegated-to-shared-client**: every network call in both modules MUST go through
  `authedJson` or `authedRequest` (re-exported from `@agentic-toolkit/auth/client` via `./http`),
  which attaches `Authorization: Bearer <token>` from `readAccessToken()`; neither module MUST
  read, store, or attach a token itself.
- **session-refresh-waterfall**: a 401 response to any call MUST trigger exactly one token refresh
  and one retried request, inherited unconditionally from `authedFetch`; a second 401 on the
  retried request MUST propagate as a thrown `AuthHttpError` with `status: 401`.
- **errors-carry-status-and-code**: any non-2xx response other than an unresolved 401 MUST cause
  the call to throw `AuthHttpError`, carrying the response's HTTP status and, when the body
  supplies one, a machine-readable `code`.
- **authorization-enforced-server-side**: neither module MUST perform any client-side permission
  check before sending a request. Per `organizations.ts`'s own comments: `create`'s split (open in
  a personal workspace, admin-of-the-organization required from an organization workspace),
  `rename`'s split (name/description need org-team-admin, slug needs site-admin), `archive`'s
  allowed roles (organization creator, org-team admin, or site-admin), and the roster's membership
  gate are all enforced entirely by the backend — a violation surfaces as a 403 (or, for the
  roster, a 404) that this client does not distinguish or pre-check.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `workspaceSlug` (`organizationsApi.list`, `.create`) | `string` | none — required | Names the workspace whose organizations are listed, or the workspace an organization is created FROM (and will OWN). |
| `key` (`organizationsApi.resolve`) | `string` | none — required | A UUID, slug, or reverse-domain rdid identifying the organization; passed through unmodified. |
| `id` (`organizationsApi.rename`, `.archive`, `.restore`) | `string` | none — required | The organization's stored handle (`Organization.id`), percent-encoded into the URL path. |
| `input` (`organizationsApi.create`) | `OrganizationCreateInput` | none — required | `{ slug, name }`, sent verbatim as the `POST` body. |
| `input` (`organizationsApi.rename`) | `OrganizationRenameInput` | none — required | Any subset of `{ name, slug, description }`; sent through `compact` so unset fields are omitted. |
| `slug` (`workspaceMembersApi.list`) | `string` | none — required | The organization workspace slug whose member roster is requested. |
| `/api/organization/organizations` | route literal, no exported constant | fixed | Base path every `organizationsApi` method inlines per call; unlike the sibling `ecosystemsApi`/`accessApi` clients, no `BASE` module constant is extracted. |
| `/api/workspaces/<slug>/members` | route literal | fixed | Roster route `workspaceMembersApi.list` inlines per call. |

## Localization

| String Key | Default (en) | Context |
|-----------|---------------|---------|
| — | An organization with that slug already exists. | Thrown by `create` when the backend reports a slug conflict |
| — | That organization slug is already taken. | Thrown by `rename` when the backend reports a slug conflict |
| — | That organization's handle has been taken, so it can't be restored. | Thrown by `restore` when the backend reports a 409 |

There is no localization mechanism in either file (no catalog, no key, no `i18n` call) — the three
strings above are fixed English literals, stated as fact per the non-UI component guidance rather
than as a hidden gap (see Compliance). Every other error message a caller can observe from either
module originates in the backend's response body and is extracted by `extractErrorMessage` in
`auth/src/client.ts`, not authored here.

## Privacy

- **Data collected**: organization administrative metadata (`id`, `slug`, `name`, `description`,
  `rdid`, and the provisioned `namespace`/`teamId`/`ecosystem` ids), plus, via
  `workspaceMembersApi.list`, roster rows naming a member's `userId`, `email`, `displayName`,
  `isAdmin` status, and `addedAt` timestamp. Unlike the organization fields, the roster's `email`
  and `displayName` ARE personal data about a real person.
- **Storage**: neither module holds a cache of its own; every call is a live round-trip, per
  `no-client-side-cache`. Whatever a caller does with the resolved data (for example, a react-query
  cache keyed via `ORGANIZATIONS_QUERY_KEY`) is outside these two files.
- **Transmission**: every call travels through `authedJson`/`authedRequest`, per
  `auth-delegated-to-shared-client`; neither module attaches its own credentials or reads cookies.
- **Retention**: none within these files. `email`/`displayName`'s exposure is already narrowed
  server-side to members within the caller's ecosystem, per `workspace-member-nullable-fields` —
  this client neither widens nor persists that exposure.

## Platform Notes

- **React/Web** (source platform): `packages/web/packages/data/src/organizations/organizations.ts`,
  `members.ts`, and `wire.ts` hold the client; every method is a plain async function over
  `authedJson`/`authedRequest` (`@agentic-toolkit/auth/client`, re-exported through `./http`) and
  `enc`/`compact` from `./client-helpers`; `index.ts` re-exports both files as the package's public
  surface (`@agentic-toolkit/data/organizations`).
- **SwiftUI**: a Swift port would model `Organization`/`OrganizationListRow`/
  `OrganizationCreateInput`/`OrganizationProvisioned`/`OrganizationRenameInput`/
  `OrganizationRestored`/`WorkspaceMember`/`WorkspaceMembersResponse` as `Codable, Hashable,
  Sendable` structs, mirroring the pattern the sibling Hub Ecosystems/Access recipes' Apple models
  already use, and `organizationsApi`/`workspaceMembersApi` as an `actor` or `@MainActor final
  class` exposing `async throws` functions built on `URLSession`, with a dedicated error type
  carrying the HTTP status and an optional machine code in place of `AuthHttpError`.
- **AppKit / UIKit**: no direct UI dependency exists in either module; a macOS/iOS Hub feature
  would consume the ported client through an injected data-source protocol — the same pattern the
  sibling `EcosystemsDataSource` already uses — rather than calling `URLSession` from the view
  layer.
- **Compose**: model the eight wire shapes as Kotlin `data class`es annotated `@Serializable`, and
  `organizationsApi`/`workspaceMembersApi` as classes exposing `suspend fun` equivalents built on
  Ktor or OkHttp, with a sealed error type carrying the HTTP status and optional code.
- **WinUI 3**: `HttpClient` with `System.Text.Json` replaces `fetch`/`URLSession` for every
  organizations/roster request this recipe documents. A `ContentDialog` hosting
  `Microsoft.UI.Xaml.Controls` (`TextBox` for `slug`/`name`, a multi-line `TextBox` for
  `description`) is the equivalent of a create/rename form, and a second `ContentDialog` with a
  destructive-styled primary button is the equivalent of an archive-confirmation flow a host would
  build around `archive(id)`. `Task`/`async`-`await` replaces every `Promise` call; a custom
  `AccessApiException`-equivalent exception (status, code) should carry the same conflict-versus-
  not-found distinctions this recipe's error-mapping requirements rely on — and, per
  `organization-restore-conflict-status-based`, a WinUI port MUST keep `restore`'s conflict
  detection status-code-based rather than message-text-based, since the backend's 409 wording
  differs between the create/rename routes and the restore route.

