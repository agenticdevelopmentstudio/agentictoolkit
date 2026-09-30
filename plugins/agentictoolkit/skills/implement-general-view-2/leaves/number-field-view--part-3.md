<!-- leaf: implement-general-view-2/number-field-view--part-3 · source: number-field-view.md -->

# NumberFieldView — continued (part 3)

**Rules** (cite as `implement-general-view-2/number-field-view--part-3#<slug>`):

- `winui-3` MUST (the reason this recipe exists) — Build the row as a Grid with column definitions Auto,* — a TextBlock for the title in column 0, and a NumberBox — …

## Platform Notes

- **SwiftUI**: `TextField("", value: $numericValue, format: .number)` (or a
  `String`-backed `TextField` with a manual parse/format pair, to reproduce
  the POSIX-write/locale-read asymmetry) inside an `HStack` with a leading
  `Text(viewModel.title)`, giving the field a fixed `.frame(width:)`
  matching `fieldWidth` and `.font(.system(.body, design: .monospaced))` for
  the code-role font. Commit and clamp from the `Binding`'s setter (or
  `.onSubmit`) rather than on every keystroke, mirroring
  commits-on-editing-end and reverts-on-unparseable-text; SwiftUI's own
  `FocusState` change is the analog of `controlTextDidEndEditing`.
