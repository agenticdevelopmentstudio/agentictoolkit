---
id: 071e67a8-54a7-4f8b-b747-e6384713efde
title: RDID Editor
domain: agentictoolkit://cookbook/adh/hub/identifiers/rdid-editor
type: ingredient
version: 1.2.0
status: review
language: en
created: 2026-09-23
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The one control for editing a type-prefixed rdid: a fixed, non-editable
  `<type>.<scope>.` prefix as static text plus a lowercase-normalized input for the
  leaf.'
platforms:
- typescript
- web
tags:
- form
- input
- rdid
- identifier
depends-on: []
related:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references: []
approved-by: ''
approved-date: ''
---

# RDID Editor

## Overview

The Rdid Editor is the one control for editing a type-prefixed rdid
(`<type>.<scope>.<name>`). An rdid's type and inherited scope are fixed at
creation and can never change afterward — mirroring how the backend
rejects any type/scope change — so the control renders that fixed portion
as inert, non-interactive text and exposes only the editable leaf segment
as a real input field. When the prefix is the empty string there is
nothing fixed to protect (e.g. a brand-new, unsaved draft, or a top-level
rdid kind), so the whole value is edited as one full-width input instead.

The component is backend-agnostic by design: it does not compute the
prefix or validate the leaf itself. The caller computes the prefix
(typically derived from the rdid grammar) and any error (from leaf
validation) and passes them in as plain inputs, so the editor has no
dependency on the rdid grammar's validation rules — only on displaying
whatever the caller decides.

It composes two lower-tier shared components rather than building its own
field shell: a shared form-control shell (border, radius, focus/invalid
styling) for the editable leaf, and a shared hint/error footnote component
for the slot beneath it. The caption above the control uses a shared
"uppercase-mono caption" typography role rather than a bespoke label
style.

## Behavioral Requirements

- **renders-associated-label**: The editor MUST render its label
  associated with the input, so assistive technology and a pointer click
  on the label both target the input.
- **generates-stable-input-id**: The editor MUST use a caller-supplied
  input identifier when provided, and otherwise MUST generate a stable
  one itself, so the label association always resolves to a real
  element.
- **renders-static-prefix**: WHEN `prefix` is a non-empty string, the
  editor MUST render it as static, non-interactive text immediately
  before the input, and MUST NOT include it in the input's editable
  value.
- **renders-single-input-without-prefix**: WHEN `prefix` is the empty
  string, the editor MUST render one full-width input with no prefix
  element, so the entire value is editable.
- **displays-controlled-value**: The editor MUST render the input's
  current value from the value it is given (a controlled component; it
  holds no value state of its own).
- **lowercases-input-on-change**: On every input change, the editor MUST
  report the new value converted to lowercase.
- **forwards-placeholder**: WHEN a placeholder is provided, the editor
  MUST set it as the input's native placeholder text.
- **shows-hint-below-input**: WHEN a hint is provided and no error is,
  the editor MUST render the hint in the footnote slot below the input.
- **shows-error-in-place-of-hint**: WHEN an error is provided, the editor
  MUST render the error in the footnote slot below the input instead of
  the hint.
- **marks-input-invalid-on-error**: WHEN an error is provided, the editor
  MUST mark the input as invalid to assistive technology.
- **omits-invalid-attribute-without-error**: WHEN no error is provided,
  the editor MUST NOT mark the input as invalid at all (not even an
  explicit "not invalid" marker).
- **disables-input-when-disabled**: WHEN disabled, the editor MUST
  render the input in a disabled state that rejects further edits.
- **supports-native-keyboard-input**: The editor MUST accept text entry
  and full keyboard focus navigation through the platform's native text
  input; the source attaches no custom key handlers that would intercept
  or block native keyboard behavior.

## Appearance

The editor sets its own styling only for the caption, the prefix text,
and the row/stack spacing; the field's corner radius, padding, colors,
border, and size all come from the shared field-control shell and the
shared hint/error footnote component — see the Overview.

- **Corner radius**: none set by the editor itself; the input's rounded
  corners come from the shared field shell.
- **Padding**: root stack has 0.375rem gap between label, field row, and
  footnote; the prefix row has 0.25rem gap between the prefix text and
  the input. The input's own horizontal/vertical padding comes from the
  shared field shell.
- **Font**: the label uses a small, uppercase, wide-tracked monospace
  caption style (the shared caption typography role); the prefix text
  uses a small size in the muted-text color role, set directly by the
  editor. The input's text size and the footnote's font come from the
  shared field shell and footnote component respectively.
- **Background**: none set by the editor itself; the input's background
  comes from the shared field shell.
