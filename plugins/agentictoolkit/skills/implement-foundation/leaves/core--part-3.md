<!-- leaf: implement-foundation/core--part-3 · source: foundation-core.md -->

# Foundation Core — continued (part 3)

**Rules** (cite as `implement-foundation/core--part-3#<slug>`):

- `semver-shape` MUST
- `semver-parse-forms` MUST
- `semver-parse-rejects-invalid` MUST
- `semver-component-bound` MUST
- `semver-ordering` MUST
- `semver-description-round-trip` MUST
- `text-folding-normalization` MUST
- `text-folding-locale-independence` MUST
- `text-folding-empty-input` MUST
- `text-folding-pure` MUST

### SemanticVersion

- **semver-shape**: `SemanticVersion` MUST be a value type with `let major:
  Int`, `let minor: Int`, `let patch: Int`, and MUST conform to `Sendable`,
  `Hashable`, `Comparable`, and `CustomStringConvertible`.
- **semver-parse-forms**: `SemanticVersion.init?(_ string: String)` MUST
  accept a string of one, two, or three dot-separated numeric components
  (`"1"`, `"1.74"`, `"1.74.0"`), MUST accept an optional leading `"v"`, and
  MUST default any component missing from a short form to `0`.
- **semver-parse-rejects-invalid**: `init?(_:)` MUST return `nil` for a
  string carrying a prerelease suffix (`"1.74.0-rc.1"`), build metadata
  (`"1.74.0+build"`), non-numeric text (`"abc"`), the empty string, or a
  non-numeric component (`"1.x.0"`).
- **semver-component-bound**: `init?(_:)` MUST return `nil` when any parsed
  component exceeds `Int32.max` (`2_147_483_647`), and MUST accept a
  component exactly equal to `Int32.max`.
- **semver-ordering**: `SemanticVersion`'s `Comparable` conformance MUST
  order strictly by `major`, then `minor`, then `patch`, as numeric integer
  comparisons — it MUST NOT compare components as strings (`"9"` MUST sort
  before `"10"`).
- **semver-description-round-trip**: `description` MUST render as
  `"\(major).\(minor).\(patch)"`, and `SemanticVersion(description)` MUST
  equal the original value for every value the type can represent.

### TextFolding

- **text-folding-normalization**: `TextFolding.folded(_ string: String) ->
  String` MUST fold both case and diacritics, so that two strings differing
  only in letter case or in diacritical marks MUST fold to the same result
  (`folded("CAFÉ") == folded("cafe")`).
- **text-folding-locale-independence**: `folded(_:)` MUST call `String
  .folding(options:locale:)` with `locale: nil` rather than
  `Locale.current`, so its result MUST NOT vary with the current locale
  (for example, it MUST fold identically whether the current locale is
  Turkish or U.S. English).
- **text-folding-empty-input**: `folded("")` MUST return `""`.
- **text-folding-pure**: `folded(_:)` MUST have no side effects and MUST
  depend only on its input string.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `KeychainHelper.service` | `String` (static var) | `Bundle.main.bundleIdentifier ?? "com.agentictoolkit"` | Keychain service identifier that scopes every query, set, and delete. |
| `KeychainHelper.accessGroup` | `String?` (static var) | `nil` | Optional shared Keychain access group; when non-nil, forces `kSecUseDataProtectionKeychain` and `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` on new writes. |
| `KeychainHelper.legacyServices` | `[String]` (static var) | `[]` | Retired service identifiers `get`/`exists` fall back to, newest-retired-first, for migrating secrets forward. |
| `SemanticVersion`'s component ceiling | `Int` (private static constant, `Int32.max`) | `2_147_483_647` | Fixed plausibility bound on `major`/`minor`/`patch`; not caller-configurable. |

`CodableIgnored`, `Loggable`, `MathUtils`'s `CGFloat.clamped(to:)`, and
`TextFolding` take no static or environment configuration — every input
they act on is a per-call argument.

## Privacy

`KeychainHelper` is the one file in this recipe that handles sensitive
data; the other five collect, store, and transmit nothing.

- **Data handled**: the secret string values a caller passes to
  `KeychainHelper.set(_:forKey:)` — arbitrary caller-supplied text such as
  an API key or credential. `KeychainHelper` never inspects, parses, or
  transforms the value itself.
