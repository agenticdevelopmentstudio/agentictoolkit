<!-- leaf: implement-ai-plugin-2/runtime-ai-plugin-kit-secret-storing--edge-cases · source: ai-plugin-runtime-ai-plugin-kit-secret-storing.md -->

# SecretStoring

**Rules** (cite as `implement-ai-plugin-2/runtime-ai-plugin-kit-secret-storing--edge-cases#<slug>`):

- `empty-key` MUST — get, set, delete, and deleteLegacy MUST NOT reject it; KeychainHelper.makeQuery builds a query with kSecAttrAccount: …
- `empty-value` MUST — set MUST succeed and store the empty string as a legitimate value, and a subsequent get for the same key MUST return …
- `missing-key` MUST — get(forKey:) for a key never stored MUST return nil; delete(forKey:) and deleteLegacy(forKey:) for such a key MUST …
- `boundary-oversized-value` SHOULD — SecretStoring and KeychainSecretStore impose no maximum length on value before calling KeychainHelper.set; SHOULD the …
- `concurrent-access-deletelegacy-s-global-service-swap` MUST — MUST be serialized by the caller with any other KeychainHelper access (see deletelegacy-caller-serialization); the …

## Edge Cases

- **Empty `key` (`""`)**: `get`, `set`, `delete`, and `deleteLegacy` MUST NOT reject it; `KeychainHelper.makeQuery` builds a query with `kSecAttrAccount: ""`, treating it as an ordinary (if unusual) account name in the current service scope.
- **Empty `value` (`set(_: "", forKey:)`)**: `set` MUST succeed and store the empty string as a legitimate value, and a subsequent `get` for the same key MUST return `""`, not `nil` (see `secret-storing-007`); an empty stored value is distinct from an absent one.
- **Missing key**: `get(forKey:)` for a key never stored MUST return `nil`; `delete(forKey:)` and `deleteLegacy(forKey:)` for such a key MUST return `true` (see `delete-idempotent`, `deletelegacy-idempotent`).
- **Boundary — oversized `value`**: `SecretStoring` and `KeychainSecretStore` impose no maximum length on `value` before calling `KeychainHelper.set`; SHOULD the Keychain reject an oversized payload at `SecItemAdd`, `set` returns `false` through the same `status != errSecSuccess` path any other Keychain failure takes — no length validation happens in this file before that point.
- **Concurrent access — same key**: this is the open question in Behavioral Requirements (`same-key-concurrent-mutation`); concurrent `set`/`delete` calls targeting the *same* key have no documented ordering guarantee and can produce a spurious `false` result or a transient false-negative read.
- **Concurrent access — `deleteLegacy`'s global service swap**: MUST be serialized by the caller with any other `KeychainHelper` access (see `deletelegacy-caller-serialization`); the source documents this obligation but performs no internal locking to enforce it, so a caller that violates it races the shared `KeychainHelper.service` static — recorded as a design decision below, not as an unresolved gap, since the required ordering is stated explicitly by the source.
- **Error states — Keychain unavailable or returns a non-success status**: `KeychainHelper.get`/`.set` log the failing `OSStatus` via `KeychainHelper.logger` and return `nil`/`false`; `SecretStoring`'s `get`/`set`/`delete` propagate that `nil`/`false` verbatim with no distinct error type, retry, or additional detail — a caller cannot distinguish "no value was ever stored" from "the Keychain rejected this specific read/write."
- **Offline or disconnected state**: Not applicable — `SecretStoring.swift` and `KeychainHelper.swift` make no network call of any kind (neither imports a networking framework); the Keychain is local to the device, so there is no connectivity-loss case to handle.
