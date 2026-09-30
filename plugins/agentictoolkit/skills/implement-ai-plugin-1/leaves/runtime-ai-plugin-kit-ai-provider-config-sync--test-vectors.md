<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-provider-config-sync--test-vectors · source: ai-plugin-runtime-ai-plugin-kit-ai-provider-config-sync.md -->

# AI Provider Config Sync

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| ai-provider-config-sync-001 | codable-field-names, equatable-structural | Construct `AIProviderConfigSync(enabled: true, selectedConfigId: id, configs: [ResolvedProviderConfig(id: id, name: "Groq", pluginIdentifier: "com.x.openai-compatible", templateId: "custom", model: "llama-3.3-70b", values: ["baseURL": "https://api.groq.com/openai/v1"], secrets: ["apiKey": "sk-abc"])])`, encode with `JSONEncoder`, decode with `JSONDecoder` | Decoded value `== ` the original — `AIProviderConfigSyncTests.testRoundTrip` |
| ai-provider-config-sync-002 | selected-config-id-decodes-missing-as-nil | Decode `{"enabled":false,"configs":[]}` | `decoded.selectedConfigId == nil`, `decoded.enabled == false`, `decoded.configs.isEmpty == true` — `AIProviderConfigSyncTests.testDecodesMissingSelectionAsNil` |
| ai-provider-config-sync-003 | selected-config-id-omits-key-when-nil | Encode `AIProviderConfigSync(enabled: false, selectedConfigId: nil, configs: [])` with `JSONEncoder` | The resulting JSON object has no `selectedConfigId` key at all (not a `null` value) |
| ai-provider-config-sync-004 | configs-collection | Encode `AIProviderConfigSync(enabled: true, selectedConfigId: nil, configs: [])` | The resulting JSON's `configs` key is present as `[]` |
| ai-provider-config-sync-005 | empty-secret-clears-credential | Round-trip a `ResolvedProviderConfig` whose `secrets` is `["apiKey": ""]` through `JSONEncoder`/`JSONDecoder` | Decoded `secrets["apiKey"] == ""` — the empty string survives the wire unchanged (not stripped or converted to a missing key), preserving the "clear this credential" signal |
| ai-provider-config-sync-006 | equatable-structural | Two `ResolvedProviderConfig` values built with identical `id`, `name`, `pluginIdentifier`, `templateId`, `model`, `values`, `secrets`, versus a third differing only in `model` | The first two compare `==`; the third compares `!=` to either |
| ai-provider-config-sync-007 | equatable-structural | Two `AIProviderConfigSync` values with identical `enabled`/`selectedConfigId`/`configs`, versus a third differing only in `enabled` | The first two compare `==`; the third compares `!=` to either |
| ai-provider-config-sync-008 | codable-field-names | Encode `ResolvedProviderConfig(id: UUID("11111111-2222-3333-4444-555555555555")!, ...)` | The JSON `id` field is the string `"11111111-2222-3333-4444-555555555555"` (Foundation's canonical uppercase, hyphenated `uuidString` form) |
| ai-provider-config-sync-009 | sendable-conformance, concurrency-isolation | Capture a constructed `AIProviderConfigSync` value in a closure passed to a new `Task` with no `await` and no actor hop | Compiles with no `Sendable`-conformance diagnostic, because every stored property is itself `Sendable` |
