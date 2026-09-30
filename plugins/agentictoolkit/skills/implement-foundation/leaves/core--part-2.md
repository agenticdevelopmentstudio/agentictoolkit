<!-- leaf: implement-foundation/core--part-2 · source: foundation-core.md -->

# Foundation Core — continued (part 2)

**Rules** (cite as `implement-foundation/core--part-2#<slug>`):

- `codable-ignored-shape` MUST
- `codable-ignored-decode-yields-nil` MUST
- `codable-ignored-encode-noop` MUST
- `keyed-decoding-container-ignored-decode` MUST
- `keyed-encoding-container-ignored-encode` MUST
- `codable-ignored-round-trip-loses-value` MUST
- `codable-ignored-concurrency` MUST
- `keychain-service-default` MUST
- `keychain-access-group-default` MUST
- `keychain-legacy-services-default` MUST
- `keychain-query-shape` MUST
- `keychain-query-access-group-forces-data-protection` MUST
- `keychain-set-overwrites` MUST
- `keychain-set-access-group-accessibility` MUST
- `keychain-set-returns-status` MUST
- `keychain-get-primary-lookup` MUST
- `keychain-get-access-group-migration` MUST
- `keychain-get-legacy-service-migration` MUST
- `keychain-get-exhausted-returns-nil` MUST
- `keychain-legacy-item-not-deleted` MUST
- `keychain-copy-value-single-match` MUST
- `keychain-copy-value-logs-unexpected-errors-only` MUST
- `keychain-delete-idempotent` MUST
- `keychain-exists-checks-current-scope` MUST
- `keychain-exists-checks-legacy-scopes` MUST
- `keychain-exists-does-not-migrate` MUST
- `keychain-global-state-not-isolated` MUST
- `keychain-secret-storage-mechanism` MUST
- `keychain-secret-value-not-logged` MUST
- `keychain-secret-no-transmission` MUST
- `keychain-secret-lifetime-caller-controlled` MUST
- `loggable-requirement` MUST
- `loggable-default-subsystem` MUST
- `loggable-default-category` MUST
- `loggable-instance-forwarding` MUST
- `loggable-factory` MUST
- `cgfloat-clamped-shape` MUST
- `cgfloat-clamped-degenerate-range` MUST
- `cgfloat-clamped-pure` MUST

## Behavioral Requirements

### CodableIgnored

- **codable-ignored-shape**: `CodableIgnored<T>` MUST be declared as
  `@propertyWrapper public struct CodableIgnored<T>` with a single mutable
  `public var wrappedValue: T?`, and MUST provide `public init(wrappedValue:
  T?)`.
- **codable-ignored-decode-yields-nil**: `CodableIgnored<T>`'s
  `Decodable` conformance MUST initialize `wrappedValue` to `nil`
  unconditionally, regardless of whether the corresponding key is present or
  absent in the decoded input.
- **codable-ignored-encode-noop**: `CodableIgnored<T>`'s `Encodable`
  conformance's `encode(to:)` MUST be a no-op — it MUST NOT write anything
  to the given encoder.
- **keyed-decoding-container-ignored-decode**: the
  `KeyedDecodingContainer` extension's `decode(_:forKey:)` overload
  specialized for `CodableIgnored<T>` MUST return `CodableIgnored(wrappedValue:
  nil)` without attempting to read the container at `key` at all.
- **keyed-encoding-container-ignored-encode**: the
  `KeyedEncodingContainer` extension's `encode(_:forKey:)` overload
  specialized for `CodableIgnored<T>` MUST return without calling
  `encodeNil`, `encode`, or any other container-mutating method — the key
  MUST NOT appear in the encoded output at all.
- **codable-ignored-round-trip-loses-value**: encoding a model whose
  `@CodableIgnored` property holds a non-nil value and then decoding the
  result back MUST yield `wrappedValue == nil` on the decoded copy — the
  original value MUST NOT survive an encode/decode round trip.
- **codable-ignored-concurrency**: `CodableIgnored<T>` MUST NOT declare
  `Sendable` conformance; its `wrappedValue` is a mutable `var`, so a caller
  sharing one instance across concurrency domains MUST supply its own
  synchronization.

