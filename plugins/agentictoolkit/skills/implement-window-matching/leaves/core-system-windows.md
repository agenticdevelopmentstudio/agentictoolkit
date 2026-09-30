<!-- leaf: implement-window-matching/core-system-windows · source: window-matching-core-system-windows.md -->

**Rules** (cite as `implement-window-matching/core-system-windows#<slug>`):

- `value-semantics` MUST
- `sendable` MUST
- `codable` MUST
- `equatable` MUST
- `computed-not-encoded` MUST
- `optional-omitted` MUST
- `missing-key-throws` MUST
- `frame-encoding` MUST
- `no-side-effects` MUST
- `no-errors` MUST
- `strategy-cases` MUST
- `strategy-raw-values` MUST
- `strategy-case-iterable` MUST
- `strategy-unknown-raw` MUST
- `display-name-exact` MUST
- `display-name-substring` MUST
- `display-name-regex` MUST
- `display-name-app-only` MUST
- `strategy-semantics-declared` MUST
- `fingerprint-fields` MUST
- `fingerprint-immutable` MUST
- `fingerprint-init-verbatim` MUST
- `title-pattern-meaning` MUST
- `regex-not-validated` MUST
- `display-tie-breaker` MUST
- `info-fields` MUST
- `info-identifiable` MUST
- `info-init-verbatim` MUST
- `info-empty-title` MUST
- `with-title-copy` MUST
- `with-title-non-mutating` MUST
- `with-title-purpose` MUST
- `snapshot-fields` MUST
- `snapshot-immutable-identity` MUST
- `snapshot-stable-id` MUST
- `snapshot-id-default` MUST
- `snapshot-window-id-default` MUST
- `snapshot-last-seen-default` MUST
- `snapshot-is-live` MUST
- `snapshot-dormant` MUST
- `snapshot-display-independent` MUST
- `snapshot-app-duplicated` MUST

# Window Matching Core System Windows

## Overview

The core model of the AgenticToolkit "system window contexts" feature: five platform-neutral value types under `packages/apple/AgenticToolkit/Core/SystemWindows/`. They carry no behavior beyond in-memory collection edits; matching, persistence and window movement live in their consumers.

- `MatchStrategy.swift` declares `MatchStrategy`, a `String`-backed enum (`appAndTitleExact`, `appAndTitleSubstring`, `appAndTitleRegex`, `appOnly`) that says how strictly a fingerprint must match a live window, plus an English `displayName` per case.
- `SystemWindowFingerprint.swift` declares `SystemWindowFingerprint`, an immutable record (`app`, `titlePattern`, `matchStrategy`, `display`) that identifies a window across restarts, "even though the CGWindowID has changed".
- `SystemWindowInfo.swift` declares `SystemWindowInfo`, an immutable description of one live window "obtained from CGWindowListCopyWindowInfo" (`id`, `app`, `pid`, `title`, `frame`, `display`, `isOnScreen`, `layer`), with `withTitle(_:)` to backfill a title read through Accessibility.
- `SystemWindowSnapshot.swift` declares `SystemWindowSnapshot`, a window's stable identity and saved position inside a context: a stable `id` (not the CGWindowID), an optional live `windowID`, the `fingerprint`, `savedFrame`, `display`, `app`, `title` and `lastSeen`, with `isLive` derived from `windowID`.
- `SystemWindowContext.swift` declares `SystemWindowContext`, a named, colored group of snapshots ("a logical workspace — for example, 'iOS App', 'Backend API', or 'Docs'") with add, remove, look-up and in-place update operations and a `liveWindowCount`.

Consumers named for orientation: `SystemWindowMatcher` builds fingerprints (`fingerprint(window:)`) and scores live windows against them (`score(window:against:)`); `SystemWindowContextManager` owns the list of contexts and enforces cross-context rules; `SystemWindowContextStore` persists contexts as JSON files. Use this ingredient when an app needs a serializable model for grouping another app's windows into named workspaces that survive a restart of either app or the OS.

## Behavioral Requirements

### Shared conformances

- **value-semantics**: All five types MUST be value types (`struct` or `enum`); copying a value MUST NOT share mutable state with the original.
- **sendable**: All five types MUST conform to `Sendable`, so a value MAY cross any concurrency-domain boundary without synchronization.
- **codable**: All five types MUST conform to `Codable` using the compiler-synthesized implementation, so each stored property encodes under a key equal to its Swift name and no custom key mapping, versioning or default-on-missing logic exists.
- **equatable**: All five types MUST conform to `Equatable` using the synthesized implementation, so two values are equal if and only if every stored property is equal (including `lastSeen` and `createdAt` timestamps).
- **computed-not-encoded**: The computed members `MatchStrategy.displayName`, `SystemWindowSnapshot.isLive` and `SystemWindowContext.liveWindowCount` MUST NOT appear in encoded output.
- **optional-omitted**: An optional stored property whose value is `nil` (`SystemWindowSnapshot.windowID`, `SystemWindowContext.lastFocusedWindowID`) MUST be omitted from encoded output, and a missing key MUST decode as `nil` (synthesized `encodeIfPresent` / `decodeIfPresent`).
- **missing-key-throws**: Decoding any of the four struct types MUST throw a `DecodingError` when a non-optional stored property's key is absent; no field has a decode-time default.
- **frame-encoding**: `CGRect` fields (`SystemWindowInfo.frame`, `SystemWindowSnapshot.savedFrame`) MUST encode with CoreGraphics' own `Codable` form, a nested array `[[x, y], [width, height]]`.
- **no-side-effects**: No member of the five types MUST perform file I/O, network access, logging, process launches or notification posting; every operation is a pure computation or an in-memory mutation of the receiver.
- **no-errors**: No member MUST throw or return an error; lookups signal "not found" with `nil` or `false`.

