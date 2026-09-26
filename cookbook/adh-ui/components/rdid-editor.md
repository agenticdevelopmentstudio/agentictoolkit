---
id: 071e67a8-54a7-4f8b-b747-e6384713efde
title: RdidEditor
domain: agentictoolkit://cookbook/adh-ui/components/rdid-editor
type: ingredient
version: 1.1.2
status: review
language: en
created: 2026-09-23
modified: '2026-09-25'
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

# RdidEditor

## Overview

`RdidEditor`, in `@agentic-toolkit/adh-ui` (`packages/web/packages/adh-ui/src/components/rdid-editor.tsx`),
is the one control for editing a type-prefixed rdid (`<type>.<scope>.<name>`).
An rdid's `type` and inherited `scope` are fixed at creation and can never change
afterward — the component's own doc comment states it mirrors "how the backend
rejects any type/scope change" — so it renders that fixed portion as inert
`<code>` text and exposes only the editable leaf segment as a real input. When
`prefix` is the empty string there is nothing fixed to protect (e.g. a brand-new,
unsaved draft, or a top-level rdid kind), so the whole value is edited as one
full-width input instead.

The component is backend-agnostic by design: it does not import or call
`@agentic-toolkit/adh-ui/rdid`'s `prefixFor` or `validateLeaf` itself. The caller
computes `prefix` (via `prefixFor`, typically fed by `rdidPrefix`/`parseRdid`) and
`error` (via `validateLeaf`) and passes them in as plain props, so `RdidEditor`
has no dependency on the rdid grammar's validation rules — only on displaying
whatever the caller decides.

It composes two lower-tier shared components rather than building its own field
shell: `Input` from `@agenticdevelopertoolkit/ui` (the shared form-control shell —
border, radius, focus/invalid styling) for the editable leaf, and `FieldFootnote`
from `@agenticdevelopertoolkit/ui` for the shared hint/error slot beneath it.
The caption above the control uses the shared `fieldCaptionClass` typography
token (an "uppercase-mono caption," per the component's own prop doc) rather than
a bespoke label style.

## Behavioral Requirements

- **renders-associated-label**: RdidEditor MUST render `label` inside a `<label>`
  element whose `htmlFor` matches the input's `id`.
- **generates-stable-input-id**: RdidEditor MUST use the caller-supplied `id` prop
  as the input's `id` when provided, and otherwise MUST generate one (via
  `React.useId`) so the label association always resolves to a real element.
- **renders-static-prefix**: WHEN `prefix` is a non-empty string, RdidEditor MUST
  render it as static, non-interactive `<code>` text immediately before the
  input, and MUST NOT include it in the input's editable value.
- **renders-single-input-without-prefix**: WHEN `prefix` is the empty string,
  RdidEditor MUST render one full-width input with no prefix element, so the
  entire value is editable.
- **displays-controlled-value**: RdidEditor MUST render the input's current value
  from the `value` prop (a controlled component; it holds no value state of its
  own).
- **lowercases-input-on-change**: On every input change event, RdidEditor MUST
  call `onChange` with the new value converted to lowercase.
- **forwards-placeholder**: WHEN `placeholder` is provided, RdidEditor MUST set
  it as the input's native placeholder text.
- **shows-hint-below-input**: WHEN `hint` is provided and `error` is not,
  RdidEditor MUST render `hint` in the footnote slot below the input.
- **shows-error-in-place-of-hint**: WHEN `error` is provided, RdidEditor MUST
  render `error` in the footnote slot below the input instead of `hint`.
- **marks-input-invalid-on-error**: WHEN `error` is provided, RdidEditor MUST set
  `aria-invalid="true"` on the input.
- **omits-invalid-attribute-without-error**: WHEN `error` is not provided,
  RdidEditor MUST NOT set an `aria-invalid` attribute on the input at all (not
  even `aria-invalid="false"`).
- **disables-input-when-disabled**: WHEN `disabled` is `true`, RdidEditor MUST
  render the input in a disabled state that rejects further edits.
- **supports-native-keyboard-input**: RdidEditor MUST accept text entry and full
  keyboard focus navigation through the browser's native `<input>` element; the
  source attaches no custom key handlers that would intercept or block native
  keyboard behavior.

## Appearance