### KeychainHelper

- **keychain-service-default**: `KeychainHelper.service` MUST default to
  `Bundle.main.bundleIdentifier ?? "com.agentictoolkit"` and MUST be
  reassignable by a caller at any time (`nonisolated(unsafe) public static
  var service`).
- **keychain-access-group-default**: `KeychainHelper.accessGroup` MUST
  default to `nil` (`nonisolated(unsafe) public static var accessGroup:
  String?`).
- **keychain-legacy-services-default**: `KeychainHelper.legacyServices`
  MUST default to `[]` (`nonisolated(unsafe) public static var
  legacyServices: [String]`), ordered newest-retired-first.
- **keychain-query-shape**: `makeQuery(account:accessGroup:)` MUST return a
  dictionary with `kSecClass == kSecClassGenericPassword`, `kSecAttrService
  == KeychainHelper.service`, and `kSecAttrAccount == account`.
- **keychain-query-access-group-forces-data-protection**: when
  `makeQuery(account:accessGroup:)` is called with a non-nil `accessGroup`,
  the returned dictionary MUST additionally include `kSecAttrAccessGroup ==
  accessGroup` and `kSecUseDataProtectionKeychain == true`; when
  `accessGroup` is `nil`, neither key MUST be present.
- **keychain-set-overwrites**: `set(_:forKey:)` calling `SecItemAdd` and
  receiving `errSecDuplicateItem` MUST fall back to `SecItemUpdate` for the
  same query, so a second `set` call for the same key MUST overwrite the
  first value rather than fail.
- **keychain-set-access-group-accessibility**: when `KeychainHelper
  .accessGroup` is non-nil at the time `set(_:forKey:)` runs, the item's
  `kSecAttrAccessible` attribute MUST be set to
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- **keychain-set-returns-status**: `set(_:forKey:)` MUST return `true` only
  when the underlying `SecItemAdd`/`SecItemUpdate` call reports
  `errSecSuccess`, and MUST return `false` for any other status.
- **keychain-get-primary-lookup**: `get(forKey:)` MUST first query under the
  current `service`/`accessGroup` scope and MUST return the stored string
  directly when that query succeeds.
- **keychain-get-access-group-migration**: when the primary lookup fails
  and `KeychainHelper.accessGroup` is non-nil, `get(forKey:)` MUST retry the
  query with `accessGroup: nil`; on success it MUST re-store the recovered
  value under the current `service`/`accessGroup` scope via `set(_:forKey:)`
  before returning it.
- **keychain-get-legacy-service-migration**: when the access-group retry
  also fails (or does not apply), `get(forKey:)` MUST iterate
  `KeychainHelper.legacyServices` in order and, for the first retired
  service under which the key is found, MUST re-store the recovered value
  under the current `service` before returning it.
- **keychain-get-exhausted-returns-nil**: when the primary lookup, the
  access-group retry, and every entry in `legacyServices` all fail to
  locate the key, `get(forKey:)` MUST return `nil`.
- **keychain-legacy-item-not-deleted**: when `get(forKey:)` recovers a
  value from a legacy access-group scope or a retired service, it MUST NOT
  delete the original item under that legacy scope — only a new copy is
  written under the current scope.
- **keychain-copy-value-single-match**: `copyValue(query:)` MUST set
  `kSecMatchLimit` to `kSecMatchLimitOne` and `kSecReturnData` to `true`, and
  MUST decode the returned `Data` as UTF-8 into the `String` it returns.
- **keychain-copy-value-logs-unexpected-errors-only**: `copyValue(query:)`
  MUST log an error via `Loggable`'s logger when `SecItemCopyMatching`
  returns a status other than `errSecSuccess` and other than
  `errSecItemNotFound`; it MUST NOT log anything when the status is
  `errSecItemNotFound`.
- **keychain-delete-idempotent**: `delete(forKey:)` MUST return `true` when
  the underlying `SecItemDelete` reports `errSecSuccess` or
  `errSecItemNotFound`, and MUST return `false` for any other status —
  deleting an already-absent key is therefore never an error.
