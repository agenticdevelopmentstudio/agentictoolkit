<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-daemon-ai-chat--part-4 · source: ai-plugin-runtime-ai-plugin-kit-daemon-ai-chat.md -->

# DaemonAIChat — continued (part 4)

## Design Decisions

**Decision**: `complete` dispatches to `completeViaCLI` (a zero-config `claude -p` fallback) whenever no provider configuration is selected, rather than throwing a "not configured" error.
**Rationale**: the source's own doc comment states the CLI default "needs no API key, so it works before any provider is configured" — this lets a daemon feature call `complete` unconditionally, without special-casing the "user hasn't opened Settings yet" state.
**Approved**: pending

**Decision**: the local-inference guard is consulted twice — once against the configuration's STORED model before the plugin loads, and again against the EFFECTIVE (descriptor-default-resolved) model inside `completeViaPlugin`, immediately before the request is built.
**Rationale**: the stored model can be empty (meaning "use the plugin's own default"), which is only known once the plugin's descriptor has been loaded; a single early check against an empty string could pass a request whose real model is large enough to be refused, so the source adds a second checkpoint that re-verdicts the model that will actually run, per its own doc comment on `complete`.
**Approved**: pending

**Decision**: secret resolution scopes to the configuration's own resolved template's fields, not the plugin descriptor's full field union.
**Rationale**: the source's inline comment records that listing `descriptor.fields` (rather than the template's own fields) previously synthesized a phantom empty `apiKey` for a keyless template such as Ollama, which made `OpenAICompatiblePlugin` reject the request with "An API key is required" — breaking every daemon summarize/oversight call for that provider until the template-scoped fix.
**Approved**: pending

**Decision**: `LivePluginCache` retains a loaded `AIPlugin` instance and its owning `AIPluginManager` for the process's lifetime, rebuilding only when the given search-path set changes.
**Rationale**: the source's own comment documents this as an accepted tradeoff — a plugin installed after the daemon process started stays invisible until the daemon's next launch (which host installers perform anyway) — in exchange for never repeating discovery/`dlopen` work on the hot completion path.
**Approved**: pending

**Decision**: for a configuration with no stored model, whatever surfaces as "the model" in the AI-Log's ok-row column is the configuration's `pluginIdentifier`, not the descriptor-resolved default `completeViaPlugin` actually used.
**Rationale**: the source's own inline comment labels this an "accepted residual," noting that fixing it would require changing `complete`'s return type (to carry the resolved model back out alongside the reply text) — a larger change than the source's author judged worthwhile for a log-display detail.
**Approved**: pending
