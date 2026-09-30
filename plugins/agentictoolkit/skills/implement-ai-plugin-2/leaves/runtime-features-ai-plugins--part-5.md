<!-- leaf: implement-ai-plugin-2/runtime-features-ai-plugins--part-5 · source: ai-plugin-runtime-features-ai-plugins.md -->

# AI Plugin Runtime Features (AIPlugins) — continued (part 5)

## Design Decisions

- **Decision**: `AIPluginChatBackend` and `LocalChatSession` are declared
  `@unchecked Sendable` rather than `actor`s or fully `@MainActor` types.
  **Rationale**: each type's own doc comment states the invariant that makes
  this safe — every mutable field is guarded by exactly one synchronization
  primitive (`NSLock` for `subscribers`/`history`/`continuation`, a
  `Synchronization.Mutex` for the busy flag), and any `@MainActor`-isolated
  dependency (`pluginManager`, `configProvider`) is read only inside a
  `MainActor.run` block — so the compiler's inability to verify isolation
  across an `async` boundary is a known limitation being worked around, not
  an unverified assumption.
  **Approved**: pending.
- **Decision**: `AIProviderResolver.resolve` returns `nil` rather than
  falling back to `descriptor.resolvedTemplates.first` when the
  configuration's `templateId` no longer resolves.
  **Rationale**: falling back would silently bind the configuration's
  already-stored credentials and model to whatever template happens to be
  first — an unrelated provider, base URL, and auth mode — and push that to
  the daemon as though nothing had changed. Failing closed surfaces the
  break instead of masking it.
  **Approved**: pending.
- **Decision**: `AIProviderConfigStore.configValues` always overlays a
  secret field's stored value (even when empty) but only overlays a
  non-secret field's stored value when it is non-empty.
  **Rationale**: an empty non-secret value would otherwise silently clobber
  a meaningful template default (e.g. a `baseURL`); a secret field has no
  default to clobber, and including it even when blank is what lets a
  plugin distinguish "this template requires a key and it is blank" from
  "this template has no secret field at all."
  **Approved**: pending.
- **Decision**: `AIProviderDefaults.seedIfNeeded` seeds a default
  `claude-local` configuration but leaves it unselected.
  **Rationale**: an empty `selectedAIProviderConfigurationId` and a selected
  `claude-local` configuration both resolve to the same effective behavior
  at the daemon (its own zero-config "Default (Claude CLI)" path), so
  leaving the selection empty avoids pushing a plugin id the daemon might
  not itself resolve, at no behavioral cost.
  **Approved**: pending.
- **Decision**: `AIProviderMigration.plan` carries forward a keyless
  descriptor whose only signal is a customized non-secret field
  (`hasCustomField`), not only descriptors with a secret or the legacy
  selection.
  **Rationale**: an OpenAI-compatible-style provider pointed at a local,
  keyless endpoint has no secret to detect and may never have been the
  legacy selection, but a customized `baseURL` is still evidence the user
  configured it; treating it as unconfigured would silently drop that
  setup during migration.
  **Approved**: pending.
- **Decision**: `LocalChatSession.maxToolIterations` is fixed at `8` with no
  configuration point and no explicit UI signal when the cap is reached.
  **Rationale**: bounds the worst-case latency and cost of a runaway
  tool-calling loop; the source gives no rationale for the specific value
  `8` beyond the constant itself, and a caller cannot distinguish "the model
  stopped on its own" from "the turn hit the iteration cap" from the emitted
  events alone.
  **Approved**: pending.
