---
id: 87ca0139-6cd0-46dd-a9fb-40ad3406f175
title: Ecosystem Config
domain: agentictoolkit://recipes/hub-domain-ecosystem-config
type: ingredient
version: 1.0.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Five product-rail topics (User Auth, Sign-in apps, Feature flags, Server
  bags, Storage Access Tokens) that let a hub caller view and edit one ecosystem's
  configuration, plus their shared data models and the matching web data clients.
platforms:
- swift
- macos
- ios
- typescript
- web
tags:
- hub
- ecosystem-config
- configuration
- feature-flags
- server-bags
- oauth
- storage-tokens
depends-on: []
related:
- agentictoolkit://recipes/auth-client-authentication
- agentictoolkit://recipes/hub-domain-ecosystems
references:
- packages/apple/AgenticToolkit/Hub/Features/EcosystemConfig/AuthSettingsTopic.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/EcosystemConfig/EcosystemConfigModels.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/EcosystemConfig/FeatureFlagsTopic.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/EcosystemConfig/ServerBagsTopic.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/EcosystemConfig/SigninAppsTopic.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/EcosystemConfig/StorageTokensRail.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/EcosystemConfig/StorageTokensTopic.swift
  (agentictoolkit)
- packages/web/packages/data/src/ecosystem-config/feature-flags.ts (agentictoolkit)
- packages/web/packages/data/src/ecosystem-config/server-bags.ts (agentictoolkit)
- packages/web/packages/data/src/ecosystem-config/signin-apps.ts (agentictoolkit)
- packages/web/packages/data/src/ecosystem-config/storage-tokens.ts (agentictoolkit)
- packages/web/packages/data/src/ecosystem-config/wire.ts (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitHubTests/EcosystemConfigTopicsTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/HubError.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Ecosystems/EcosystemTopic.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Ecosystems/EcosystemsModels.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Support/Slug.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Support/HubDates.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Support/HubText.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Support/JSONValue.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Hub/Features/Applications/ApplicationsTopic.swift
  (agentictoolkit)
- packages/web/packages/data/src/http.ts (agentictoolkit)
- packages/web/packages/data/src/client-helpers.ts (agentictoolkit)
- packages/apple/AgenticToolkit/project.yml (agentictoolkit)
- packages/web/packages/features/ecosystem-config/src/dialog-state/bag-dialog-state.ts
  (agentictoolkit)
- packages/web/packages/features/ecosystem-config/src/dialog-state/flag-dialog-state.ts
  (agentictoolkit)
- packages/web/packages/features/ecosystem-config/src/SigninAppDetail.tsx (agentictoolkit)
approved-by: ''
approved-date: ''
---

# Ecosystem Config

## Overview

This component is five `EcosystemTopicProvider` implementations that hang off one ecosystem's product rail — `AuthSettingsTopic` ("User Auth"), `SigninAppsTopic` ("Sign-in apps"), `FeatureFlagsTopic` ("Feature flags"), `ServerBagsTopic` ("Server bags"), and `StorageTokensTopic` ("Storage Access Tokens", a thin wrapper around the shared `StorageTokensRail`) — plus the data models and five data-source protocols they share (`EcosystemConfigModels.swift`), and the matching web data-client layer (`feature-flags.ts`, `server-bags.ts`, `signin-apps.ts`, `storage-tokens.ts`, `wire.ts`). Each Apple topic resolves a rail-relative `path: [HTDVItem]` into a level (a list of that ecosystem's flags/bags/apps/tokens, with a create action) or a detail (a `FormSpec` for viewing/editing one entity), orchestrating an injected data-source protocol, domain validation, and error normalization through `HubError`. The web files are the corresponding fetch-layer clients for the same five resources, consumed by UI panes and dialog-state modules that are not part of this component's given sources. This is a **logic** component: `AuthSettingsTopic`, `SigninAppsTopic`, `FeatureFlagsTopic`, `ServerBagsTopic`, and `StorageTokensRail`/`StorageTokensTopic` render nothing themselves — they build declarative `FormSpec`/`HTDVLevel`/`HTDVDetail` value objects that a separate presentation layer (outside these sources) turns into UI, and the five TypeScript files are plain `fetch`-based clients with no JSX.

## Behavioral Requirements

### Cross-cutting (all five topics)

