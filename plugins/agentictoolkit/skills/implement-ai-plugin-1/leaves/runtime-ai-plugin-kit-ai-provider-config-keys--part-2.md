<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-provider-config-keys--part-2 · source: ai-plugin-runtime-ai-plugin-kit-ai-provider-config-keys.md -->

# AI Provider Config Keys — continued (part 2)

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-ai-provider-config-keys--part-2#<slug>`):

- `compose` MUST — model as a Kotlin top-level object AIProviderConfigKeys — the direct analog of a case-less Swift enum used as a …

## Platform Notes

- **SwiftUI**: not applicable to this file — `AIProviderConfigKeys.swift` imports only `Foundation`, with no SwiftUI dependency; a SwiftUI-based settings screen calls the same static functions unchanged.
- **AppKit / UIKit**: this is the source. The file is `packages/apple/AgenticToolkit/AIPluginKit/AIProviderConfigKeys.swift`, part of the `AIPluginKit` framework target, which `project.yml` declares `platform: macOS` only (no iOS target exists for it today). It is consumed by the AppKit-facing, `@MainActor`-isolated `AIProviderConfigStore.swift` (`macOS/Features/AIPlugins/`) and by the daemon-side `DaemonProviderResolver`/`DaemonAIChat`, both plain Foundation with no AppKit import of their own.
- **Compose**: model as a Kotlin top-level `object AIProviderConfigKeys` — the direct analog of a case-less Swift `enum` used as a namespace — with functions taking a `java.util.UUID`. Note that `UUID.toString()` on the JVM returns *lowercase* hex, unlike Foundation's uppercase `uuidString`; an Android daemon and an Apple app sharing this key format over the same settings store MUST agree on one case (or do a case-insensitive lookup), or otherwise-identical configuration ids will produce non-matching keys.
- **React/Web**: model as a module of plain exported functions (e.g. `fieldKey(id: string, field: string): string`) over a UUID already serialized as a string, since JavaScript has no native `UUID` type. The same cross-platform case-sensitivity note applies: `crypto.randomUUID()` produces a lowercase string, so a web client sharing this key format with the Apple app/daemon needs the same case-normalization decision noted for Compose.
- **WinUI 3**: model `AIProviderConfigKeys` as a `static class` with `static string` methods and `const string` fields, e.g. `public static string FieldKey(Guid configId, string field) => $"aiplugin.config.{configId}.field.{field}";`, `public static string ModelKey(Guid configId) => $"aiplugin.config.{configId}.model";`, `public static string SecretFieldsKey(Guid configId) => $"aiplugin.config.{configId}.secretfields";`, `public static string FieldsKey(Guid configId) => $"aiplugin.config.{configId}.fields";`, and `public const string SelectedConfigIdKey = "ai_selected_config_id";` (plus `ConfigurationsKey`, `EnabledKey`, `LegacyCleanedKey` as further `const string` fields). Critically, `Guid.ToString()`'s default `"D"` format is *lowercase*, unlike Foundation's uppercase `UUID.uuidString` — call `configId.ToString("D").ToUpperInvariant()` (or normalize consistently on read) so a WinUI 3 client and an Apple app/daemon sharing one settings store produce byte-identical keys for the same configuration id. Persist the ledger values (`FieldsKey`/`SecretFieldsKey`) as a `\n`-joined `string` (e.g. `string.Join("\n", fieldNames)`) to match the Swift side's `split(separator: "\n")` parsing exactly, including the same unresolved risk if a field name itself contains `\n` (see `field-name-newline-safety`).

## Design Decisions

**Decision**: The same `fieldKey(config:field:)` string addresses both a plain (non-secret) settings entry and a Keychain-backed secret entry for the same field, distinguished only by the caller's own routing (`field.isSecret`, `UserSetting(isSecure:)`, `SecretStoring`), never by any structural difference in the key itself.
**Rationale**: per the file's own doc comment, the goal is that "a configuration id maps to the same key strings on both sides" of the app/daemon boundary; encoding a "secure" marker into the key string would create two parallel namespaces for what is otherwise one field, duplicating the distinction `AIPluginDescriptor.Field.isSecret` already drives at the call site (`AIProviderConfigStore.fieldSetting`, `DaemonAIChat.completeViaPlugin`).
**Approved**: pending

**Decision**: `enabledKey` and `legacyCleanedKey` are declared as fixed constants but have no call site anywhere in `packages/apple/AgenticToolkit` that reads or writes them by name; `enabledKey`'s literal value (`"ai_summaries_enabled"`) is independently duplicated as a hardcoded string in `AIModelChatConfig.swift`'s `UserSettings.aiSummariesEnabled`, rather than referencing `AIProviderConfigKeys.enabledKey`.
**Rationale**: this is recorded here as an observed fact rather than corrected, because routing `UserSettings.aiSummariesEnabled` through `AIProviderConfigKeys.enabledKey` would change `AIModelChatConfig.swift`, a file outside this component's own contract; nothing today ties the two literals together, so a future rename of either would silently break the pairing with no compiler error.
**Approved**: pending

**Decision**: `secretFieldsKey(config:)` and its newline-joined ledger shape are documented on the type but never populated or consulted anywhere in this repository.
**Rationale**: the doc comment attributes the ledger to daemon-side removal logic ("(Daemon-side.)"), which may live outside this repository; rather than assume that consumer exists and behaves correctly, or invent one, this is flagged as the open `secret-fields-key-consumer` question in Behavioral Requirements.
**Approved**: pending
