<!-- leaf: implement-foundation/core--edge-cases · source: foundation-core.md -->

# Foundation Core

**Rules** (cite as `implement-foundation/core--edge-cases#<slug>`):

- `empty-string-as-a-stored-secret` MUST — KeychainHelper.set("", forKey:) MUST succeed, and a subsequent get(forKey:) MUST return "", not nil — an empty string …
- `empty-string-as-a-version-or-a-fold-target` MUST — SemanticVersion("") MUST return nil (empty is not a valid version), while TextFolding.folded("") MUST return "" (empty …
- `version-component-at-the-arithmetic-ceiling` MUST — a component equal to Int32.max MUST parse; a component one greater MUST NOT — the boundary is exact, not approximate.
- `degenerate-clamp-range` MUST — clamped(to:) with range.lowerBound == range.upperBound MUST collapse every input to that single value, never trap or …
- `secret-recovered-from-a-legacy-or-access-group-scope` MUST — get(forKey:) re-stores the recovered value under the current scope but MUST NOT delete the original — a second install …
- `unicode-and-control-characters-in-a-stored-secret` MUST — KeychainHelper MUST round-trip a value containing multibyte Unicode, emoji, and control characters (newline, tab) …

## Edge Cases

- **Empty string as a stored secret**: `KeychainHelper.set("", forKey:)`
  MUST succeed, and a subsequent `get(forKey:)` MUST return `""`, not
  `nil` — an empty string is a valid, distinct value from "absent."
- **Empty string as a version or a fold target**: `SemanticVersion("")`
  MUST return `nil` (empty is not a valid version), while
  `TextFolding.folded("")` MUST return `""` (empty is a valid, if trivial,
  fold result) — the two types MUST NOT be conflated.
- **Version component at the arithmetic ceiling**: a component equal to
  `Int32.max` MUST parse; a component one greater MUST NOT — the boundary
  is exact, not approximate.
- **Degenerate clamp range**: `clamped(to:)` with `range.lowerBound ==
  range.upperBound` MUST collapse every input to that single value, never
  trap or produce an unrelated result.
- **Concurrent mutation of `KeychainHelper`'s global statics**: `service`,
  `accessGroup`, and `legacyServices` are `nonisolated(unsafe)`; concurrent
  mutation from more than one isolation domain without external
  synchronization is a documented data race, not a crash the type guards
  against.
- **Concurrent mutation of a shared `CodableIgnored` instance**: the
  wrapper is not `Sendable`; sharing one instance's mutable `wrappedValue`
  across concurrency domains without synchronization is the caller's
  responsibility, not something the wrapper prevents.
- **Keychain query failure that is not "not found"**: `copyValue` logs any
  `SecItemCopyMatching` status other than `errSecSuccess` and
  `errSecItemNotFound`, but `get(forKey:)` still returns `nil` for that
  case exactly as it does for a genuine absence — see
  `keychain-get-error-ambiguity` above.
- **Secret recovered from a legacy or access-group scope**: `get(forKey:)`
  re-stores the recovered value under the current scope but MUST NOT
  delete the original — a second install still pointed at the old scope
  MUST continue to find its copy.
- **Unicode and control characters in a stored secret**: `KeychainHelper`
  MUST round-trip a value containing multibyte Unicode, emoji, and control
  characters (newline, tab) exactly, since `set`/`get` encode/decode as raw
  UTF-8 `Data` with no transformation.
- **Offline or disconnected operation**: not applicable — none of the six
  files performs networking, so there is no offline/disconnected state to
  define.
