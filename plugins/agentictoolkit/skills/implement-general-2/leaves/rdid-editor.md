<!-- leaf: implement-general-2/rdid-editor · source: rdid-editor.md -->

**Rules** (cite as `implement-general-2/rdid-editor#<slug>`):

- `renders-associated-label` MUST
- `generates-stable-input-id` MUST
- `renders-static-prefix` MUST
- `renders-single-input-without-prefix` MUST
- `displays-controlled-value` MUST
- `lowercases-input-on-change` MUST
- `forwards-placeholder` MUST
- `shows-hint-below-input` MUST
- `shows-error-in-place-of-hint` MUST
- `marks-input-invalid-on-error` MUST
- `omits-invalid-attribute-without-error` MUST
- `disables-input-when-disabled` MUST
- `supports-native-keyboard-input` MUST

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

## Privacy

- **Data collected**: None by this component. It holds no state of its own; the
  typed value lives in whatever state the caller's `onChange` writes it to.
- **Storage**: Not applicable — `RdidEditor` performs no storage of its own.
- **Transmission**: Not applicable — `RdidEditor` performs no network I/O of its
  own.
- **Retention**: Not applicable — no data is retained by this component.

