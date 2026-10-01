---
id: 87ca0139-6cd0-46dd-a9fb-40ad3406f175
title: Ecosystem Config
domain: agentictoolkit://cookbook/adh/hub/ecosystems/ecosystem-config
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Five product-rail topics (User Auth, Sign-in apps, Feature flags, Server
  bags, Storage Access Tokens) that let a hub caller view and edit one ecosystem's
  configuration, plus their shared data models and matching client-side data layer.
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
- agentictoolkit://cookbook/adh/hub/security/authentication-client
- agentictoolkit://cookbook/adh/hub/ecosystems/ecosystems
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

This component is five topic implementations that hang off one ecosystem's product
rail — a user-auth topic, a sign-in-apps topic, a feature-flags topic, a
server-bags topic, and a storage-tokens topic (a thin wrapper around a shared token
rail) — plus the data models and five data-source interfaces they share, and a
matching client-side data layer for the same five resources. Each topic resolves a
rail-relative navigation path into a level (a list of that ecosystem's
flags/bags/apps/tokens, with a create action) or a detail (a form specification for
viewing/editing one entity), orchestrating an injected data-source interface, domain
validation, and error normalization through a shared error type. A second,
independently maintained client layer implements the corresponding fetch operations
for the same five resources, consumed by presentation-layer panes and dialog-state
modules that are not part of this component's given sources. This is a **logic**
component: none of these five topics render anything themselves — they build
declarative form/level/detail value objects that a separate presentation layer
(outside these sources) turns into UI, and the second client layer is a set of plain
fetch-based operations with no view code of its own.

## Behavioral Requirements

### Cross-cutting (all five topics)

- **ecosystem-scoped-navigation**: every rail path resolution MUST scope its
  data-source calls to the given ecosystem's id; every topic passes that id through
  on every call, including the storage-tokens topic passing it through to the shared
  token rail.
- **path-depth-dispatch**: for sign-in apps, feature flags, server bags, and storage
  tokens, a rail path resolution MUST return a level when the path is empty, MUST
  look up the matching entity by id/key and return a detail when found or an empty
  result when not found for a one-segment path, and MUST return an empty result for
  any longer path. User auth has no level at all: an empty path MUST return the
  single detail, and any non-empty path MUST return an empty result.
- **hub-error-wrapping**: every data-source call in each of the five topics — except
  the storage-tokens topic's create call, which uses a different pattern (see
  **tokens-create-three-way-catch**) — MUST be wrapped in the shared error-wrapping
  step, so a thrown transport/API error is normalized to a shared error kind before
  it reaches the caller.

### User Auth

- **auth-detail-only-entry**: the entry point MUST declare that it leads straight to
  a detail — there is no list level for this topic; navigating to it goes straight
  to the one settings form.
- **auth-field-order**: the detail's form specification MUST present fields in the
  order `signupMode`, `signupHelp`, `loginEnabled`, grouped into a "Sign-up" section
  (`signupMode` select plus a read-only `signupHelp` line) and a "Sign-in" section
  (the `loginEnabled` toggle).
- **auth-signup-options**: the `signupMode` select field's options MUST be every
  recognized sign-up mode in a fixed declaration order (`open`, `inviteOnly`,
  `closed`), titled "Open", "Invite only", "Closed" respectively.
- **auth-signin-help-text**: the `loginEnabled` toggle's help text MUST be the fixed
  string "When off, no one can sign in to this ecosystem." — it does not vary by
  ecosystem or current setting.
- **auth-save-sends-both-values**: the save action MUST always construct an update
  carrying both `signupMode` and `loginEnabled`, never a partial patch, even if only
  one field changed.
- **auth-save-fallback-values**: if the submitted `signupMode` value cannot be
  parsed into a recognized sign-up mode, the save action MUST silently fall back to
  `inviteOnly`; if the submitted `loginEnabled` value is missing, it MUST fall back
  to `false`. Both are documented, in-source fallbacks, not swallowed errors — the
  field's fixed option set makes an invalid `signupMode` value unreachable through
  normal use.
- **auth-detail-id-format**: the detail's id MUST be the string
  `auth-settings:<ecosystem.id>`.
- **auth-no-delete-action**: the detail's delete action MUST be absent — auth
  settings can be edited but never removed.
- **auth-allowed-providers-not-editable**: the user-auth record's `allowedProviders`
  list decodes from the read operation's response, but the detail's form
  specification never reads, displays, or edits it, and the update shape has no
  field to write it back; this component offers no way to view or change the
  allowed providers.

### Sign-in Apps

- **signinapps-list-sort**: the level's items MUST be sorted by `name` using a
  case-insensitive, locale-aware comparison ("Admin console" before "Shop web");
  each item's sublabel MUST be the app's full `slug` (e.g. "shop.shop-web").
- **signinapps-leaf-computation**: the leaf-computation step MUST strip the
  `"<ecosystem.slug>."` prefix from `slug` when present, returning `slug` unchanged
  when it is not — a defensive fallback, since the server prefixes the client slug
  with the ecosystem slug and forces the ecosystem, so every listed `slug` is
  expected to carry that prefix in practice.
