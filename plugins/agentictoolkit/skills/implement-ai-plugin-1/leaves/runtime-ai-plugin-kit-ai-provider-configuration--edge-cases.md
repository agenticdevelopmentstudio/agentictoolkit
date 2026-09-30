<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-provider-configuration--edge-cases · source: ai-plugin-runtime-ai-plugin-kit-ai-provider-configuration.md -->

# AI Provider Configuration

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-ai-provider-configuration--edge-cases#<slug>`):

- `empty-name-pluginidentifier-or-templateid` MUST — MUST be accepted without error (see no-content-validation); an empty name displays as a blank label to whatever UI …
- `taken-is-empty` MUST — uniqueName(_:avoiding:) MUST return base unchanged (see unique-name-unchanged-when-free) — an empty Set<String> is a …
- `base-already-ends-in-a-numeric-suffix` MUST — uniqueName("Groq 2", avoiding: ["Groq 2"]) MUST return "Groq 2 2", because the source concatenates "\(base) \(suffix)" …
- `extremely-large-taken-sets` MUST — the suffix loop in uniqueName(_:avoiding:) has no iteration cap; for any finite Set<String> — the only kind …
- `concurrent-access` MUST — this type declares no shared mutable state — it is a Sendable struct, and each variable holding a copy is independent …
- `orphaned-pluginidentifier-templateid` MUST — a configuration whose plugin has since been uninstalled, or whose template id no longer resolves in that plugin's …

## Edge Cases

- **Empty `name`, `pluginIdentifier`, or `templateId`**: MUST be accepted without error (see `no-content-validation`); an empty `name` displays as a blank label to whatever UI renders it, but this type performs no rejection.
- **`taken` is empty**: `uniqueName(_:avoiding:)` MUST return `base` unchanged (see `unique-name-unchanged-when-free`) — an empty `Set<String>` is a valid, ordinary input, not a special case in the source.
- **`base` already ends in a numeric suffix**: `uniqueName("Groq 2", avoiding: ["Groq 2"])` MUST return `"Groq 2 2"`, because the source concatenates `"\(base) \(suffix)"` unconditionally with no check for whether `base` already looks like a suffixed name; this is a documented quirk of the naming scheme, not a bug the type guards against.
- **Extremely large `taken` sets**: the suffix loop in `uniqueName(_:avoiding:)` has no iteration cap; for any finite `Set<String>` — the only kind constructible by a caller — the loop MUST terminate at the first untaken `"\(base) \(suffix)"`. The source places no overflow guard on the `Int` suffix counter, but reaching `Int.max` iterations would require a caller to have first supplied that many already-taken names, which is not a realistic input for a list of a user's own configurations.
- **Concurrent access**: this type declares no shared mutable state — it is a `Sendable` `struct`, and each variable holding a copy is independent memory (see `value-semantics`); two threads or tasks each holding their own copy MUST NOT be able to race on this type's own storage. Concurrent mutation of a shared collection of configurations (e.g. an array in `UserSettings` read and written from two threads at once) is the concern of that collection's own synchronization, not of this type.
- **Error states from a dependency**: Not applicable — the type has no dependency (no network, database, or file-system call) that could fail; per `no-persistence`, it never touches a store.
- **Offline or disconnected state**: Not applicable — `AIProviderConfiguration.swift` performs no network access of its own.
- **Cancellation and timeouts**: Not applicable — every member is a synchronous, non-`async`, non-throwing computation; there is nothing to cancel and no operation that can time out.
- **Missing file or unreachable server**: Not applicable — this file opens no file and makes no server call.
- **Orphaned `pluginIdentifier`/`templateId`**: a configuration whose plugin has since been uninstalled, or whose template id no longer resolves in that plugin's descriptor, MUST still decode, compare, and hash normally; this type performs no liveness check against the current plugin registry (see `no-registry-validation` and Design Decisions).
