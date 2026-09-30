<!-- leaf: implement-general-1/auth-client-authentication · source: auth-client-authentication.md -->

# Authentication Client

## Overview

Four Swift types under `packages/apple/AgenticToolkit/Hub/Features/Authentication/` and one sibling
under `.../EcosystemConfig/` form the client-side contract for everything the Hub's "Authentication"
surface manages: `AuthenticationModule` (`AuthenticationModule.swift`) is the `HTDVDataSource` root —
"Tokens" — that routes to two child rails and an explainer; `ApiTokensRail` (`ApiTokensRail.swift`)
mints, lists, reveals-once, and revokes the caller's personal API tokens (`tmp_…`, scoped by REST
path); `StorageTokensRail` (`StorageTokensRail.swift`, shared with the separate `EcosystemConfig`
feature) does the same for storage tokens (`adh_…`, each its own principal with one isolated bucket),
parameterized by an optional ecosystem id so the identical rail serves both the caller's own tokens
(`ecosystemID: nil`) and a specific ecosystem's tokens; and `AccessListsTopic`
(`AccessListsTopic.swift`) is a separate `EcosystemTopicProvider` — the "Access" product-rail topic —
managing bucket access-control lists (groups), their members, and their C/R/U/D grants, nested three
levels deep. `AuthenticationModels.swift` holds the `Codable`/`Sendable` wire types and the four
`AnyObject, Sendable` data-source protocols (`ApiTokensDataSource`, `BucketAccessDataSource`, plus
`StorageTokensDataSource` in `EcosystemConfigModels.swift`) that all four types depend on but never
implement themselves — every network call is delegated to an injected data source, and every thrown
error is normalized to `HubError` before it reaches a caller. `AccessListsTopic` is not reachable from
`AuthenticationModule`'s tree — the two live in the same folder and share vocabulary (`HubError`,
`FormSpec`, reveal-once secrets) but are wired into the app as two independent entry points.