RdidEditor sets its own styling only for the caption, the prefix `<code>`, and
the row/stack spacing; the field's corner radius, padding, colors, border, and
size all come from the shared `Input` shell (`fieldShellClass` plus `Input`'s
own classes) and the shared `FieldFootnote` component — see the Overview.

- **Corner radius**: none set by RdidEditor; the input's `rounded-lg` comes from
  the shared `Input` shell.
- **Padding**: root stack `gap-1.5` (0.375rem) between label, field row, and
  footnote; prefix row `gap-1` (0.25rem) between the `<code>` prefix and the
  input. The input's own `px-3 py-2` padding comes from the shared `Input`
  component.
- **Font**: label `font-mono text-[0.7rem] uppercase tracking-wider`
  (`fieldCaptionClass`); prefix `text-sm text-apt-text-muted`, set directly on
  the `<code>` element by RdidEditor. The input's text size and the footnote's
  font come from `Input` and `FieldFootnote` respectively.
- **Background**: none set by RdidEditor; the input's `bg-apt-bg` comes from the
  shared `Input` shell.
- **Foreground/Text**: label `text-apt-text-muted` (`fieldCaptionClass`); prefix
  `text-apt-text-muted`, set directly by RdidEditor. Input text color and
  hint/error footnote colors come from `Input` and `FieldFootnote`.
- **Border**: none set by RdidEditor; the input's border, focus ring, and
  invalid-state border/ring come from the shared `Input` shell.
- **Shadow**: none — no shadow utility appears anywhere in the source.
- **Min/Max size**: the prefix `<code>` is `shrink-0` so the input absorbs
  remaining row width. The input's fixed height, full width, and `min-w-0`
  come from the shared `Input` component. No maximum width is set by RdidEditor.

## States

| State | Appearance change |
|-------|------------------|
| Default (no prefix) | Label + full-width input; no footnote |
| Prefix mode | Static `<code>` prefix, `shrink-0`, before the input |
| Hint shown | Footnote renders `hint`, styled by the shared `FieldFootnote` component |
| Error shown | Footnote renders `error` in place of `hint`, styled by `FieldFootnote`; input gains `aria-invalid`, with its invalid border/ring supplied by the shared `Input` shell |
| Focused | Input gains its focus ring, supplied by the shared `Input` shell |
| Disabled | Input gains its disabled styling, supplied by the shared `Input` shell |
| Pressed | Not applicable: a text input has no discrete pressed visual state — pointer-down produces focus, not a press. |
| Loading | Not applicable: the source contains no async operation or loading flag; `RdidEditor` is a synchronous, controlled view. |

## Accessibility

- Role: native `<label>` + native `<input>` (no `type` is passed to `Input`, so
  it defaults to a plain text input).
- Label requirement: satisfied unconditionally — `label` is a required prop and
  is always rendered in a `<label htmlFor>` bound to the input's `id`
  (`renders-associated-label`).
- Announce state changes: `aria-invalid` is toggled to `"true"` when `error` is
  set and is otherwise absent (`marks-input-invalid-on-error`,
  `omits-invalid-attribute-without-error`); `disabled` maps to the native
  `disabled` attribute, which assistive technology announces natively.
- **minimum-tap-target**: NEEDS REVIEW: Not implemented in source. The input's fixed height is `h-9` (36px), with no minimum width enforced beyond `w-full`; whether that meets or is exempt from a 44×44 CSS-pixel touch-target guideline requires measuring the rendered control against the platform's guideline (see the `platform-design-languages` reference) with the ecosystem's actual viewport/pointer usage in mind.
- Error announcement to assistive technology: not linked. `FieldFootnote`
  accepts an `errorId` prop specifically so a caller can point the field's
  `aria-describedby` at the rendered error text, but `RdidEditor` never
  supplies `errorId` to `FieldFootnote` nor forwards `aria-describedby` to
  `Input`. A screen-reader user hears `aria-invalid` but has no programmatic
  link to the error message itself (tracked as a pending Design Decision
  below).