- **signinapps-create-fields**: the create form specification MUST expose only
  `name` and `clientId`; `allowedReturnOrigins` and `githubEnabled` are editable
  only after creation, in the detail.
- **signinapps-duplicate-leaf-check**: before calling create, the save action MUST
  reject a `clientId` whose lowercased value matches any existing app's lowercased
  leaf, with the message `App id "<leaf>" is already in use.`.
- **signinapps-clientid-pattern**: the `clientId` field MUST validate against the
  shared slug-format rule with message `App id must be a lowercase token, e.g.
  my-app.` before the duplicate check runs.
- **signinapps-create-conflict-message**: a conflict error thrown by create MUST be
  caught and re-thrown as a validation error reading `A sign-in app "<leaf>" already
  exists in this ecosystem.`; any other error MUST be re-wrapped through the shared
  error-wrapping step.
- **signinapps-origin-validation**: the origin-validation step MUST return no error
  for an acceptable origin and, for a rejected one, the first-violated-rule message:
  not-a-URL ("... is not a valid URL."), non-http(s) scheme ("... must be http(s)."),
  embedded credentials ("... must not include credentials."), or a
  non-empty/non-"/" path, query, or fragment ("... must be just a scheme + host (no
  path).").
- **signinapps-origin-canonicalization-and-dedup**: the origin-canonicalization step
  MUST lowercase the scheme and host and drop a trailing slash while preserving the
  port (e.g. `"HTTPS://Example.com:8443/"` → `"https://example.com:8443"`); the
  origin-list canonicalization step MUST validate every raw origin (throwing a
  validation error on the first failure), then canonicalize and de-duplicate in
  first-seen order.
- **signinapps-start-url-placeholder**: the start-URL text MUST be a fixed,
  non-resolvable placeholder-templated string of the form
  `<your-adh-auth-host>/oauth/signin/start?clientId=<clientID>&providerId=github&return=<your-app-origin>/auth/callback`
  — it is documentation text for the detail's read-only "Start URL" field, not a URL
  the app itself ever fetches.
- **signinapps-detail-fields**: the detail form specification MUST present fields in
  the order `name`, `slug`, `githubEnabled`, `allowedReturnOrigins`, `startURL`;
  `slug` is read-only.
