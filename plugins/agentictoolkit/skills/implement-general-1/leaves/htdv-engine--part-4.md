<!-- leaf: implement-general-1/htdv-engine--part-4 · source: htdv-engine.md -->

# HTDV Engine — continued (part 4)

**Rules** (cite as `implement-general-1/htdv-engine--part-4#<slug>`):

- `validator-is-pure` MUST
- `text-required-and-trims` MUST
- `text-pattern-is-whole-value-anchored` MUST
- `json-field-validates-text-then-parse` MUST
- `select-required-and-membership` MUST
- `number-required-bounds-and-integer` MUST
- `date-and-toggle-and-readonly` MUST
- `string-set-required` MUST
- `bound-message-uses-locale-aware-formatting` MUST
- `bound-formatting-does-not-trap-on-extreme-values` MUST
- `markdown-editing-contract` MUST
- `markdown-text-replacing-contract` MUST
- `plain-text-default-implementation` MUST
- `plain-text-editor-replace-also-notifies` MUST
- `plain-text-editor-forwards-live-edits` MUST
- `plain-text-editor-disables-smart-substitution` MUST
- `plain-text-uses-the-theme-code-font` MUST

### FormValidator.swift — field validation rules

- **validator-is-pure**: `FormValidator` MUST be a case-less `enum`
  (a namespace) whose sole public member, `validate(field:value:locale:)`,
  MUST be a pure function from a `FormField` and a `FormValue` to an
  optional user-facing message string, with `nil` meaning the value is
  acceptable; `locale` MUST default to `Locale.current`.
- **text-required-and-trims**: For `.text`, `.textArea`, and `.markdown`
  fields, validation MUST trim the value in `.whitespacesAndNewlines`
  before checking emptiness, and MUST return `"<label> is required"` if and
  only if the trimmed value is empty and the field's `isRequired` is
  `true`; an optional field with an empty or whitespace-only value MUST
  validate with no error.
- **text-pattern-is-whole-value-anchored**: When a `.text` field declares a
  non-`nil` `pattern` and the (untrimmed) value is non-empty, validation
  MUST match the pattern against the whole value by wrapping it as
  `^(?:<pattern>)$` before evaluating it as a regular expression — so a
  pattern that itself matches only a substring of the value MUST be
  rejected — and MUST return the field's `patternMessage` when set, or
  `"<label> has an invalid format"` otherwise, when the anchored match
  fails.
- **json-field-validates-text-then-parse**: For a `.json` field, validation
  MUST first apply the same required/trim check as `.text` fields with no
  pattern; if that passes and the trimmed value is non-empty, it MUST then
  attempt to parse the value as UTF-8 JSON via `JSONSerialization` with
  `.fragmentsAllowed`, and MUST return `"<label> must be valid JSON"` when
  parsing fails.
- **select-required-and-membership**: For a `.select` field, validation
  MUST return `"<label> is required"` when the value is empty/`nil` and
  `isRequired` is `true`, and otherwise, for a non-empty value, MUST return
  `"<label> must be one of the listed options"` unless the value equals
  some option's `value`.
- **number-required-bounds-and-integer**: For a `.number` field, validation
  MUST return `"<label> is required"` when the value is not a number and
  `isRequired` is `true`; for a present number, MUST return `"<label> must
  be a whole number"` when `isInteger` is `true` and the value is not equal
  to its own rounding; and MUST return a formatted "at least"/"at most"
  message when the value falls outside a declared `minimum`/`maximum`
  (inclusive bounds — a value exactly equal to `minimum` or `maximum` MUST
  pass).
- **date-and-toggle-and-readonly**: `.toggle` and `.readOnly` fields MUST
  always validate with no error; a `.date` field MUST return `"<label> is
  required"` when `isRequired` is `true` and the value's `dateValue` is
  `nil`, and MUST otherwise validate with no error.
- **string-set-required**: For a `.stringSet` field, validation MUST return
  `"<label> is required"` when `isRequired` is `true` and the value's
  `stringSetValue` (or `[]` when absent) is empty; validation performs no
  per-item check on the set's contents.
- **bound-message-uses-locale-aware-formatting**: The numeric bound quoted
  in a `.number` field's "at least"/"at most" message MUST be formatted with
  a decimal-style `NumberFormatter` configured with the supplied `locale`,
  no grouping separator, and up to 15 fraction digits — so a whole-number
  bound prints without a decimal point and a fractional bound renders using
  the locale's own decimal separator — falling back to `String(number)`
  only if the formatter itself returns `nil`.
- **bound-formatting-does-not-trap-on-extreme-values**: The bound-formatting
  helper MUST build a fresh `NumberFormatter` per call (not a cached
  `static let`, since `NumberFormatter` is not `Sendable`) and MUST format
  via `NumberFormatter`/`NSNumber` rather than `Int(_:)`, so a `maximum` or
  `minimum` far outside `Int`'s range (e.g. `1e19`) MUST NOT crash while the
  message that reports the violation is being built.

### MarkdownEditing.swift — markdown editor/viewer factory contract

- **markdown-editing-contract**: `MarkdownEditing` MUST be a `Sendable`
  protocol declaring two `@MainActor` factory methods:
  `makeEditor(initialText:onChange:) -> PlatformViewController`, whose
  `onChange` closure MUST be invoked with the current text on every edit,
  and `makeViewer(text:) -> PlatformViewController` for a read-only
  presentation of fixed text.
