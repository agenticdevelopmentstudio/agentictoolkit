---
id: d274abfa-3696-4fd0-b3e8-cff6fdffb825
title: SecretStoring
domain: agentictoolkit://cookbook/ai-plugin-kit/secret-storing
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-23'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Sendable protocol indirection over the Keychain for AI-plugin credentials,
  with a KeychainHelper-backed production store and a one-time pre-pin legacy-service
  cleanup path.
platforms:
- swift
- macos
tags:
- ai-plugin
- keychain
- secrets
- credential-storage
- protocol
depends-on: []
related:
- agentictoolkit://cookbook/ai-plugin-kit/daemon-ai-chat
- agentictoolkit://cookbook/ai-plugin-kit/ai-provider-config-keys
references:
- packages/apple/AgenticToolkit/AIPluginKit/SecretStoring.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Core/KeychainHelper.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitCoreTests/KeychainHelperTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AIPluginKitTests/AIPluginKitTestSupport.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/AIPluginKit/DaemonAIChat.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AIPluginKitTests/DaemonAIChatTests.swift (agentictoolkit)
- packages/apple/AgenticToolkit/AIPluginKit/AIProviderConfigKeys.swift (agentictoolkit)
approved-by: ''
approved-date: ''
---

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

## Appearance

Not applicable — this is a Keychain-backed secret-storage protocol and its production implementation, not a visual component.

## States

Not applicable — this is a Keychain-backed secret-storage protocol and its production implementation, not a visual component. Its only stateful behavior is the `deletelegacy-caller-serialization` requirement above, which is a concurrency contract, not a visual or lifecycle state.

## Accessibility

Not applicable — this is a Keychain-backed secret-storage protocol and its production implementation, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| secret-storing-001 | protocol-sendable-conformance | Pass `KeychainSecretStore()` as `DaemonAIChat.complete`'s `secretStore: any SecretStoring = KeychainSecretStore()` default and capture it inside the daemon's async completion `Task` | Compiles cleanly under `SWIFT_STRICT_CONCURRENCY: complete` with no Sendable diagnostic — `DaemonAIChat.swift` |
| secret-storing-002 | get-contract | `KeychainSecretStore().set("sk-secret-123", forKey: key)` then `.get(forKey: key)` | Returns `"sk-secret-123"` — mirrors `KeychainHelperTests.setGetRoundTrip`, delegated verbatim by `KeychainSecretStore` |
| secret-storing-003 | get-contract | `.get(forKey: neverStoredKey)` | Returns `nil` — mirrors `KeychainHelperTests.getMissing` |
| secret-storing-004 | set-overwrites | `.set("first", forKey: key)` then `.set("second", forKey: key)`, then `.get(forKey: key)` | Returns `"second"` — mirrors `KeychainHelperTests.setOverwrites` |
| secret-storing-005 | set-delete-discardable-result | `store.set("x", forKey: key)` called as a bare statement with the result unused | Compiles with no "result unused" warning, because `set` is `@discardableResult` — `SecretStoring.swift` |
| secret-storing-006 | delete-idempotent | `.delete(forKey: neverStoredKey)` | Returns `true` — mirrors `KeychainHelperTests.deleteMissingReturnsTrue`, delegated verbatim by `KeychainSecretStore.delete` |
| secret-storing-007 | key-value-opacity | `.set("", forKey: key)` then `.get(forKey: key)` | Returns `""`, not `nil` — an empty string is a legitimate stored value distinct from "absent"; mirrors `KeychainHelperTests.emptyStringRoundTrip` |
| secret-storing-008 | keychain-secret-store-delegation | Read the bodies of `KeychainSecretStore.get`, `.set`, `.delete` | Each is a single-expression call to the corresponding `KeychainHelper` static function with no other statement — `SecretStoring.swift` |
| secret-storing-009 | keychain-secret-store-stateless, keychain-secret-store-init | Construct `KeychainSecretStore()` twice and call `.get(forKey:)` on the same key from each instance | Both instances return the identical result, since neither holds instance state — `SecretStoring.swift` |
| secret-storing-010 | legacy-service-constant | Read `KeychainSecretStore.legacyService` | Equals `"com.agentictoolkit"`, matching `KeychainHelper.service`'s own default-fallback literal — `SecretStoring.swift`, `KeychainHelper.swift` |
| secret-storing-011 | deletelegacy-targets-legacy-service | Pin `KeychainHelper.service = "com.example.host"`; store `"legacy-value"` for `key` while temporarily retargeting `KeychainHelper.service = KeychainSecretStore.legacyService`; restore the pin; store `"current-value"` for `key` under `"com.example.host"`; then call `KeychainSecretStore().deleteLegacy(forKey: key)` | The legacy-service entry for `key` is gone (a direct `KeychainHelper.get` under `legacyService` returns `nil`); `KeychainSecretStore().get(forKey: key)` under the pinned service still returns `"current-value"` |
| secret-storing-012 | deletelegacy-restores-pinned-service | Pin `KeychainHelper.service = "com.example.host"`; call `KeychainSecretStore().deleteLegacy(forKey: key)`; read `KeychainHelper.service` immediately after the call returns | Equals `"com.example.host"` — the value held immediately before the call, per the `defer { KeychainHelper.service = pinned }` in `SecretStoring.swift` |
| secret-storing-013 | deletelegacy-idempotent | `KeychainSecretStore().deleteLegacy(forKey: neverStoredUnderLegacyKey)` | Returns `true` |
| secret-storing-014 | protocol-over-concrete-usage | Read `DaemonAIChat.complete`/`completeViaPlugin`'s parameter type for `secretStore`, and `DaemonAIChatTests`'s fixtures | Parameter type is `any SecretStoring`, never the concrete `KeychainSecretStore`; every test call site substitutes `InMemorySecretStore()` — `DaemonAIChat.swift`; `DaemonAIChatTests.swift,...` |
| secret-storing-015 | same-key-concurrent-mutation (open question) | Issue `set("A", forKey: key)` and `set("B", forKey: key)` from two concurrent tasks with no external lock | Per `KeychainHelper.set`'s internal `delete` then `SecItemAdd`, the losing task's `SecItemAdd` can return `errSecDuplicateItem`, making that `set` call return `false` for well-formed input — demonstrating the open question; no test in the given sources exercises this concurrent scenario |

