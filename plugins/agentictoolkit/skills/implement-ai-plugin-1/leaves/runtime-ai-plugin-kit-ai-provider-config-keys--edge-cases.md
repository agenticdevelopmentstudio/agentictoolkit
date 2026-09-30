<!-- leaf: implement-ai-plugin-1/runtime-ai-plugin-kit-ai-provider-config-keys--edge-cases · source: ai-plugin-runtime-ai-plugin-kit-ai-provider-config-keys.md -->

# AI Provider Config Keys

**Rules** (cite as `implement-ai-plugin-1/runtime-ai-plugin-kit-ai-provider-config-keys--edge-cases#<slug>`):

- `empty-field-string` MUST — fieldKey(config:field:) MUST NOT reject field: ""; it returns "aiplugin.config.<id>.field." with a trailing separator …
- `whitespace-only-or-containing-field` MUST — fieldKey(config:field:) MUST NOT reject or alter such input; the string is interpolated verbatim (see …
- `two-different-configuration-ids-same-field` MUST — MUST produce two different keys for every one of fieldKey, modelKey, secretFieldsKey, and fieldsKey (see …
- `repeated-calls-with-identical-arguments` MUST — MUST return the identical string every time (see pure-computation); there is no cache to invalidate and no counter or …
- `concurrent-calls` MUST — applicable and safe by construction — AIProviderConfigKeys holds no stored or shared mutable state, so calls from the …

## Edge Cases

- **Empty `field` string**: `fieldKey(config:field:)` MUST NOT reject `field: ""`; it returns `"aiplugin.config.<id>.field."` with a trailing separator and no error, because the source performs no content check on `field`.
- **Whitespace-only or `.`-containing `field`**: `fieldKey(config:field:)` MUST NOT reject or alter such input; the string is interpolated verbatim (see `field-character-permissiveness`).
- **`field` containing `\n`**: See the open question in `field-name-newline-safety`. The key itself is still produced without error, but a caller that also maintains the `fieldsKey`/`secretFieldsKey` ledger for that configuration will corrupt the ledger's newline-delimited parsing.
- **Two different configuration ids, same `field`**: MUST produce two different keys for every one of `fieldKey`, `modelKey`, `secretFieldsKey`, and `fieldsKey` (see `key-namespace-isolation`); `UUID.uuidString` never coincides for two distinct `UUID` values, so no collision is possible.
- **Repeated calls with identical arguments**: MUST return the identical string every time (see `pure-computation`); there is no cache to invalidate and no counter or clock involved.
- **Concurrent calls**: applicable and safe by construction — `AIProviderConfigKeys` holds no stored or shared mutable state, so calls from the app's main actor and the daemon's own concurrency domain MUST NOT require any lock, queue hop, or `await` (see `concurrency-isolation`).
- **Boundary values on `id`**: none apply beyond what `UUID` itself enforces; every `UUID` value (including `UUID()`'s randomly generated form and a fixed literal like the test fixture's `11111111-2222-3333-4444-555555555555`) produces a well-formed 36-character `uuidString`, so there is no minimum/maximum or malformed-`id` case to handle — the type system rules it out before this code runs.
- **Error states from a dependency**: Not applicable — this file has no dependency (no network, database, or file-system call) that could fail; it never touches a store, only names one.
- **Offline or disconnected state**: Not applicable — `AIProviderConfigKeys.swift` performs no network access of its own; whether the daemon or app can currently be reached is a concern of whatever `ProviderSettingsReader`/`SecretStoring`/Keychain call site uses the returned key, not of this file.
- **Cancellation and timeouts**: Not applicable — every member is a synchronous, non-async, non-throwing computation; there is nothing to cancel and no operation that can time out.
- **Missing file or unreachable server**: Not applicable — this file opens no file and makes no server call; a missing settings row or an unreadable Keychain entry at the key this file returns is the caller's failure mode, not this file's.
