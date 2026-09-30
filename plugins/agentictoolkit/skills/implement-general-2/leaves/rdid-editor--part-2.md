<!-- leaf: implement-general-2/rdid-editor--part-2 · source: rdid-editor.md -->

# RdidEditor — continued (part 2)

## Platform Notes

- **React/Web**: Source at
  `packages/web/packages/adh-ui/src/components/rdid-editor.tsx`. Composes
  `Input` from `@agenticdevelopertoolkit/ui`
  (`external/agenticdevelopertoolkit/packages/web/packages/ui/src/components/input.tsx`)
  for the field shell and `FieldFootnote` from `@agenticdevelopertoolkit/ui`
  for the hint/error slot, plus `fieldCaptionClass` from
  `@agenticdevelopertoolkit/ui`'s typography module for the caption. It never
  imports the rdid grammar (`prefixFor`, `validateLeaf`) itself — the caller
  supplies `prefix` and `error` already computed.
- **SwiftUI**: Start from a `TextField` inside an `HStack` (for the prefix mode)
  or alone (for the no-prefix mode), since SwiftUI's `TextField` has no built-in
  leading-adornment slot — the fixed prefix has to be composed as a separate
  `Text` view, mirroring the web version's manual layout. Lowercasing has to be
  applied explicitly in the `onChange`/`.onChange(of:)` handler (SwiftUI does
  not lowercase input automatically); the caption becomes a `Text` styled to
  match `fieldCaptionClass`'s mono/uppercase/tracked look, and the
  hint/error footnote becomes a second `Text` below the field, switching its
  content and color the same way `FieldFootnote` does.
- **Compose**: Start from Material 3's `TextField`/`OutlinedTextField`, which —
  unlike the web version — has a native `prefix: @Composable (() -> Unit)?`
  slot, so the fixed prefix does not need a hand-built `Row`. Its `isError`
  parameter maps directly to whether `error` is set, and its `supportingText`
  slot maps directly to the hint/error footnote (swap content the same way
  `FieldFootnote` does, rather than showing both). Lowercase the value inside
  `onValueChange` to match `lowercases-input-on-change`.
- **AppKit / UIKit**: Start from `NSTextField`/`UITextField`. Neither has a
  built-in prefix slot, so compose the fixed prefix as a sibling
  `NSTextField(labelWithString:)`/`UILabel` inside an `NSStackView`/`UIStackView`,
  the same manual-composition shape the web version uses. Lowercase the typed
  value inside the delegate callback
  (`controlTextDidChange`/`textField(_:shouldChangeCharactersIn:)`) before
  propagating it, and render the hint/error footnote as a separate label below
  the field whose text and color swap exactly as `FieldFootnote`'s do.
- **WinUI 3**: Start from `TextBox`, which has a built-in `Header` property that
  can absorb the caption (`label`) instead of a separate label element, and a
  `PlaceholderText` property that maps directly to `placeholder`. WinUI 3's
  `TextBox` has no built-in leading-adornment slot (unlike Compose's `prefix`
  slot), so for the prefix mode, compose a `TextBlock` bound to `prefix` next to
  the `TextBox` inside a horizontal `StackPanel`, the same hand-built layout the
  web version uses. `TextBox`'s default control template only defines
  `Normal`/`PointerOver`/`Focused`/`Disabled`/`ReadOnly` visual states in its
  `CommonStates`/`FocusStates` groups — there is no built-in `Invalid` state
  equivalent to `aria-invalid:border-apt-red`, so mark the invalid state with a
  bound `BorderBrush`/`BorderThickness` (or a custom `VisualState` added to an
  overridden `ControlTemplate`) rather than assuming one exists. `TextBox` has
  no per-field hint/error slot either, so render a `TextBlock` below it (e.g.
  `Foreground="{ThemeResource SystemFillColorCriticalBrush}"` when showing the
  error) whose text swaps between hint and error exactly as `FieldFootnote`
  does, and lowercase the value in the `TextChanged` handler to match
  `lowercases-input-on-change`.

## Design Decisions

- **Decision**: Render the fixed `<type>.<scope>.` prefix as inert static text
  rather than as an editable part of the input's value.
  **Rationale**: Mirrors the backend's own invariant that an rdid's type and
  inherited scope can never change after creation — the component's own doc
  comment states this explicitly — so the UI never offers an edit the backend
  would reject.
  **Approved**: pending
- **Decision**: Lowercase every keystroke inside the `onChange` handler, rather
  than leaving casing to the caller or flagging it only via `error`.
  **Rationale**: The rdid grammar (`SEGMENT_RE` in `rdid.ts`) only accepts
  lowercase segments; normalizing at input time keeps the `error` slot reserved
  for genuinely invalid characters or format rather than surprising the user
  with a case-mismatch error on an otherwise valid leaf.
  **Approved**: pending
- **Decision**: Share one footnote slot for `hint` and `error` (via
  `FieldFootnote`) instead of rendering both at once.
  **Rationale**: Matches `FieldFootnote`'s own designed precedence — error
  replaces hint, they are never shown together — so `RdidEditor` composes that
  component's contract rather than re-implementing or duplicating it.
  **Approved**: pending
- **Decision**: Leave `FieldFootnote`'s `errorId` unset, so the rendered error
  text is not linked to the input via `aria-describedby`.
  **Rationale**: `FieldFootnote` exposes `errorId` precisely so a caller can
  wire this link, but `RdidEditor` does not thread one through today; a
  screen-reader user hears `aria-invalid` on the input without a guaranteed
  programmatic path to the error text itself (see Accessibility).
  **Approved**: pending
