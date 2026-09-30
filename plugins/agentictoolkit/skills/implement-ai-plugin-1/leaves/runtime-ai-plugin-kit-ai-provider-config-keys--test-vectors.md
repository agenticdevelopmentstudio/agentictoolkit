<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-provider-config-keys--test-vectors · source: ai-plugin-runtime-ai-plugin-kit-ai-provider-config-keys.md -->

# AI Provider Config Keys

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| ai-provider-config-keys-001 | field-key-format | `fieldKey(config: UUID("11111111-2222-3333-4444-555555555555")!, field: "apiKey")` | `"aiplugin.config.11111111-2222-3333-4444-555555555555.field.apiKey"` — `AIProviderConfigKeysTests.testFieldKeyFormat` |
| ai-provider-config-keys-002 | model-key-format | `modelKey(config: id)` (same `id` as above) | `"aiplugin.config.11111111-2222-3333-4444-555555555555.model"` — `AIProviderConfigKeysTests.testModelAndLedgerKeys` |
| ai-provider-config-keys-003 | secret-fields-key-format | `secretFieldsKey(config: id)` | `"aiplugin.config.11111111-2222-3333-4444-555555555555.secretfields"` — `AIProviderConfigKeysTests.testModelAndLedgerKeys` |
| ai-provider-config-keys-004 | fields-key-format | `fieldsKey(config: id)` | `"aiplugin.config.11111111-2222-3333-4444-555555555555.fields"` — `AIProviderConfigKeysTests.testModelAndLedgerKeys` |
| ai-provider-config-keys-005 | registry-keys-fixed | Read `selectedConfigIdKey`, `configurationsKey`, `enabledKey`, `legacyCleanedKey` | `"ai_selected_config_id"`, `"ai_configurations"`, `"ai_summaries_enabled"`, `"ai_legacy_cleaned"` respectively — `AIProviderConfigKeys.swift` |
| ai-provider-config-keys-006 | key-namespace-isolation | `fieldKey(config: idA, field: "apiKey")` vs. `fieldKey(config: idB, field: "apiKey")` for `idA != idB` | Two distinct strings, since `idA.uuidString != idB.uuidString` |
| ai-provider-config-keys-007 | fields-ledger-format | `DaemonAIChatTests.makeSettings` seeds `fieldsKey(config: id)` with `values.keys.joined(separator: "\n")`, then `DaemonAIChat.completeViaPlugin` reads it back via `fieldsLedger.split(separator: "\n")` | The recovered field-name set equals the original `values.keys` set — `DaemonAIChatTests.swift` and `DaemonAIChat.swift` |
| ai-provider-config-keys-008 | secret-fields-key-consumer (open question) | Grep `packages/apple/AgenticToolkit` for `secretFieldsKey` | Only `AIProviderConfigKeys.swift`'s declaration and `AIProviderConfigKeysTests.testModelAndLedgerKeys`'s format check appear; no production writer or reader exists |
| ai-provider-config-keys-009 | pure-computation, no-error-domain | Call `fieldKey(config: id, field: "apiKey")` twice in immediate succession | Both calls return the identical string; no error is thrown and no state changes between calls |
| ai-provider-config-keys-010 | concurrency-isolation | Call `AIProviderConfigKeys.modelKey(config:)` from several concurrent `Task`s with no `await` | The code compiles with no actor-isolation error, and every task observes the same result, because the type is `nonisolated` and holds no stored state |
| ai-provider-config-keys-011 | no-instantiation | Attempt `let x = AIProviderConfigKeys()` | Fails to compile: a case-less `enum` has no initializer |
| ai-provider-config-keys-012 | field-name-newline-safety (open question) | `fieldKey(config: id, field: "a\nb")`, whose value is later folded into a `fieldsKey` ledger and parsed with `split(separator: "\n")` | The ledger parses as two entries (`"a"` and `"b"`) instead of the intended single field key `"a\nb"`, corrupting the field lookup — demonstrates the unresolved gap; no test in the given suite exercises this because the source implements no guard against it |
| ai-provider-config-keys-013 | single-source-of-truth-usage (documented deviation) | Grep the codebase for the literal `"ai_summaries_enabled"` outside `AIProviderConfigKeys.swift` | `AIModelChatConfig.swift`'s `UserSettings.aiSummariesEnabled = UserSetting<Bool>("ai_summaries_enabled", default: false)` duplicates the literal independently rather than referencing `AIProviderConfigKeys.enabledKey` — the one known deviation from this SHOULD, documented in Design Decisions |