- **keychain-exists-checks-current-scope**: `exists(forKey:)` MUST return
  `true` when a query under the current `service`/`accessGroup` scope
  locates the key.
- **keychain-exists-checks-legacy-scopes**: when the current-scope check
  fails, `exists(forKey:)` MUST check `KeychainHelper.legacyServices` in
  order and MUST return `true` if any retired service holds the key.
- **keychain-exists-does-not-migrate**: unlike `get(forKey:)`,
  `exists(forKey:)` MUST NOT call `set(_:forKey:)` when it locates a key
  under a legacy scope — it only reports presence, it never re-stores.
- **keychain-global-state-not-isolated**: `service`, `accessGroup`, and
  `legacyServices` are declared `nonisolated(unsafe)`; `KeychainHelper`
  itself performs no locking around reads or writes of these three statics,
  so a caller that mutates one of them from more than one concurrency
  domain without external synchronization MUST accept the resulting data
  race as the type's documented behavior, not a defect to report.
- **keychain-get-error-ambiguity**: `get(forKey:)`'s `String?` return cannot distinguish "no secret was ever stored for this key" from "a Keychain query failed for a reason other than not-found" (for example `errSecInteractionNotAllowed` while the device is locked, or a missing entitlement); `copyValue` logs the status in that second case, but `get` still returns `nil` either way, so no caller can tell the two outcomes apart from the return value alone.

### Security

- **keychain-secret-storage-mechanism**: every value `KeychainHelper.set`
  writes MUST go into a macOS Keychain generic-password item via
  `SecItemAdd`/`SecItemUpdate` — `KeychainHelper` MUST NOT write a secret to
  `UserDefaults`, a file, or any other unencrypted store.
- **keychain-secret-value-not-logged**: every `Loggable` log call inside
  `KeychainHelper.swift` MUST interpolate only the account `key` and a
  status/error value — none MUST interpolate the secret string passed to
  `set(_:forKey:)` or returned by `get(forKey:)`.
- **keychain-secret-no-transmission**: `KeychainHelper` MUST perform no
  networking of any kind — it MUST NOT transmit a stored or retrieved
  secret off-device.
- **keychain-secret-lifetime-caller-controlled**: `KeychainHelper` MUST
  define no TTL, expiry timer, or automatic-eviction policy for a stored
  item — a secret MUST persist until a caller calls `delete(forKey:)` or
  the OS/user removes it independently.

### Loggable

- **loggable-requirement**: `Loggable`'s sole protocol requirement MUST be
  `static nonisolated var logger: Logger { get }`.
- **loggable-default-subsystem**: the default `subsystem` extension member
  MUST equal `Bundle.main.bundleIdentifier ?? "nil"`.
- **loggable-default-category**: the default `category` extension member
  MUST equal `"\(type(of: self))"` with the substring `".Type"` removed via
  `replacingOccurrences(of:with:)`.
- **loggable-instance-forwarding**: the default instance-level `logger`
  extension member MUST forward to `Self.logger` — an instance and its type
  MUST expose the identical `Logger` value.
- **loggable-factory**: `makeLogger()` MUST return `Logger(subsystem:
  self.subsystem, category: self.category)`.
- **loggable-default-members-isolation**: only the protocol's `logger`
  requirement carries an explicit `nonisolated` annotation; the default
  `subsystem`, `category`, instance `logger`, and `makeLogger()` extension
  members carry no isolation annotation of their own and so inherit
  whatever global-actor isolation, if any, applies at each call site.

### MathUtils

- **cgfloat-clamped-shape**: `CGFloat.clamped(to range: ClosedRange<CGFloat>)
  -> CGFloat` MUST return `self` unchanged when `self` already lies within
  `range`, MUST return `range.lowerBound` when `self` is below it, and MUST
  return `range.upperBound` when `self` is above it.
- **cgfloat-clamped-degenerate-range**: when `range.lowerBound ==
  range.upperBound`, `clamped(to:)` MUST return that single value for every
  possible `self`.
- **cgfloat-clamped-pure**: `clamped(to:)` MUST have no side effects and
  MUST depend only on `self` and `range` — it MUST NOT read or mutate any
  external state.

