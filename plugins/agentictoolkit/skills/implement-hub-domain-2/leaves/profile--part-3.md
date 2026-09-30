<!-- leaf: implement-hub-domain-2/profile--part-3 · source: hub-domain-profile.md -->

# Hub Domain Profile — continued (part 3)

**Rules** (cite as `implement-hub-domain-2/profile--part-3#<slug>`):

- `decision` MUST — none of listSocialLinks, listAddresses, getPrivacyGrants, or getUsageSummary runtime-validates its response shape, …

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `opts.workspace` (every list/create/update/delete/usage function) | `string` (optional) | omitted → the caller's own principal | Workspace slug scoping the call to an organization's profile instead of the caller's own; percent-encoded via `encodeURIComponent` when present. |
| `body` (`createSocialLink`/`updateSocialLink`) | `SocialLinkWrite` | none — required | `{ platform, url, handle, sortOrder? }`, sent verbatim as the request body. |
| `body` (`createAddress`/`updateAddress`) | `AddressWrite` | none — required | `{ label, line1, line2, city, region, postalCode, country }`, sent verbatim as the request body. |
| `targetTable`/`targetId`/`level` (`setPrivacyGrant`) | `PrivacyTargetTable` (`string`), `string`, `PrivacyLevel` | none — required | `level` is mapped through the fixed `AUDIENCE_MASK` constant to an integer bitmask before sending. |
| `grants` (`resolvePrivacyLevel`) | `PrivacyGrant[]` | none — required, caller supplies the already-loaded list | Pure lookup; issues no network call of its own. |
| `AUDIENCE_MASK` | module constant | fixed `{"only-me": 0, public: 1, hub: 2}` | Not injectable or configurable. |
| `SOCIAL_LINKS_KEY` / `ADDRESSES_KEY` / `USAGE_SUMMARY_KEY` / `PRIVACY_KEY` | module constants | fixed | Not injectable; `PRIVACY_KEY` alone is exported directly, per `privacy-key-not-namespaced`. |

## Privacy

- **Data collected**: address rows (`label`, `line1`, `line2`, `city`, `region`, `postalCode`,
  `country`), social link rows (`platform`, `url`, `handle`), the caller's own privacy audience
  setting per target row (`targetTable`/`targetId`/`audienceMask`), and metered usage/cost figures
  (`requests`/`bytes`/`tokens`/`costMicros`) for the caller's own principals or, with `?workspace=`,
  a workspace's. `PrivacyGrant` is itself the mechanism that decides who else may see the address
  and social-link rows above.
- **Storage**: none client-side — per `module-holds-no-mutable-state` and
  `no-client-side-storage-of-sensitive-fields`, nothing in `profile.ts`/`usage.ts` is retained
  beyond the lifetime of a single call. Server-side storage is outside the scope of these three
  files.
- **Transmission**: yes. Every call carries a bearer credential attached by
  `@agentic-toolkit/auth/client` (`auth-delegated-to-shared-client`), not by this module; whatever
  transport security the deployment provides is outside the scope of these three files.
- **Retention**: none within this module; nothing this module handles is retained after the
  response it produced is returned to the caller.

## Platform Notes

- **React/Web** (source platform): `packages/web/packages/data/src/profile/profile.ts`,
  `usage.ts`, and `wire.ts` hold the client, re-exported as the package's public surface by
  `index.ts`; every network operation is built on `authedJson`/`authedRequest` from
  `@agentic-toolkit/auth/client` (re-exported through `./http`), and the four cache-key functions
  are plain string-array builders with no framework dependency of their own — a consumer wires them
  into whatever cache layer (e.g. react-query) it uses.
- **SwiftUI**: model `SocialLink`/`SocialLinkWrite`/`Address`/`AddressWrite`/`PrivacyGrant`/
  `UsageRow`/`UsageLimits` as `Codable, Hashable, Sendable` structs, `PrivacyLevel`/`UsageScope`/
  `UsageRowKind` as Swift `enum`s, and the client as an `actor` or `@MainActor final class` exposing
  `async throws` functions built on `URLSession`, mirroring the pattern the sibling
  `hub-domain-access` recipe's Swift port note already describes for this repo's Hub Apple targets.
