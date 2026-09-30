<!-- leaf: implement-ai-plugin-2/runtime-ai-plugin-kit-provider-type-facet--edge-cases · source: ai-plugin-runtime-ai-plugin-kit-provider-type-facet.md -->

# Provider Type Facet

**Rules** (cite as `implement-ai-plugin-2/runtime-ai-plugin-kit-provider-type-facet--edge-cases#<slug>`):

- `empty-configtype-string` MUST — init(configType:) given "" MUST bucket to .custom, since the lowercased empty string satisfies none of the six matched …
- `multiple-rules-satisfied-at-once` MUST — A configType string satisfying more than one rule's substring test MUST resolve via the fixed evaluation order …
- `unrecognized-rawvalue` MUST — init?(rawValue:) given a string that is not one of the four case names MUST return nil rather than crash or default to …
- `malformed-json-during-codable-decode` MUST — Because Codable is synthesized for a String-RawRepresentable enum, JSONDecoder decoding a JSON string that is not …
- `concurrent-access` MUST — Because ProviderTypeFacet is a case-only Sendable enum with no stored mutable state, calling matches(type:selected:) or …

## Edge Cases

- **Empty `configType` string**: `init(configType:)` given `""` MUST bucket to `.custom`, since the lowercased empty string satisfies none of the six matched substrings (provider-type-facet-002).
- **Multiple rules satisfied at once (boundary of the matching rules)**: A `configType` string satisfying more than one rule's substring test MUST resolve via the fixed evaluation order subscription, then local, then apiKey, then custom; no input can reach a later rule once an earlier one has matched (provider-type-facet-003, provider-type-facet-008).
- **Unrecognized `rawValue`**: `init?(rawValue:)` given a string that is not one of the four case names MUST return `nil` rather than crash or default to a case (provider-type-facet-007); this is the compiler-provided `RawRepresentable` behavior, not custom logic in this file.
- **Malformed JSON during `Codable` decode**: Because `Codable` is synthesized for a `String`-`RawRepresentable` enum, `JSONDecoder` decoding a JSON string that is not `"subscription"`, `"apiKey"`, `"local"`, or `"custom"` MUST throw `DecodingError.dataCorrupted`, since the synthesized `init(from:)` calls `init?(rawValue:)` and throws when it returns `nil`.
- **Concurrent access**: Because `ProviderTypeFacet` is a case-only `Sendable` enum with no stored mutable state, calling `matches(type:selected:)` or `init(configType:)` concurrently from multiple threads or actors MUST be safe with no synchronization, since neither function reads or writes shared state.
- **Error states from a dependency**: Not applicable — this file has no dependency (no network, database, or file-system call) of its own to fail; `init(configType:)` is a pure string transform over a value already resolved by `AIPluginDescriptor.ProviderTemplate.resolvedConfigType`.
- **Offline or disconnected state**: Not applicable — this file performs no network access of its own.
- **Cancellation and timeouts**: Not applicable — every member is a synchronous, non-throwing function or computed property; there is no asynchronous or long-running operation to cancel or time out.
