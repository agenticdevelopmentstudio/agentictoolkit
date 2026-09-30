<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-chat-context--part-2 · source: ai-plugin-runtime-ai-plugin-kit-ai-chat-context.md -->

# AI Chat Context — continued (part 2)

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-ai-chat-context--part-2#<slug>`):

- `decision` SHOULD — AIPluginConfig stores configuration as a flat [String: String] dictionary with three convenience accessors (apiKey, …

## Platform Notes

- **SwiftUI**: not applicable to this file — `AIChatContext.swift` imports only `Foundation`, with no SwiftUI dependency; any SwiftUI-based host or plugin consumes these value types unchanged, since all four are `Sendable` and carry no UI state.
- **AppKit / UIKit**: this is the source. The file is `packages/apple/AgenticToolkit/AIPluginKit/AIChatContext.swift`, part of the `AIPluginKit` framework target, which `project.yml` declares as `platform: macOS` only (no iOS target exists for it today). The file is plain Foundation — `struct`/`enum` value types, `Sendable` conformance, no AppKit import — so nothing in it is macOS-specific beyond the target's current platform scope.
- **Compose**: a Kotlin port would model `AIChatMessage`, `AIToolSpec`, `AIPluginConfig`, and `AIChatContext` as immutable `data class`es with `val` properties; `AIChatMessage.Role` as a `kotlinx.serialization`-backed enum whose `@SerialName` values are `"tool_use"`/`"tool_result"` (matching the raw-value divergence from the case names); `parametersJSONSchema`/`toolArgumentsJSON` as `ByteArray`; `AIToolSpec`'s `Hashable` conformance is free on a Kotlin `data class` (structural `equals`/`hashCode`).
- **React/Web**: a TypeScript port would use `readonly`-field interfaces or types for all four shapes; `Role` as the string-literal union `'system' | 'user' | 'assistant' | 'tool_use' | 'tool_result'` (the union members already match the Swift raw values, unlike the Swift case names); `Data` fields as `Uint8Array` or pre-parsed `unknown`/`JSONSchema` values depending on whether the schema travels as raw bytes or parsed JSON on that platform; there is no built-in structural-equality operator, so porting `tool-spec-equality` requires a manual deep-equality helper (or a library) rather than a free `==`.
- **WinUI 3**: a .NET port would model the four types as `record`s so equality is free, mirroring Swift's synthesized `Hashable` on `AIToolSpec` — e.g. `public sealed record AIToolSpec(string Name, string Description, byte[] ParametersJsonSchema);`. `AIChatMessage.Role` would be a C# `enum` with `[EnumMember(Value = "tool_use")]`/`[EnumMember(Value = "tool_result")]` (or a custom `JsonConverter`) so JSON serialization preserves the same raw strings the Swift `rawValue`s produce. `AIChatContext` would be a `record` with C# default parameter values matching the Swift defaults exactly — `int MaxTokens = 4096` and `IReadOnlyList<AIToolSpec> Tools = Array.Empty<AIToolSpec>()` — and `AIPluginConfig` would wrap an `IReadOnlyDictionary<string, string>` with `ApiKey`/`BaseUrl`/`Model` properties reading the same three conventional keys via `TryGetValue`. `byte[]` plus `System.Text.Json.JsonSerializer`/`JsonDocument` replace Foundation's `Data`/`JSONSerialization` for the two JSON-carrying fields.

## Design Decisions

**Decision**: `AIPluginConfig` stores configuration as a flat `[String: String]` dictionary with three convenience accessors (`apiKey`, `baseURL`, `model`), rather than a strongly-typed struct with one property per plugin field.
**Rationale**: a plugin's settings schema (its `descriptor.json`, described in `AIPlugin.swift`'s doc comment) is host-resolved data, not compile-time-known fields — a stringly-typed bag is the only shape that can carry an arbitrary, plugin-declared field set without `AIPluginKit` knowing every plugin's schema in advance. Callers SHOULD use the literal keys `apiKey`, `baseURL`, and `model` for those conventional fields, since `AIPluginConfig` performs no key aliasing or normalization — a caller that stores an API key under a different key name will find `config.apiKey` returns `nil`.
**Approved**: pending

**Decision**: `AIChatContext.maxTokens` defaults to `4096` with no enforced minimum or maximum.
**Rationale**: the source treats `maxTokens` as an opaque budget number to forward to whichever provider the plugin targets; per the Edge Cases entry above, no validation exists anywhere in the current call chain (this file, `AIPlugin.buildRequest(_:)`, or any of the four current plugins), so `4096` is a convenience default rather than a validated floor.
**Approved**: pending
