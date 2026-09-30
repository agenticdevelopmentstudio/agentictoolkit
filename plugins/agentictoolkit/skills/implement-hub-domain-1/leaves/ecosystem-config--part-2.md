<!-- leaf: implement-hub-domain-1/ecosystem-config--part-2 · source: hub-domain-ecosystem-config.md -->

# Ecosystem Config — continued (part 2)

**Rules** (cite as `implement-hub-domain-1/ecosystem-config--part-2#<slug>`):

- `ecosystem-scoped-navigation` MUST
- `path-depth-dispatch` MUST
- `hub-error-wrapping` MUST
- `main-actor-isolation` MUST
- `nonisolated-form-callbacks` MUST
- `sendable-models` MUST
- `auth-detail-only-entry` MUST
- `auth-field-order` MUST
- `auth-signup-options` MUST
- `auth-signin-help-text` MUST
- `auth-save-sends-both-values` MUST
- `auth-save-fallback-values` MUST
- `auth-detail-id-format` MUST
- `auth-no-delete-action` MUST
- `signinapps-list-sort` MUST
- `signinapps-leaf-computation` MUST
- `signinapps-create-fields` MUST
- `signinapps-duplicate-leaf-check` MUST
- `signinapps-clientid-pattern` MUST
- `signinapps-create-conflict-message` MUST
- `signinapps-origin-validation` MUST
- `signinapps-origin-canonicalization-and-dedup` MUST
- `signinapps-start-url-placeholder` MUST
- `signinapps-detail-fields` MUST
- `signinapps-delete-confirmation` MUST
- `signinapps-unknown-app-empty` MUST
- `web-signinapps-slug-normalization` MUST
- `web-signinapps-conflict-message-parity` MUST

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

