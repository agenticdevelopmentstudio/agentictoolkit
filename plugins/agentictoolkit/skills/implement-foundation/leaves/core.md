<!-- leaf: implement-foundation/core · source: foundation-core.md -->

# Foundation Core

## Overview

`foundation-core` covers six top-level files in `AgenticToolkitCore`'s `Core/`
directory. Each file has no dependency on anything else in this recipe or on
any other part of the package; together they form the lowest tier of the
toolkit — the tier every other logic and UI component in `AgenticToolkitCore`
is built on top of.

- **`CodableIgnored`** — a property wrapper that removes a field from
  `Codable` encoding and decoding entirely, so a value can exist on a model
  without ever appearing in its JSON representation.
- **`KeychainHelper`** — a static, namespace-style API over macOS Keychain
  generic-password items, with built-in migration across a configurable
  access group and a list of retired service identifiers. Consumed directly
  by `KeychainSecureSettingsStorageProvider` and by the AI Plugin Kit's
  secret-storing component.
- **`Loggable`** — a protocol that gives any conforming type a
  `Logger` derived from the app's bundle identifier and the type's own name,
  with no boilerplate at each call site beyond a single `static nonisolated
  let logger = makeLogger()` line.
- **`MathUtils`** — a single `CGFloat.clamped(to:)` extension method; pure
  arithmetic, no state.
- **`SemanticVersion`** — a `major.minor.patch` parser and comparable value
  type with an explicit upper bound on each component, guarding arithmetic
  callers (such as `VSCodeEngineRange`'s caret-range ceiling) against
  `Int` overflow traps.
- **`TextFolding`** — a single `String` case-and-diacritic folding helper for
  locale-independent text matching, used by `CommandPaletteModel` and
  `ExtensionQuickPickModel`.

None of the six files import `SwiftUI`, `AppKit`, or `UIKit`; none renders
anything, holds view state, or performs networking.

