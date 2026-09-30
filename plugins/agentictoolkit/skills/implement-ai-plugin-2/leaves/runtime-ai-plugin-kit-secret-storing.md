<!-- leaf: implement-ai-plugin-2/runtime-ai-plugin-kit-secret-storing · source: ai-plugin-runtime-ai-plugin-kit-secret-storing.md -->

**Rules** (cite as `implement-ai-plugin-2/runtime-ai-plugin-kit-secret-storing#<slug>`):

- `protocol-sendable-conformance` MUST
- `get-contract` MUST
- `set-overwrites` MUST
- `set-delete-discardable-result` MUST
- `delete-idempotent` MUST
- `key-value-opacity` MUST
- `keychain-secret-store-delegation` MUST
- `keychain-secret-store-stateless` MUST
- `keychain-secret-store-init` MUST
- `legacy-service-constant` MUST
- `deletelegacy-targets-legacy-service` MUST
- `deletelegacy-restores-pinned-service` MUST
- `deletelegacy-idempotent` MUST
- `deletelegacy-caller-serialization` MUST
- `protocol-over-concrete-usage` SHOULD

# SecretStoring

## Overview

`SecretStoring` (`packages/apple/AgenticToolkit/AIPluginKit/SecretStoring.swift`) is a `Sendable` Swift protocol that indirects an AI-plugin host's credential storage away from the Keychain, so, per its own doc comment, "tests can substitute an in-memory store and never touch the real login keychain." It declares four operations — `get(forKey:)`, `set(_:forKey:)`, `delete(forKey:)`, and `deleteLegacy(forKey:)` — each keyed by an opaque, caller-supplied `String`; the protocol deliberately says nothing about key-naming convention, leaving that to the caller (in practice, `AIProviderConfigKeys.fieldKey(config:field:)` for this framework's one production consumer, `DaemonAIChat.completeViaPlugin`). `KeychainSecretStore` is the production conformance: a stateless `struct` that delegates `get`/`set`/`delete` verbatim to `AgenticToolkitCore`'s `KeychainHelper`, plus a fifth capability, `deleteLegacy(forKey:)`, that removes an entry written by a pre-pin daemon build under `KeychainHelper`'s own default fallback service name (`"com.agentictoolkit"`) by briefly retargeting `KeychainHelper.service` and restoring it afterward. The test-only conformance, `InMemorySecretStore` (`Tests/AIPluginKitTests/AIPluginKitTestSupport.swift`), backs the same protocol with a lock-guarded in-memory dictionary so `DaemonAIChatTests` never touches the real Keychain.

## Behavioral Requirements