## Edge Cases

- **Empty `key` (`""`)**: `get`, `set`, `delete`, and `deleteLegacy` MUST NOT reject it; `KeychainHelper.makeQuery` builds a query with `kSecAttrAccount: ""`, treating it as an ordinary (if unusual) account name in the current service scope.
- **Empty `value` (`set(_: "", forKey:)`)**: `set` MUST succeed and store the empty string as a legitimate value, and a subsequent `get` for the same key MUST return `""`, not `nil` (see `secret-storing-007`); an empty stored value is distinct from an absent one.
- **Missing key**: `get(forKey:)` for a key never stored MUST return `nil`; `delete(forKey:)` and `deleteLegacy(forKey:)` for such a key MUST return `true` (see `delete-idempotent`, `deletelegacy-idempotent`).
- **Boundary — oversized `value`**: `SecretStoring` and `KeychainSecretStore` impose no maximum length on `value` before calling `KeychainHelper.set`; SHOULD the Keychain reject an oversized payload at `SecItemAdd`, `set` returns `false` through the same `status != errSecSuccess` path any other Keychain failure takes — no length validation happens in this file before that point.
- **Concurrent access — same key**: this is the open question in Behavioral Requirements (`same-key-concurrent-mutation`); concurrent `set`/`delete` calls targeting the *same* key have no documented ordering guarantee and can produce a spurious `false` result or a transient false-negative read.
- **Concurrent access — `deleteLegacy`'s global service swap**: MUST be serialized by the caller with any other `KeychainHelper` access (see `deletelegacy-caller-serialization`); the source documents this obligation but performs no internal locking to enforce it, so a caller that violates it races the shared `KeychainHelper.service` static — recorded as a design decision below, not as an unresolved gap, since the required ordering is stated explicitly by the source.
- **Error states — Keychain unavailable or returns a non-success status**: `KeychainHelper.get`/`.set` log the failing `OSStatus` via `KeychainHelper.logger` and return `nil`/`false`; `SecretStoring`'s `get`/`set`/`delete` propagate that `nil`/`false` verbatim with no distinct error type, retry, or additional detail — a caller cannot distinguish "no value was ever stored" from "the Keychain rejected this specific read/write."
- **Offline or disconnected state**: Not applicable — `SecretStoring.swift` and `KeychainHelper.swift` make no network call of any kind (neither imports a networking framework); the Keychain is local to the device, so there is no connectivity-loss case to handle.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `key` | `String` | none (required) | Opaque per-secret identifier passed to `get`/`set`/`delete`/`deleteLegacy`; naming convention is entirely the caller's, e.g. `AIProviderConfigKeys.fieldKey(config:field:)`. |
| `value` | `String` | none (required, `set` only) | The secret to store under `key`; treated as opaque and never validated, transformed, or interpreted. |
| `KeychainHelper.service` | `String` (mutable static, in `AgenticToolkitCore`) | `Bundle.main.bundleIdentifier ?? "com.agentictoolkit"` | Process-wide Keychain service every `KeychainSecretStore` call is implicitly scoped to; a host pins this once at startup outside this file. |
| `KeychainHelper.accessGroup` | `String?` (mutable static, in `AgenticToolkitCore`) | `nil` | Optional shared-Keychain access group `KeychainSecretStore` calls are implicitly scoped to via `KeychainHelper`; referenced, not set, by this file. |
| `KeychainSecretStore.legacyService` | `String` (static constant) | `"com.agentictoolkit"` | Fixed pre-pin fallback service `deleteLegacy(forKey:)` retargets `KeychainHelper.service` to for the duration of one call. |
| `secretStore` | `any SecretStoring` (injected dependency) | `KeychainSecretStore()` | The `SecretStoring` conformance a caller such as `DaemonAIChat.complete` injects; substituted with `InMemorySecretStore` in tests. |