### MatchStrategy

- **strategy-cases**: `MatchStrategy` MUST declare exactly four cases, in this order: `appAndTitleExact`, `appAndTitleSubstring`, `appAndTitleRegex`, `appOnly`.
- **strategy-raw-values**: Each case MUST use its case name as its `String` raw value (`"appAndTitleExact"`, `"appAndTitleSubstring"`, `"appAndTitleRegex"`, `"appOnly"`), and MUST encode and decode as that string.
- **strategy-case-iterable**: `MatchStrategy.allCases` MUST contain exactly 4 elements in declaration order.
- **strategy-unknown-raw**: Decoding a string that is not one of the four raw values MUST throw a `DecodingError.dataCorrupted`; `MatchStrategy(rawValue:)` with such a string MUST return `nil`.
- **display-name-exact**: `displayName` on `appAndTitleExact` MUST return `"Exact"`.
- **display-name-substring**: `displayName` on `appAndTitleSubstring` MUST return `"Substring"`.
- **display-name-regex**: `displayName` on `appAndTitleRegex` MUST return `"Regex"`.
- **display-name-app-only**: `displayName` on `appOnly` MUST return `"App Only"`.
- **strategy-semantics-declared**: Each case's meaning is the contract its doc comment declares, implemented by the consumer `SystemWindowMatcher.score(window:against:)`: `appAndTitleExact` is app plus exact title match, `appAndTitleSubstring` is app plus title containment, `appAndTitleRegex` is app plus a regular-expression test of the live title, and `appOnly` is app alone, ignoring the title. The enum itself MUST NOT perform any matching.

### SystemWindowFingerprint

- **fingerprint-fields**: `SystemWindowFingerprint` MUST store exactly `app: String`, `titlePattern: String`, `matchStrategy: MatchStrategy` and `display: UInt32`.
- **fingerprint-immutable**: Every stored property of `SystemWindowFingerprint` MUST be immutable (`let`); a changed fingerprint is a new value.
- **fingerprint-init-verbatim**: `init(app:titlePattern:matchStrategy:display:)` MUST store each argument unchanged, with no trimming, case folding or validation; all four parameters are required and have no defaults.
- **title-pattern-meaning**: `titlePattern` MUST hold the pattern a heuristic extracted from the title (for example `"MyProject"` from `"MyProject — ContentView.swift"`) or, when no heuristic applies, the full title; per the `appAndTitleRegex` doc comment, for that strategy it MUST hold "the regex source (not a captured value)".
- **regex-not-validated**: A `titlePattern` that is not a compilable regular expression is a value the fingerprint MUST accept; compiling and rejecting it belongs to `SystemWindowMatcher`, which logs the compile error and scores the window 0.
- **display-tie-breaker**: `display` MUST hold the display ID the window was on when fingerprinted; per its doc comment it is "a tie-breaker when multiple candidate windows match" (the consumer adds a 10-point bonus when a live window's `display` equals it).

### SystemWindowInfo

- **info-fields**: `SystemWindowInfo` MUST store exactly `id: UInt32` (the CGWindowID), `app: String`, `pid: Int32`, `title: String`, `frame: CGRect`, `display: UInt32`, `isOnScreen: Bool` and `layer: Int32`, all immutable (`let`).
- **info-identifiable**: `SystemWindowInfo.id` MUST be the `Identifiable` identity, so two infos for the same CGWindowID share an `id` even when other fields differ.
- **info-init-verbatim**: `init(id:app:pid:title:frame:display:isOnScreen:layer:)` MUST store each argument unchanged; all eight parameters are required.
- **info-empty-title**: `title` MUST accept an empty string; per its doc comment the title "may be empty for some windows".
- **with-title-copy**: `withTitle(_:)` MUST return a new `SystemWindowInfo` whose `title` is the argument and whose other seven fields equal the receiver's.
- **with-title-non-mutating**: `withTitle(_:)` MUST NOT modify the receiver.
- **with-title-purpose**: `withTitle(_:)` exists to "backfill titles obtained via Accessibility when CGWindowListCopyWindowInfo omits them (no Screen Recording permission)"; it MUST accept any string, including an empty one, without validation.

### SystemWindowSnapshot

- **snapshot-fields**: `SystemWindowSnapshot` MUST store `id: UUID`, `windowID: UInt32?`, `fingerprint: SystemWindowFingerprint`, `savedFrame: CGRect`, `display: UInt32`, `app: String`, `title: String` and `lastSeen: Date`.
- **snapshot-immutable-identity**: `id`, `fingerprint` and `app` MUST be immutable (`let`); `windowID`, `savedFrame`, `display`, `title` and `lastSeen` MUST be mutable (`var`).
- **snapshot-stable-id**: `id` MUST be a stable identifier that is NOT the CGWindowID and persists across restarts.
- **snapshot-id-default**: `init` MUST generate a fresh random `UUID` for `id` when the caller omits it.
- **snapshot-window-id-default**: `init` MUST default `windowID` to `nil` when the caller omits it.
- **snapshot-last-seen-default**: `init` MUST default `lastSeen` to the current date and time when the caller omits it.
- **snapshot-is-live**: `isLive` MUST return `true` if and only if `windowID` is non-nil.
- **snapshot-dormant**: A snapshot with `windowID == nil` MUST represent the dormant state: per the doc comment, the window "has been closed or the app has been quit".
- **snapshot-display-independent**: `display` (the restore target) and `fingerprint.display` (the display at fingerprint time) MUST be stored independently; changing `display` MUST NOT change `fingerprint.display`.
- **snapshot-app-duplicated**: `app` and `fingerprint.app` MUST be stored independently; the initializer MUST NOT check that they are equal (`SystemWindowContextManager` passes the same live window's `app` to both).

