<!-- leaf: implement-foundation/core--logging · source: foundation-core.md -->

# Foundation Core

## Logging

`KeychainHelper` conforms to `Loggable`. Subsystem: `Bundle.main
.bundleIdentifier` (via `Loggable.subsystem`) — Category: `KeychainHelper`
(via `Loggable.category`, the conforming type's own name).

| Event | Level | Message shape |
|-------|-------|----------------|
| `SecItemAdd`/`SecItemUpdate` did not report `errSecSuccess` in `set(_:forKey:)` | error | interpolates the account key and the resulting `OSStatus` |
| `SecItemCopyMatching` reported a status other than `errSecSuccess` or `errSecItemNotFound` in `copyValue` | error | interpolates the account key and the resulting `OSStatus` |
| a secret was recovered from a legacy access-group scope or a retired service and re-stored under the current scope | info | interpolates the account key and the scope it was recovered from |

No log call in `KeychainHelper.swift` interpolates the secret value itself
(see `keychain-secret-value-not-logged` above). The other five files in
this recipe produce no log output at all; `Loggable` only provides the
factory `KeychainHelper` and other conforming types build their logger
from.
