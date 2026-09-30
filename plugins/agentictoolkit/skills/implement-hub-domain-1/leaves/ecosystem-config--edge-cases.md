<!-- leaf: implement-hub-domain-1/ecosystem-config--edge-cases · source: hub-domain-ecosystem-config.md -->

# Ecosystem Config

**Rules** (cite as `implement-hub-domain-1/ecosystem-config--edge-cases#<slug>`):

- `path-deeper-than-one-segment` MUST — SigninAppsTopic, FeatureFlagsTopic, ServerBagsTopic, and StorageTokensRail MUST return .empty for path.count > 1; …
- `unmatched-id-key-at-depth-one` MUST — a path[0].id matching no existing entity MUST return .empty for all four list-based topics (verified for sign-in apps …
- `malformed-json-in-a-server-bag-s-value-field` MUST — parsedValue MUST discard the specific DecodingError text and surface only the fixed invalidJSONMessage, on both create …
- `server-side-duplicate-after-client-pre-check-passes` MUST — a HubError.conflict from dataSource.create for flags, bags, or sign-in apps MUST be caught and re-thrown with the same …
- `case-insensitive-sign-in-app-leaf-collision` MUST — a new leaf that differs only in case from an existing one (e.g. "kiosk" vs. an existing "Kiosk") MUST be rejected by …
- `origin-with-credentials-a-path-or-a-non-http-scheme` MUST — each MUST be rejected by validateOrigin with its own specific message and MUST NOT reach the network (verified by …
- `re-rendering-the-detail-currently-showing-a-revealed-secret` MUST — MUST NOT drop the secret (expireRevealedSecret(unless:)'s showing != tokenID guard); only navigating to a *different* …
- `a-non-huberror-thrown-during-storage-token-create` MUST — MUST be converted to HubError.unexpected(StorageTokensRail.createFailedMessage), discarding the original error's own …

## Edge Cases

- **Path deeper than one segment**: `SigninAppsTopic`, `FeatureFlagsTopic`, `ServerBagsTopic`, and `StorageTokensRail` MUST return `.empty` for `path.count > 1`; `AuthSettingsTopic` MUST return `.empty` for any non-empty path at all (it has no detail-lookup segment to descend into).
- **Unmatched id/key at depth one**: a `path[0].id` matching no existing entity MUST return `.empty` for all four list-based topics (verified for sign-in apps by `testUnknownAppIsEmpty`; the same `guard let ... else { return .empty }` pattern applies identically to flags, bags, and tokens).
- **Malformed JSON in a server bag's value field**: `parsedValue` MUST discard the specific `DecodingError` text and surface only the fixed `invalidJSONMessage`, on both create and detail save.
- **Server-side duplicate after client pre-check passes**: a `HubError.conflict` from `dataSource.create` for flags, bags, or sign-in apps MUST be caught and re-thrown with the same friendly message the client-side pre-check uses, so the user sees identical wording regardless of which check caught the duplicate.
- **Case-insensitive sign-in-app leaf collision**: a new leaf that differs only in case from an existing one (e.g. `"kiosk"` vs. an existing `"Kiosk"`) MUST be rejected by `signinapps-duplicate-leaf-check`, even though the raw strings are not equal.
- **Origin with credentials, a path, or a non-http(s) scheme**: each MUST be rejected by `validateOrigin` with its own specific message and MUST NOT reach the network (verified by `testOriginValidation`'s four distinct cases).
- **Re-rendering the detail currently showing a revealed secret**: MUST NOT drop the secret (`expireRevealedSecret(unless:)`'s `showing != tokenID` guard); only navigating to a *different* destination drops it.
- **A non-`HubError` thrown during storage-token create**: MUST be converted to `HubError.unexpected(StorageTokensRail.createFailedMessage)`, discarding the original error's own message text — a deliberate divergence from `HubError.wrap`'s usual behavior of preserving as much detail as possible (see Design Decisions).
- **A feature-flag key containing a reserved character (e.g. `:`)**: see the open question on `flags-key-charset` — no given source rejects it, but it is later embedded unescaped in a colon-delimited composite id.
- **Web path segments containing special characters**: `enc()` (`encodeURIComponent`) is applied to every ecosystem id, flag key, bag key, and sign-in-app id interpolated into a URL path in `feature-flags.ts`, `server-bags.ts`, and `signin-apps.ts`, so a key/id with `/`, `?`, or similar cannot corrupt the request path even though no character-set validation rejects such a key upstream.
- **`StorageTokenCreate.ecosystemId` / `MintTokenPrincipalBody.ecosystemId` left unset while a scope parameter is also given**: neither the Apple rail nor the web client reconciles the two channels; `web-tokens-dual-scoping-channels` documents that this rail always leaves the body field `nil` and relies on the parameter/query channel exclusively.
