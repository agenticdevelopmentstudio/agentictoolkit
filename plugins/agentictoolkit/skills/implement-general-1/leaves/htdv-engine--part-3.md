<!-- leaf: implement-general-1/htdv-engine--part-3 · source: htdv-engine.md -->

# HTDV Engine — continued (part 3)

**Rules** (cite as `implement-general-1/htdv-engine--part-3#<slug>`):

- `compact-always-stacks` MUST
- `zero-levels-shape` MUST
- `rails-width-budget` MUST
- `rail-width-divisor-clamp` MUST
- `at-least-one-rail-when-levels-exist` MUST
- `fitting-count-is-floored-and-clamped` MUST
- `layout-is-pure` MUST
- `rail-width-init-precondition` MUST
- `form-spec-shape` MUST
- `field-kinds` MUST
- `field-key-and-label-projection` MUST
- `field-default-values` MUST
- `field-editability` MUST
- `action-shapes` MUST
- `form-value-shape` MUST
- `form-value-accessors` MUST
- `form-state-initial-values` MUST
- `duplicate-field-key-detection` MUST
- `is-dirty-derivation` MUST
- `can-save-derivation` MUST
- `set-validates-the-changed-field-only` MUST
- `validate-all-replaces-error-set` MUST
- `save-lifecycle` MUST
- `save-failure-preserves-dirty-state` MUST
- `revert-restores-baseline` MUST
- `mark-saved-rebaselines-without-performing` MUST
- `blocked-reason-disables-saving` MUST
- `requires-changes-toggle` MUST
- `concurrent-edit-during-save-stays-dirty` MUST
- `form-state-main-actor-confinement` MUST

### HTDVLayoutEngine.swift — rails-vs-stack layout decision

- **compact-always-stacks**: `layout(availableWidth:levelCount:hasDetail:isCompact:)`
  MUST return `.stack` whenever `isCompact` is `true`, regardless of
  `availableWidth`, `levelCount`, or `hasDetail`.
- **zero-levels-shape**: When `levelCount <= 0` and `isCompact` is `false`,
  `layout` MUST return `.columns(visibleRails: 0..<0, showsDetail:
  hasDetail)`.
- **rails-width-budget**: When `levelCount > 0` and `isCompact` is `false`,
  `layout` MUST subtract `minDetailWidth` from `availableWidth` only when
  `hasDetail` is `true` before dividing by the (clamped) `railWidth` to
  decide how many rails fit.
- **rail-width-divisor-clamp**: `layout` MUST clamp the effective rail width
  used as its division's divisor to a minimum of `1`
  (`max(railWidth, 1)`), so a caller who has set the public `railWidth` var
  to `0` or a negative value MUST NOT cause a division-by-zero or a trapping
  integer conversion.
- **at-least-one-rail-when-levels-exist**: When `levelCount > 0`, `layout`
  MUST return a `visibleRails` range containing at least `1` rail — the
  rightmost rails, `(levelCount - visible)..<levelCount` — even when the
  computed available width would otherwise fit zero.
- **fitting-count-is-floored-and-clamped**: `layout` MUST compute the number
  of rails that fit as `floor(availableRailsWidth / effectiveRailWidth)`,
  clamped into `0...levelCount` before any integer conversion, so that an
  infinite or extremely large `availableWidth` MUST produce
  `visibleRails` capped at `levelCount` rather than trapping on an
  out-of-range `Int` conversion.
- **layout-is-pure**: `layout` MUST hold no state of its own beyond the two
  `var` properties (`railWidth`, `minDetailWidth`) supplied at
  construction or mutated by the caller between calls, and MUST return a
  value computed solely from its four parameters and those two properties.
- **rail-width-init-precondition**: `HTDVLayoutEngine.init(railWidth:minDetailWidth:)`
  MUST `precondition(railWidth > 0)`, trapping at construction time if a
  non-positive `railWidth` is supplied there — a guarantee `rail-width-
  divisor-clamp` exists specifically because this precondition does not
  protect a later mutation of the public `railWidth` var.

### FormSpec.swift — declarative form shape

- **form-spec-shape**: `FormSpec` MUST be a `Sendable` struct exposing
  mutable `sections: [FormSection]` and `actions: FormActions`, whose
  `actions` defaults to `FormActions()`, and MUST expose `fields` as
  `sections.flatMap(\.fields)` in section-then-field display order.
- **field-kinds**: `FormField` MUST be a `Sendable` enum with exactly ten
  cases — `.text`, `.textArea`, `.toggle`, `.select`, `.number`, `.date`,
  `.stringSet`, `.readOnly`, `.markdown`, and `.json` — each wrapping a
  field-specific struct that carries at minimum a `key: String` and
  `label: String`.
- **field-key-and-label-projection**: `FormField.key` and `FormField.label`
  MUST forward to the wrapped field struct's own `key`/`label` for every
  case, with no case-specific transformation.
- **field-default-values**: `FormField.defaultValue` MUST return `.string("")`
  for `.text`, `.textArea`, `.markdown`, `.json`, and `.readOnly`; `.bool(false)`
  for `.toggle`; `.stringSet([])` for `.stringSet`; and `.null` for
  `.select`, `.number`, and `.date`.
- **field-editability**: `FormField.isEditable` MUST return `false` for
  `.readOnly` and `true` for every other case.
- **action-shapes**: `FormAction` MUST carry an `id: String`, `title:
  String`, `isDestructive: Bool` (defaulting to `false`), and a
  `perform: @Sendable ([String: FormValue]) async throws -> Void` closure
  that receives the current, already-validated values when it is the save
  action; `FormDeleteAction` MUST carry a `title: String`, an optional
  `confirmationText: String?`, and a non-parameterized, throwing
  `perform: @Sendable () async throws -> Void`; `FormActions` MUST group an
  optional `save: FormAction?`, an optional `delete: FormDeleteAction?`, and
  an `extra: [FormAction]` list, all defaulting to `nil`/`nil`/`[]`.