- **Foreground/Text**: label and prefix both use the muted-text color
  role, the prefix set directly by the editor. Input text color and
  hint/error footnote colors come from the shared field shell and
  footnote component.
- **Border**: none set by the editor itself; the input's border, focus
  ring, and invalid-state border/ring come from the shared field shell.
- **Shadow**: none — no shadow appears anywhere in the source.
- **Min/Max size**: the prefix text does not shrink, so the input
  absorbs remaining row width. The input's fixed height, full width, and
  minimum width come from the shared field shell. No maximum width is
  set by the editor.

## States

| State | Appearance change |
|-------|------------------|
| Default (no prefix) | Label + full-width input; no footnote |
| Prefix mode | Static, non-shrinking prefix text before the input |
| Hint shown | Footnote renders the hint, styled by the shared footnote component |
| Error shown | Footnote renders the error in place of the hint, styled by the footnote component; input is marked invalid, with its invalid border/ring supplied by the shared field shell |
| Focused | Input gains its focus ring, supplied by the shared field shell |
| Disabled | Input gains its disabled styling, supplied by the shared field shell |
| Pressed | Not applicable: a text input has no discrete pressed visual state — pointer-down produces focus, not a press. |
| Loading | Not applicable: the source contains no async operation or loading flag; the editor is a synchronous, controlled view. |

## Accessibility

- Role: a native label and text input pairing (no special input type is
  set, so it defaults to a plain text field).
- Label requirement: satisfied unconditionally — the label is a required
  input and is always rendered associated with the input's identifier
  (**renders-associated-label**).
- Announce state changes: the input's invalid state is toggled on when
  an error is set and is otherwise absent
  (**marks-input-invalid-on-error**, **omits-invalid-attribute-without-error**);
  the disabled state maps to the native disabled state, which assistive
  technology announces natively.
- **minimum-tap-target**: NEEDS REVIEW: Not implemented in source. The
  input's fixed height is 36px, with no minimum width enforced beyond
  filling its row; whether that meets or is exempt from a 44×44
  touch-target guideline requires measuring the rendered control against
  the platform's guideline (see the referenced platform-design-languages
  guidance) with the ecosystem's actual viewport/pointer usage in mind.
- Error announcement to assistive technology: not linked. The shared
  footnote component accepts an identifier specifically so a caller can
  point the field's description at the rendered error text, but the
  editor never supplies that identifier to the footnote nor forwards a
  description link to the input. A screen-reader user hears the invalid
  state but has no programmatic link to the error message itself
  (tracked as a pending Design Decision below).
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source.
  The prefix's muted-text color role on the field background resolves at
  runtime from the theme's semantic role variables; whether that pairing
  meets a minimum contrast ratio for small text cannot be determined
  from this component's source alone — it requires inspecting the
  resolved token values.
- Differentiate without color: satisfied — the invalid state is conveyed
  by the error text itself (**shows-error-in-place-of-hint** swaps in the
  error message, not just a color change) and by the invalid-state
  marker, not by border/ring color alone.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| rdid-editor-001 | renders-associated-label | label `"Name"`, input identifier `"leaf"` | A label reading `Name` renders, associated with the input; the input's identifier is `leaf` |
| rdid-editor-002 | generates-stable-input-id | no input identifier supplied | The rendered label's association target matches the rendered input's identifier (both non-empty) |
| rdid-editor-003 | renders-static-prefix | prefix `"persona.acme."`, value `"bob"` | Static text `persona.acme.` renders before the input; the input's value is `bob`, not `persona.acme.bob` |
| rdid-editor-004 | renders-single-input-without-prefix | prefix `""`, value `"my-org"` | No prefix element renders; a single full-width input shows value `my-org` |
| rdid-editor-005 | displays-controlled-value | value `"acme-2"` | The rendered input's value is exactly `acme-2` |
| rdid-editor-006 | lowercases-input-on-change | user types `ACME` into the input | The change is reported with value `acme` |
| rdid-editor-007 | forwards-placeholder | placeholder `"my-slug"` | The rendered input has placeholder text `my-slug` |
| rdid-editor-008 | shows-hint-below-input | hint `"Lowercase, hyphens only"`, error omitted | The footnote below the input reads `Lowercase, hyphens only` |
| rdid-editor-009 | shows-error-in-place-of-hint | hint `"Lowercase, hyphens only"`, error `"Required."` | The footnote below the input reads `Required.`, not the hint text |
| rdid-editor-010 | marks-input-invalid-on-error | error `"Required."` | The rendered input is marked invalid |
| rdid-editor-011 | omits-invalid-attribute-without-error | error omitted | The rendered input carries no invalid marker at all |
| rdid-editor-012 | disables-input-when-disabled | disabled `true` | The rendered input is in its disabled state and rejects typed input |
| rdid-editor-013 | supports-native-keyboard-input | component focused via keyboard navigation | The input receives focus and accepts typed characters with no custom key interception |
| rdid-editor-014 | generates-stable-input-id | no input identifier supplied; component re-rendered with a new value | The rendered input's generated identifier is identical before and after the re-render |
| rdid-editor-015 | shows-hint-below-input, shows-error-in-place-of-hint | hint and error both omitted | No footnote element renders below the input |