- **markdown-text-replacing-contract**: `MarkdownTextReplacing` MUST be a
  `@MainActor`, class-bound (`AnyObject`) protocol declaring
  `replaceText(with:)`, adopted by an editor produced by `makeEditor` so a
  caller — documented as Revert's use case — can push a restored value
  back into the live editor without knowing its concrete type.
- **plain-text-default-implementation**: `PlainTextMarkdownEditing` MUST be
  the default `MarkdownEditing` implementation, producing monospaced,
  unstyled plain-text editing with no markdown rendering; per the source's
  own doc comment, it is "adequate for configuration notes until the
  markdown module lands," and the hub app injects a richer implementation
  through `HubModules.markdownEditing` (a type not among this recipe's given
  sources).
- **plain-text-editor-replace-also-notifies**: On both AppKit and UIKit,
  `PlainTextEditorViewController.replaceText(with:)` MUST set the text
  view's text to the new value AND invoke the `onChange` closure with that
  same value, so a programmatic replacement (used by "revert") is
  observationally identical to the user typing it.
- **plain-text-editor-forwards-live-edits**: On AppKit,
  `NSTextViewDelegate.textDidChange(_:)` MUST invoke `onChange` with the
  text view's current `string`; on UIKit,
  `UITextViewDelegate.textViewDidChange(_:)` MUST invoke `onChange` with the
  text view's current `text` (or `""` when `nil`).
- **plain-text-editor-disables-smart-substitution**: `PlainTextEditorViewController`
  MUST disable automatic quote/dash substitution (AppKit:
  `isAutomaticQuoteSubstitutionEnabled`/`isAutomaticDashSubstitutionEnabled`;
  UIKit: `smartQuotesType`/`smartDashesType`) and autocorrection/
  autocapitalization (UIKit: `autocorrectionType`/`autocapitalizationType`),
  since markdown source text MUST NOT be silently rewritten by text-input
  conveniences meant for prose.
- **plain-text-uses-the-theme-code-font**: Both the editor and viewer MUST
  observe the ambient theme and set the text view's background, foreground,
  cursor/tint, and font from the palette's `code` role rather than the
  system default, per the source's own comment: "`code` is the theme's own
  monospaced role, so a plain-text markdown pane follows the selected theme's
  code font instead of the system's."

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `dataSource` (parameter to `HTDVController.init`) | `any HTDVDataSource` | none — required | The tree the controller navigates; the host supplies its own implementation. |
| `onChange` (property on `HTDVController`) | `(HTDVController) -> Void` | `{ _ in }` | Callback fired after every state transition; single-slot, not multicast. |
| `railWidth` (property on `HTDVLayoutEngine`) | `CGFloat` | `240` | Width budgeted per rail column when deciding how many fit. |
| `minDetailWidth` (property on `HTDVLayoutEngine`) | `CGFloat` | `480` | Width reserved for the detail pane, subtracted from `availableWidth` when `hasDetail` is `true`. |
| `sections`, `actions` (parameters to `FormSpec.init`) | `[FormSection]`, `FormActions` | none — required / `FormActions()` | The form's fields grouped into sections, and its save/delete/extra actions. |
| `values` (parameter to `FormState.init`) | `[String: FormValue]` | `[:]` | Initial field values; any field absent here falls back to its own `defaultValue`. |
| `requiresChanges` (property on `FormState`) | `Bool` | `true` | Whether `canSave` requires `isDirty`; a create dialog sets this to `false`. |
| `blockedReason` (property on `FormState`) | `String?` | `nil` | When non-`nil`, disables saving and is shown as the reason (e.g. a read-only member). |
| `onChange` (property on `FormState`) | `(FormState) -> Void` | `{ _ in }` | Callback fired after every state transition; single-slot, not multicast. |
| `locale` (parameter to `FormValidator.validate`) | `Locale` | `Locale.current` | Locale used to format numeric bounds quoted in validation messages. |
| `pattern`, `patternMessage` (fields on `FormTextField`) | `String?`, `String?` | `nil`, `nil` | An optional whole-value-anchored regular expression and its custom failure message. |
| `minimum`, `maximum`, `isInteger` (fields on `FormNumberField`) | `Double?`, `Double?`, `Bool` | `nil`, `nil`, `false` | Inclusive numeric bounds and whether a non-integral value is rejected. |

`ModelFitPolicy`-style settings-key constants do not appear in these
sources: none of the nine given files reads an environment variable or a
named settings key. `FormNumberField`, `FormTextField`, and the rest are
supplied programmatically by the caller building the `FormSpec`, not read
from a store.

## Localization

None of the nine given sources reference a string-key or localization
table; every user-facing string is a hardcoded English literal composed
inline:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal, no key) | `Nothing here yet` | `HTDVLevel.emptyMessage`'s default. |
| (none — literal, no key) | `This cannot be undone.` | `FormDeleteAction`'s documented fallback confirmation text when `confirmationText` is `nil` (the display of this text is not among the given sources). |
| (none — literal, no key) | `<label> is required` | `FormValidator` — required text, select, number, date, and string-set fields. |
| (none — literal, no key) | `<label> has an invalid format` | `FormValidator`'s default pattern-mismatch message. |
| (none — literal, no key) | `<label> must be one of the listed options` | `FormValidator`'s select-field membership check. |
| (none — literal, no key) | `<label> must be a whole number` | `FormValidator`'s integer check. |
| (none — literal, no key) | `<label> must be at least <value>` / `<label> must be at most <value>` | `FormValidator`'s numeric bounds check. |
| (none — literal, no key) | `<label> must be valid JSON` | `FormValidator`'s `.json` field parse check. |

