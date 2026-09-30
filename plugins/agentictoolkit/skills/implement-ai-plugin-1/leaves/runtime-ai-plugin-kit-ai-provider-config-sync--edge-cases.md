<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-provider-config-sync--edge-cases · source: ai-plugin-runtime-ai-plugin-kit-ai-provider-config-sync.md -->

# AI Provider Config Sync

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-ai-provider-config-sync--edge-cases#<slug>`):

- `empty-configs-array` MUST — AIProviderConfigSync.init MUST NOT reject configs: []; the source has no non-empty check, and this is exactly the shape …
- `selectedconfigid-is-nil` MUST — MUST be accepted as the documented zero-config path (see selected-config-id-optional); this is not an error state.
- `selectedconfigid-does-not-match-any-id-in-configs` MUST — AIProviderConfigSync.init MUST NOT reject this combination; the type enforces no referential relationship between the …
- `empty-string-identity-or-model-fields` MUST (`name: ""`, `pluginIdentifier: ""`, `templateId: ""`, `model: ""`) — ResolvedProviderConfig.init MUST NOT reject any of these; the source performs no content validation on any String field.
- `empty-values-or-secrets-dictionaries` MUST — ResolvedProviderConfig.init MUST NOT reject values: [:] or secrets: [:]; both are plain [String: String] with no …
- `very-large-configs-array` MUST — AIProviderConfigSync.init MUST NOT reject any array length; the source declares no upper bound on the number of …
- `concurrent-access` MAY — applicable, and safe by construction for reads — AIProviderConfigSync and ResolvedProviderConfig are Sendable, so an …

## Edge Cases

- **Empty `configs` array**: `AIProviderConfigSync.init` MUST NOT reject `configs: []`; the source has no non-empty check, and this is exactly the shape `AIProviderConfigSyncTests.testDecodesMissingSelectionAsNil` decodes.
- **`selectedConfigId` is `nil`**: MUST be accepted as the documented zero-config path (see `selected-config-id-optional`); this is not an error state.
- **`selectedConfigId` does not match any `id` in `configs`**: `AIProviderConfigSync.init` MUST NOT reject this combination; the type enforces no referential relationship between the two fields. Downstream, `DaemonProviderResolver.selectedConfiguration` already tolerates exactly this case gracefully — `configurations(settings).first { $0.id == uuid }` returns `nil` when no entry matches, and `DaemonAIChat.complete` falls through to the zero-config CLI default — so a dangling selection is a defined, non-crashing outcome once the payload reaches that resolver, even though this file itself does not validate it.
- **Duplicate `id` values across `configs` entries**: See `configs-id-uniqueness-unenforced` — the type accepts duplicates with no error, and what happens once such a payload is persisted is undefined in source.
- **Empty string identity or model fields** (`name: ""`, `pluginIdentifier: ""`, `templateId: ""`, `model: ""`): `ResolvedProviderConfig.init` MUST NOT reject any of these; the source performs no content validation on any `String` field.
- **Empty `values` or `secrets` dictionaries**: `ResolvedProviderConfig.init` MUST NOT reject `values: [:]` or `secrets: [:]`; both are plain `[String: String]` with no minimum-count requirement.
- **The same field key present in both `values` and `secrets`**: the source enforces no disjointness between the two dictionaries; nothing in this file resolves which one a receiver should prefer if both contain the same key.
- **Very large `configs` array**: `AIProviderConfigSync.init` MUST NOT reject any array length; the source declares no upper bound on the number of configurations a sync payload may carry.
- **Concurrent access**: applicable, and safe by construction for reads — `AIProviderConfigSync` and `ResolvedProviderConfig` are `Sendable`, so an already-constructed, unshared copy MAY be read from multiple tasks concurrently with no synchronization. Because every stored property is `var` (see `mutable-stored-properties`), a single instance held in shared mutable storage (e.g. a `var` captured by multiple concurrent tasks) still needs the caller's own synchronization (an actor, a lock, or a serial queue) to avoid a data race on that shared variable — `Sendable` guarantees a value is safe to *transfer*, not that a shared mutable binding to it is automatically synchronized.
- **Error states from a dependency**: Not applicable — this file has no dependency (no network, database, or file-system call) of its own that could fail; whatever eventually sends or receives this payload over the app-daemon boundary is a different, currently-unimplemented component (see `sync-application-unimplemented`), not this file.
- **Offline or disconnected state**: Not applicable — `AIProviderConfigSync.swift` performs no network access itself; it only defines the shape of a payload some other, unimplemented transport would carry.
- **Cancellation and timeouts**: Not applicable — every operation in this file (construction, encoding, decoding, equality) is synchronous and non-`async`; there is nothing to cancel and no operation that can time out.
