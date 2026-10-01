---
id: d274abfa-3696-4fd0-b3e8-cff6fdffb825
title: Secret Storing
domain: agentictoolkit://cookbook/ai/plugins/secret-storing
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: An interface that indirects an AI-plugin host's credential storage
  away from its concrete backing store, with a secure-storage-backed
  production implementation and a one-time pre-pin legacy-service cleanup
  path.
platforms:
- swift
- macos
tags:
- ai-plugin
- secrets
- credential-storage
- protocol
depends-on: []
related:
- agentictoolkit://cookbook/ai/chat/daemon-ai-chat
- agentictoolkit://cookbook/ai/providers/provider-config-keys
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

# Secret Storing

## Overview

The secret store is an interface that indirects an AI-plugin host's
credential storage away from its concrete backing store, so, per its own
documented contract, tests can substitute an in-memory store and never touch
the real secure-storage system. It declares four operations — get, set,
delete, and delete-legacy — each keyed by an opaque, caller-supplied text
value; the interface deliberately says nothing about key-naming convention,
leaving that to the caller (in practice, a provider configuration's
field-key operation, for this framework's one production consumer, the
daemon's chat-completion path). The production implementation is a
stateless conformance that delegates get/set/delete verbatim to the
platform's secure-storage helper, plus a fifth capability, delete-legacy,
that removes an entry written by a pre-pin build under the secure-storage
helper's own default fallback service identifier ("com.agentictoolkit") by
briefly retargeting the helper's active service identifier and restoring it
afterward. A test-only implementation backs the same interface with a
lock-guarded in-memory dictionary so the daemon's chat-completion tests
never touch the real secure store.

## Behavioral Requirements

- **concurrent-share-safety**: The secret-store interface MUST require
  every conforming implementation to be safe to share across concurrent
  execution contexts, so a single store instance MAY be captured and
  invoked from any concurrency domain — the daemon's chat-completion
  operation captures its injected store inside asynchronous completion
  work.
- **get-contract**: get MUST return the value currently stored for key, and
  MUST return none when no value is stored for that key.
- **set-overwrites**: set MUST store value under key, overwriting — never
  appending to, merging with, or rejecting — any value already stored under
  that key.
- **return-value-optional**: set, delete, and delete-legacy MUST each allow
  their returned success value to be ignored by a caller without a warning
  or diagnostic.
- **delete-idempotent**: delete MUST return success both when it removes an
  existing value for key and when no value was stored for key; the absence
  of a value MUST NOT be reported as a failure, per the operation's own
  documented contract: "Idempotent — deleting an absent key is not an
  error."
- **key-value-opacity**: the secret-store interface MUST treat key and
  value as opaque caller-supplied strings, imposing no format, length, or
  character-set restriction of its own, per the documented contract: "The
  secret-storage abstraction is a separate concern from key naming — hosts
  bring their own key convention."
- **production-store-delegation**: the production implementation's get,
  set, and delete operations MUST delegate verbatim, in a single
  expression, to the secure-storage helper's corresponding get/set/delete
  operations, applying no additional transformation, validation, or caching
  of their own.
- **production-store-stateless**: the production implementation MUST hold
  no instance-stored property; every operation MUST read or mutate the
  secure-storage helper's process-wide shared state rather than any
  per-instance state, so every instance of the production implementation
  behaves identically to every other.
- **production-store-init**: the production implementation MUST expose a
  public, synchronous, non-failing, zero-argument way to construct an
  instance.
- **legacy-service-constant**: the production implementation's
  legacy-service identifier MUST equal the fixed literal
  "com.agentictoolkit", mirroring the secure-storage helper's own default
  fallback service identifier.
- **deletelegacy-targets-legacy-service**: delete-legacy MUST remove the
  entry stored under the legacy-service identifier for key, and MUST NOT
  remove or read any entry stored under the currently active service
  identifier.
- **deletelegacy-restores-pinned-service**: delete-legacy MUST restore the
  active service identifier to the value it held immediately before the
  call, before returning, regardless of whether the underlying delete found
  an entry.
- **deletelegacy-idempotent**: delete-legacy MUST return success when no
  entry exists under the legacy service for key, for the same reason
  delete-idempotent holds: it delegates to the same underlying delete
  operation, whose status check already treats "not found" as success.
- **deletelegacy-caller-serialization**: because delete-legacy retargets
  the shared, process-wide active-service identifier for the duration of
  the call, a caller MUST serialize every invocation of delete-legacy with
  any other concurrent access to the secure-storage helper — through this
  or any other secret-store instance — since neither the interface nor the
  production implementation performs any internal locking of its own; this
  obligation is stated directly by the operation's own documented contract:
  "Callers must serialize this with their other [secure-storage] access...
  so no concurrent access races the swap."
- **interface-over-concrete-usage**: a caller SHOULD depend on the abstract
  secret-store interface rather than the concrete production implementation,
  so a test double can be substituted without touching the real secure
  store — see Design Decisions for the rationale and the one production
  call site (the daemon's chat-completion operation) that follows it.
- **same-key-concurrent-mutation**: NEEDS REVIEW: Not implemented in
  source. When two concurrent calls target set for the same key (or a
  concurrent set/delete pair on the same key), the outcome is unspecified:
  the production implementation's underlying write path performs a plain
  delete followed by a fresh add with no lock or compare-and-swap, so a
  losing writer's add can fail — making that set call return failure for
  otherwise well-formed input — or a concurrent get on the same key can
  observe a transient false-negative between the internal delete and the
  re-add. Neither the interface nor the production implementation states an
  ordering guarantee for concurrent same-key access (contrast with
  delete-legacy, whose serialization requirement is documented explicitly).
  What is missing: a documented ordering rule (e.g. last-writer-wins with
  retry, or a required external per-key lock) for concurrent set/delete
  calls sharing a key. Evidence that would settle it: a production call
  site that mutates the same key from more than one concurrency domain, or
  an explicit statement of the intended guarantee from the type's
  maintainers.

## Appearance

Not applicable — this is a secure-storage-backed secret-storage interface
and its production implementation, not a visual component.

## States

Not applicable — this is a secure-storage-backed secret-storage interface
and its production implementation, not a visual component. Its only
stateful behavior is the deletelegacy-caller-serialization requirement
above, which is a concurrency contract, not a visual or lifecycle state.

## Accessibility

Not applicable — this is a secure-storage-backed secret-storage interface
and its production implementation, not a visual component.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| secret-storing-001 | concurrent-share-safety | Inject the production implementation as a chat-completion operation's default secret-store argument and capture it inside the daemon's asynchronous completion work | Compiles and runs cleanly with no concurrency-safety diagnostic |
| secret-storing-002 | get-contract | Call set with value "sk-secret-123" for key, then call get for the same key | Returns "sk-secret-123" |
| secret-storing-003 | get-contract | Call get for a key never stored | Returns none |
| secret-storing-004 | set-overwrites | Call set with "first" for key, then set with "second" for the same key, then call get for that key | Returns "second" |
| secret-storing-005 | return-value-optional | Call set as a bare statement with its returned success value unused | Succeeds with no "result unused" diagnostic |
| secret-storing-006 | delete-idempotent | Call delete for a key never stored | Returns success |
| secret-storing-007 | key-value-opacity | Call set with an empty string for key, then call get for the same key | Returns an empty string, not none — an empty string is a legitimate stored value distinct from "absent" |
| secret-storing-008 | production-store-delegation | Inspect the production implementation's get, set, and delete operations | Each is a single-expression call to the corresponding secure-storage-helper operation with no other statement |
| secret-storing-009 | production-store-stateless, production-store-init | Construct two separate instances of the production implementation and call get for the same key from each | Both instances return the identical result, since neither holds instance state |
| secret-storing-010 | legacy-service-constant | Read the production implementation's legacy-service identifier | Equals "com.agentictoolkit", matching the secure-storage helper's own default-fallback identifier |
| secret-storing-011 | deletelegacy-targets-legacy-service | Pin the active service identifier to "com.example.host"; store "legacy-value" for key while temporarily retargeting the active service identifier to the legacy-service identifier; restore the pin; store "current-value" for key under "com.example.host"; then call delete-legacy for key | The legacy-service entry for key is gone (a direct read under the legacy-service identifier returns none); a get for key under the pinned service still returns "current-value" |
| secret-storing-012 | deletelegacy-restores-pinned-service | Pin the active service identifier to "com.example.host"; call delete-legacy for key; read the active service identifier immediately after the call returns | Equals "com.example.host" — the value held immediately before the call |
| secret-storing-013 | deletelegacy-idempotent | Call delete-legacy for a key never stored under the legacy service | Returns success |
| secret-storing-014 | interface-over-concrete-usage | Inspect the chat-completion operation's parameter type for its injected secret store, and its tests' fixtures | Parameter type is the abstract secret-store interface, never the concrete production implementation; every test call site substitutes the in-memory test double |
| secret-storing-015 | same-key-concurrent-mutation (open question) | Issue set("A") and set("B") for the same key from two concurrent tasks with no external lock | Per the underlying store's internal delete-then-add write path, the losing task's add can fail, making that set call return failure for well-formed input — demonstrating the open question; no test in the given sources exercises this concurrent scenario |

## Edge Cases

- **Empty key ("")**: get, set, delete, and delete-legacy MUST NOT reject
  it; the production implementation's query construction treats it as an
  ordinary (if unusual) account identifier in the current service scope.
- **Empty value (set with "")**: set MUST succeed and store the empty
  string as a legitimate value, and a subsequent get for the same key MUST
  return an empty string, not none (see secret-storing-007); an empty
  stored value is distinct from an absent one.
- **Missing key**: get for a key never stored MUST return none; delete and
  delete-legacy for such a key MUST return success (see delete-idempotent,
  deletelegacy-idempotent).
- **Boundary — oversized value**: the interface and its production
  implementation impose no maximum length on value before delegating to the
  secure-storage helper; SHOULD the underlying secure store reject an
  oversized payload, set returns failure through the same not-successful
  path any other secure-storage failure takes — no length validation
  happens in this component before that point.
- **Concurrent access — same key**: this is the open question in
  Behavioral Requirements (same-key-concurrent-mutation); concurrent
  set/delete calls targeting the *same* key have no documented ordering
  guarantee and can produce a spurious failure result or a transient
  false-negative read.
- **Concurrent access — delete-legacy's global service swap**: MUST be
  serialized by the caller with any other secure-storage-helper access (see
  deletelegacy-caller-serialization); the source documents this obligation
  but performs no internal locking to enforce it, so a caller that violates
  it races the shared active-service identifier — recorded as a design
  decision below, not as an unresolved gap, since the required ordering is
  stated explicitly by the source.
- **Error states — secure store unavailable or returns a non-success
  status**: the secure-storage helper's get/set log the failing status and
  return none/failure; the interface's get/set/delete propagate that
  none/failure verbatim with no distinct error type, retry, or additional
  detail — a caller cannot distinguish "no value was ever stored" from "the
  secure store rejected this specific read/write."
- **Offline or disconnected state**: Not applicable — this component makes
  no network call of any kind; the secure store is local to the device, so
  there is no connectivity-loss case to handle.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| key | text | none (required) | Opaque per-secret identifier passed to get/set/delete/delete-legacy; naming convention is entirely the caller's, e.g. a provider configuration's field-key operation. |
| value | text | none (required, set only) | The secret to store under key; treated as opaque and never validated, transformed, or interpreted. |
| Active service identifier | text (mutable, process-wide) | the host application's own bundle identifier, or "com.agentictoolkit" if unavailable | The secure-storage scope every production-implementation call is implicitly scoped to; a host pins this once at startup outside this component. |
| Shared-storage access group | optional text (mutable, process-wide) | none | Optional shared-storage access group production-implementation calls are implicitly scoped to; referenced, not set, by this component. |
| Legacy service identifier | text (constant) | "com.agentictoolkit" | Fixed pre-pin fallback service delete-legacy retargets the active service identifier to for the duration of one call. |
| Injected secret store | abstract secret-store interface (injected dependency) | the production implementation | The secret-store implementation a caller such as the daemon's chat-completion operation injects; substituted with the in-memory test double in tests. |

## Deep Linking

Not applicable: this component defines no URL, route, or navigable
destination — it is a storage abstraction with no navigation surface of its
own.

## Localization

Not applicable: the source contains no user-facing string literal; the only
string literal it defines ("com.agentictoolkit", the legacy service
identifier) is an internal secure-storage service identifier, never text
displayed to a user.

## Accessibility Options

Not applicable: this component renders nothing and reads no accessibility
display setting (Reduce Motion, Increase Contrast, Differentiate Without
Color) — it has no UI of its own.

## Feature Flags

Not applicable: the source declares no feature-flag key and contains no
conditional feature-gating logic; every operation is always available to a
caller that holds a secret-store value.

## Analytics

Not applicable: the source contains no analytics or event-emission call of
any kind.

## Privacy

- **Data collected**: the secret store keeps exactly the caller-supplied
  value under key — in this framework's one production call path, an AI
  provider credential (e.g. an API key) addressed by a provider
  configuration's field-key operation. Neither the interface nor the
  production implementation inspects, parses, or interprets the content of
  value; it is handled as an opaque secret throughout.
- **Storage**: the production implementation stores value as a secure
  credential item via the platform's secure-storage helper, scoped to the
  active service identifier (and, when set, the shared-storage access
  group); the operating system's secure store provides the actual
  encryption-at-rest and access control — this component itself performs
  no additional encryption or obfuscation.
- **Transmission**: this component performs no network transmission of its
  own.
- **Retention**: a stored secret persists in the secure store until a
  caller explicitly calls delete or delete-legacy, or until it is removed
  outside this component (e.g. the platform's own credential-management
  interface, an OS reset); the source defines no time-to-live, expiry, or
  automatic revocation. The secret store performs no verification of
  caller authorization beyond what the OS-level secure store and any
  platform access-control entitlement already enforce, and detects no
  misuse of a stored secret — it raises no signal when a credential is used
  out of its intended context.

## Logging

Not applicable: this component makes no logging call of its own; failures
inside the operations it delegates to are logged by the secure-storage
helper's own get/set operations, a dependency of this component, not a call
this component makes itself.

## Platform Notes

- **SwiftUI**: not a dependency of this file — `SecretStoring.swift` imports only `Foundation`; a SwiftUI settings screen calls `get`/`set`/`delete` through an injected `any SecretStoring` the same as any other consumer, with no `@State`/`@Observable` wiring needed since these calls are one-shot, not observed.
- **AppKit / UIKit**: this is the source. The file is `packages/apple/AgenticToolkit/AIPluginKit/SecretStoring.swift`, part of the macOS-only `AIPluginKit` framework target (`project.yml` declares `platform: macOS`, no iOS target today), depending on `AgenticToolkitCore`'s `KeychainHelper` and `Loggable`. Apple-specific: `Security` framework Keychain calls (`SecItemAdd`, `SecItemCopyMatching`, `SecItemDelete`) wrapped by `KeychainHelper`, and `Bundle.main.bundleIdentifier` as the default service; neither AppKit nor UIKit is imported, so the type is equally usable from the headless daemon process, an AppKit host, or a UIKit host. Concretely, the interface is `public protocol SecretStoring: Sendable` declaring `get(forKey:) -> String?`, `set(_:forKey:) -> Bool`, `delete(forKey:) -> Bool`, and `deleteLegacy(forKey:) -> Bool` — the latter three each `@discardableResult`, which is the return-value-optional requirement above. `KeychainSecretStore` is the production conformance (a stateless `struct` with `public init() {}` and `static let legacyService = "com.agentictoolkit"`); `InMemorySecretStore` (`Tests/AIPluginKitTests/AIPluginKitTestSupport.swift`) is the lock-guarded in-memory test double referenced throughout this recipe. `deleteLegacy(forKey:)` captures `KeychainHelper.service` into a local `pinned` constant, swaps in `legacyService`, and restores `pinned` via `defer` regardless of the delete's outcome. The unspecified same-key-concurrent-mutation behavior traces to `KeychainHelper.set`'s implementation issuing a plain `delete(forKey:)` followed by `SecItemAdd`, whose query is built with `kSecAttrAccount` set to `key`; a losing concurrent writer's `SecItemAdd` call can return `errSecDuplicateItem`, which `KeychainSecretStore.set` (and hence `SecretStoring.set`) reports simply as `false`.
- **Compose**: model `SecretStoring` as a Kotlin `interface` (`fun get(key: String): String?`, `fun set(value: String, key: String): Boolean`, `fun delete(key: String): Boolean`, `fun deleteLegacy(key: String): Boolean`) backed by Android's Keystore-backed `EncryptedSharedPreferences` (Jetpack Security) in place of the macOS Keychain; Android has no single-item "service" concept to retarget the way `KeychainHelper.service` does, so a `deleteLegacy` port would instead open the pre-migration `SharedPreferences` file or Keystore alias directly rather than mutating a shared global.
- **React/Web**: model as an async interface, e.g. `interface SecretStoring { get(key: string): Promise<string | null>; set(value: string, key: string): Promise<boolean>; delete(key: string): Promise<boolean>; deleteLegacy(key: string): Promise<boolean>; }`, since the browser has no OS Keychain equivalent; back it with an Electron `safeStorage`/native-keychain bridge or a server-side secrets API, and expect every method to be `Promise`-based rather than the Swift original's synchronous calls.
- **WinUI 3**: the reason this recipe exists. Model `SecretStoring` as a C# interface — `string? Get(string key); bool Set(string value, string key); bool Delete(string key); bool DeleteLegacy(string key);` — backed by `Windows.Security.Credentials.PasswordVault`, the Windows App SDK's closest Keychain analog. `Set` MUST first remove any existing credential for the same resource/key (mirroring `KeychainHelper.set`'s internal delete-then-add) before calling `vault.Add(new PasswordCredential(resource, key, value))`; `Get` MUST wrap `vault.Retrieve(resource, key)` in a `try`/`catch`, because `PasswordVault.Retrieve` throws rather than returning `null` when the credential is absent; `Delete`/`DeleteLegacy` MUST similarly catch-and-succeed on a missing-credential exception to preserve the idempotent contract this recipe requires (`delete-idempotent`, `deletelegacy-idempotent`). `PasswordVault`'s `resource` string is the WinUI analog of `KeychainHelper.service`; a `DeleteLegacy` port that retargets a shared `resource` field for the duration of one call carries the same un-synchronized-global-swap caveat this recipe documents for `KeychainHelper.service` (`deletelegacy-caller-serialization`) — threading the legacy resource string explicitly through the call instead, rather than mutating shared state, avoids reproducing that caveat in C#. Because `SecretStoring` requires `Sendable` in Swift, a WinUI 3 `ISecretStoring` implementation SHOULD be safe to call concurrently from any `Task`, and MUST serialize any global-resource-swap the same way the Swift original requires of `DeleteLegacy`.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/AIPluginKit/SecretStoring.swift` |

## Design Decisions

**Decision**: `deleteLegacy(forKey:)` retargets the process-wide `KeychainHelper.service` static for the duration of the call rather than taking an explicit service parameter, then restores the prior value via `defer`; neither this method nor `SecretStoring` performs any locking around the swap. (Apple platform implementation.)
**Rationale**: `KeychainHelper.service` is the single global every `KeychainSecretStore` call is already scoped to, so reaching the pre-pin fallback service means temporarily repointing that one global rather than threading a service parameter through every `SecretStoring` method just for this one narrowly-scoped, rarely-invoked migration path. The source's own doc comment places the serialization burden entirely on the caller ("Callers must serialize this with their other Keychain access... stenographer runs it only inside its one-time, lock-serialized legacy cleanup"), trading compiler-enforced safety for a smaller API surface on a path that runs at most once per install.
**Approved**: pending

**Decision**: `KeychainHelper.set`'s implementation issues a `delete(forKey:)` before every `SecItemAdd`, making `KeychainSecretStore.set` a non-atomic two-step overwrite rather than a single atomic update. (Apple platform implementation.)
**Rationale**: this is the mechanism both `set-overwrites` and the open `same-key-concurrent-mutation` question depend on — a reader of `SecretStoring.set`'s one-line signature would not expect an implicit delete-then-add pair, and that pair is exactly what makes concurrent same-key writes racy. Recorded here as observed technical debt affecting behavioral correctness, per Source Fidelity, rather than corrected, since changing it would mean changing `KeychainHelper.swift`, a file outside this component's own contract.
**Approved**: pending

**Decision**: callers SHOULD depend on the abstract secret-store interface rather than the concrete production implementation (interface-over-concrete-usage).
**Rationale**: per the interface's own documented contract, the entire point of the indirection is "so tests can substitute an in-memory store and never touch the real login keychain." The daemon's chat-completion operation's default injected argument and the test-only in-memory implementation both depend on this indirection; a caller that instead hardcodes the concrete production implementation loses the ability to substitute a fake, and its tests would touch the real secure store. No deviation from this SHOULD is observed in the given sources.
**Approved**: pending

**Decision**: delete's documented contract describes a caller-side convention — "when the host clears a credential field it pushes an empty value, and the daemon deletes the entry rather than keeping a stale key" — that is not itself implemented or enforced by the interface, its production implementation, or any call site in the given sources; the daemon's chat-completion path only ever calls get, never set or delete. (Apple platform implementation.)
**Rationale**: the documented contract describes intended behavior of a host outside this repository (elsewhere referred to as the daemon's settings/config layer), not a contract this component's own code implements. Recorded here rather than turned into a formal requirement on the secret-store interface itself, since an interface method cannot enforce how its callers choose between setting an empty value and deleting.
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
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ai/plugins/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