- **AppKit / UIKit**: no direct UI dependency exists in this module; a macOS/iOS feature would
  consume the ported client through an injected data-source protocol rather than calling
  `URLSession` from the view layer, and the `opts.workspace` parameter becomes a constructor/init
  argument on that protocol rather than a per-call option.
- **Compose**: model the wire rows as Kotlin `data class`es annotated `@Serializable`, `PrivacyLevel`
  as a Kotlin `enum class`, and the client as a class exposing `suspend fun` equivalents built on
  Ktor or OkHttp; the cache-key arrays become a small `data class` or sealed key type rather than a
  plain list, since Kotlin has no equivalent to comparing array prefixes at the call site.
- **WinUI 3**: model `SocialLink`/`SocialLinkWrite`/`Address`/`AddressWrite`/`PrivacyGrant`/
  `UsageRow`/`UsageLimits` as `record`s attributed for `System.Text.Json`, `PrivacyLevel` as a C#
  `enum` with a `Dictionary<PrivacyLevel,int>` in place of `AUDIENCE_MASK`, and the client as a class
  exposing `Task<T>`-returning methods built on `HttpClient`, attaching `Authorization: Bearer
  <token>` and the same one-retry-on-401 refresh waterfall `authedFetch` performs. Back the two list
  surfaces (social links, addresses) with `ObservableCollection<T>` for a Settings-page editor, with
  each row implementing `INotifyPropertyChanged` for two-way binding in the address/social-link edit
  forms. The `socialLinksKey`/`addressesKey`/`usageSummaryKey` namespacing has no direct WinUI 3
  analog, since there is no react-query-style cache — a port would instead key any local cache
  `Dictionary` by the same `(ownerKind, ownerId)` tuple to preserve the same non-aliasing guarantee.

## Design Decisions

**Decision**: `PrivacyTargetTable` is typed as a plain `string` rather than a closed union of known
target tables.
**Rationale**: `wire.ts`'s own comment states that a client that hard-coded the members would
refuse a target table the backend later adds; `data-profile-wire.test-d.ts` pins this as a
permanent, deliberate asymmetry against the generated backend type, not a placeholder meant to be
narrowed later.
**Approved**: pending

**Decision**: `SOCIAL_LINKS_KEY`, `ADDRESSES_KEY`, and `USAGE_SUMMARY_KEY` are not exported; only
their namespaced accessor functions are.
**Rationale**: `profile.ts`'s own comment explains that using a bare root as a cache key would alias
one owner's list onto another's under prefix-based cache invalidation. Exporting only the accessor
keeps every consumer going through the one function that produces the owner-namespaced shape,
rather than risking a second, independently-derived key that silently desyncs from it.
**Approved**: pending

**Decision**: none of `listSocialLinks`, `listAddresses`, `getPrivacyGrants`, or `getUsageSummary`
runtime-validates its response shape, unlike this cookbook's sibling `hub-domain-access` recipe's
`listFeatures`.
**Rationale**: recorded as observed source behavior, not smoothed over — no comment in `profile.ts`
or `usage.ts` documents an equivalent guard or a reason one was omitted. A port MUST preserve this
same trust-the-cast behavior rather than adding validation these two files don't have, since nothing
in the given sources establishes that the omission was a deliberate choice versus simply not yet
needed.
**Approved**: pending

**Decision**: `OwnerScopedRow.customerId` is documented as the denormalized creator of a row, not
its owner.
**Rationale**: `wire.ts`'s own comment warns "do not read it as 'whose row this is'" — a directly
relevant trap for a port that might otherwise assume `customerId` identifies the row's owning
principal, when the `ownerKind`/`ownerId` pair is the actual owner.
**Approved**: pending