## Edge Cases

- **Empty value** (empty string): renders the input empty; this is an
  ordinary controlled-value state, not a special case in the source
  (MUST, per **displays-controlled-value**).
- **Empty prefix** (empty string): renders one full-width input with the
  whole rdid editable, per the component's own documentation ("an empty
  string renders a single full-width input") (MUST, per
  **renders-single-input-without-prefix**).
- **Boundary values (leaf length/character set)**: not enforced by this
  component. The editor does not import the rdid grammar's
  character-set pattern or length limit; it relies entirely on the
  caller-supplied error (typically derived externally from leaf
  validation) to signal an invalid or over-length leaf (MUST, per
  **shows-error-in-place-of-hint** — the component's only lever over
  invalid input is displaying what it is told).
- **Mixed-case paste**: pasting `ACME-Org` into the input fires the same
  change handling as typing, so the full pasted value is lowercased
  before the change is reported, not just newly typed characters (MUST,
  per **lowercases-input-on-change**).
- **Uppercase character typed mid-value**: typing an uppercase letter in
  the middle of an already-lowercase value (e.g. inserting `A` into
  `acme` to get `aAcme`) still lowercases the whole value on the same
  change event (per **lowercases-input-on-change**); because the
  resulting controlled value differs from what was just displayed, the
  input's displayed value is resynced on the next render and the caret
  moves to the end of the field rather than staying at the edit point.
- **Concurrent access**: not applicable — the editor is a stateless,
  purely controlled view. It holds no value state of its own and
  performs no I/O, so there is no shared state for concurrent renders or
  events to race on.
- **Error states (dependency/network failure)**: not applicable — the
  source makes no network or storage calls; its only "error" is the
  caller-supplied error input, which is a display concern already
  covered under Behavioral Requirements, not a failure of a dependency
  this component owns.
- **Offline/disconnected state**: not applicable — the component
  performs no network operation of its own.
- **Caller-supplied identifier collision**: if a caller passes an input
  identifier that collides with another element's identifier elsewhere
  on the page, the component does not detect or guard against it — no
  such check exists in the source. Avoiding collisions is the caller's
  responsibility.

## Configuration

This component's configuration inputs:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `label` | text/rich content | — (required) | Uppercase-mono caption above the control |
| `prefix` | string | — (required) | Fixed, inherited prefix shown as static text before the input (e.g. `app.my-eco.`); `""` edits the whole value |
| `value` | string | — (required) | The editable leaf when `prefix` is set, or the whole rdid when `prefix` is `""` |
| `onChange` | callback taking the next string | — (required) | Called with the lowercased next value |
| `placeholder` | string | none | Native input placeholder |
| `hint` | text/rich content | none | Footnote text shown when there is no `error` |
| `error` | text/rich content | none | Inline error, shown in the footnote in place of `hint` |
| `disabled` | boolean | none | Disables the input |
| `id` | string | generated automatically | Input identifier, and the target of the label's association |

## Deep Linking

Not applicable: the editor is an inline form field composed into a
caller's page — it has no route or navigable identity of its own, and the
source contains no routing or URL-handling code.

## Localization

Every piece of display text (`label`, `placeholder`, `hint`, `error`) is
supplied by the caller as an input; the component defines no string
literals of its own to key or translate.

The one text-processing operation the component performs itself —
**lowercases-input-on-change** — is a casing transform, and casing
transforms are locale-sensitive: the same character can lowercase
differently depending on locale (e.g. Turkish `İ`/`I`). Here that
locale-sensitivity is deliberately not honored: the value being
transformed is an rdid leaf, a machine-readable identifier the backend
re-parses with a fixed, locale-invariant grammar, not user-facing prose,
so it needs to lowercase identically no matter the editing user's
locale. A plain, locale-invariant lowercasing (as opposed to a
locale-aware one) already gives exactly that here, since it applies
Unicode's locale-independent default case folding.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the source contains no transition, animation, or motion of any kind — every state change (invalid marker, disabled, focus ring) is an instant state swap. |
| Increase Contrast | Not applicable to this component directly: contrast is governed entirely by the shared color/typography token theme used by the field shell and caption style; the editor implements no separate high-contrast behavior of its own (the open token-contrast question is tracked once, under Accessibility above). |
| Differentiate Without Color | Satisfied: the invalid state is carried by the error text itself (**shows-error-in-place-of-hint**) and by the invalid marker, not by a color change alone. |