- **signinapps-delete-confirmation**: the delete action's title MUST be "Delete
  sign-in app" and its confirmation text MUST be `Delete sign-in app "<app.name>"?
  Apps using it will stop signing in.`.
- **signinapps-unknown-app-empty**: a path segment id matching no existing app's id
  MUST return an empty result.
- **client-slug-normalization**: the alternate client's create operation MUST trim
  and lowercase the submitted `slug` and trim the submitted `name` client-side
  before sending the create request — a defensive normalization not strictly
  required at create time, since the `clientId` field's slug-format rule already
  constrains it to lowercase in the primary implementation.
- **conflict-message-parity**: the alternate client's create operation's conflict
  handling MUST use the message `A sign-in app "<slug>" already exists in this
  ecosystem.` — identical wording to **signinapps-create-conflict-message**,
  keeping the two implementations' user-visible error text in parity.
- **origin-validation-delegated**: the alternate client's create/update operations
  MUST forward `allowedReturnOrigins` with no client-side format check of their own;
  the equivalent scheme/credentials/path checks (mirroring
  **signinapps-origin-validation**) live in a separate presentation-layer file
  outside this component's given sources, not in the data-client layer itself (see
  Design Decisions).
- **leaf-helper-absent**: the alternate client's own data shape has no equivalent of
  the leaf-computation step; a caller on that side that needs the ecosystem-stripped
  leaf must recompute it from `slug` and the ecosystem's own slug itself.

### Feature Flags

- **flags-no-cache-per-call**: the rail path resolver MUST fetch the flag list
  fresh on every invocation — there is no in-memory cache of the flag list between
  calls.
- **flags-list-sort-and-sublabel**: the level's items MUST be sorted by `key`
  ascending (e.g. `["dark_mode", "new_checkout"]`); each item's sublabel MUST be
  "On" or "Off", with " · <description>" appended when `description` is non-empty,
  and its icon MUST visually distinguish the enabled state from the disabled state.
- **flags-create-fields**: the create form specification MUST expose `key`,
  `description`, `enabled` in that order; `key` is required.
- **flags-duplicate-key-check**: before calling create, the save action MUST reject
  a `key` already present in the passed-in `existing` list with `A flag named
  "<key>" already exists.`; a conflict error from the network call itself MUST be
  caught and re-thrown with the identical message.
- **flags-detail-fields**: the detail form specification MUST present `key`
  (read-only), `enabled`, `description` in that order; the update sent on save MUST
  fall back to the current `flag.enabled`/`flag.description` for any field the
  values dictionary omits.
- **flags-delete-confirmation**: the delete action's title MUST be "Delete flag" and
  its confirmation text MUST be `"<flag.key>" will be removed. Anything reading it
  falls back to its default.`.
- **flags-detail-id-format**: the detail id MUST be
  `feature-flag:<ecosystem.id>:<flag.key>`.
- **flags-key-charset**: NEEDS REVIEW: Not implemented in source. Neither the
  create form's `key` field in the primary implementation nor the alternate
  client's create operation/dialog state enforce any character-set restriction on a
  feature-flag key — only non-blank and non-duplicate are checked — yet the key is
  later embedded unescaped in the colon-delimited composite id
  `feature-flag:<ecosystem.id>:<flag.key>` and used directly as a navigation-item
  id; a key containing a colon could collide with another item's composite id. What
  is missing: a defined character-set restriction for flag keys, matching the
  slug-pattern restriction already applied to the sign-in-app `clientId` field and
  the storage-token `name` field. Evidence that would settle it: confirmation from
  the composite-id format's other consumers on whether a colon or other reserved
  character in a key can actually cause a collision, or a validating pattern added
  to the key field.
- **flag-key-immutable-in-path**: the alternate client's update/delete operations
  MUST address a flag by embedding its `key` in the request path, never in the
  body — the key is immutable once created, matching the primary implementation's
  use of `key` as the flag's own identifier.
- **flags-no-precheck-in-alternate-client**: the alternate client's create operation
  MUST send the request unconditionally and let a duplicate key surface as whatever
  status the backend returns; unlike the primary implementation's create form, it
  performs no pre-flight duplicate check against an existing list and does not
  intercept a conflict into a friendlier message.

### Server Bags

- **bags-list-preview**: the level's items MUST be sorted by `key` ascending, with
  sublabel set to the bag's value collapsed to one line by splitting on newlines and
  rejoining with a single space (e.g. `{ "maxItems" : 20 }`).
- **bags-create-fields**: the create form specification MUST expose `key`, `value`
  (a required JSON-value field), `description`, in that order.
- **bags-json-parse-before-duplicate-check**: in the create save action, `value`
  MUST be parsed via the value-parsing step before the duplicate-`key` check runs —
  invalid JSON with a taken key still surfaces the JSON error first.
- **bags-invalid-json-message-generic**: the value-parsing step MUST discard the
  underlying decode error's specific message and throw a validation error reading
  `Value must be valid JSON — e.g. true, 42, "text", or {"a": 1}.` instead.
- **bags-duplicate-key-check**: the same dual client-pre-check-plus-conflict-catch
  pattern as feature flags applies, with the message `A bag named "<key>" already
  exists.`.
- **bags-detail-full-replace-on-save**: the detail save action MUST re-parse
  `value` from the form's current text on every save and send it as a full
  replacement in the update's `value` field, never a merge of the previous and new
  JSON.
- **bags-removal-message-distinct-from-flags**: the server-bags delete
  confirmation's removal message ("will be deleted. Anything reading it gets
  nothing — there is no default.") MUST NOT reuse the feature-flags delete
  confirmation's message ("will be removed. Anything reading it falls back to its
  default.") — server bags have no default fallback, unlike feature flags, so
  borrowing the flags' message would promise a fallback that does not exist (see
  Design Decisions).
- **bags-json-equality-int-number**: the wrapped JSON value type's equality and
  hashing MUST treat an integral floating-point number and a plain integer as the
  same value whenever they represent the same integral quantity — e.g. a stored
  value of `20` (decoded as a floating-point JSON number), updated by typing
  `{"maxItems": 50}`, produces an update whose value is written as the integer `50`
  even though the original was decoded as a floating-point `20` — this exists
  because naive derived equality otherwise misfires a form's dirty-check.
- **bag-value-validation-delegated**: the alternate client's bag data shapes MUST
  leave `value` untyped, and that layer performs no JSON-shape validation of its
  own — the equivalent of the value-parsing step's parse-or-reject behavior lives
  in a sibling presentation-layer package outside this component's given sources,
  not in the data-client layer itself (see Design Decisions).

### Storage Access Tokens

- **tokens-shared-rail-parameterization**: the shared token rail's resolution
  operation MUST serve both the ecosystem-scoped case and the caller's-own-tokens
  case through the same operation, parameterized only by the ecosystem id (or its
  absence), the level id, and the title.
- **tokens-ecosystem-scoping-via-parameter**: the create form's save action MUST
  always construct its create body with no ecosystem id of its own — ecosystem
  scoping happens exclusively through the operation's own ecosystem-id parameter,
  never through the body's own ecosystem-id field.
- **tokens-about-text-variant**: the rail's about-text MUST return the no-ecosystem
  variant when no ecosystem id is given and the ecosystem-scoped variant otherwise.
- **tokens-name-pattern**: the create form's `name` field MUST validate against the
  shared slug-format rule ("Use lowercase letters, numbers and hyphens.").
- **tokens-create-three-way-catch**: the create form's save action MUST catch
  errors in three tiers: a conflict error becomes a validation error with a fixed
  "name taken" message; any other shared error kind MUST be re-thrown unchanged;
  any error outside that shared taxonomy MUST become a generic unexpected error
  with a fixed message, discarding the original error's own message. This is an
  explicitly different pattern from the shared error-wrapping convention used
  everywhere else in this component (see Design Decisions).
- **tokens-reveal-once-on-create**: on a successful create, the raw secret MUST be
  stored in the revealed-secrets store keyed by the created token's id.
- **tokens-detail-extra-fields-while-revealed**: the token detail MUST append
  `token` and `notice` read-only fields — with `notice` set to the fixed reveal
  notice ("Copy this token now — you won't be able to see it again.") — only while
  the revealed-secrets store holds a value for that token, and MUST set the
  on-screen-token marker to that token's id as a side effect of building that
  detail.
- **tokens-expire-revealed-secret-on-navigate**: the secret-expiry check MUST run
  at the top of every rail path resolution; it MUST drop the revealed secret and
  clear the on-screen-token marker when navigating to any destination other than
  the detail currently showing the secret, and MUST leave it untouched when
  re-rendering that same detail.
- **tokens-revoke-clears-revealed-secret**: the revoke action MUST wrap the revoke
  operation in the shared error-wrapping step and then clear that token's entry in
  the revealed-secrets store, regardless of whether a value was present.
- **tokens-no-save-action-on-detail**: the token detail's save action MUST be
  absent — a storage token has no editable fields once created, only revoke.
- **tokens-delete-confirmation**: the revoke action's title MUST be "Revoke token"
  and its confirmation text MUST be `Revoke storage token "<token.slug>"? Anything
  using it will lose access to its bucket.`.
- **tokens-detail-date-formatting**: the `lastUsed`/`created`/`expires` fields MUST
  format through the shared date-display helper, falling back to "never
  used"/"never" respectively when the underlying value is absent.
- **dual-scoping-channels**: the alternate client's list/mint/revoke operations
  MUST accept scoping through a query-parameter scope channel independently of the
  mint-request body's own ecosystem-id field, a separate channel; that layer
  performs no reconciliation between the two channels — a caller sets whichever one
  the operation needs (mirroring the primary implementation's rail, whose create
  form always leaves the body's ecosystem-id field unset and relies solely on the
  parameter channel).
- **token-created-once**: the created-token result (the response that carries the
  plaintext secret) MUST be a distinct shape from the token list-row shape (which
  carries only a `prefix`); the alternate client gives no other route through which
  the raw secret can be retrieved again.

## Appearance

Not applicable — this is a set of navigation/data-orchestration topics and data
clients, not a visual component.

## States

Not applicable — this is a set of navigation/data-orchestration topics and data
clients, not a visual component. The only stateful runtime behavior is the shared
token rail's revealed-secrets/on-screen-token reveal-once lifecycle, which is
specified under Behavioral Requirements (**tokens-reveal-once-on-create**,
**tokens-expire-revealed-secret-on-navigate**,
**tokens-revoke-clears-revealed-secret**), not here.

## Accessibility

Not applicable — this is a set of navigation/data-orchestration topics and data
clients, not a visual component. Accessibility of the forms these topics build is
the concern of whatever renders the form/level/detail value objects, a different
component not among these given sources.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| ecosystem-config-001 | auth-field-order, auth-signup-options | The user-auth detail resolved with sign-up mode "invite only" and sign-in enabled | Detail id "auth-settings:org.acme.shop"; fields ["signupMode", "signupHelp", "loginEnabled"]; the sign-up-help text reads "Only people you've invited can create an account." |
| ecosystem-config-002 | auth-save-sends-both-values | Sign-up mode set to "closed", sign-in disabled, then saved | The recorded update carries both fields: sign-up mode "closed" and sign-in disabled |
| ecosystem-config-003 | path-depth-dispatch | A one-segment path resolved against the user-auth topic | An empty result |
| ecosystem-config-004 | signinapps-list-sort | Two apps named "Shop web" and "Admin console" | Level items ordered ["Admin console", "Shop web"] |
| ecosystem-config-005 | signinapps-origin-validation | The origin-validation step given "https://user:pw@example.com" | "Return origin \"https://user:pw@example.com\" must not include credentials." |
| ecosystem-config-006 | signinapps-origin-canonicalization-and-dedup | The origin-canonicalization step given "HTTPS://Example.com:8443/" | "https://example.com:8443" |
| ecosystem-config-007 | signinapps-duplicate-leaf-check, signinapps-clientid-pattern | Create attempted with `clientId = "Bad.Id"`, then "shop-web" (taken, case-insensitive), then "kiosk" | First save fails with the slug-format message; second fails with "App id \"shop-web\" is already in use."; third succeeds |
| ecosystem-config-008 | signinapps-create-conflict-message | The create operation throws a conflict error for slug "kiosk" | Save fails with "A sign-in app \"kiosk\" already exists in this ecosystem." |
| ecosystem-config-009 | signinapps-detail-fields, signinapps-origin-validation | `allowedReturnOrigins` set to ["https://Shop.acme.test/", "bogus"], then saved | Save fails with "Return origin \"bogus\" is not a valid URL." |
| ecosystem-config-010 | signinapps-delete-confirmation | The delete action read for app "Shop web" | Title "Delete sign-in app"; text "Delete sign-in app \"Shop web\"? Apps using it will stop signing in." |
| ecosystem-config-011 | flags-list-sort-and-sublabel | Flags `new_checkout` (enabled, described) and `dark_mode` (disabled) | Items ordered ["dark_mode", "new_checkout"]; `dark_mode` sublabel "Off"; `new_checkout` sublabel "On · New checkout flow"; each item's icon reflects its enabled state |
| ecosystem-config-012 | flags-duplicate-key-check | Create attempted with key "dark_mode" (taken), then "beta_search" | First save fails with "A flag named \"dark_mode\" already exists."; second succeeds |
| ecosystem-config-013 | flags-delete-confirmation, flags-detail-id-format | Delete action read for flag `new_checkout` | Detail id "feature-flag:org.acme.shop:new_checkout"; confirmation "\"new_checkout\" will be removed. Anything reading it falls back to its default." |
| ecosystem-config-014 | bags-list-preview | Bag `onboarding` with value `{"maxItems": 20}` | Sublabel `{ "maxItems" : 20 }` |
| ecosystem-config-015 | bags-json-parse-before-duplicate-check, bags-invalid-json-message-generic | Create attempted with key "limits", value "{oops" | Save fails with a JSON error on the value field before any duplicate check runs |
| ecosystem-config-016 | bags-detail-full-replace-on-save, bags-json-equality-int-number | Bag `onboarding` (originally value 20) edited by typing `{"maxItems": 50}` | The recorded update's value is the object `{maxItems: 50}` with `50` written as an integer even though the original was a floating-point `20`; delete confirmation reads "\"onboarding\" will be deleted. Anything reading it gets nothing — there is no default." |
| ecosystem-config-017 | tokens-reveal-once-on-create, tokens-detail-extra-fields-while-revealed, tokens-expire-revealed-secret-on-navigate | Mint token "nightly", view its detail twice, then view the level, then view its detail again | Secret shown both times before navigating away; the revealed-secrets store holds nothing for that token and the `token`/`notice` fields are absent after visiting the level |
| ecosystem-config-018 | tokens-create-three-way-catch | The create operation throws a conflict error for name "ci-sync" | Save fails with the fixed "name taken" message |
| ecosystem-config-019 | tokens-revoke-clears-revealed-secret, tokens-no-save-action-on-detail | Revoke token `tok-1` | No save action present; the revocation is recorded against ecosystem "org.acme.shop", token id "tok-1" |
| ecosystem-config-020 | tokens-shared-rail-parameterization, tokens-about-text-variant | The shared token rail resolved with no ecosystem id | The caller's-own-tokens listing is used; the no-ecosystem about-text reads "A storage principal scoped to your account; it gets its own empty bucket." |
| ecosystem-config-021 | flag-key-immutable-in-path | The alternate client's update operation invoked for ecosystem "eco-1", flag "dark_mode", disabling it | The request addresses the flag by embedding its key in the request path, with only `{enabled: false}` in the body |
| ecosystem-config-022 | conflict-message-parity | The alternate client's create operation invoked for slug "kiosk", where the backend responds with a conflict status | Rejects with "A sign-in app \"kiosk\" already exists in this ecosystem." |
| ecosystem-config-023 | dual-scoping-channels | The alternate client's mint operation invoked with name "nightly" and ecosystem id "eco-1" via the scope-query channel | The request carries the ecosystem id only in the scope-query channel, not in the body |

## Edge Cases

- **Path deeper than one segment**: sign-in apps, feature flags, server bags, and
  storage tokens MUST return an empty result for any path longer than one segment;
  user auth MUST return an empty result for any non-empty path at all (it has no
  detail-lookup segment to descend into).
- **Unmatched id/key at depth one**: a path segment id matching no existing entity
  MUST return an empty result for all four list-based topics.
- **Malformed JSON in a server bag's value field**: the value-parsing step MUST
  discard the specific decode-error text and surface only the fixed invalid-JSON
  message, on both create and detail save.
- **Server-side duplicate after client pre-check passes**: a conflict error from
  create for flags, bags, or sign-in apps MUST be caught and re-thrown with the same
  friendly message the client-side pre-check uses, so the user sees identical
  wording regardless of which check caught the duplicate.
- **Case-insensitive sign-in-app leaf collision**: a new leaf that differs only in
  case from an existing one (e.g. "kiosk" vs. an existing "Kiosk") MUST be rejected
  by **signinapps-duplicate-leaf-check**, even though the raw strings are not equal.
- **Origin with credentials, a path, or a non-http(s) scheme**: each MUST be
  rejected by the origin-validation step with its own specific message and MUST NOT
  reach the network.
- **Re-rendering the detail currently showing a revealed secret**: MUST NOT drop the
  secret — the secret-expiry check's same-detail guard leaves it untouched; only
  navigating to a *different* destination drops it.
- **A value outside the shared error taxonomy thrown during storage-token create**:
  MUST be converted to a generic unexpected error with a fixed message, discarding
  the original error's own message text — a deliberate divergence from the shared
  error-wrapping step's usual behavior of preserving as much detail as possible (see
  Design Decisions).
- **A feature-flag key containing a reserved character (e.g. `:`)**: see the open
  question on **flags-key-charset** — no given implementation rejects it, but it is
  later embedded unescaped in a colon-delimited composite id.
- **Path segments containing special characters**: the alternate client's
  path-encoding step MUST percent-encode every ecosystem id, flag key, bag key, and
  sign-in-app id interpolated into a request path, so a key/id with `/`, `?`, or
  similar cannot corrupt the request path even though no character-set validation
  rejects such a key upstream.
- **The create body's own ecosystem-id field left unset while a scope parameter is
  also given**: neither implementation reconciles the two channels;
  **dual-scoping-channels** documents that the rail always leaves the body field
  unset and relies on the parameter/query channel exclusively.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `dataSource` | data-source interface | none (required) | Injected transport for the user-auth topic: read and update operations. |
| `dataSource` | data-source interface | none (required) | Injected transport for the sign-in-apps topic: list / create / update / delete, all scoped by the ecosystem id. |
| `dataSource` | data-source interface | none (required) | Injected transport for the feature-flags topic: list / create / update(key) / delete(key). |
| `dataSource` | data-source interface | none (required) | Injected transport for the server-bags topic: list / create / update(key) / delete(key). |
| `dataSource` | data-source interface | none (required) | Injected transport for the storage-tokens topic and its shared rail: list / create / revoke, where an absent ecosystem id means the caller's own workspace tokens. |
| `ecosystem` | record | none (required) | Supplies the id/slug used to scope every list/create/update/delete call and to build composite detail ids. |
| `path` | list of navigation-path segments | empty | Rail-relative navigation path; see **path-depth-dispatch**. |
| `rail` | rail-provider interface | none (required, unused) | Passed to every rail path resolution per the topic-provider contract; none of these five topics call back through it themselves. |
| ecosystem id (alternate client) | string | none (required) | Ecosystem id, percent-encoded into every ecosystem-config request path. |
| scope parameters (alternate client) | optional strings | unset | Optional query-string scoping used only by the token operations. |

## Deep Linking

Not applicable: none of the given implementation files define a URL scheme, route
table, or app-continuation/universal-link handler. Navigation is expressed entirely
through the navigation-path values that a separate rail-rendering component (not
among these sources) turns into UI.

## Localization

Every user-facing string in this component is a hardcoded English literal — there
is no localization-catalog reference or i18n library call anywhere in the given
implementation files. Representative examples: the user-auth topic's "When off, no
one can sign in to this ecosystem."; the sign-up-mode help text's three case
strings; the feature-flags and server-bags removal messages; the origin-validation
step's four rejection messages; the storage-tokens rail's name-taken, create-failed,
and about-text messages. This is a fact of the current implementation, not a gap
this recipe marks — nothing in the source suggests localization is planned or
partially wired.

## Accessibility Options

Not applicable: these files render nothing and read no accessibility display
setting (Reduce Motion, Increase Contrast, Differentiate Without Color, VoiceOver)
— that is the concern of whatever renders the form/level/detail value objects these
topics build.

## Feature Flags

Not applicable, in the build-time/runtime-toggle sense this section means: none of
the given implementations gate their own behavior behind a feature flag. (The
feature-flags topic itself *manages* feature flags as domain data for other apps to
read — that is the component's subject matter, documented under Behavioral
Requirements, not a toggle over this component's own code paths.)

## Analytics

Not applicable: no given source calls an analytics or event-emission API of any
kind.

## Privacy

- **Data collected**: this component collects no analytics of its own. It
  transports user-auth, sign-in-app, feature-flag, and server-bag records —
  configuration entities holding no end-user personal data — and storage-token
  records, which do carry a security-sensitive secret: the raw `adh_`-prefixed
  token minted by the create/mint operation.
- **Storage**: on the primary implementation, the revealed-secrets store holds the
  raw secret in an in-memory map on the topic instance only; it is never written to
  persistent storage or any file by this component. It is dropped by the revoke
  action and by the secret-expiry check on navigating away from the detail that
  revealed it. On the alternate client, the mint operation returns the
  created-token result to the caller with no persistence of any kind in that
  layer — the create-response body is the only response that carries the raw
  secret, and it is shown once.
- **Transmission**: the mint/create request travels over whichever transport the
  injected data source (primary implementation) or the equivalent
  authenticated-fetch helper (alternate client) implementation uses — neither is
  part of this component's given sources, and this component configures no TLS or
  transport-level behavior itself.
- **Retention**: the plaintext secret is retained only until the reveal-once
  contract expires it (primary implementation) or for as long as the caller holds
  the create response (alternate client; no retention logic is given). User-auth,
  sign-in-app, feature-flag, and server-bag records have no retention policy
  defined in these sources beyond whatever the backend itself enforces.

## Logging

Not applicable: none of the given implementation files call a logging API of any
kind.

## Platform Notes

- **SwiftUI**: not applicable to these sources directly — none of the Swift files
  imports SwiftUI; they build form/level/detail value objects that a SwiftUI (or
  AppKit) rendering layer elsewhere consumes unchanged.
- **AppKit / UIKit**: this is one of the two source platforms. The files live under
  `packages/apple/AgenticToolkit/Hub/Features/EcosystemConfig/`
  (`AuthSettingsTopic.swift`, `EcosystemConfigModels.swift`,
  `FeatureFlagsTopic.swift`, `ServerBagsTopic.swift`, `SigninAppsTopic.swift`,
  `StorageTokensRail.swift`, `StorageTokensTopic.swift`), part of the
  `AgenticToolkitHub` sources directory that `project.yml` builds into both
  `AgenticToolkitHub-macOS` and `AgenticToolkitHub-iOS` targets from the same
  source tree — there is no platform-specific branch anywhere in these files. Each
  topic conforms to `EcosystemTopicProvider` and implements
  `child(for:path:rail:)`; every data-source call not covered by the exception
  below is wrapped in `HubError.wrap { ... }`, with specific mappings to
  `HubError.conflict`/`.validation`/`.unexpected` where the requirements above call
  for a distinct message.

  Three requirements exist only because of Swift's concurrency and protocol model
  and apply to this platform alone: `AuthSettingsTopic`, `SigninAppsTopic`,
  `FeatureFlagsTopic`, `ServerBagsTopic`, and `StorageTokensRail`/
  `StorageTokensTopic` are declared `@MainActor final class`, with every method
  that touches their own stored state running only on the main actor. Static
  helpers a `FormAction.perform` closure calls directly —
  `ServerBagsTopic.parsedValue`, `SigninAppsTopic.validateOrigin`/
  `canonicalOrigin`/`canonicalOrigins`, `StorageTokensRail.nameTakenMessage`/
  `createFailedMessage` — are declared `nonisolated`, because `FormAction.perform`
  closures are not `@MainActor`-isolated (per the source's own comments citing
  `FormSpec.swift`). `AuthSettings`, `AuthSettingsUpdate`, `SigninApp`,
  `SigninAppCreate`, `SigninAppUpdate`, `FeatureFlag`, `FeatureFlagCreate`,
  `FeatureFlagUpdate`, `ServerBag`, `ServerBagCreate`, `ServerBagUpdate`,
  `StorageToken`, `StorageTokenCreated`, and `StorageTokenCreate` are all declared
  `Codable, Hashable, Sendable` value types, so they can cross actor boundaries
  (e.g. into a `FormAction.perform` closure) without a data race.

  `AuthSettingsTopic.entry` declares `leadsTo: .detail`; the sign-up options come
  from `SignupMode.allCases`, parsed with `SignupMode(rawValue:)`, with help text
  from `SignupMode.help` (declared in `EcosystemConfigModels.swift`).
  `AuthSettings.allowedProviders: [String]?` decodes from
  `AuthSettingsDataSource.get`'s response but `AuthSettingsTopic.detail`'s form
  specification never surfaces it, and `AuthSettingsUpdate` has no field for it.

  `SigninApp.leaf(in:)` implements leaf computation; the duplicate check compares
  against it case-insensitively; the `clientId` field validates against
  `Slug.pattern` with message `SigninAppsTopic.leafMessage`.

  The flags level's icon is `systemImage: "flag.fill"` when enabled or `"flag"`
  when disabled. `FeatureFlagsTopic.removalMessage` and
  `ServerBagsTopic.removalMessage` are the two distinct removal-message constants
  (**bags-removal-message-distinct-from-flags**). The wrapped JSON value type is
  `JSONValue` (`Support/JSONValue.swift`); its `.int`/`.number` cases are the two
  representations **bags-json-equality-int-number** reconciles;
  `ServerBagsTopic.parsedValue(_:)` discards `JSONValue.parse`'s specific
  `DecodingError`-derived message in favor of the fixed
  `ServerBagsTopic.invalidJSONMessage`; the detail save writes through
  `ServerBagUpdate.value`.

  `StorageTokensRail.child(path:ecosystemID:levelID:title:)` is the shared
  parameterized resolution operation; `StorageTokensRail.createSpec` implements the
  three-way catch and the reveal-once write via `MainActor.run`;
  `StorageTokensRail.aboutText(ecosystemID:)` returns `aboutWithoutEcosystem`/
  `aboutWithEcosystem`; the `name` field validates against `Slug.pattern` with
  `Slug.patternMessage`; `revealedSecrets`/`revealedOnScreen` are the rail's own
  `@MainActor`-isolated stored state, read and cleared by
  `expireRevealedSecret(unless:)`; the post-reveal notice text is
  `ApplicationsTopic.revealMessage`, declared in the sibling Applications module
  (see Design Decisions); date fields format through `HubDates.display`.

  The test suite (`EcosystemConfigTopicsTests.swift`) exercises every Apple topic
  against fakes with concrete assertions for each requirement above.
- **React / Web**: this is the other source platform. `feature-flags.ts`,
  `server-bags.ts`, `signin-apps.ts`, `storage-tokens.ts`, and `wire.ts` under
  `packages/web/packages/data/src/ecosystem-config/` (plus shared helpers in
  `http.ts` and `client-helpers.ts`) are plain `fetch`-based clients with no JSX.
  `signinAppsApi.create`'s conflict handling calls a shared `rethrowConflict`
  helper; `ecosystemFeatureFlagsApi.update`/`delete` embed `key` in the URL path via
  `enc()` (`encodeURIComponent`), as do the equivalent path segments in
  `server-bags.ts` and `signin-apps.ts`. `tokenPrincipalsApi.list`/`mint`/`revoke`
  accept a `TokenScope` (`ecosystemId`/`workspace`, serialized by `scopeQuery`)
  independently of `MintTokenPrincipalBody.ecosystemId`, a separate body field;
  `TokenPrincipalCreated` (the 201-only body carrying `token`) is a distinct type
  from `TokenPrincipal` (the list-row shape, carrying only `prefix`).
  `EcosystemServerBag.value`/`EcosystemServerBagCreate.value`/
  `EcosystemServerBagUpdate.value` are typed `unknown` in `server-bags.ts`. The UI
  panes and dialog-state modules that call these clients (`FeatureFlagsPane.tsx`,
  `bag-dialog-state.ts`, `flag-dialog-state.ts`, `SigninAppDetail.tsx`) are not
  among this recipe's given sources, but see Design Decisions for the
  validation-layering split observed there.
- **Compose**: model each Apple protocol as a Kotlin `interface` with `suspend
  fun`s (e.g. `interface FeatureFlagsDataSource { suspend fun list(ecosystemId:
  String): List<FeatureFlag> }`); represent the shared token rail's revealed-secrets
  store as a `MutableStateFlow<Map<String, String>>` so Compose recomposition
  observes the reveal-once transition; model the wrapped JSON value type with
  `kotlinx.serialization.json.JsonElement`, noting the same integral-`Double`-vs-`Long`
  equality pitfall **bags-json-equality-int-number** documents applies to
  `JsonPrimitive` unless normalized the same way.
- **WinUI 3**: model each data-source interface as a C# interface returning
  `Task<T>` (e.g. `Task<IReadOnlyList<FeatureFlag>> ListAsync(string
  ecosystemId)`) backed by `HttpClient` and `System.Text.Json` for
  (de)serialization, mirroring the `async`/`await` shape of Swift's `async throws`
  and TypeScript's `Promise`; back a level's item list with an
  `ObservableCollection<T>` (or a view-model implementing `INotifyPropertyChanged`)
  for a WinUI 3 `ListView`/`ItemsView`. For the shared token rail's reveal-once
  secret, keep the equivalent of `revealedSecrets` as a plain in-memory field on the
  view-model — deliberately never written to `Windows.Storage.ApplicationData` or
  any DPAPI-backed store — so the "shown once" contract this component enforces is
  preserved rather than accidentally persisted.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/Hub/Features/EcosystemConfig/` |
