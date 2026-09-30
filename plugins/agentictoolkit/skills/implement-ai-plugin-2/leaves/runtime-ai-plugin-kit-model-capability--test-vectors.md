<!-- leaf: implement-ai-plugin-2/runtime-ai-plugin-kit-model-capability--test-vectors · source: ai-plugin-runtime-ai-plugin-kit-model-capability.md -->

# ModelCapability

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| MC-001 | reported-spelling-vocabulary, reports-case-insensitive-match | `ModelCapability.reports(.tools, in: [spelling])` for each of `"tools"`, `"Tools"`, `"tool_use"`, `"function_calling"`, `"functionCalling"` | Returns `true` for every spelling — `ModelCapabilityTests.reportedSpellings` |
| MC-002 | reported-spelling-vocabulary | `ModelCapability.reports(.reasoning, in: ["thinking"])` | `true` — `ModelCapabilityTests.reportedSpellings` |
| MC-003 | reported-spelling-vocabulary | `ModelCapability.reports(.vision, in: ["multimodal"])` | `true` — `ModelCapabilityTests.reportedSpellings` |
| MC-004 | reports-false-without-match | `ModelCapability.reports(.vision, in: ["tools", "reasoning"])` | `false` — an unrelated reported capability is not evidence — `ModelCapabilityTests.reportedSpellings` |
| MC-005 | conversation-never-self-reported | `ModelCapability.reports(.conversation, in: ["chat"])` | `false` — `ModelCapabilityTests.reportedSpellings` |
| MC-006 | has-tools-fallback-to-curated-flag, capabilities-of-order | `let m = ResolvedModel(id: "m", capabilities: ["vision"], tools: true)`; `ModelCapability.has(.tools, m)`; `ModelCapability.capabilities(of: m)` | `has(.tools, m) == true`; `capabilities(of: m) == [.tools, .vision]` — `ModelCapabilityTests.curatedToolsFlag` |
| MC-007 | has-conversation-fallback-to-facets | `ModelCapability.has(.conversation, ResolvedModel(id: "m"))` (no `description`, `goodFor`, or `extraText`) | `false` — `ModelCapabilityTests.conversationFromProse` |
| MC-008 | has-conversation-fallback-to-facets, has-short-circuits-on-report | `ModelCapability.has(.conversation, ResolvedModel(id: "m"), extraText: "A chat assistant model")` | `true` — `ModelCapabilityTests.conversationFromProse` |
| MC-009 | capabilities-of-order | `ModelCapability.capabilities(of: ResolvedModel(id: "m"), extraText: "A chat assistant model")` | `[.conversation]` (no other case present) — `ModelCapabilityTests.conversationFromProse` |
| MC-010 | has-conversation-fallback-to-facets | `ModelCapability.has(.conversation, ResolvedModel(id: "m", description: "Built for conversation"))` | `true` — derived from `description` alone, no `extraText` needed — `ModelCapabilityTests.conversationFromProse` |
| MC-011 | has-reasoning-vision-never-inferred | `let prose = ResolvedModel(id: "m", description: "Exceptional reasoning over images and charts")`; `has(.reasoning, prose)`; `has(.vision, prose)` | Both `false` — prose is not a gateway assertion — `ModelCapabilityTests.hardCapabilitiesAreNotInferred` |
| MC-012 | title-labels, detail-tooltips | `ModelCapability.conversation.title`; `ModelCapability.conversation.detail` | `"Chat"`; `"Built for chat, assistants and personas"` — traced to the `title`/`detail` switch statements in `ModelCapability.swift` (no dedicated test in the given suite) |
| MC-013 | capability-cases | `ModelCapability.allCases`; `ModelCapability(rawValue: "tools")` | `allCases == [.tools, .reasoning, .vision, .conversation]`; `ModelCapability(rawValue: "tools") == .tools` — traced to the `enum ModelCapability: String, CaseIterable` declaration (no dedicated test in the given suite) |
| MC-014 | reports-resolved-model-overload | `ModelCapability.reports(.vision, ResolvedModel(id: "m", capabilities: ["multimodal"]))` | `true`, identical to `reports(.vision, in: ["multimodal"])` — traced to `reports(_:_:)` forwarding to `reports(_:in:)` (no dedicated test in the given suite) |
| MC-015 | pure-and-stateless | `ModelCapability.reports(.tools, in: ["tools"])` called twice in sequence, and again from two concurrent `Task`s in a `TaskGroup` | Every call returns `true` with no observable difference and no synchronization required — traced to `ModelCapability` and its static functions carrying no stored mutable state (no dedicated concurrency test in the given suite) |
