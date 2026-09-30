<!-- leaf: implement-hub-domain-1/ecosystem-config--part-3 · source: hub-domain-ecosystem-config.md -->

# Ecosystem Config — continued (part 3)

**Rules** (cite as `implement-hub-domain-1/ecosystem-config--part-3#<slug>`):

- `flags-no-cache-per-call` MUST
- `flags-list-sort-and-sublabel` MUST
- `flags-create-fields` MUST
- `flags-duplicate-key-check` MUST
- `flags-detail-fields` MUST
- `flags-delete-confirmation` MUST
- `flags-detail-id-format` MUST
- `web-flags-key-immutable-in-path` MUST
- `web-flags-no-client-duplicate-precheck` MUST
- `bags-list-preview` MUST
- `bags-create-fields` MUST
- `bags-json-parse-before-duplicate-check` MUST
- `bags-invalid-json-message-generic` MUST
- `bags-detail-full-replace-on-save` MUST
- `bags-removal-message-distinct-from-flags` MUST
- `bags-json-equality-int-number` MUST
- `web-bags-value-untyped-no-validation` MUST

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