| web | `packages/web/packages/data/src/ecosystem-config/` |

## Design Decisions

**Decision**: the server-bags delete confirmation's removal message ("will be deleted. Anything reading it gets nothing — there is no default.") is declared independently rather than reusing the feature-flags delete confirmation's message ("will be removed. Anything reading it falls back to its default."), even though both are one-line "what deleting this costs" strings for a very similar delete-confirmation UI.
**Rationale**: the source's own comment states the reason directly: server bags have no defaults to fall back to, unlike feature flags — deleting one leaves readers with nothing at all. Borrowing the flags' message promised a fallback that does not exist, in the one dialog whose job is to say what deleting costs. Sharing the string would have made the confirmation dialog lie about what actually happens.
**Approved**: pending

**Decision**: the storage-tokens create form's save action uses a three-way catch (a conflict error → friendly message; any other shared error kind → rethrown as-is; anything else → a generic unexpected error) instead of the shared error-wrapping convention every other create/update/delete call in this component uses.
**Platform**: Swift implementation (the alternate client has no equivalent create-error taxonomy to diverge from).
**Rationale**: the conflict case needs its own friendly text rather than whatever detail the backend's conflict response carries, and the source chooses to discard a non-shared-error-kind failure's own message in favor of a generic one rather than risk surfacing raw transport detail from a mint request specifically. This is documented here as an observed, intentional divergence rather than corrected to match the shared error-wrapping convention, since changing it would alter the exact error text this component's tests assert.
**Approved**: pending