- **Compose**: `OutlinedTextField`/`BasicTextField` with
  `keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)`, a
  leading `Text(title)`, and a `Modifier.width(...)` matching `fieldWidth`.
  Keep `onValueChange` parsing against a `String` buffer only (coercing to
  the numeric type on every keystroke would fight a user mid-edit, the same
  problem the source's no-formatter comment describes), and commit/clamp
  when focus is lost (`Modifier.onFocusChanged`), mirroring
  commits-on-editing-end.
- **React/Web**: `<input type="text" inputMode="decimal">` (not
  `type="number"`, whose native spinner and silent-empty-on-invalid behavior
  diverges from the source's explicit revert-on-invalid path, and no `pattern`
  attribute, which cannot express the source's locale-aware grammar — a
  POSIX-only pattern like `-?[0-9]*\.?[0-9]*` would reject comma-decimal
  locales and would also accept a fraction for the `Int` case) paired with a
  `<label>` wired via `aria-labelledby`/`htmlFor`, the web analog of
  `setAccessibilityTitleUIElement`. Parse and clamp on `blur`/`Enter`
  (mirroring commits-on-editing-end and commits-on-field-action), reverting
  the displayed text on a parse failure rather than accepting it, using the
  same two thin parse/format functions per type (rather than the `pattern`
  attribute) to police what each type accepts — the same generalization
  `SettingsNumberValue` gives the Swift source.
- **AppKit/UIKit** (source platform): Source file
  `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/Views/NumberFieldView.swift`.
  A macOS-only (`import AppKit`) `NSView` subclass, `@MainActor`, generic
  over `Value: SettingsNumberValue`, inside the `ComposableSettings`
  namespace, conforming to `SettingsViewProtocol` and
  `NSTextFieldDelegate`. The same file declares the `SettingsNumberValue`
  protocol and its `Int`/`Double` conformances, each supplying a
  POSIX-first, then locale-`NumberFormatter`-based parse and a canonical
  `settingsFieldString`. There is no UIKit code path in source; a UIKit
  port would replace `NSTextField` with `UITextField`
  (`keyboardType = .numbersAndPunctuation` to allow a leading `-` and a
  decimal separator), replace target/action with
  `.addTarget(_:action:for: .editingDidEnd)`, and reimplement the generic
  `SettingsNumberValue`-driven parse/clamp/revert logic against
  `UITextField.text` — UIKit has no `NSCoder`-vs-frame initializer split to
  fatal-error on the way requires-designated-initializer and
  rejects-frame-only-initialization do.
- **WinUI 3** (the reason this recipe exists): Build the row as a `Grid`
  with column definitions `Auto,*` — a `TextBlock` for the title in column
  0, and a `NumberBox` — WinUI's purpose-built numeric field — in column 1,
  in place of a raw `TextBox`. Because `NumberBox.Value` is always a
  `double`, an `Int`-typed field (mirroring this recipe's `Int`
  conformance) MUST convert at the boundary with the same exactness check
  `Int.settingsExactInt(from:)` performs, rejecting (via
  `NumberBox.ValidationMode`/a `NumberBoxNumberFormatter` override) any
  value the round trip through `double` would not reproduce exactly; a
  `Double`-typed field maps directly. `NumberBox` already exposes
  `Minimum`/`Maximum` properties that map directly to this component's
  `minimum`/`maximum` when non-nil; their own unset defaults are
  `double.MinValue`/`double.MaxValue` (not `NaN`), which already mirrors
  `nil`'s no-clamp-at-that-end behavior with no extra sentinel needed.
  `NumberBox` has no equivalent of **skips-clamp-on-contradictory-bounds**,
  though: it documents no escape hatch for a caller-supplied `Minimum >
  Maximum`, so a port either validates that bounds are non-contradictory
  before setting them or accepts that `NumberBox`'s own (unspecified)
  behavior governs that case instead of this source's unclamped fallback —
  the two diverge there. `NumberBox` also parses its displayed text in the
  current culture only, with no POSIX-first fallback, so the round-trip
  guarantee behind this source's POSIX-first Design Decision (text this
  component itself wrote is guaranteed to read back correctly regardless of
  a later locale change) does not carry over automatically; a port that
  needs it must format and re-parse `NumberBox.Text` itself with the same
  POSIX-first-then-current-culture ordering rather than relying on
  `NumberBox`'s own culture-aware parsing. Setting
  `SpinButtonPlacementMode="Collapsed"` keeps it visually a bare field
  rather than a stepper. Set `NumberBox.ValidationMode=
  "InvalidInputOverwritten"` to reproduce reverts-on-unparseable-text
  (WinUI overwrites the box with the last valid value on an invalid commit,
  the same behavior as this source's `sync()` revert), and handle the
  `ValueChanged` event to write the already-clamped, committed value into
  the bound setting with an equality guard before writing, mirroring
  skips-redundant-commits. Set `AutomationProperties.LabeledBy` on the
  `NumberBox` to the `TextBlock`, the WinUI analog of
  `setAccessibilityTitleUIElement`. Give `NumberBox` a fixed `Width`
  matching `fieldWidth` (72 by default here) rather than letting it stretch
  to fill its column, the WinUI analog of fixes-field-width.

## Design Decisions

- **Decision**: Attach no `NSFormatter` to `textField`.
  **Rationale**: Per the source's own comment, a formatter with a minimum
  would reject valid intermediate text on the way to a valid number (e.g.
  typing "-" before "-5", or the "1" of "12" against a minimum of 10);
  parsing happens only on commit instead.
  **Approved**: pending
- **Decision**: Parse POSIX-first, falling back to a locale-aware parse only
  when the POSIX parse fails (or, for `Double`, produces a non-finite
  result).
  **Rationale**: Per the source's own comment on `SettingsNumberValue`, the
  field's own writer (`settingsFieldString`) is POSIX; a locale-first parse
  risks misreading the POSIX text `sync()` itself just wrote as a
  locale-formatted number instead. The source itself notes this ordering is
  unobservable and deliberately untested for `Int` (`settingsFieldString`
  emits no separators for `Int`, so neither parse branch can see a string
  the other reads differently), while `Double`'s ordering is pinned by a
  dedicated test, because a `Double`'s POSIX writer can emit a decimal point
  a locale parse could misread.
  **Approved**: pending
- **Decision**: Skip clamping entirely when `minimum` and `maximum` are both
  set and `minimum > maximum`, rather than clamping to one of them.
  **Rationale**: Per the source's own comment, "a contradictory pair comes
  from a caller's own mistake, and the field's job then is to stay usable,
  not to enforce an empty range" — whichever bound clamping would apply
  first is an arbitrary artifact of the code's line order, so the source
  instead leaves the field unbounded in that case.
  **Approved**: pending
- **Decision**: Revert silently to the last committed value on unparseable
  text, rather than storing a coerced or default value.
  **Rationale**: Per the source's own comment, "text that is not a number of
  this type is not a zero; it is a typo," and a silently-stored zero (or a
  rounded fraction) would be a value the user never typed.
  **Approved**: pending
- **Decision**: Reject a parsed `Int` whose magnitude `Int64` would otherwise
  silently clamp, via a `Decimal`-based exactness check
  (`Int.settingsExactInt(from:)`), rather than accepting the clamped
  result.
  **Rationale**: Per the source's own comment, `NSNumber.int64Value`
  saturates rather than failing on overflow, and `Double(Int64.max)` rounds
  up to exactly 2^63 — indistinguishable from a true 2^63 input as a
  `Double` — so only the `Decimal` comparison can tell a genuinely-typed
  `Int.max` apart from an overflow that would otherwise be silently stored
  as `Int.max`.
  **Approved**: pending
- **Decision**: Render a whole `Double` without a trailing fraction
  (`20.0` → `"20"`) via `Int(exactly:)`, rather than always using
  `String(self)`.
  **Rationale**: Per the source's own comment, `String(20.0)` is `"20.0"`,
  and a field that turns the `20` an extension author wrote into `20.0` the
  moment it is shown has edited a setting nobody touched.
  **Approved**: pending