## Feature Flags

Not applicable: the source contains no feature-flag reads. The editor
renders unconditionally whenever its caller mounts it.

## Analytics

Not applicable: the source contains no analytics or tracking calls.

## Privacy

- **Data collected**: None by this component. It holds no state of its
  own; the typed value lives in whatever state the caller's change
  handler writes it to.
- **Storage**: Not applicable — the editor performs no storage of its
  own.
- **Transmission**: Not applicable — the editor performs no network I/O
  of its own.
- **Retention**: Not applicable — no data is retained by this component.

## Logging

Not applicable: the source contains no logging calls of any kind (no
console output, no logger import).

## Platform Notes

- **React/Web**: Source at
  `packages/web/packages/adh-ui/src/components/rdid-editor.tsx`, exported
  as `RdidEditor` from `@agentic-toolkit/adh-ui`. Its props
  (`RdidEditorProps`): `label: React.ReactNode`, `prefix: string`,
  `value: string`, `onChange: (next: string) => void`,
  `placeholder?: string`, `hint?: React.ReactNode`,
  `error?: React.ReactNode`, `disabled?: boolean`, `id?: string`.
  Composes `Input` from `@agenticdevelopertoolkit/ui`
  (`external/agenticdevelopertoolkit/packages/web/packages/ui/src/components/input.tsx`)
  for the field shell and `FieldFootnote` from
  `@agenticdevelopertoolkit/ui` for the hint/error slot, plus
  `fieldCaptionClass` from `@agenticdevelopertoolkit/ui`'s typography
  module for the caption (**renders-associated-label** uses a native
  `<label htmlFor>` bound to the input's `id`, generated via
  `React.useId` when not supplied — **generates-stable-input-id**). The
  fixed prefix renders as an inert `<code>` element
  (**renders-static-prefix**); **lowercases-input-on-change** calls
  plain `.toLowerCase()` (not `.toLocaleLowerCase()`) on every change
  event. The invalid state is `aria-invalid="true"` set or omitted
  entirely (**marks-input-invalid-on-error**,
  **omits-invalid-attribute-without-error**); `FieldFootnote`'s
  `errorId` prop (for wiring `aria-describedby`) is never supplied (see
  Design Decisions). It never imports the rdid grammar (`prefixFor`,
  `validateLeaf`, `SEGMENT_RE`, `IDENTIFIER_MAX_LENGTH` from `rdid.ts`)
  itself — the caller supplies `prefix` and `error` already computed.
  Styling: root stack `gap-1.5`; prefix row `gap-1`; label
  `font-mono text-[0.7rem] uppercase tracking-wider text-apt-text-muted`
  (`fieldCaptionClass`); prefix `text-sm text-apt-text-muted shrink-0`;
  the input's `rounded-lg`, `px-3 py-2`, `bg-apt-bg`, height (`h-9`),
  `w-full`, `min-w-0`, border, focus ring, and invalid-state ring all
  come from the shared `Input` shell, which resolves its `apt-*` color
  tokens from the M3 role variables `AdhThemeStyle` injects.
- **SwiftUI**: Start from a `TextField` inside an `HStack` (for the
  prefix mode) or alone (for the no-prefix mode), since SwiftUI's
  `TextField` has no built-in leading-adornment slot — the fixed prefix
  has to be composed as a separate `Text` view, mirroring the web
  version's manual layout. Lowercasing has to be applied explicitly in
  the `onChange`/`.onChange(of:)` handler (SwiftUI does not lowercase
  input automatically); the caption becomes a `Text` styled to match
  the shared caption style's mono/uppercase/tracked look, and the
  hint/error footnote becomes a second `Text` below the field, switching
  its content and color the same way the shared footnote component
  does.
- **Compose**: Start from Material 3's `TextField`/`OutlinedTextField`,
  which — unlike the web version — has a native
  `prefix: @Composable (() -> Unit)?` slot, so the fixed prefix does not
  need a hand-built `Row`. Its `isError` parameter maps directly to
  whether an error is set, and its `supportingText` slot maps directly
  to the hint/error footnote (swap content the same way the shared
  footnote component does, rather than showing both). Lowercase the
  value inside `onValueChange` to match
  **lowercases-input-on-change**.