### FormValue.swift — field value type

- **form-value-shape**: `FormValue` MUST be a `Hashable`, `Sendable` enum
  with exactly six cases — `.string(String)`, `.bool(Bool)`,
  `.number(Double)`, `.date(Date)`, `.stringSet([String])`, and `.null` —
  one value type shared by every `FormField` case.
- **form-value-accessors**: `stringValue`, `boolValue`, `numberValue`,
  `dateValue`, and `stringSetValue` MUST each return the wrapped associated
  value when `self` is the matching case and `nil` for every other case
  (including `.null`); `isNull` MUST return `true` if and only if `self` is
  `.null`.

### FormState.swift — mutable form model and save lifecycle

- **form-state-initial-values**: `FormState.init(spec:values:)` MUST seed
  each field's initial value from the supplied `values` dictionary when
  present, and MUST otherwise use that field's `defaultValue`; the seeded
  dictionary MUST become both `values` and the dirty-tracking `baseline`.
- **duplicate-field-key-detection**: `FormState.duplicateFieldKeys(in:)` MUST
  return every field key that `FormSpec.fields` declares more than once,
  each key appearing exactly once in the result in first-seen order; `init`
  MUST call `assertionFailure` for each such key (a debug-build-only trap)
  and MUST otherwise continue constructing the instance with last-write-wins
  semantics for that key, per the source's own comment: "a shipped app
  keeps today's last-write-wins render rather than crashing on a form it
  could still mostly show."
- **is-dirty-derivation**: `isDirty` MUST be `true` if and only if `values !=
  baseline`; it MUST NOT be backed by its own stored flag.
- **can-save-derivation**: `canSave` MUST be `true` if and only if
  `spec.actions.save` is non-`nil`, `blockedReason` is `nil`, `isSaving` is
  `false`, and either `requiresChanges` is `false` or `isDirty` is `true`.
- **set-validates-the-changed-field-only**: `set(_:for:)` MUST no-op for a
  key not present in the spec's fields; for a known key it MUST store the
  value, MUST re-run `FormValidator.validate` for that single field and
  update `errors[key]` with the result (or clear it on `nil`), MUST clear
  `saveError`, and MUST fire `onChange`.
- **validate-all-replaces-error-set**: `validateAll()` MUST re-validate
  every field in the spec, MUST replace `errors` wholesale with exactly the
  fields that failed (dropping stale errors for fields that now pass), MUST
  fire `onChange`, and MUST return `true` if and only if no field failed.
- **save-lifecycle**: `save()` MUST return `false` without side effects when
  `spec.actions.save` is `nil`, `blockedReason` is non-`nil`, or `isSaving`
  is already `true`; otherwise it MUST call `validateAll()` and return
  `false` without invoking the save action when validation fails; on a
  validated save it MUST set `isSaving` to `true`, fire `onChange`, invoke
  the save action with a snapshot of `values`, and on success MUST adopt
  that snapshot as the new `baseline`, clear `isSaving`, fire `onChange`,
  and return `true`.
- **save-failure-preserves-dirty-state**: When the save action throws,
  `save()` MUST set `saveError` to `(error as? LocalizedError)?.errorDescription
  ?? String(describing: error)`, MUST clear `isSaving`, MUST fire
  `onChange`, MUST return `false`, and MUST NOT update `baseline` — so
  `isDirty` remains `true` and the caller's edits are not lost.
- **revert-restores-baseline**: `revert()` MUST reset `values` to `baseline`,
  clear `errors` and `saveError`, and fire `onChange`.
- **mark-saved-rebaselines-without-performing**: `markSaved()` MUST adopt the
  current `values` as the new `baseline` and fire `onChange`, without
  invoking `spec.actions.save` or any other action.
- **blocked-reason-disables-saving**: Setting `blockedReason` to a non-`nil`
  value MUST make `canSave` `false` regardless of dirtiness, and its
  property observer MUST fire `onChange` on every assignment (including
  reassigning the same value).
- **requires-changes-toggle**: `requiresChanges` MUST default to `true`
  (an edit form disables Save until something changes); setting it to
  `false` (a create dialog with nothing to change against) MUST make
  `canSave` depend only on `blockedReason == nil && !isSaving`, relying on
  `validateAll()` inside `save()` to reject an empty or invalid form
  instead.
- **concurrent-edit-during-save-stays-dirty**: A `set(_:for:)` call that
  lands while a `save()` is in flight MUST mutate `values` immediately
  (visible via `onChange`) without affecting the in-flight save's already-
  captured snapshot; when that save later succeeds, `baseline` MUST be set
  to the pre-edit snapshot it captured, not to the newer `values`, so the
  form MUST remain `isDirty` after the save completes.
- **form-state-main-actor-confinement**: `FormState` MUST be declared
  `@MainActor` and MUST NOT declare `Sendable` conformance of its own,
  confining every mutable property and method to the main actor's isolation
  domain.
- **delete-and-extra-actions-are-outside-the-save-lifecycle**: `FormState`
  exposes no method that invokes `spec.actions.delete` or any entry of
  `spec.actions.extra`, and tracks no `isDeleting`/`deleteError`-style state
  for them; per the type's own doc comment, `FormState` is "the save
  lifecycle" model specifically, and invoking delete/extra actions and
  displaying `FormDeleteAction.confirmationText` (or its documented
  `"This cannot be undone."` fallback) is the presentation layer's
  responsibility.

