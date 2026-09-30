<!-- leaf: implement-hub-domain-1/ecosystem-config--part-4 · source: hub-domain-ecosystem-config.md -->

# Ecosystem Config — continued (part 4)

**Rules** (cite as `implement-hub-domain-1/ecosystem-config--part-4#<slug>`):

- `tokens-shared-rail-parameterization` MUST
- `tokens-ecosystem-scoping-via-parameter` MUST
- `tokens-about-text-variant` MUST
- `tokens-name-pattern` MUST
- `tokens-create-three-way-catch` MUST
- `tokens-reveal-once-on-create` MUST
- `tokens-detail-extra-fields-while-revealed` MUST
- `tokens-expire-revealed-secret-on-navigate` MUST
- `tokens-revoke-clears-revealed-secret` MUST
- `tokens-no-save-action-on-detail` MUST
- `tokens-delete-confirmation` MUST
- `tokens-detail-date-formatting` MUST
- `web-tokens-dual-scoping-channels` MUST
- `web-tokens-created-once` MUST

### StorageTokensTopic / StorageTokensRail (Apple) and storage-tokens.ts / wire.ts (Web)

- **tokens-shared-rail-parameterization**: `StorageTokensRail.child(path:ecosystemID:levelID:title:)` MUST serve both the ecosystem-scoped case (`StorageTokensTopic` passing `ecosystemID: ecosystem.id`) and the caller's-own-tokens case (`ecosystemID: nil`) through the same method, parameterized only by `ecosystemID`, `levelID`, and `title` (verified by `testRailWithoutEcosystemListsOwnTokens` calling `topic.rail.child` directly with `ecosystemID: nil`).
- **tokens-ecosystem-scoping-via-parameter**: `StorageTokensRail.createSpec`'s save action MUST always construct its `StorageTokenCreate` body with `ecosystemId: nil` (verified by `testCreateSpecMintsAndRevealsSecret`) — ecosystem scoping happens exclusively through the `ecosystemID:` function parameter passed to `dataSource.create(ecosystemID:_:)`, never through the body's own `ecosystemId` field.
- **tokens-about-text-variant**: `StorageTokensRail.aboutText(ecosystemID:)` MUST return `aboutWithoutEcosystem` when `ecosystemID == nil` and `aboutWithEcosystem` otherwise (verified by `testCreateSpecMintsAndRevealsSecret` and `testRailWithoutEcosystemListsOwnTokens`).
- **tokens-name-pattern**: the create form's `name` field MUST validate against `Slug.pattern` with `Slug.patternMessage` ("Use lowercase letters, numbers and hyphens.") (verified by `testCreateSpecMintsAndRevealsSecret`'s rejection of `"Bad Name"`).
- **tokens-create-three-way-catch**: `createSpec`'s save action MUST catch errors in three tiers: a `HubError.conflict` becomes `HubError.validation(StorageTokensRail.nameTakenMessage)`; any other `HubError` MUST be re-thrown unchanged; any non-`HubError` MUST become `HubError.unexpected(StorageTokensRail.createFailedMessage)`, discarding the original error's own message. This is an explicitly different pattern from the `HubError.wrap` convention used everywhere else in this component (see Design Decisions).
- **tokens-reveal-once-on-create**: on a successful create, the raw `created.token` MUST be stored in `revealedSecrets[created.id]` via `MainActor.run` (verified by `testCreateSpecMintsAndRevealsSecret`).
- **tokens-detail-extra-fields-while-revealed**: `detail(for:ecosystemID:)` MUST append `token` and `notice` read-only fields — with `notice` set to `ApplicationsTopic.revealMessage` ("Copy this token now — you won't be able to see it again.") — only while `revealedSecrets[token.id]` holds a value, and MUST set `revealedOnScreen = token.id` as a side effect of building that detail (verified by `testCreateSpecMintsAndRevealsSecret`).
- **tokens-expire-revealed-secret-on-navigate**: `expireRevealedSecret(unless:)` MUST run at the top of every `child(path:...)` call; it MUST drop `revealedSecrets[revealedOnScreen]` and clear `revealedOnScreen` when navigating to any destination other than the detail currently showing the secret, and MUST leave it untouched when re-rendering that same detail (verified by `testCreateSpecMintsAndRevealsSecret`: the secret survives a second `rail.form(["tok-nightly"])` call but is dropped after `rail.level([])`).
- **tokens-revoke-clears-revealed-secret**: the revoke action MUST call `HubError.wrap` around `dataSource.revoke(ecosystemID:id:)` and then clear `revealedSecrets[token.id]` via `MainActor.run`, regardless of whether a value was present (verified by `testDetailFactsAndRevoke`).
- **tokens-no-save-action-on-detail**: the detail `FormSpec`'s `actions.save` MUST be `nil` (verified by `testDetailFactsAndRevoke`) — a storage token has no editable fields once created, only revoke.
- **tokens-delete-confirmation**: the revoke action's title MUST be "Revoke token" and its confirmation text MUST be `Revoke storage token "<token.slug>"? Anything using it will lose access to its bucket.` (verified by `testDetailFactsAndRevoke`).
- **tokens-detail-date-formatting**: `lastUsed`/`created`/`expires` fields MUST format through `HubDates.display`, falling back to `"never used"`/`"never"` respectively when the underlying ISO string is `nil` (verified by `testDetailFactsAndRevoke`).
- **web-tokens-dual-scoping-channels**: `tokenPrincipalsApi.list`/`mint`/`revoke` MUST accept scoping through the `TokenScope` query-parameter channel (`ecosystemId`, `workspace`, serialized by `scopeQuery`) independently of `MintTokenPrincipalBody.ecosystemId`, a separate body field; `storage-tokens.ts` performs no reconciliation between the two channels — a caller sets whichever one the operation needs (mirroring Apple's rail, whose `createSpec` always leaves the body field `nil` and relies solely on the parameter channel).
- **web-tokens-created-once**: `TokenPrincipalCreated` (the 201-only body carrying `token`) MUST be a distinct type from `TokenPrincipal` (the list-row shape, which carries only `prefix`); `storage-tokens.ts`/`wire.ts` give no other route through which the raw secret can be retrieved again.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `dataSource` (`AuthSettingsDataSource`) | protocol | none (required) | Injected transport for `AuthSettingsTopic`: `get(ecosystemID:)` / `update(ecosystemID:_:)`. |
| `dataSource` (`SigninAppsDataSource`) | protocol | none (required) | Injected transport for `SigninAppsTopic`: `list` / `create` / `update` / `delete`, all scoped by `ecosystemID`. |
| `dataSource` (`FeatureFlagsDataSource`) | protocol | none (required) | Injected transport for `FeatureFlagsTopic`: `list` / `create` / `update(key:)` / `delete(key:)`. |
| `dataSource` (`ServerBagsDataSource`) | protocol | none (required) | Injected transport for `ServerBagsTopic`: `list` / `create` / `update(key:)` / `delete(key:)`. |
| `dataSource` (`StorageTokensDataSource`) | protocol | none (required) | Injected transport for `StorageTokensRail`/`StorageTokensTopic`: `list(ecosystemID:)` / `create(ecosystemID:_:)` / `revoke(ecosystemID:id:)`, where `ecosystemID: nil` means the caller's own workspace tokens. |
| `ecosystem` (`Ecosystem`) | struct | none (required) | Supplies `id`/`slug` used to scope every list/create/update/delete call and to build composite detail ids. |
| `path` (`[HTDVItem]`) | array | `[]` | Rail-relative navigation path; see `path-depth-dispatch`. |
| `rail` (`EcosystemRail`) | protocol | none (required, unused) | Passed to every `child(for:path:rail:)` call per the `EcosystemTopicProvider` contract; none of these five given sources call back through it themselves. |
| `ecoId` (Web) | `string` | none (required) | Ecosystem id, URL-encoded via `enc()` into every ecosystem-config request path. |
| `TokenScope.ecosystemId` / `.workspace` (Web) | `string?` | `undefined` | Optional query-string scoping used only by `tokenPrincipalsApi`. |

## Localization

Every user-facing string in this component is a hardcoded English literal — there is no `NSLocalizedString`, `String(localized:)`, `.strings`/`.stringsdict` reference, or i18n library call anywhere in the given Swift or TypeScript files. Representative examples: `AuthSettingsTopic`'s "When off, no one can sign in to this ecosystem."; `SignupMode.help`'s three case strings (`EcosystemConfigModels.swift`); `FeatureFlagsTopic.removalMessage` and `ServerBagsTopic.removalMessage`; `SigninAppsTopic.validateOrigin`'s four rejection messages; `StorageTokensRail.nameTakenMessage`, `createFailedMessage`, `aboutWithEcosystem`, and `aboutWithoutEcosystem`. This is a fact of the current implementation, not a gap this recipe marks — nothing in the source suggests localization is planned or partially wired.

## Privacy

- **Data collected**: this component collects no analytics of its own. It transports `AuthSettings`, `SigninApp`, `FeatureFlag`, and `ServerBag` — configuration entities holding no end-user personal data — and `StorageToken`/`StorageTokenCreated`/`TokenPrincipal`/`TokenPrincipalCreated`, which do carry a security-sensitive secret: the raw `adh_…` token minted by `StorageTokensDataSource.create` / `tokenPrincipalsApi.mint`.
- **Storage**: on Apple, `StorageTokensRail.revealedSecrets: [String: String]` holds the raw secret in an in-memory dictionary on the `@MainActor`-isolated instance only; it is never written to `UserDefaults`, the Keychain, or any file by this component. It is dropped by `revoke`'s `MainActor.run { self?.revealedSecrets[token.id] = nil }` and by `expireRevealedSecret(unless:)` on navigating away from the detail that revealed it. On Web, `tokenPrincipalsApi.mint` returns `TokenPrincipalCreated.token` to the caller with no persistence of any kind in `storage-tokens.ts`/`wire.ts` — per `wire.ts`'s own comment, the 201 response is "the ONLY response that carries the raw secret, and it is shown once."
- **Transmission**: the mint/create request travels over whichever transport the injected `StorageTokensDataSource` (Apple) or `authedJson` (Web) implementation uses — neither is part of this component's given sources, and this component configures no TLS or transport-level behavior itself.
- **Retention**: the plaintext secret is retained only until the reveal-once contract expires it (Apple) or for as long as the caller holds the 201 response (Web; no retention logic is given). `AuthSettings`, `SigninApp`, `FeatureFlag`, and `ServerBag` have no retention policy defined in these sources beyond whatever the backend itself enforces.