- **Storage**: macOS Keychain generic-password items, scoped by `service`
  and optionally `accessGroup`. An access-group item is additionally
  marked `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — readable
  only after the device's first unlock, and never synced off-device.
- **Transmission**: none. `KeychainHelper` performs no networking; a
  caller that later transmits a retrieved secret does so outside this
  component's boundary.
- **Retention**: indefinite. A stored item persists until a caller calls
  `delete(forKey:)` or the OS/user removes it independently —
  `KeychainHelper` defines no TTL or automatic expiry (see
  `keychain-secret-lifetime-caller-controlled` above).

## Platform Notes

- **SwiftUI (source platform)**: all six files (`CodableIgnored.swift`,
  `KeychainHelper.swift`, `Loggable.swift`, `MathUtils.swift`,
  `SemanticVersion.swift`, `TextFolding.swift`) depend only on `Foundation`,
  `Security`, and `os` (`OSLog`) — none imports `SwiftUI`, so they are
  usable unchanged from any SwiftUI view model or view.
- **Compose (Kotlin/Android)**: `CodableIgnored` maps to a `kotlinx
  .serialization` field marked `@Transient` (or a custom `SerialDescriptor`
  override) so the field never serializes and always deserializes to its
  default. `KeychainHelper` maps to Android Keystore-backed
  `EncryptedSharedPreferences`, keyed the same way `service`/`account`
  scope a Keychain query. `Loggable` maps to a `Timber` tree, or plain
  `android.util.Log`, tagged with the conforming class's simple name.
  `clamped(to:)` maps directly to Kotlin's `coerceIn(range)`.
  `SemanticVersion` maps to a small `data class` with a hand-written parser
  (matching this type's short-form leniency, since a general semver
  library would reject `"1.74"`), guarded by the same `Int.MAX_VALUE`-scale
  bound. `TextFolding` maps to Java/Kotlin's `java.text.Normalizer`
  (`NFD`) with combining marks stripped, followed by
  `.lowercase(Locale.ROOT)` to keep the fold locale-independent.
- **React/Web**: `CodableIgnored` maps to a `class-transformer`
  `@Exclude()` decorator, or simply omitting the field from both the
  serializer and the deserializer's output type. `KeychainHelper` has no
  direct browser analog — there is no OS keychain in a browser sandbox; a
  Node.js backend's closest equivalent is a native keytar-style module
  wrapping the host OS's credential store. `Loggable` maps to a per-module
  logger factory (for example `pino().child({ category: name })`) keyed by
  module or class name. `clamped(to:)` maps to `Math.min(Math.max(value,
  lower), upper)` — JavaScript has no built-in clamp. `SemanticVersion`
  should still be hand-parsed rather than delegated to the npm `semver`
  package, to preserve this type's short-form leniency and its explicit
  `Number.MAX_SAFE_INTEGER`-scale bound check, since JavaScript numbers do
  not trap on overflow the way `Int` arithmetic does. `TextFolding` maps to
  `string.normalize('NFKD').replace(/[̀-ͯ]/g, '').toLowerCase()`,
  with no locale argument, matching this type's `locale: nil`.
- **AppKit/UIKit**: identical to the SwiftUI note — none of the six files
  imports `AppKit` or `UIKit`, so an AppKit- or UIKit-hosted app consumes
  the same `AgenticToolkitCore` types unchanged. One platform-specific
  nuance carries forward regardless of UI framework: `KeychainHelper`'s
  `kSecUseDataProtectionKeychain` flag (set only when `accessGroup` is
  non-nil) is required for access-group Keychain sharing on macOS
  specifically, per the type's own source comment.
- **WinUI 3**: the reason this recipe exists — none of these six types has
  a direct Windows App SDK equivalent, so each needs a concrete port.
  `CodableIgnored` maps to `System.Text.Json`'s `[JsonIgnore]` attribute
  directly (the BCL already provides this exact "never encode, always
  null/default on decode" contract — no wrapper type is needed).
  `KeychainHelper` maps to `Windows.Security.Credentials.PasswordVault`
  (`PasswordCredential`), resourced by the same string `service` scopes a
  Keychain query with; Windows has no access-group concept, so the
  access-group migration path (`accessGroup`, and the migration branch of
  `get(forKey:)`) has no analog and should be dropped, while the
  `legacyServices` migration path still applies (a `PasswordVault` resource
  rename). `Loggable` maps to `Microsoft.Extensions.Logging`'s
  `ILogger<T>`, resolved per type the same way `makeLogger()` derives a
  category from the conforming type's own name. `clamped(to:)` maps
  directly to .NET's `Math.Clamp(value, min, max)` — no port needed.
  `SemanticVersion` maps to a `readonly struct` with `int major`, `int
  minor`, `int patch` implementing `IComparable`, guarding each parsed
  component against `int.MaxValue` explicitly, mirroring
  `SemanticVersion.maximumComponent`. `TextFolding` maps to `string
  .Normalize(NormalizationForm.FormD)` with combining marks stripped by
  Unicode category, followed by `ToUpperInvariant()`/`ToLowerInvariant()`
  (never the current-culture `ToLower()`) to preserve `locale: nil`'s
  locale independence. `Task`, `HttpClient`, and `Windows.Storage` have no
  role in any of the six ports: every operation here is synchronous, with
  at most one credential-vault round trip.

