<!-- leaf: implement-general-view-2/number-field-view--edge-cases · source: number-field-view.md -->

# NumberFieldView

**Rules** (cite as `implement-general-view-2/number-field-view--edge-cases#<slug>`):

- `overwritten-external-observer` MUST — viewModel.onChange is a single closure property. The initializer unconditionally assigns viewModel.onChange = { [weak …

## Edge Cases

- **Null/empty input**: `viewModel` (`ViewModel<Value>`) is a non-optional,
  typed constructor parameter; Swift's type system rules out `nil`. An empty
  `textField.stringValue` fails `Value(settingsFieldString:)` for both `Int`
  and `Double` (a trimmed empty string fails both the POSIX and the
  locale-aware parse), so `commit()` takes the revert path
  (**reverts-on-unparseable-text**) rather than storing `0`.
- **Boundary values**: A typed value exactly equal to `minimum` or `maximum`
  commits unclamped (the clamp is a no-op at the boundary). A value one
  below `minimum` clamps up to `minimum`; one above `maximum` clamps down to
  `maximum`. When `minimum` and `maximum` are both set and `minimum >
  maximum`, clamping is skipped entirely and the raw typed value is stored
  (**skips-clamp-on-contradictory-bounds**) — a caller configuration error,
  not a range this component enforces.
- **Out-of-range magnitude (Int)**: A typed value whose magnitude exceeds
  what `Int` can hold exactly — per `Int.settingsExactInt(from:)`'s
  `Decimal`-based check, which catches the case `NSNumber.int64Value` would
  otherwise silently saturate — is treated as unparseable and reverts rather
  than storing a clamped `Int.max`/`Int.min`.
- **Non-finite values (Double)**: `"nan"`, `"inf"`, and `"-inf"` all parse
  syntactically under `Double(_:)`, but `Double.init(settingsFieldString:
  locale:)` explicitly rejects a non-finite POSIX result and a non-finite
  locale-aware result, returning `nil` rather than storing a NaN or
  infinite value that would make every bounds comparison in `commit()`
  false.
- **Fractional and locale-formatted text (Int)**: A fractional string
  (`"1.5"`, or `"1,5"` in a comma-decimal locale) is rejected outright —
  `Int.settingsAllowsFloats` is `false`, so the locale `NumberFormatter`
  refuses it, and the whole-string-consumed check refuses a partial parse
  like the leading `"1"` of `"1,5"`. An integral-valued fractional spelling
  (`"1.0"`) is refused for the same reason.
- **Whole-number round-trip stability (Double)**: A stored `20.0` renders as
  `"20"` (**writes-whole-doubles-without-fraction**) rather than `"20.0"`,
  so a field showing a value the caller never edited does not visibly
  rewrite it into a longer, decorated form.
- **Concurrent access**: Not applicable — `SettingsNumberValue`'s extension
  methods and the `Int`/`Double` conformances are `nonisolated`, synchronous,
  pure value-type code (the protocol itself requires only `Sendable`); only
  `NumberFieldView` is `@MainActor` (see **confines-to-main-actor**), so all
  construction and mutation of the view is serialized to the main actor even
  though the parsing/formatting code they call is not itself isolated.
- **Error states**: Not applicable — every operation in this file (parsing,
  clamping, the `settingObserver.value` write) is synchronous and
  non-throwing; the one `try` in the file (`formatter.getObjectValue`) is
  caught locally and converted to a `nil` return, never propagated. No
  error reaches the caller.
- **Offline/disconnected state**: Not applicable — the component performs no
  networking; it only reads from and writes to an in-process view model.
- **Overwritten external observer**: `viewModel.onChange` is a single
  closure property. The initializer unconditionally assigns
  `viewModel.onChange = { [weak self] _ in self?.sync() }`, replacing
  whatever handler (if any) was previously registered on that view model —
  the same closure-overwrite behavior `CheckboxView` and
  `CaptionedSliderView` document. The component MUST NOT be assumed to
  coexist with another `onChange` observer already registered on the same
  view model instance.