- **ecosystem-scoped-navigation**: every `child(for:path:rail:)` MUST scope its data-source calls to the given `ecosystem.id` (Apple) or `ecoId` (Web); `AuthSettingsTopic`, `SigninAppsTopic`, `FeatureFlagsTopic`, and `ServerBagsTopic` pass `ecosystemID: ecosystem.id` on every call, and `StorageTokensTopic` passes `ecosystemID: ecosystem.id` through to `StorageTokensRail.child`.
- **path-depth-dispatch**: for `SigninAppsTopic`, `FeatureFlagsTopic`, `ServerBagsTopic`, and `StorageTokensRail`, `path.count == 0` MUST return a `.level`, `path.count == 1` MUST look up the matching entity by id/key and return `.detail` when found or `.empty` when not found, and `path.count > 1` MUST return `.empty`. `AuthSettingsTopic` has no level at all: `path.isEmpty` MUST return the single `.detail`, and any non-empty path MUST return `.empty` (confirmed by `testUnknownPathIsEmpty`, which passes a one-element path and expects `.empty`).
- **hub-error-wrapping**: every data-source call in `AuthSettingsTopic`, `SigninAppsTopic.child`, `FeatureFlagsTopic.child`, `ServerBagsTopic.child`, and every non-create/non-mint call in `StorageTokensRail` MUST be wrapped in `HubError.wrap { ... }` so a thrown transport/API error is normalized to a `HubError` case before it reaches the caller.
- **main-actor-isolation**: `AuthSettingsTopic`, `SigninAppsTopic`, `FeatureFlagsTopic`, `ServerBagsTopic`, and `StorageTokensRail`/`StorageTokensTopic` are declared `@MainActor final class`; every method that touches their own stored state MUST run on the main actor.
- **nonisolated-form-callbacks**: static helpers that a `FormAction.perform` closure calls directly — `ServerBagsTopic.parsedValue`, `SigninAppsTopic.validateOrigin`/`canonicalOrigin`/`canonicalOrigins`, `StorageTokensRail.nameTakenMessage`/`createFailedMessage` — MUST be declared `nonisolated`, because `FormAction.perform` closures are not `@MainActor`-isolated (per the source's own comments citing `FormSpec.swift`).
- **sendable-models**: `AuthSettings`, `AuthSettingsUpdate`, `SigninApp`, `SigninAppCreate`, `SigninAppUpdate`, `FeatureFlag`, `FeatureFlagCreate`, `FeatureFlagUpdate`, `ServerBag`, `ServerBagCreate`, `ServerBagUpdate`, `StorageToken`, `StorageTokenCreated`, and `StorageTokenCreate` MUST all be `Codable, Hashable, Sendable` value types, so they can cross actor boundaries (e.g. into a `FormAction.perform` closure) without a data race.

### AuthSettingsTopic

- **auth-detail-only-entry**: `AuthSettingsTopic.entry` MUST declare `leadsTo: .detail` (verified by `testEntry`) — there is no list level for this topic; navigating to it goes straight to the one settings form.
- **auth-field-order**: the detail `FormSpec` MUST present fields in the order `signupMode`, `signupHelp`, `loginEnabled` (verified by `testDetailShowsPolicy`'s `form.state.spec.fields.map(\.key)`), grouped into a "Sign-up" section (`signupMode` select plus a read-only `signupHelp` line) and a "Sign-in" section (the `loginEnabled` toggle).
- **auth-signup-options**: the `signupMode` select field's options MUST be `SignupMode.allCases` in declaration order (`open`, `inviteOnly`, `closed`), titled "Open", "Invite only", "Closed" respectively (verified by `testDetailShowsPolicy`).
- **auth-signin-help-text**: the `loginEnabled` toggle's help text MUST be the fixed string "When off, no one can sign in to this ecosystem." — it does not vary by ecosystem or current setting.
- **auth-save-sends-both-values**: the save action MUST always construct an `AuthSettingsUpdate` carrying both `signupMode` and `loginEnabled`, never a partial patch, even if only one field changed (verified by `testSaveSendsBothValues`).
- **auth-save-fallback-values**: if `values["signupMode"]` cannot be parsed into a `SignupMode` (via `SignupMode(rawValue:)`), the save action MUST silently fall back to `.inviteOnly`; if `values["loginEnabled"]` is missing, it MUST fall back to `false`. Both are documented, in-source fallbacks, not swallowed errors — the field's fixed option set makes an invalid `signupMode` value unreachable through normal use.
- **auth-detail-id-format**: the detail's id MUST be the string `auth-settings:<ecosystem.id>` (verified by `testDetailShowsPolicy`: `"auth-settings:org.acme.shop"`).
- **auth-no-delete-action**: the detail `FormSpec`'s `actions.delete` MUST be `nil` (verified by `testDetailShowsPolicy`) — auth settings can be edited but never removed.
- **auth-allowed-providers-not-editable**: `AuthSettings.allowedProviders: [String]?` decodes from `AuthSettingsDataSource.get`'s response, but `AuthSettingsTopic.detail`'s `FormSpec` never reads, displays, or edits it, and `AuthSettingsUpdate` has no field to write it back; this component offers no way to view or change the allowed providers.

### SigninAppsTopic (Apple) and signin-apps.ts (Web)

- **signinapps-list-sort**: the level's items MUST be sorted by `name` using `localizedCaseInsensitiveCompare` (verified by `testListSortedByName`: "Admin console" before "Shop web"); each item's sublabel MUST be the app's full `slug` (e.g. "shop.shop-web").
- **signinapps-leaf-computation**: `SigninApp.leaf(in:)` MUST strip the `"<ecosystem.slug>."` prefix from `slug` when present, returning `slug` unchanged when it is not — a defensive fallback, since the web client's own comment on `signin-apps.ts` documents that "the server prefixes the client slug with the ecosystem slug and FORCES the ecosystem," so every listed `slug` is expected to carry that prefix in practice.
- **signinapps-create-fields**: the create `FormSpec` MUST expose only `name` and `clientId` (verified by `testCreateSpecValidatesLeafAndDuplicates`); `allowedReturnOrigins` and `githubEnabled` are editable only after creation, in the detail.
- **signinapps-duplicate-leaf-check**: before calling `dataSource.create`, the save action MUST reject a `clientId` whose lowercased value matches any existing app's lowercased `leaf(in:)`, with the message `App id "<leaf>" is already in use.` (verified by `testCreateSpecValidatesLeafAndDuplicates`, which shows "kiosk" rejected against an existing "Kiosk"-cased leaf via case-insensitive comparison).
- **signinapps-clientid-pattern**: the `clientId` field MUST validate against `Slug.pattern` with message `SigninAppsTopic.leafMessage` ("App id must be a lowercase token, e.g. my-app.") before the duplicate check runs (verified by `testCreateSpecValidatesLeafAndDuplicates`'s rejection of `"Bad.Id"`).
- **signinapps-create-conflict-message**: a `HubError.conflict` thrown by `dataSource.create` MUST be caught and re-thrown as `HubError.validation("A sign-in app \"<leaf>\" already exists in this ecosystem.")` (verified by `testCreateConflictMessage`); any other error MUST be re-wrapped via `HubError.wrap(error)`.
- **signinapps-origin-validation**: `SigninAppsTopic.validateOrigin(_:)` MUST return `nil` for an acceptable origin and, for a rejected one, the first-violated-rule message: not-a-URL ("... is not a valid URL."), non-http(s) scheme ("... must be http(s)."), embedded credentials ("... must not include credentials."), or a non-empty/non-"/" path, query, or fragment ("... must be just a scheme + host (no path)."). All four cases are verified verbatim by `testOriginValidation`.
- **signinapps-origin-canonicalization-and-dedup**: `canonicalOrigin(_:)` MUST lowercase the scheme and host and drop a trailing slash while preserving the port (verified: `"HTTPS://Example.com:8443/"` → `"https://example.com:8443"`); `canonicalOrigins(_:)` MUST validate every raw origin (throwing `HubError.validation` on the first failure), then canonicalize and de-duplicate in first-seen order using a `Set` for the membership check and an ordered array for the result.
- **signinapps-start-url-placeholder**: `startURL(clientID:)` MUST return a fixed, non-resolvable placeholder-templated string of the form `<your-adh-auth-host>/oauth/signin/start?clientId=<clientID>&providerId=github&return=<your-app-origin>/auth/callback` — it is documentation text for the detail's read-only "Start URL" field, not a URL the app itself ever fetches.
- **signinapps-detail-fields**: the detail `FormSpec` MUST present fields in the order `name`, `slug`, `githubEnabled`, `allowedReturnOrigins`, `startURL` (verified by `testDetailAndSave`); `slug` is read-only.
- **signinapps-delete-confirmation**: the delete action's title MUST be "Delete sign-in app" and its confirmation text MUST be `Delete sign-in app "<app.name>"? Apps using it will stop signing in.` (verified by `testDeleteConfirmation`).
- **signinapps-unknown-app-empty**: a `path[0].id` matching no existing app's `id` MUST return `.empty` (verified by `testUnknownAppIsEmpty`).
- **web-signinapps-slug-normalization**: `signinAppsApi.create` MUST trim and lowercase `input.slug` and trim `input.name` client-side before sending the POST body — a defensive normalization Swift does not need at create time, because `clientId`'s `Slug.pattern` already constrains it to lowercase.
- **web-signinapps-conflict-message-parity**: `signinAppsApi.create`'s catch handler MUST call `rethrowConflict(err, ...)` with the message `A sign-in app "<input.slug>" already exists in this ecosystem.` — the identical wording `SigninAppsTopic`'s create-conflict path uses on Apple, keeping the two platforms' user-visible error text in parity.
- **web-signinapps-origin-validation-elsewhere**: `signinAppsApi.create`/`update` in `signin-apps.ts` forward `allowedReturnOrigins` with no client-side format check of their own; the equivalent scheme/credentials/path checks (mirroring `validateOrigin`) live in `SigninAppDetail.tsx`'s `validateOrigin`/`canonicalizeOrigin` helpers — a UI-pane file outside this component's given web sources, not a gap in the given `signin-apps.ts` client (see Design Decisions).
- **web-signinapps-leaf-helper-absence**: the web `SigninApp` interface has no equivalent of Apple's `leaf(in:)` computed property; a web caller that needs the ecosystem-stripped leaf must recompute it from `slug` and the ecosystem's own slug itself.

### FeatureFlagsTopic (Apple) and feature-flags.ts (Web)

- **flags-no-cache-per-call**: `FeatureFlagsTopic.child` MUST call `dataSource.list(ecosystemID:)` fresh on every invocation — there is no in-memory cache of the flag list between calls.
- **flags-list-sort-and-sublabel**: the level's items MUST be sorted by `key` ascending (verified by `testListSortedByKey`: `["dark_mode", "new_checkout"]`); each item's sublabel MUST be `"On"` or `"Off"`, with `" · <description>"` appended when `description` is non-empty, and its `systemImage` MUST be `"flag.fill"` when enabled or `"flag"` when disabled.
- **flags-create-fields**: the create `FormSpec` MUST expose `key`, `description`, `enabled` in that order (verified by `testCreateSpec`); `key` is required.
- **flags-duplicate-key-check**: before calling `dataSource.create`, the save action MUST reject a `key` already present in the passed-in `existing` list with `A flag named "<key>" already exists.`; a `HubError.conflict` from the network call itself MUST be caught and re-thrown with the identical message (both paths verified by `testCreateSpec`).
- **flags-detail-fields**: the detail `FormSpec` MUST present `key` (read-only), `enabled`, `description` in that order (verified by `testDetailSaveAndDelete`); the update sent on save MUST fall back to the current `flag.enabled`/`flag.description` for any field the values dictionary omits.
- **flags-delete-confirmation**: the delete action's title MUST be "Delete flag" and its confirmation text MUST be `"<flag.key>" will be removed. Anything reading it falls back to its default.` (`FeatureFlagsTopic.removalMessage`, verified by `testDetailSaveAndDelete`).
- **flags-detail-id-format**: the detail id MUST be `feature-flag:<ecosystem.id>:<flag.key>` (verified: `"feature-flag:org.acme.shop:new_checkout"`).
- **flags-key-charset**: NEEDS REVIEW: Not implemented in source. Neither `FeatureFlagsTopic.createSpec`'s `key` field (Apple) nor `ecosystemFeatureFlagsApi.create`/the flag-dialog's key input (Web, per `flag-dialog-state.ts`) enforce any character-set restriction on a feature-flag key — only non-blank and non-duplicate are checked — yet the key is later embedded unescaped in the colon-delimited composite id `feature-flag:<ecosystem.id>:<flag.key>` and used directly as an `HTDVItem` id; a key containing a colon could collide with another item's composite id. What is missing: a defined character-set restriction for flag keys, matching the `Slug`-pattern restriction already applied to `SigninAppsTopic`'s `clientId` and `StorageTokensRail`'s `name`. Evidence that would settle it: confirmation from the composite-id format's other consumers on whether a colon or other reserved character in a key can actually cause a collision, or a validating pattern added to the key field.
- **web-flags-key-immutable-in-path**: `ecosystemFeatureFlagsApi.update`/`delete` MUST address a flag by embedding its `key` in the URL path (`enc(key)`), never in the body — the key is immutable once created, matching Apple's use of `key` as `FeatureFlag.id`.
- **web-flags-no-client-duplicate-precheck**: `ecosystemFeatureFlagsApi.create` MUST send the POST unconditionally and let a duplicate key surface as whatever HTTP status the backend returns; unlike `FeatureFlagsTopic.createSpec`, it performs no pre-flight duplicate check against an existing list and does not intercept a conflict into a friendlier message (no `rethrowConflict` call, unlike `signin-apps.ts`).

### ServerBagsTopic (Apple) and server-bags.ts (Web)

- **bags-list-preview**: the level's items MUST be sorted by `key` ascending, with sublabel `ServerBag.preview` — `value.prettyText` collapsed to one line by splitting on newlines and rejoining with a single space (verified by `testListShowsPreview`: `{ "maxItems" : 20 }`).
- **bags-create-fields**: the create `FormSpec` MUST expose `key`, `value` (a `FormJSONField`, required), `description`, in that order (verified by `testCreateSpecRequiresValidJSON`).
- **bags-json-parse-before-duplicate-check**: in the create save action, `value` MUST be parsed via `ServerBagsTopic.parsedValue` before the duplicate-`key` check runs (verified by `testCreateSpecRequiresValidJSON`'s ordering: invalid JSON with a taken key still surfaces the JSON error first).
- **bags-invalid-json-message-generic**: `parsedValue(_:)` MUST discard `JSONValue.parse`'s specific `DecodingError`-derived message and throw `HubError.validation(ServerBagsTopic.invalidJSONMessage)` instead, where `invalidJSONMessage` is the fixed string `Value must be valid JSON — e.g. true, 42, "text", or {"a": 1}.`
- **bags-duplicate-key-check**: the same dual client-pre-check-plus-conflict-catch pattern as `FeatureFlagsTopic` applies, with the message `A bag named "<key>" already exists.` (verified by `testCreateSpecRequiresValidJSON`).
- **bags-detail-full-replace-on-save**: the detail save action MUST re-parse `value` from the form's current text on every save and send it as a full replacement in `ServerBagUpdate.value`, never a merge of the previous and new JSON (verified by `testDetailSaveAndDelete`).
- **bags-removal-message-distinct-from-flags**: `ServerBagsTopic.removalMessage` ("will be deleted. Anything reading it gets nothing — there is no default.") MUST NOT reuse `FeatureFlagsTopic.removalMessage` ("will be removed. Anything reading it falls back to its default.") — the source's own comment states the reason: server bags have no default fallback, unlike feature flags, so borrowing the flags' message would promise a fallback that does not exist (see Design Decisions).
- **bags-json-equality-int-number**: `JSONValue`'s hand-written `==`/`hash(into:)` MUST treat `.int` and `.number` as the same value whenever they represent the same integral quantity (verified by `testDetailSaveAndDelete`: a stored `.number(20)` bag, updated by typing `{"maxItems": 50}`, produces `ServerBagUpdate(value: .object(["maxItems": .int(50)]), ...)`, and the update's expected value is written as `.int(50)` even though the original was `.number(20)`) — the source's own comment explains this exists because the synthesized equality otherwise misfired a form's dirty-check.
- **web-bags-value-untyped-no-validation**: `EcosystemServerBag.value`/`EcosystemServerBagCreate.value`/`EcosystemServerBagUpdate.value` MUST be typed `unknown` in `server-bags.ts`, and this file performs no JSON-shape validation of its own — the equivalent of `ServerBagsTopic.parsedValue`'s parse-or-reject step lives in `bag-dialog-state.ts`, a sibling `features/ecosystem-config` package outside this component's given web sources, not in the data client itself (see Design Decisions).

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

## Appearance

Not applicable — this is a set of navigation/data-orchestration topics and data clients, not a visual component.

## States

Not applicable — this is a set of navigation/data-orchestration topics and data clients, not a visual component. The only stateful runtime behavior is `StorageTokensRail`'s `revealedSecrets`/`revealedOnScreen` reveal-once lifecycle, which is specified under Behavioral Requirements (`tokens-reveal-once-on-create`, `tokens-expire-revealed-secret-on-navigate`, `tokens-revoke-clears-revealed-secret`), not here.

## Accessibility

Not applicable — this is a set of navigation/data-orchestration topics and data clients, not a visual component. Accessibility of the forms these topics build is the concern of whatever renders `FormSpec`/`HTDVLevel`/`HTDVDetail`, a different component not among these given sources.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| ecosystem-config-001 | auth-field-order, auth-signup-options | `AuthSettingsTopic(dataSource: fake).child(for: .fixture(), path: [], rail:)` with `settings = AuthSettings(signupMode: .inviteOnly, loginEnabled: true)` | detail id `"auth-settings:org.acme.shop"`, fields `["signupMode", "signupHelp", "loginEnabled"]`, `signupHelp` = "Only people you've invited can create an account." — `AuthSettingsTopicTests.testDetailShowsPolicy` |
| ecosystem-config-002 | auth-save-sends-both-values | Set `signupMode = "closed"`, `loginEnabled = false`, then save | `data.updates == [AuthSettingsUpdate(signupMode: .closed, loginEnabled: false)]` — `testSaveSendsBothValues` |
| ecosystem-config-003 | path-depth-dispatch (auth) | `rail.child(["x"])` on `AuthSettingsTopic` | `.empty` — `testUnknownPathIsEmpty` |
| ecosystem-config-004 | signinapps-list-sort | Two apps named "Shop web" and "Admin console" | level items ordered `["Admin console", "Shop web"]` — `SigninAppsTopicTests.testListSortedByName` |
| ecosystem-config-005 | signinapps-origin-validation | `validateOrigin("https://user:pw@example.com")` | `"Return origin \"https://user:pw@example.com\" must not include credentials."` — `testOriginValidation` |
| ecosystem-config-006 | signinapps-origin-canonicalization-and-dedup | `canonicalOrigin("HTTPS://Example.com:8443/")` | `"https://example.com:8443"` — `testOriginValidation` |
| ecosystem-config-007 | signinapps-duplicate-leaf-check, signinapps-clientid-pattern | Create with `clientId = "Bad.Id"`, then `"shop-web"` (taken, case-insensitive), then `"kiosk"` | first save fails with `leafMessage`; second fails with `App id "shop-web" is already in use.`; third succeeds — `testCreateSpecValidatesLeafAndDuplicates` |
| ecosystem-config-008 | signinapps-create-conflict-message | `dataSource.create` throws `HubError.conflict("dup")` for slug `"kiosk"` | save fails with `A sign-in app "kiosk" already exists in this ecosystem.` — `testCreateConflictMessage` |
| ecosystem-config-009 | signinapps-detail-fields, signinapps-origin-validation | Set `allowedReturnOrigins = ["https://Shop.acme.test/", "bogus"]`, save | save fails with `Return origin "bogus" is not a valid URL.` — `testDetailAndSave` |
| ecosystem-config-010 | signinapps-delete-confirmation | Read `actions.delete` for app "Shop web" | title "Delete sign-in app", text `Delete sign-in app "Shop web"? Apps using it will stop signing in.` — `testDeleteConfirmation` |
| ecosystem-config-011 | flags-list-sort-and-sublabel | Flags `new_checkout` (enabled, described) and `dark_mode` (disabled) | items ordered `["dark_mode", "new_checkout"]`; `dark_mode` sublabel "Off", systemImage "flag"; `new_checkout` sublabel "On · New checkout flow", systemImage "flag.fill" — `FeatureFlagsTopicTests.testListSortedByKey` |
| ecosystem-config-012 | flags-duplicate-key-check | Create with key `"dark_mode"` (taken), then `"beta_search"` | first save fails with `A flag named "dark_mode" already exists.`; second succeeds — `testCreateSpec` |
| ecosystem-config-013 | flags-delete-confirmation, flags-detail-id-format | Delete flag `new_checkout` | detail id `"feature-flag:org.acme.shop:new_checkout"`; confirmation `"new_checkout" will be removed. Anything reading it falls back to its default.` — `testDetailSaveAndDelete` |
| ecosystem-config-014 | bags-list-preview | Bag `onboarding` with value `.object(["maxItems": .number(20)])` | sublabel `{ "maxItems" : 20 }` — `ServerBagsTopicTests.testListShowsPreview` |
| ecosystem-config-015 | bags-json-parse-before-duplicate-check, bags-invalid-json-message-generic | Create with key `"limits"`, value `"{oops"` | save fails with a JSON error on the `value` field before any duplicate check runs — `testCreateSpecRequiresValidJSON` |
| ecosystem-config-016 | bags-detail-full-replace-on-save, bags-json-equality-int-number | Edit bag `onboarding` (originally `.number(20)`), typing `{"maxItems": 50}` | `data.updates.last?.body == ServerBagUpdate(value: .object(["maxItems": .int(50)]), description: "Onboarding limits")`; delete confirmation `"onboarding" will be deleted. Anything reading it gets nothing — there is no default.` — `testDetailSaveAndDelete` |
| ecosystem-config-017 | tokens-reveal-once-on-create, tokens-detail-extra-fields-while-revealed, tokens-expire-revealed-secret-on-navigate | Mint token "nightly", view its detail twice, then view the level, then view its detail again | secret shown both times before navigating away; `revealedSecrets["tok-nightly"]` is `nil` and the `token`/`notice` fields are absent after `rail.level([])` — `StorageTokensTopicTests.testCreateSpecMintsAndRevealsSecret` |
| ecosystem-config-018 | tokens-create-three-way-catch | `dataSource.create` throws `HubError.conflict("taken")` for name `"ci-sync"` | save fails with `StorageTokensRail.nameTakenMessage` — `testCreateConflictMessage` |
| ecosystem-config-019 | tokens-revoke-clears-revealed-secret, tokens-no-save-action-on-detail | Revoke token `tok-1` | `actions.save == nil`; `data.revoked.last == (ecosystemID: "org.acme.shop", id: "tok-1")` — `testDetailFactsAndRevoke` |
| ecosystem-config-020 | tokens-shared-rail-parameterization, tokens-about-text-variant | `rail.child(path: [], ecosystemID: nil, ...)` | `data.listedEcosystems == [nil]`; `aboutText(ecosystemID: nil) == "A storage principal scoped to your account; it gets its own empty bucket."` — `testRailWithoutEcosystemListsOwnTokens` |
| ecosystem-config-021 | web-flags-key-immutable-in-path | `ecosystemFeatureFlagsApi.update("eco-1", "dark_mode", {enabled: false})` | request goes to `PUT /api/ecosystem/feature-flags/eco-1/dark_mode` with only `{enabled: false}` in the body — `feature-flags.ts` |
| ecosystem-config-022 | web-signinapps-conflict-message-parity | `signinAppsApi.create("eco-1", {slug: "kiosk", ...})` where the backend responds 409 | rejects with `A sign-in app "kiosk" already exists in this ecosystem.` — `signin-apps.ts`'s `rethrowConflict` call |
| ecosystem-config-023 | web-tokens-dual-scoping-channels | `tokenPrincipalsApi.mint({name: "nightly"}, {ecosystemId: "eco-1"})` | `POST /api/tokens?ecosystemId=eco-1` with body `{"name":"nightly"}` (no `ecosystemId` in the body) — `storage-tokens.ts`'s `scopeQuery` |

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

## Deep Linking

Not applicable: none of the nine given Swift files or five given TypeScript files define a URL scheme, route table, or `NSUserActivity`/universal-link handler. Navigation is expressed entirely through the `HTDVItem`/`[HTDVItem]` path values that a separate rail-rendering component (not among these sources) turns into UI.

## Localization

Every user-facing string in this component is a hardcoded English literal — there is no `NSLocalizedString`, `String(localized:)`, `.strings`/`.stringsdict` reference, or i18n library call anywhere in the given Swift or TypeScript files. Representative examples: `AuthSettingsTopic`'s "When off, no one can sign in to this ecosystem."; `SignupMode.help`'s three case strings (`EcosystemConfigModels.swift`); `FeatureFlagsTopic.removalMessage` and `ServerBagsTopic.removalMessage`; `SigninAppsTopic.validateOrigin`'s four rejection messages; `StorageTokensRail.nameTakenMessage`, `createFailedMessage`, `aboutWithEcosystem`, and `aboutWithoutEcosystem`. This is a fact of the current implementation, not a gap this recipe marks — nothing in the source suggests localization is planned or partially wired.

## Accessibility Options

Not applicable: these files render nothing and read no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color, VoiceOver) — that is the concern of whatever renders the `FormSpec`/`HTDVLevel`/`HTDVDetail` value objects these topics build.

## Feature Flags

Not applicable, in the build-time/runtime-toggle sense this section means: none of the given sources gate their own behavior behind a feature flag. (`FeatureFlagsTopic` itself *manages* feature flags as domain data for other apps to read — that is the component's subject matter, documented under Behavioral Requirements, not a toggle over this component's own code paths.)

## Analytics

Not applicable: no given source calls an analytics or event-emission API of any kind.

## Privacy

- **Data collected**: this component collects no analytics of its own. It transports `AuthSettings`, `SigninApp`, `FeatureFlag`, and `ServerBag` — configuration entities holding no end-user personal data — and `StorageToken`/`StorageTokenCreated`/`TokenPrincipal`/`TokenPrincipalCreated`, which do carry a security-sensitive secret: the raw `adh_…` token minted by `StorageTokensDataSource.create` / `tokenPrincipalsApi.mint`.
- **Storage**: on Apple, `StorageTokensRail.revealedSecrets: [String: String]` holds the raw secret in an in-memory dictionary on the `@MainActor`-isolated instance only; it is never written to `UserDefaults`, the Keychain, or any file by this component. It is dropped by `revoke`'s `MainActor.run { self?.revealedSecrets[token.id] = nil }` and by `expireRevealedSecret(unless:)` on navigating away from the detail that revealed it. On Web, `tokenPrincipalsApi.mint` returns `TokenPrincipalCreated.token` to the caller with no persistence of any kind in `storage-tokens.ts`/`wire.ts` — per `wire.ts`'s own comment, the 201 response is "the ONLY response that carries the raw secret, and it is shown once."
- **Transmission**: the mint/create request travels over whichever transport the injected `StorageTokensDataSource` (Apple) or `authedJson` (Web) implementation uses — neither is part of this component's given sources, and this component configures no TLS or transport-level behavior itself.
- **Retention**: the plaintext secret is retained only until the reveal-once contract expires it (Apple) or for as long as the caller holds the 201 response (Web; no retention logic is given). `AuthSettings`, `SigninApp`, `FeatureFlag`, and `ServerBag` have no retention policy defined in these sources beyond whatever the backend itself enforces.

## Logging

Not applicable: none of the nine given Swift files or five given TypeScript files call `Logger`, `os_log`, `print`, `console.log`, or any other logging API.

## Platform Notes

- **SwiftUI**: not applicable to these sources directly — none of the nine Swift files imports SwiftUI; they build `FormSpec`/`HTDVLevel`/`HTDVDetail` value objects that a SwiftUI (or AppKit) rendering layer elsewhere consumes unchanged.
- **AppKit / UIKit**: this is one of the two source platforms. The files live under `packages/apple/AgenticToolkit/Hub/Features/EcosystemConfig/`, part of the `AgenticToolkitHub` sources directory that `project.yml` builds into both `AgenticToolkitHub-macOS` and `AgenticToolkitHub-iOS` targets from the same source tree — there is no platform-specific branch anywhere in these nine files.
- **React / Web**: this is the other source platform. `feature-flags.ts`, `server-bags.ts`, `signin-apps.ts`, `storage-tokens.ts`, and `wire.ts` under `packages/web/packages/data/src/ecosystem-config/` are plain `fetch`-based clients with no JSX; the UI panes and dialog-state modules that call them (`FeatureFlagsPane.tsx`, `bag-dialog-state.ts`, `SigninAppDetail.tsx`) are not among this recipe's given sources, but see Design Decisions for the validation-layering split observed there.
- **Compose**: model each Apple protocol as a Kotlin `interface` with `suspend fun`s (e.g. `interface FeatureFlagsDataSource { suspend fun list(ecosystemId: String): List<FeatureFlag> }`); represent `StorageTokensRail.revealedSecrets` as a `MutableStateFlow<Map<String, String>>` so Compose recomposition observes the reveal-once transition; model `JSONValue` with `kotlinx.serialization.json.JsonElement`, noting the same integral-`Double`-vs-`Long` equality pitfall `bags-json-equality-int-number` documents applies to `JsonPrimitive` unless normalized the same way.
- **WinUI 3**: model each data-source protocol as a C# interface returning `Task<T>` (e.g. `Task<IReadOnlyList<FeatureFlag>> ListAsync(string ecosystemId)`) backed by `HttpClient` and `System.Text.Json` for (de)serialization, mirroring the `async`/`await` shape of Swift's `async throws` and TypeScript's `Promise`; back a level's item list with an `ObservableCollection<T>` (or a view-model implementing `INotifyPropertyChanged`) for a WinUI 3 `ListView`/`ItemsView`. For `StorageTokensRail`'s reveal-once secret, keep the equivalent of `revealedSecrets` as a plain in-memory field on the view-model — deliberately never written to `Windows.Storage.ApplicationData` or any DPAPI-backed store — so the "shown once" contract this component enforces is preserved rather than accidentally persisted.

## Design Decisions

**Decision**: `ServerBagsTopic.removalMessage` ("will be deleted. Anything reading it gets nothing — there is no default.") is declared independently rather than reusing `FeatureFlagsTopic.removalMessage` ("will be removed. Anything reading it falls back to its default."), even though both are one-line "what deleting this costs" strings for a very similar delete-confirmation UI.
**Rationale**: the source's own comment on `ServerBagsTopic.removalMessage` states the reason directly: "Server bags have no defaults to fall back to, unlike feature flags: deleting one leaves readers with nothing at all. Borrowing `FeatureFlagsTopic.removalMessage` promised a fallback that does not exist, in the one dialog whose job is to say what deleting costs." Sharing the string would have made the confirmation dialog lie about what actually happens.
**Approved**: pending

**Decision**: `StorageTokensRail.createSpec`'s save action uses a three-way catch (`HubError.conflict` → friendly message; other `HubError` → rethrown as-is; anything else → generic `HubError.unexpected(createFailedMessage)`) instead of the `HubError.wrap { ... }` convention every other create/update/delete call in this component uses.
**Rationale**: the conflict case needs its own friendly text (`nameTakenMessage`) rather than whatever detail the backend's 409 carries, and the source chooses to discard a non-`HubError` failure's own message in favor of a generic one rather than risk surfacing raw transport detail from a mint request specifically. This is documented here as an observed, intentional divergence rather than corrected to match `HubError.wrap`, since changing it would alter the exact error text this component's tests assert.
**Approved**: pending

**Decision**: `StorageTokensRail.detail` sources its post-reveal notice text from `ApplicationsTopic.revealMessage`, a constant declared in a sibling `Applications` module, rather than declaring its own copy.
**Rationale**: the source's own comment states this directly — the reveal-once behavior exists specifically because `ApplicationsTopic.revealMessage`'s promise ("you won't be able to see it again") must actually hold; the same lifecycle and constant are documented as canonical in the sibling recipe `agentictoolkit://recipes/auth-client-authentication`, which this recipe treats as the complete reference for that shared behavior rather than re-deriving it here. The coupling means a future rename of `ApplicationsTopic.revealMessage` would need to be tracked across both modules with no compiler-enforced link beyond the direct reference.
**Approved**: pending

**Decision**: JSON-shape validation for a server bag's value lives inside `ServerBagsTopic.parsedValue` on Apple, combining transport-adjacent orchestration with domain validation in one type; on Web, the equivalent validation is not in the given `server-bags.ts` data client at all — it lives in `bag-dialog-state.ts`, a sibling `features/ecosystem-config` package.
**Rationale**: the two platforms split responsibilities differently: Apple's `EcosystemTopicProvider` types are the single place that both talk to the data source and build the declarative form, so validation naturally lives there too; Web keeps its data-client layer (`packages/data`) free of any dependency on UI-adjacent validation state, pushing that concern into the `packages/features` package that owns the dialog. Both are internally consistent with their own layering; this recipe documents the divergence rather than treating either as a gap.
**Approved**: pending

**Decision**: on Web, origin-format validation for a sign-in app's `allowedReturnOrigins` (mirroring Apple's `validateOrigin`/`canonicalOrigin`) is not present in the given `signin-apps.ts` data client — it lives in `SigninAppDetail.tsx`'s own `validateOrigin`/`canonicalizeOrigin` helpers, a UI-pane file outside this component's given sources.
**Rationale**: this follows the same data-client/features-package split as the server-bag JSON validation above, and was confirmed by reading the actual caller rather than assumed, per this recipe's requirement to resolve an apparent gap against the real codebase before marking it unresolved.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | partial | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | partial | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [input-sanitization](agenticdevelopercookbook://compliance/security#input-sanitization) | partial | Security |
| [secure-storage](agenticdevelopercookbook://compliance/security#secure-storage) | partial | Security |

`separation-of-concerns` is partial: transport is cleanly isolated behind five single-purpose protocols (`AuthSettingsDataSource`, `SigninAppsDataSource`, `FeatureFlagsDataSource`, `ServerBagsDataSource`, `StorageTokensDataSource`), and none of the twelve given files import a UI-rendering framework — but each Topic still combines data-source orchestration, domain validation (origin/JSON/duplicate-key checks), and declarative `FormSpec`/`HTDVLevel` construction with hardcoded user-facing strings in one type; this follows from the HTDV framework's declarative-model design rather than a UI-rendering leak, but it is still multiple responsibilities sharing one file. `unit-test-coverage` is partial: `EcosystemConfigTopicsTests.swift` exercises every Apple sub-component with fakes and concrete assertions, but none of the five given web files (`feature-flags.ts`, `server-bags.ts`, `signin-apps.ts`, `storage-tokens.ts`, `wire.ts`) has any adjacent test anywhere in the repository. `explicit-error-handling` passes: every Apple call site wraps its data-source call in `HubError.wrap` or an explicit `catch` (including `StorageTokensRail`'s three-way catch, which is still explicit, never silent), and every web call either lets `authedJson`'s thrown rejection propagate or maps it through `rethrowConflict`; no given source catches and discards an error. `input-sanitization` is partial: `SigninAppsTopic.validateOrigin`/`canonicalOrigin`, `ServerBagsTopic.parsedValue`, and the `Slug.pattern`-constrained `clientId`/token-`name` fields validate before any network call on Apple, but the parallel web data clients (`signin-apps.ts`, `server-bags.ts`) forward `allowedReturnOrigins`/`value` with no validation of their own (that validation lives in sibling UI-layer files outside this component's given sources — see Design Decisions), and neither platform restricts a feature-flag key's character set at all (see the open question on `flags-key-charset`). `secure-storage` is partial: the one genuinely sensitive value, the storage-token secret, is deliberately never written to the Keychain, `UserDefaults`, or any persistent store by this component — it lives only in `StorageTokensRail.revealedSecrets`'s in-memory dictionary and is dropped on navigation-away or revoke — which avoids insecure persistence entirely rather than routing through a platform secure-storage API, so the check's literal Keychain/DPAPI expectation does not apply the way it would to a persisted credential.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-24 | | Initial creation |