**Decision**: the storage-tokens detail sources its post-reveal notice text from a constant declared in a sibling Applications module (Applications' own token-reveal notice), rather than declaring its own copy.
**Platform**: Swift implementation — this is a cross-module source-file coupling specific to that codebase's module layout.
**Rationale**: the source's own comment states this directly — the reveal-once behavior exists specifically because that sibling constant's promise ("you won't be able to see it again") must actually hold; the same lifecycle and constant are documented as canonical in the sibling recipe `agentictoolkit://cookbook/adh/hub/security/authentication-client`, which this recipe treats as the complete reference for that shared behavior rather than re-deriving it here. The coupling means a future rename of that constant would need to be tracked across both modules with no compiler-enforced link beyond the direct reference.
**Approved**: pending

**Decision**: JSON-shape validation for a server bag's value lives inside the value-parsing step on the Swift implementation, combining transport-adjacent orchestration with domain validation in one type; on the web implementation, the equivalent validation is not in the given data client at all — it lives in a sibling `features/ecosystem-config` package's dialog-state module.
**Platform**: applies differently to each of the two reference implementations, by design.
**Rationale**: the two platforms split responsibilities differently: the Swift topic types are the single place that both talk to the data source and build the declarative form, so validation naturally lives there too; the web implementation keeps its data-client layer free of any dependency on UI-adjacent validation state, pushing that concern into the package that owns the dialog. Both are internally consistent with their own layering; this recipe documents the divergence rather than treating either as a gap.
**Approved**: pending

**Decision**: on the web implementation, origin-format validation for a sign-in app's `allowedReturnOrigins` (mirroring the Swift implementation's origin-validation/canonicalization steps) is not present in the given data client — it lives in a UI-pane file's own validation helpers, outside this component's given sources.
**Platform**: web implementation.
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to adh/hub/ecosystems/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | | Initial creation |
