<!-- leaf: implement-general-1/auth-client-authentication--part-5 · source: auth-client-authentication.md -->

# Authentication Client — continued (part 5)

## Platform Notes

- **SwiftUI**: not applicable to these files directly — all four types return `HTDVLevel`/`HTDVDetail`/
  `FormSpec` values consumed by the shared `FormViewController`/HTDV presentation layer; a SwiftUI-based
  presenter would consume the same values unchanged, since none of the four imports SwiftUI or performs
  any rendering itself.
- **AppKit / UIKit**: this is the source. `AuthenticationModule.swift`, `ApiTokensRail.swift`,
  `AuthenticationModels.swift`, and `AccessListsTopic.swift` live in the `Hub` module of the
  `AgenticToolkitHub-macOS`/`AgenticToolkitHub-iOS` targets (both declared in `project.yml`, sharing one
  source set); `StorageTokensRail.swift` lives in the sibling `EcosystemConfig` feature folder of the
  same module. None of the five files imports `AppKit` or `UIKit` directly — each is plain
  `AgenticToolkitHTDV` + `Foundation`, with the platform-specific `NSViewController`/`UIViewController`
  split handled entirely inside `FormViewController` (a different file), one level below where these
  types operate.
- **Compose**: a Kotlin port would model each `Codable` struct (`ApiToken`, `AccessGroup`,
  `AccessGrant`, `StorageToken`, etc.) as an immutable `data class`; the four rails/topics as classes
  exposing `suspend fun` equivalents of `child(...)` returning a sealed `HtdvChild` class
  (`Level`/`Detail`/`Empty`); `HubError` as a Kotlin `sealed class` with the same eight cases, each
  computing its own `message`; `revealedSecrets` as a `MutableMap<String, String>` guarded by
  confinement to a single `Dispatchers.Main`-bound coroutine scope, mirroring `@MainActor`.
- **React/Web**: a TypeScript port would use `readonly`-field interfaces for the wire types, a
  discriminated-union `HubError` type (`{kind: "conflict", detail: string} | ...`) with a
  `hubErrorMessage()` helper mirroring `HubError.message`, and plain `async` functions returning
  `Promise<HtdvChild>` for each `child(...)`/`level(...)`/`detail(...)` equivalent; the reveal-once
  mechanic would need an explicit teardown (e.g., a router's `onBeforeRouteLeave`/`useEffect` cleanup
  keyed by the outgoing route's first path segment) to reproduce `expireRevealedSecret(unless:)`'s
  "same detail re-renders, anything else expires" rule, since there is no `@MainActor`-style confinement
  to lean on for correctness — the map mutation itself would need to happen on the same thread
  (JavaScript's single-threaded event loop already guarantees this, unlike a truly concurrent runtime).
- **WinUI 3**: a .NET port would model the wire types as `record`s (free structural equality, mirroring
  the Swift `Hashable` conformances) and the four rails/topics as classes with `async Task<HtdvChild>`
  methods, backed by an `HttpClient` + `System.Text.Json` implementation of each `*DataSource` protocol
  (`IApiTokensDataSource`, `IBucketAccessDataSource`, `IStorageTokensDataSource`) with method shapes
  matching the Swift protocols one-to-one (`Task<ApiToken[]> ListAsync()`,
  `Task<ApiTokenCreated> CreateAsync(ApiTokenCreate body)`, etc.); `revealedSecrets` as a
  `Dictionary<string, string>` field on a class instantiated per-window/per-`ContentDialog`, with the
  one-shot expiry implemented in the page's `OnNavigatedFrom` override (or the view model's disposal)
  rather than a `@MainActor`-checked property; `Slug.pattern`/`Slug.patternMessage` port directly to a
  `System.Text.RegularExpressions.Regex` constant plus a `TextBox` validation error string; UI-bound
  collections (the token/group/member/grant lists) become `ObservableCollection<T>` wrapped in a view
  model implementing `INotifyPropertyChanged`, with each list rebuilt (not incrementally patched) on
  every re-fetch, mirroring `access-detail-refetches-every-call`'s "no caching" rule.

## Design Decisions

**Decision**: `StorageTokensRail` is a single class parameterized by an optional `ecosystemID`, shared
verbatim between `AuthenticationModule`'s "the caller's own tokens" use (`ecosystemID: nil`) and the
separate `EcosystemConfig` feature's "this ecosystem's tokens" use, rather than two separate types.
**Rationale**: the list/create/detail/revoke logic is identical in both cases — only the value passed to
`dataSource.list/create/revoke` and the `about`/level title text differ — so a shared class with the
`ecosystemID` threaded through every call avoids duplicating the reveal-once mechanic and the
create-error-tiering logic in two places.
**Approved**: pending

**Decision**: a token's plaintext secret is retained in `revealedSecrets` only until navigation departs
from the detail screen currently showing it, enforced by calling `expireRevealedSecret(unless:)` at the
top of every `child(...)` call rather than, say, on a timer or on view-disappear.
**Rationale**: per the source's own comment, retaining the secret "for the session made the notice a
lie" — the copy-once affordance (`ApplicationsTopic.revealMessage`) promises the secret disappears once
the reader has navigated away; tying the check to the navigation path itself (rather than a lifecycle
event the presentation layer would have to remember to call) means the guarantee holds regardless of
which presentation layer drives it.
**Approved**: pending

**Decision**: `ApiTokensRail.createSpec(scopes:)` disables its own save action entirely (a notice-only
form) when the scope catalogue fails to load, and separately rejects an empty scope selection when the
catalogue *did* load, rather than falling back to an unscoped ("legacy") token in either case.
**Rationale**: a `nil`/empty scope selection mints the *broadest* token this system can issue, not the
narrowest — the source's own comment calls this out explicitly as a footgun that was once unguarded when
the catalogue loaded successfully. Both guards exist to make the failure mode "creation is blocked" for
a reason the caller can see, rather than "a wide-open token was minted silently."
**Approved**: pending

**Decision**: saving an existing access grant with every CRUD toggle cleared is rejected with a
validation error, not treated as an implicit delete; a grant is removable only through its own explicit
"Remove grant" action.
**Rationale**: the source's own comment documents this as a fixed regression — the previous behavior
made a destructive action ("delete the grant") reachable through a button labelled "Save" with no
confirmation, "behind clearing the last checkbox." The current contract makes "no permissions selected"
an error identical to the one the create form already throws, and reserves actual deletion for the
button whose label and confirmation text say so.
**Approved**: pending

**Decision**: `StorageTokensRail`'s create path uses a three-way `catch` (rethrow a specific
`HubError.conflict` as a friendlier validation message, rethrow any other `HubError` unchanged, and
convert anything else into a fixed `HubError.unexpected(createFailedMessage)`) instead of the single
`HubError.wrap(_:)` call every other create/update/delete path in this component uses; `StorageTokensRail`
also sorts its list by raw `slug` rather than `localizedCaseInsensitiveCompare`d name, unlike
`ApiTokensRail`.
**Rationale**: both divergences are observed, deliberate facts of the current source, not oversights to
be silently unified — `slug` is a `Slug`-pattern-constrained ASCII identifier, so a locale-aware compare
buys nothing there, while a token's display `name` in `ApiTokensRail` is free-form caller text where
locale-aware ordering matters. This recipe states both divergences as requirements
(`storage-tokens-list-sorted-by-slug`, `storage-tokens-create-error-tiering`) rather than smoothing them
into the other rail's pattern.
**Approved**: pending