- **protocol-sendable-conformance**: `SecretStoring` MUST require every conforming type to be `Sendable` (`public protocol SecretStoring: Sendable`), so a single store instance MAY be captured and invoked from any concurrency domain — `DaemonAIChat.complete`'s `secretStore: any SecretStoring = KeychainSecretStore()` parameter is captured inside the daemon's async completion work under `SWIFT_STRICT_CONCURRENCY: complete`.
- **get-contract**: `get(forKey:)` MUST return the `String` currently stored for `key`, and MUST return `nil` when no value is stored for that key.
- **set-overwrites**: `set(_:forKey:)` MUST store `value` under `key`, overwriting — never appending to, merging with, or rejecting — any value already stored under that key.
- **set-delete-discardable-result**: `set(_:forKey:)`, `delete(forKey:)`, and `deleteLegacy(forKey:)` MUST each be declared `@discardableResult`, so a caller MAY ignore the returned success `Bool` without a compiler warning.
- **delete-idempotent**: `delete(forKey:)` MUST return `true` both when it removes an existing value for `key` and when no value was stored for `key`; the absence of a value MUST NOT be reported as a failure, per the doc comment "Idempotent — deleting an absent key is not an error."
- **key-value-opacity**: `SecretStoring` MUST treat `key` and `value` as opaque caller-supplied strings, imposing no format, length, or character-set restriction of its own, per the doc comment: "The secret-storage abstraction is a separate concern from key naming — hosts bring their own key convention."
- **keychain-secret-store-delegation**: `KeychainSecretStore.get`, `.set`, and `.delete` MUST delegate verbatim, in a single expression, to `KeychainHelper.get(forKey:)`, `KeychainHelper.set(_:forKey:)`, and `KeychainHelper.delete(forKey:)` respectively, applying no additional transformation, validation, or caching of their own.
- **keychain-secret-store-stateless**: `KeychainSecretStore` MUST hold no instance-stored property; every operation MUST read or mutate `KeychainHelper`'s process-wide static state rather than any per-instance state, so every `KeychainSecretStore()` value behaves identically to every other.
- **keychain-secret-store-init**: `KeychainSecretStore` MUST expose a public, synchronous, non-throwing, zero-argument initializer (`public init() {}`).
- **legacy-service-constant**: `KeychainSecretStore.legacyService` MUST equal the fixed literal `"com.agentictoolkit"`, mirroring `KeychainHelper.service`'s own default fallback (`Bundle.main.bundleIdentifier ?? "com.agentictoolkit"`).
- **deletelegacy-targets-legacy-service**: `deleteLegacy(forKey:)` MUST remove the entry stored under `KeychainSecretStore.legacyService` for `key`, and MUST NOT remove or read any entry stored under the currently pinned `KeychainHelper.service`.
- **deletelegacy-restores-pinned-service**: `deleteLegacy(forKey:)` MUST restore `KeychainHelper.service` to the value it held immediately before the call, before returning, regardless of whether the underlying delete found an entry — the source captures `pinned` before the swap and restores it via `defer`.
- **deletelegacy-idempotent**: `deleteLegacy(forKey:)` MUST return `true` when no entry exists under the legacy service for `key`, for the same reason `delete-idempotent` holds: it delegates to `KeychainHelper.delete`, whose status check already treats "not found" as success.
- **deletelegacy-caller-serialization**: because `deleteLegacy(forKey:)` retargets the shared, process-wide `KeychainHelper.service` static for the duration of the call, a caller MUST serialize every invocation of `deleteLegacy(forKey:)` with any other concurrent access to `KeychainHelper` — through this or any other `SecretStoring` instance — since neither `SecretStoring` nor `KeychainSecretStore` performs any internal locking of its own; the source's doc comment states this obligation directly: "Callers must serialize this with their other Keychain access... so no concurrent access races the swap."
- **protocol-over-concrete-usage**: a caller SHOULD depend on `any SecretStoring` rather than the concrete `KeychainSecretStore`, so a test double (`InMemorySecretStore`) can be substituted without touching the real login Keychain — see Design Decisions for the rationale and the one production call site (`DaemonAIChat.complete`) that follows it.
- **same-key-concurrent-mutation**: NEEDS REVIEW: Not implemented in source. When two concurrent calls target `set(_:forKey:)` for the same `key` (or a concurrent `set`/`delete` pair on the same key), the outcome is unspecified: `KeychainHelper.set` performs a plain `delete(forKey:)` followed by `SecItemAdd` with no lock or compare-and-swap, so a losing writer's `SecItemAdd` can return `errSecDuplicateItem` — making that `set` call return `false` for otherwise well-formed input — or a concurrent `get` on the same key can observe a transient false-negative between the internal delete and the re-add. Neither `SecretStoring.swift` nor `KeychainHelper.swift` states an ordering guarantee for concurrent same-key access (contrast with `deleteLegacy`, whose serialization requirement the doc comment does state explicitly). What is missing: a documented ordering rule (e.g. last-writer-wins with retry, or a required external per-key lock) for concurrent `set`/`delete` calls sharing a key. Evidence that would settle it: a production call site that mutates the same key from more than one concurrency domain, or an explicit statement of the intended guarantee from the type's maintainers.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `key` | `String` | none (required) | Opaque per-secret identifier passed to `get`/`set`/`delete`/`deleteLegacy`; naming convention is entirely the caller's, e.g. `AIProviderConfigKeys.fieldKey(config:field:)`. |
| `value` | `String` | none (required, `set` only) | The secret to store under `key`; treated as opaque and never validated, transformed, or interpreted. |
| `KeychainHelper.service` | `String` (mutable static, in `AgenticToolkitCore`) | `Bundle.main.bundleIdentifier ?? "com.agentictoolkit"` | Process-wide Keychain service every `KeychainSecretStore` call is implicitly scoped to; a host pins this once at startup outside this file. |
| `KeychainHelper.accessGroup` | `String?` (mutable static, in `AgenticToolkitCore`) | `nil` | Optional shared-Keychain access group `KeychainSecretStore` calls are implicitly scoped to via `KeychainHelper`; referenced, not set, by this file. |
| `KeychainSecretStore.legacyService` | `String` (static constant) | `"com.agentictoolkit"` | Fixed pre-pin fallback service `deleteLegacy(forKey:)` retargets `KeychainHelper.service` to for the duration of one call. |
| `secretStore` | `any SecretStoring` (injected dependency) | `KeychainSecretStore()` | The `SecretStoring` conformance a caller such as `DaemonAIChat.complete` injects; substituted with `InMemorySecretStore` in tests. |

## Privacy

- **Data collected**: `SecretStoring` stores exactly the caller-supplied `value` under `key` — in this framework's one production call path, an AI provider credential (e.g. an API key) addressed by `AIProviderConfigKeys.fieldKey(config:field:)`. Neither `SecretStoring` nor `KeychainSecretStore` inspects, parses, or interprets the content of `value`; it is handled as an opaque secret throughout.
- **Storage**: `KeychainSecretStore` stores `value` as a generic-password Keychain item via `KeychainHelper`, scoped to `KeychainHelper.service` (and, when set, `KeychainHelper.accessGroup`); the macOS Keychain provides the actual encryption-at-rest and access control — `SecretStoring.swift` itself performs no additional encryption or obfuscation.
- **Transmission**: `SecretStoring.swift` and `KeychainHelper.swift` perform no network transmission of their own; both import only `Foundation` (plus `Security`/`os` for `KeychainHelper`), with no networking framework in either file.
- **Retention**: a stored secret persists in the Keychain until a caller explicitly calls `delete(forKey:)` or `deleteLegacy(forKey:)`, or until it is removed outside this component (e.g. Keychain Access, an OS reset); the source defines no time-to-live, expiry, or automatic revocation. `SecretStoring` performs no verification of caller authorization beyond what the OS Keychain and any code-signing entitlement (`kSecAttrAccessGroup`) already enforce, and detects no misuse of a stored secret — it raises no signal when a credential is used out of its intended context.