## Deep Linking

Not applicable: `SecretStoring.swift` defines no URL, route, or navigable destination — it is a storage abstraction with no navigation surface of its own.

## Localization

Not applicable: the source contains no user-facing string literal; the only string literals it defines (`KeychainSecretStore.legacyService`'s `"com.agentictoolkit"`) are an internal Keychain service identifier, never text displayed to a user.

## Accessibility Options

Not applicable: `SecretStoring.swift` renders nothing and reads no accessibility display setting (Reduce Motion, Increase Contrast, Differentiate Without Color) — it has no UI of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no conditional feature-gating logic; every member is always available to a caller that holds a `SecretStoring` value.

## Analytics

Not applicable: the source contains no analytics or event-emission call of any kind.

## Privacy

- **Data collected**: `SecretStoring` stores exactly the caller-supplied `value` under `key` — in this framework's one production call path, an AI provider credential (e.g. an API key) addressed by `AIProviderConfigKeys.fieldKey(config:field:)`. Neither `SecretStoring` nor `KeychainSecretStore` inspects, parses, or interprets the content of `value`; it is handled as an opaque secret throughout.
- **Storage**: `KeychainSecretStore` stores `value` as a generic-password Keychain item via `KeychainHelper`, scoped to `KeychainHelper.service` (and, when set, `KeychainHelper.accessGroup`); the macOS Keychain provides the actual encryption-at-rest and access control — `SecretStoring.swift` itself performs no additional encryption or obfuscation.
- **Transmission**: `SecretStoring.swift` and `KeychainHelper.swift` perform no network transmission of their own; both import only `Foundation` (plus `Security`/`os` for `KeychainHelper`), with no networking framework in either file.
- **Retention**: a stored secret persists in the Keychain until a caller explicitly calls `delete(forKey:)` or `deleteLegacy(forKey:)`, or until it is removed outside this component (e.g. Keychain Access, an OS reset); the source defines no time-to-live, expiry, or automatic revocation. `SecretStoring` performs no verification of caller authorization beyond what the OS Keychain and any code-signing entitlement (`kSecAttrAccessGroup`) already enforce, and detects no misuse of a stored secret — it raises no signal when a credential is used out of its intended context.

## Logging

Not applicable: `SecretStoring.swift` makes no logging call of its own (no `Logger`, `os_log`, or `print`); failures inside the operations it delegates to are logged by `KeychainHelper.get`/`.set` via `KeychainHelper.logger` (`Loggable`), a dependency of this file, not a call this file makes itself.

## Platform Notes

- **SwiftUI**: not a dependency of this file — `SecretStoring.swift` imports only `Foundation`; a SwiftUI settings screen calls `get`/`set`/`delete` through an injected `any SecretStoring` the same as any other consumer, with no `@State`/`@Observable` wiring needed since these calls are one-shot, not observed.
- **AppKit / UIKit**: this is the source. The file is `packages/apple/AgenticToolkit/AIPluginKit/SecretStoring.swift`, part of the macOS-only `AIPluginKit` framework target (`project.yml` declares `platform: macOS`, no iOS target today), depending on `AgenticToolkitCore`'s `KeychainHelper` and `Loggable`. Apple-specific: `Security` framework Keychain calls (`SecItemAdd`, `SecItemCopyMatching`, `SecItemDelete`) wrapped by `KeychainHelper`, and `Bundle.main.bundleIdentifier` as the default service; neither AppKit nor UIKit is imported, so the type is equally usable from the headless daemon process, an AppKit host, or a UIKit host.
- **Compose**: model `SecretStoring` as a Kotlin `interface` (`fun get(key: String): String?`, `fun set(value: String, key: String): Boolean`, `fun delete(key: String): Boolean`, `fun deleteLegacy(key: String): Boolean`) backed by Android's Keystore-backed `EncryptedSharedPreferences` (Jetpack Security) in place of the macOS Keychain; Android has no single-item "service" concept to retarget the way `KeychainHelper.service` does, so a `deleteLegacy` port would instead open the pre-migration `SharedPreferences` file or Keystore alias directly rather than mutating a shared global.
- **React/Web**: model as an async interface, e.g. `interface SecretStoring { get(key: string): Promise<string | null>; set(value: string, key: string): Promise<boolean>; delete(key: string): Promise<boolean>; deleteLegacy(key: string): Promise<boolean>; }`, since the browser has no OS Keychain equivalent; back it with an Electron `safeStorage`/native-keychain bridge or a server-side secrets API, and expect every method to be `Promise`-based rather than the Swift original's synchronous calls.
- **WinUI 3**: the reason this recipe exists. Model `SecretStoring` as a C# interface — `string? Get(string key); bool Set(string value, string key); bool Delete(string key); bool DeleteLegacy(string key);` — backed by `Windows.Security.Credentials.PasswordVault`, the Windows App SDK's closest Keychain analog. `Set` MUST first remove any existing credential for the same resource/key (mirroring `KeychainHelper.set`'s internal delete-then-add) before calling `vault.Add(new PasswordCredential(resource, key, value))`; `Get` MUST wrap `vault.Retrieve(resource, key)` in a `try`/`catch`, because `PasswordVault.Retrieve` throws rather than returning `null` when the credential is absent; `Delete`/`DeleteLegacy` MUST similarly catch-and-succeed on a missing-credential exception to preserve the idempotent contract this recipe requires (`delete-idempotent`, `deletelegacy-idempotent`). `PasswordVault`'s `resource` string is the WinUI analog of `KeychainHelper.service`; a `DeleteLegacy` port that retargets a shared `resource` field for the duration of one call carries the same un-synchronized-global-swap caveat this recipe documents for `KeychainHelper.service` (`deletelegacy-caller-serialization`) — threading the legacy resource string explicitly through the call instead, rather than mutating shared state, avoids reproducing that caveat in C#. Because `SecretStoring` requires `Sendable` in Swift, a WinUI 3 `ISecretStoring` implementation SHOULD be safe to call concurrently from any `Task`, and MUST serialize any global-resource-swap the same way the Swift original requires of `DeleteLegacy`.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/AIPluginKit/SecretStoring.swift` |

## Design Decisions

**Decision**: `deleteLegacy(forKey:)` retargets the process-wide `KeychainHelper.service` static for the duration of the call rather than taking an explicit service parameter, then restores the prior value via `defer`; neither this method nor `SecretStoring` performs any locking around the swap.
**Rationale**: `KeychainHelper.service` is the single global every `KeychainSecretStore` call is already scoped to, so reaching the pre-pin fallback service means temporarily repointing that one global rather than threading a service parameter through every `SecretStoring` method just for this one narrowly-scoped, rarely-invoked migration path. The source's own doc comment places the serialization burden entirely on the caller ("Callers must serialize this with their other Keychain access... stenographer runs it only inside its one-time, lock-serialized legacy cleanup"), trading compiler-enforced safety for a smaller API surface on a path that runs at most once per install.
**Approved**: pending

**Decision**: `KeychainHelper.set`'s implementation issues a `delete(forKey:)` before every `SecItemAdd`, making `KeychainSecretStore.set` a non-atomic two-step overwrite rather than a single atomic update.
**Rationale**: this is the mechanism both `set-overwrites` and the open `same-key-concurrent-mutation` question depend on — a reader of `SecretStoring.set`'s one-line signature would not expect an implicit delete-then-add pair, and that pair is exactly what makes concurrent same-key writes racy. Recorded here as observed technical debt affecting behavioral correctness, per Source Fidelity, rather than corrected, since changing it would mean changing `KeychainHelper.swift`, a file outside this component's own contract.
**Approved**: pending

**Decision**: callers SHOULD depend on `any SecretStoring` rather than the concrete `KeychainSecretStore` (`protocol-over-concrete-usage`).
**Rationale**: per the protocol's own doc comment, the entire point of the indirection is "so tests can substitute an in-memory store and never touch the real login keychain." `DaemonAIChat.complete`'s `secretStore: any SecretStoring = KeychainSecretStore()` parameter and the test-only `InMemorySecretStore` (`Tests/AIPluginKitTests/AIPluginKitTestSupport.swift`) both depend on this indirection; a caller that instead hardcodes `KeychainSecretStore` loses the ability to substitute a fake, and its tests would touch the real login Keychain. No deviation from this SHOULD is observed in the given sources.
**Approved**: pending

**Decision**: `delete(forKey:)`'s doc comment describes a caller-side convention — "when the host clears a credential field it pushes an empty value, and the daemon deletes the entry rather than keeping a stale key" — that is not itself implemented or enforced by `SecretStoring`, `KeychainSecretStore`, or any call site in the given sources; `DaemonAIChat` only ever calls `get`, never `set` or `delete`.
**Rationale**: the doc comment describes intended behavior of a host outside this repository (elsewhere referred to as the daemon's settings/config layer), not a contract this file's own code implements. Recorded here rather than turned into a formal requirement on `SecretStoring` itself, since a protocol method cannot enforce how its callers choose between `set(_: "", forKey:)` and `delete(forKey:)`.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [secure-storage](agenticdevelopercookbook://compliance/security#secure-storage) | passed | Security |
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | Best Practices |
| [data-minimization](agenticdevelopercookbook://compliance/privacy-and-data#data-minimization) | passed | Privacy And Data |
| [idempotent-operations](agenticdevelopercookbook://compliance/reliability#idempotent-operations) | passed | Reliability |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | partial | Best Practices |

`secure-storage` passes because the production conformance stores every secret in the OS Keychain, scoped by service and optional access group, with no plaintext fallback. `separation-of-concerns` passes because `SecretStoring` cleanly separates "what backs this store" (Keychain vs. in-memory fake) from "what key format to use" (the caller's job, e.g. `AIProviderConfigKeys`). `data-minimization` passes because the type stores exactly the caller-given secret per caller-given key, with no additional copying, logging, or derived data. `idempotent-operations` passes because `delete` and `deleteLegacy` are both explicitly documented and implemented as idempotent (see `delete-idempotent`, `deletelegacy-idempotent`). `data-integrity` is partial because of the open question this recipe records: concurrent `set`/`delete` calls sharing a key have no documented ordering guarantee, so a well-formed write can spuriously fail (see `same-key-concurrent-mutation`). `explicit-error-handling` is partial because `set`/`delete`/`deleteLegacy` signal failure only via a `Bool`, discarding the underlying `OSStatus` reason, and because `deleteLegacy`'s required external serialization (`deletelegacy-caller-serialization`) is documented but not enforced by any type in the given sources.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
