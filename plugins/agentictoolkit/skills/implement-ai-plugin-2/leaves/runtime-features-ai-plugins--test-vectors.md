<!-- leaf: implement-ai-plugin-2/runtime-features-ai-plugins--test-vectors · source: ai-plugin-runtime-features-ai-plugins.md -->

# AI Plugin Runtime Features (AIPlugins)

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| aiplugins-001 | coordinator-startup-order | Construct `AIPluginsCoordinator(appName: "Test")` | `pluginManager.discoverPlugins()` runs before `AIProviderMigration.runIfNeeded` and `AIProviderDefaults.seedIfNeeded`, per the fixed call order in `AIPluginsCoordinator.init` |
| aiplugins-002 | chat-backend-is-ready | `configProvider.selectedPluginIdentifier == ""` | `await backend.isReady == false` |
| aiplugins-003 | chat-backend-is-ready | `configProvider.selectedPluginIdentifier == "com.x.plugin"` | `await backend.isReady == true` |
| aiplugins-004 | chat-backend-no-plugin | `configProvider.selectedPluginIdentifier == ""`, call `sendMessages([...])` | Returned stream throws `AIPluginChatBackend.AIPluginChatError.pluginNotAvailable`; zero text chunks yielded |
| aiplugins-005 | local-session-stream-mapping, local-session-turn-finish (traced to `LocalChatSessionTests.streamsAndFinishes`) | `send("hi")` with a fake `eventStreamFactory` yielding `.textDelta("Hel")`, `.textDelta("lo")`, `.end(stopReason: "end_turn")` | Events include `.responseStarted` before the first `.responseDelta`; concatenated delta text `== "Hello"`; a terminal `.responseFinished` fires; `.stateChanged(.ready)` follows |
| aiplugins-006 | local-session-send-busy-guard | Call `session.send("first")`, then `session.send("second")` before the first turn's `runTurn` completes | The second call produces no `.userMessage`/`.responseStarted` pair in `events()` — it is dropped |
| aiplugins-007 | local-session-no-plugin | `resolvePlugin` returns `nil`, then `send("hi")` | Events emit `.turnFailed(ChatError(message: "No AI provider is configured.", isRetryable: false))` then `.stateChanged(.ready)`; no `.responseStarted` |
| aiplugins-008 | config-store-seed, config-store-values-overlay (traced to `AIProviderConfigStoreTests.seedPrefills` / `overlay`) | `seed(config:template:fields:)` with a template whose `defaultValues == ["baseURL": "https://api.groq.com/openai/v1"]` and a secret `apiKey` field, then read `configValues` | `values["baseURL"] == "https://api.groq.com/openai/v1"`, `values["model"] == "m1"`, `(values["apiKey"] ?? "").isEmpty == true`; after `fieldSetting(apiKey).value = "sk-test"`, `configValues()["apiKey"] == "sk-test"` |
| aiplugins-009 | resolver-fails-closed-on-template (traced to `AIProviderResolverTests.returnsNilForUnknownTemplate`) | `config.templateId == "renamed-away"`, a template the descriptor no longer advertises | `AIProviderResolver.resolve(config, manager:) == nil` |
| aiplugins-010 | migration-inclusion-rule (traced to `AIProviderMigrationTests.skipsEmpty`) | One descriptor, `legacySelected == ""`, `oldValues` returns `["apiKey": ""]` | `plan.configurations.isEmpty == true`, `plan.selectedId == ""` |
| aiplugins-011 | migration-inclusion-rule, migration-field-write-rule (traced to `AIProviderMigrationTests.migratesKeylessConfigured`) | A descriptor with a non-secret `baseURL` field, `legacySelected == ""`, `oldValues` returns `baseURL == "http://localhost:1234"` (differs from the template default `""`) | `plan.configurations.count == 1`; `plan.fieldWrites` contains an entry with `fieldKey == "baseURL"` and `value == "http://localhost:1234"` |
| aiplugins-012 | defaults-only-when-empty (traced to `AIProviderDefaultsTests.skipsWhenNotEmpty`) | `UserSettings.aiProviderConfigurations` already holds one entry; call `seedIfNeeded` | The list is unchanged (still exactly the pre-existing entry); `aiDefaultConfigSeeded.value == true` |
| aiplugins-013 | mcp-tool-source-unknown-tool | `callTool(name: "fs__nonexistent", argumentsJSON: Data())` where no registered pair namespaces to that name | Returns `("Unknown tool: fs__nonexistent", true)` |
| aiplugins-014 | mcp-tool-source-namespacing | Registry returns one pair `(client.name == "fs", tool.name == "read")` with an encodable `inputSchema` | `toolDefinitions()` returns exactly one `ToolDefinition` named `"fs__read"` |
