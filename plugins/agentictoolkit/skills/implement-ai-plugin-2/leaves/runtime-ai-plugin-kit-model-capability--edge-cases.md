<!-- leaf: implement-ai-plugin-2/runtime-ai-plugin-kit-model-capability--edge-cases · source: ai-plugin-runtime-ai-plugin-kit-model-capability.md -->

# ModelCapability

**Rules** (cite as `implement-ai-plugin-2/runtime-ai-plugin-kit-model-capability--edge-cases#<slug>`):

- `empty-capabilities-array` MUST — reports(_:in:) called with capabilities: [] MUST return false for every case — [].contains is false for any spelling …
- `bare-resolvedmodel-with-no-evidence` MUST — A ResolvedModel with no description, goodFor, capabilities, or tools set MUST have has(_:_:) return false for every …
- `concurrent-access` MUST — ModelCapability is Sendable; every static function is a pure function of its arguments with no shared mutable state, …
- `duplicate-redundant-spellings` MUST — capabilities: ["tools", "tool_use", "TOOLS"] MUST still yield reports(.tools, in:) == true — matching one entry is …
- `unrecognized-capability-string` MUST — capabilities: ["moonwalk"] MUST NOT match any case; reports MUST return false for all four cases, and has(.tools, ...) …
- `extratext-present-but-empty` MUST — extraText: "" MUST behave identically to extraText: nil for word-matching purposes: ModelUseFacet.facets joins the …

## Edge Cases

- **Empty `capabilities` array.** `reports(_:in:)` called with
  `capabilities: []` MUST return `false` for every case — `[].contains`
  is `false` for any spelling set, and no crash occurs. MUST.
- **Bare `ResolvedModel` with no evidence.** A `ResolvedModel` with no
  `description`, `goodFor`, `capabilities`, or `tools` set MUST have
  `has(_:_:)` return `false` for every case except when `extraText` alone
  supplies conversation evidence — traced to `conversationFromProse`'s
  `bare` fixture. MUST.
- **Boundary values: not applicable in the numeric sense.** The only
  bounded input is `ModelCapability` itself, a fixed four-case enum with
  no numeric range to bound. `capabilities: [String]` and `extraText:
  String?` are unbounded collections/strings with no length check
  anywhere in the source.
- **Concurrent access.** `ModelCapability` is `Sendable`; every static
  function is a pure function of its arguments with no shared mutable
  state, and `AIModelCatalog.ResolvedModel` is a `Sendable`, `Equatable`
  value type built from `let` properties. Concurrent calls from any
  isolation domain MUST be safe with no additional synchronization —
  this is safe by construction, not merely untested.
- **Error states: not applicable.** No function in `ModelCapability.swift`
  throws, returns an error type, or calls anything that can fail;
  `reports`, `has`, and `capabilities(of:)` are total functions over
  their arguments.
- **Offline/disconnected: not applicable.** `ModelCapability.swift`
  performs no network or file I/O; it operates only on in-memory
  `String`s and an already-resolved `AIModelCatalog.ResolvedModel` value.
- **Duplicate/redundant spellings.** `capabilities: ["tools", "tool_use",
  "TOOLS"]` MUST still yield `reports(.tools, in:) == true` — matching one
  entry is sufficient, and repeated matches change nothing observable.
  MUST.
- **Unrecognized capability string.** `capabilities: ["moonwalk"]` MUST
  NOT match any case; `reports` MUST return `false` for all four cases,
  and `has(.tools, ...)` still falls back to `info.tools` rather than
  treating the unknown string as evidence. MUST.
- **`extraText` present but empty.** `extraText: ""` MUST behave
  identically to `extraText: nil` for word-matching purposes:
  `ModelUseFacet.facets` joins the non-`nil` text pieces with a space,
  and an empty piece contributes no additional words to match against.
  MUST.
