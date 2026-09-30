<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-plugin--part-2 · source: ai-plugin-runtime-ai-plugin-kit-ai-plugin.md -->

# AIPlugin — continued (part 2)

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-ai-plugin--part-2#<slug>`):

- `decision` MAY — Instances are documented as cheap and MAY be constructed per request rather than pooled or reused. Rationale: This …

## Design Decisions

**Decision**: `buildRequest(_:)` signals a bad `AIChatContext` by throwing, while `buildValidationRequest(config:)` signals "cannot validate" by returning `nil` rather than throwing.
**Rationale**: A `buildRequest(_:)` failure is exceptional — the chat turn cannot proceed at all — while returning `nil` from `buildValidationRequest(config:)` is a normal, expected outcome for a plugin with no lightweight way to check credentials; an optional return avoids forcing every plugin to define and throw a "not supported" error for what is a routine case.
**Approved**: pending

**Decision**: Instances are documented as cheap and MAY be constructed per request rather than pooled or reused.
**Rationale**: This keeps whatever a plugin closes over isolated per call without requiring conforming types to implement reset logic, and combined with the `Sendable` requirement it lets the host construct a plugin from any concurrency domain per call. In practice, the current host (`AIPluginManager.loadPlugin(identifier:)`) caches one instance per identifier and reuses it across every request for that identifier rather than constructing fresh instances — a documented quirk that makes the `concurrent-invocation-safety` requirement above load-bearing in the actual running system, even though the protocol's own doc comment permits either approach.
**Approved**: pending

**Decision**: `describeError(status:body:)` shares one signature for both a failed chat request and a failed credential-validation request.
**Rationale**: The doc comment states this explicitly ("Used for both failed chat requests and credential validation"); both call sites only need a human-readable message derived from a status code and a response body, so a second parameter distinguishing the call site was not needed for that purpose.
**Approved**: pending

**Decision**: `AIPluginKit` is linked, not embedded, by each plugin bundle, so it resolves to the host's single loaded image at `dlopen` time.
**Rationale**: The doc comment states this is what lets the host cast a freshly loaded principal class to `AIPlugin`; embedding a second copy of the framework would give the plugin's `AIPlugin` type a distinct identity from the host's, and the cast in `AIPluginManager.loadPlugin(identifier:)` (`principalClass as? any AIPlugin.Type`) would fail. This is confirmed in `packages/apple/AIPlugins/project.yml`, where every plugin target (`ClaudeAPI`, `ClaudeLocal`, `Google`, `OpenAI`, `OpenAICompatible`) declares its `AgenticToolkit/AIPluginKit` dependency with `embed: false`.
**Approved**: pending