- **AppKit / UIKit**: Start from `NSTextField`/`UITextField`. Neither
  has a built-in prefix slot, so compose the fixed prefix as a sibling
  `NSTextField(labelWithString:)`/`UILabel` inside an
  `NSStackView`/`UIStackView`, the same manual-composition shape the web
  version uses. Lowercase the typed value inside the delegate callback
  (`controlTextDidChange`/`textField(_:shouldChangeCharactersIn:)`)
  before propagating it, and render the hint/error footnote as a
  separate label below the field whose text and color swap exactly as
  the shared footnote component's do.
- **WinUI 3**: Start from `TextBox`, which has a built-in `Header`
  property that can absorb the caption (`label`) instead of a separate
  label element, and a `PlaceholderText` property that maps directly to
  `placeholder`. WinUI 3's `TextBox` has no built-in leading-adornment
  slot (unlike Compose's `prefix` slot), so for the prefix mode, compose
  a `TextBlock` bound to `prefix` next to the `TextBox` inside a
  horizontal `StackPanel`, the same hand-built layout the web version
  uses. `TextBox`'s default control template only defines
  `Normal`/`PointerOver`/`Focused`/`Disabled`/`ReadOnly` visual states
  in its `CommonStates`/`FocusStates` groups — there is no built-in
  `Invalid` state equivalent to the web version's invalid-border
  behavior, so mark the invalid state with a bound
  `BorderBrush`/`BorderThickness` (or a custom `VisualState` added to an
  overridden `ControlTemplate`) rather than assuming one exists.
  `TextBox` has no per-field hint/error slot either, so render a
  `TextBlock` below it (e.g.
  `Foreground="{ThemeResource SystemFillColorCriticalBrush}"` when
  showing the error) whose text swaps between hint and error exactly as
  the shared footnote component does, and lowercase the value in the
  `TextChanged` handler to match **lowercases-input-on-change**.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/adh-ui/src/components/rdid-editor.tsx` |

## Design Decisions

- **Decision**: Render the fixed `<type>.<scope>.` prefix as inert static
  text rather than as an editable part of the input's value.
  **Rationale**: Mirrors the backend's own invariant that an rdid's type
  and inherited scope can never change after creation — the component's
  own doc comment states this explicitly — so the UI never offers an
  edit the backend would reject.
  **Approved**: pending
- **Decision**: Lowercase every keystroke inside the `onChange` handler,
  rather than leaving casing to the caller or flagging it only via
  `error`.
  **Rationale**: The rdid grammar (`SEGMENT_RE` in `rdid.ts`) only
  accepts lowercase segments; normalizing at input time keeps the
  `error` slot reserved for genuinely invalid characters or format
  rather than surprising the user with a case-mismatch error on an
  otherwise valid leaf.
  **Approved**: pending
- **Decision**: Share one footnote slot for `hint` and `error` (via
  `FieldFootnote`) instead of rendering both at once.
  **Rationale**: Matches `FieldFootnote`'s own designed precedence —
  error replaces hint, they are never shown together — so `RdidEditor`
  composes that component's contract rather than re-implementing or
  duplicating it.
  **Approved**: pending
- **Decision**: Leave `FieldFootnote`'s `errorId` unset, so the rendered
  error text is not linked to the input via `aria-describedby`.
  **Rationale**: `FieldFootnote` exposes `errorId` precisely so a caller
  can wire this link, but `RdidEditor` does not thread one through
  today; a screen-reader user hears `aria-invalid` on the input without
  a guaranteed programmatic path to the error text itself (see
  Accessibility).
  **Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |
| [touch-target-size](agenticdevelopercookbook://compliance/accessibility#touch-target-size) | partial | Accessibility |

`screen-reader-support` is partial because the input's label is
programmatically associated but the error text is never linked via
`errorId`/`aria-describedby`; `keyboard-navigable` passes because the source
attaches no custom key handlers to the native `<input>`; `contrast-ratio` and
`touch-target-size` are partial because the source authors color tokens and a
fixed `h-9` height without resolving them against an actual theme or measured
touch target.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: correct FieldFootnote's package attribution, deduplicate Appearance/States against the shared Input shell, correct the Input source path, align onChange/onInput naming, move the cookbook reference to related, use bare frontmatter dates, fix Design Decision approval formatting, rebuild Compliance against real catalog checks, add a stable-id re-render vector and a no-footnote vector, and document the mid-value lowercase caret jump |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to adh/hub/identifiers/. |
