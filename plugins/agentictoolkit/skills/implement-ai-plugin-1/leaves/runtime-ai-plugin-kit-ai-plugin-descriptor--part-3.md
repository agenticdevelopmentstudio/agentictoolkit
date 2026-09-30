<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-plugin-descriptor--part-3 · source: ai-plugin-runtime-ai-plugin-kit-ai-plugin-descriptor.md -->

# AI Plugin Descriptor — continued (part 3)

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-ai-plugin-descriptor--part-3#<slug>`):

- `decision` MUST — AIPluginDescriptor, Field, ProviderTemplate, and ModelDetail rely entirely on the compiler-synthesized Codable …

## Design Decisions

**Decision**: `AIPluginDescriptor.currentSchemaVersion`'s doc comment states "Bundles whose `schemaVersion` differs are skipped at discovery," but `AIPluginManager.discoverPlugins()` actually accepts the range `2...currentSchemaVersion`, not only an exact match against `currentSchemaVersion`.
**Rationale**: accepting a range lets the host stay compatible with an older still-supported schema version (v2) while treating pre-descriptor v1 plugins (which ship no `descriptor.json` at all, so there is nothing to decode) as absent rather than as a decode failure. The doc comment's "differs" wording is imprecise relative to the actual range check, but the two files agree on the outcome that matters: v1 plugins and any `schemaVersion` outside `2...3` are both skipped.
**Approved**: pending

**Decision**: `AIPluginDescriptor`, `Field`, `ProviderTemplate`, and `ModelDetail` rely entirely on the compiler-synthesized `Codable` conformance rather than a custom `init(from:)`.
**Rationale**: this keeps the file free of hand-written decoding logic, but it means the Swift-side default parameter values on `models`, `fields`, `secretRequired`, `defaultValues`, etc. — convenient for programmatic construction and for `AIPluginManager.registerForTesting` — do not apply during JSON decoding; every non-Optional property's key MUST be present in `descriptor.json` or decoding throws (json-decoding-required-keys). A plugin author who assumed the Swift default meant `"fields": []` could be omitted from their JSON would see their plugin silently skipped by `AIPluginManager.readDescriptor(from:)`'s `try?`.
**Approved**: pending

**Decision**: `resolvedTemplates` synthesizes one implicit `ProviderTemplate` (id `"default"`) from the descriptor's own fields whenever `templates` is `nil` or empty, rather than requiring every plugin to declare at least one explicit template.
**Rationale**: per the type's own doc comment, this keeps pre-v3 ("v2") plugins — which predate the `templates` field — working as a single provider without requiring every existing `descriptor.json` to be rewritten. `resolvedProvider`/`resolvedLLM`/`resolvedConfigType`'s own fallbacks (to `displayName`, `""`, and `"API Key"`/`"Local"` respectively) exist for the same reason, so an implicit template still renders sensibly in the provider picker's Provider/LLM/Config Type columns.
**Approved**: pending