- **minimum-contrast-ratio**: NEEDS REVIEW: Not implemented in source. The prefix's `text-apt-text-muted` on `bg-apt-bg` resolves at runtime from the M3 role vars injected by `AdhThemeStyle` (per `Input`'s own comment); whether that pairing meets a minimum contrast ratio for small text cannot be determined from `rdid-editor.tsx` alone — it requires inspecting the resolved token values.
- Differentiate without color: satisfied — the invalid state is conveyed by the
  error text itself (`shows-error-in-place-of-hint` swaps in the `error`
  message, not just a color change) and by the `aria-invalid` attribute, not by
  border/ring color alone.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| rdid-editor-001 | renders-associated-label | `label="Name"`, `id="leaf"` | A `<label for="leaf">Name</label>` renders, and the input has `id="leaf"` |
| rdid-editor-002 | generates-stable-input-id | `id` omitted | The rendered `<label>`'s `for` attribute matches the rendered `<input>`'s `id` attribute (both non-empty) |
| rdid-editor-003 | renders-static-prefix | `prefix="persona.acme."`, `value="bob"` | Static text `persona.acme.` renders before the input; the input's value is `bob`, not `persona.acme.bob` |
| rdid-editor-004 | renders-single-input-without-prefix | `prefix=""`, `value="my-org"` | No prefix element renders; a single full-width input shows value `my-org` |
| rdid-editor-005 | displays-controlled-value | `value="acme-2"` | The rendered input's value is exactly `acme-2` |
| rdid-editor-006 | lowercases-input-on-change | User types `ACME` into the input | `onChange` is called with `"acme"` |
| rdid-editor-007 | forwards-placeholder | `placeholder="my-slug"` | The rendered input has `placeholder="my-slug"` |
| rdid-editor-008 | shows-hint-below-input | `hint="Lowercase, hyphens only"`, `error` omitted | The footnote below the input reads `Lowercase, hyphens only` |
| rdid-editor-009 | shows-error-in-place-of-hint | `hint="Lowercase, hyphens only"`, `error="Required."` | The footnote below the input reads `Required.`, not the hint text |
| rdid-editor-010 | marks-input-invalid-on-error | `error="Required."` | The rendered input has `aria-invalid="true"` |
| rdid-editor-011 | omits-invalid-attribute-without-error | `error` omitted | The rendered input has no `aria-invalid` attribute at all |
| rdid-editor-012 | disables-input-when-disabled | `disabled={true}` | The rendered input has the native `disabled` attribute and rejects typed input |
| rdid-editor-013 | supports-native-keyboard-input | Component focused via `Tab` | The input receives focus and accepts typed characters with no custom key interception |
| rdid-editor-014 | generates-stable-input-id | `id` omitted; component re-rendered with a new `value` | The rendered `<input>`'s generated `id` is identical before and after the re-render |
| rdid-editor-015 | shows-hint-below-input, shows-error-in-place-of-hint | `hint` and `error` both omitted | No footnote element renders below the input |

## Edge Cases

- **Empty `value`** (`value=""`): renders the input empty; this is an ordinary
  controlled-value state, not a special case in the source (MUST, per
  `displays-controlled-value`).
- **Empty `prefix`** (`prefix=""`): renders one full-width input with the whole
  rdid editable, per the component's own doc comment ("An empty string renders a
  single full-width input") (MUST, per `renders-single-input-without-prefix`).
- **Boundary values (leaf length/character set)**: not enforced by this
  component. `RdidEditor` imports neither `SEGMENT_RE` nor
  `IDENTIFIER_MAX_LENGTH` from `rdid.ts`; it relies entirely on the
  caller-supplied `error` (typically derived externally via `validateLeaf`) to
  signal an invalid or over-length leaf (MUST, per `shows-error-in-place-of-hint`
  — the component's only lever over invalid input is displaying what it is
  told).
- **Mixed-case paste**: pasting `ACME-Org` into the input fires the same
  `onChange` handler as typing, so the full pasted value is lowercased before
  `onChange` is called, not just newly typed characters (MUST, per
  `lowercases-input-on-change`).
- **Uppercase character typed mid-value**: typing an uppercase letter in the
  middle of an already-lowercase value (e.g. inserting `A` into `acme` to get
  `aAcme`) still lowercases the whole value on the same `onChange` event (per
  `lowercases-input-on-change`); because the resulting controlled value differs
  from what the browser just wrote into the DOM, React resyncs the input's DOM
  value on the next render and the caret moves to the end of the field rather
  than staying at the edit point.
- **Concurrent access**: not applicable — `RdidEditor` is a stateless, purely
  controlled view. It holds no value state of its own and performs no I/O, so
  there is no shared state for concurrent renders or events to race on.
