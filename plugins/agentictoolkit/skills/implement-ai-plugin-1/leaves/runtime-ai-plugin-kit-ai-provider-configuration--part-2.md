<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-provider-configuration--part-2 · source: ai-plugin-runtime-ai-plugin-kit-ai-provider-configuration.md -->

# AI Provider Configuration — continued (part 2)

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-ai-provider-configuration--part-2#<slug>`):

- `decision` MAY — uniqueName(_:avoiding:) disambiguates by appending " 2", " 3", … to base, and the type's Equatable/Hashable conformance …

## Design Decisions

**Decision**: `AIProviderConfiguration` stores only identity (`id`, `name`, `pluginIdentifier`, `templateId`); resolved field values, secrets, and the selected model for that configuration live in separate stores keyed by `id.uuidString`, not on this type.
**Rationale**: per the type's own doc comment, this keeps "the ordered list ... a small plain-Codable array shared by the app and the daemon" — a `[AIProviderConfiguration]` can be persisted, diffed, and mirrored to the daemon's registry (`AIProviderConfigKeys.configurationsKey`) cheaply and without ever carrying secret material through that channel; secrets and values are instead addressed per-configuration via `AIProviderConfigKeys` and resolved on demand by `AIProviderConfigStore`, a sibling file.
**Approved**: pending

**Decision**: Neither `pluginIdentifier` nor `templateId` is validated against any plugin registry at construction, decode, or comparison time.
**Rationale**: `AIProviderConfigStore.clearStoredValues`'s own doc comment explicitly anticipates a configuration whose "template no longer resolves (plugin uninstalled or template renamed)" and still clears its stored values by id alone, so an orphaned `pluginIdentifier`/`templateId` is a known, caller-handled condition rather than a gap in this type; resolving those identifiers against the currently installed plugins is `AIPluginManager`'s and its descriptor's responsibility, not this type's.
**Approved**: pending

**Decision**: `uniqueName(_:avoiding:)` disambiguates by appending `" 2"`, `" 3"`, … to `base`, and the type's `Equatable`/`Hashable` conformance compares all four stored properties, including `id` — so two configurations with identical `name`, `pluginIdentifier`, and `templateId` but different `id` values are distinct, unequal configurations, not duplicates.
**Rationale**: `id` is the type's real identity (see `identifiable-conformance`); `name` is a caller-facing label a user MAY set to anything, including a value another configuration already uses. `uniqueName` exists only to make a freshly *proposed* default name friendlier, not to enforce name uniqueness as an invariant of the type itself.
**Approved**: pending