- **Error states (dependency/network failure)**: not applicable — the source
  makes no network or storage calls; its only "error" is the caller-supplied
  `error` prop, which is a display concern already covered under Behavioral
  Requirements, not a failure of a dependency this component owns.
- **Offline/disconnected state**: not applicable — the component performs no
  network operation of its own.
- **Caller-supplied `id` collision**: if a caller passes an `id` that collides
  with another element's `id` elsewhere in the DOM, the component does not
  detect or guard against it — no such check exists in the source. Avoiding
  collisions is the caller's responsibility.

## Configuration

`@agentic-toolkit/adh-ui`'s `rdid-editor` component (`RdidEditor`):

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `label` | `React.ReactNode` | — (required) | Uppercase-mono caption above the control |
| `prefix` | `string` | — (required) | Fixed, inherited prefix shown as static `code` before the input (e.g. `app.my-eco.`); `""` edits the whole value |
| `value` | `string` | — (required) | The editable leaf when `prefix` is set, or the whole rdid when `prefix` is `""` |
| `onChange` | `(next: string) => void` | — (required) | Called with the lowercased next value |
| `placeholder` | `string` | `undefined` | Native input placeholder |
| `hint` | `React.ReactNode` | `undefined` | Footnote text shown when there is no `error` |
| `error` | `React.ReactNode` | `undefined` | Inline error, shown in the footnote in place of `hint` |
| `disabled` | `boolean` | `undefined` | Disables the input |
| `id` | `string` | generated via `React.useId` | Input `id`, and the target of the label's `htmlFor` |

```ts
export interface RdidEditorProps {
  label: React.ReactNode
  prefix: string
  value: string
  onChange: (next: string) => void
  placeholder?: string
  hint?: React.ReactNode
  error?: React.ReactNode
  disabled?: boolean
  id?: string
}
```

## Deep Linking

Not applicable: `RdidEditor` is an inline form field composed into a caller's
page — it has no route or navigable identity of its own, and the source
contains no routing or URL-handling code.

## Localization

Every piece of display text (`label`, `placeholder`, `hint`, `error`) is
supplied by the caller as a prop; the component defines no string literals of
its own to key or translate.

The one text-processing operation the component performs itself —
`lowercases-input-on-change`'s `.toLowerCase()` — is a casing transform, and
casing transforms are locale-sensitive: the same character can lowercase
differently depending on locale (e.g. Turkish `İ`/`I`). Here that
locale-sensitivity is deliberately not honored: the value being transformed is
an rdid leaf, a machine-readable identifier the backend re-parses with a fixed,
locale-invariant grammar (`SEGMENT_RE`), not user-facing prose, so it needs to
lowercase identically no matter the editing user's OS locale. Plain
`.toLowerCase()` (as opposed to `.toLocaleLowerCase()`) already gives exactly
that here, since it applies Unicode's locale-independent default case folding.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: the source contains no transition, animation, or motion of any kind — every state change (`aria-invalid`, `disabled`, focus ring) is an instant class/attribute swap. |
| Increase Contrast | Not applicable to this component directly: contrast is governed entirely by the shared `apt-*` token theme referenced by `Input` and `fieldCaptionClass`; `RdidEditor` implements no separate high-contrast behavior of its own (the open token-contrast question is tracked once, under Accessibility above). |
| Differentiate Without Color | Satisfied: the invalid state is carried by the error text itself (`shows-error-in-place-of-hint`) and by `aria-invalid`, not by a color change alone. |

## Feature Flags

Not applicable: the source contains no feature-flag reads. `RdidEditor` renders
unconditionally whenever its caller mounts it.

## Analytics

Not applicable: the source contains no analytics or tracking calls.

## Privacy

- **Data collected**: None by this component. It holds no state of its own; the
  typed value lives in whatever state the caller's `onChange` writes it to.
- **Storage**: Not applicable — `RdidEditor` performs no storage of its own.
- **Transmission**: Not applicable — `RdidEditor` performs no network I/O of its
  own.
- **Retention**: Not applicable — no data is retained by this component.

## Logging

Not applicable: the source contains no logging calls (no `console.*`, no logger
import).

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

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/adh-ui/src/components/rdid-editor.tsx` |

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
