---
id: faa2c3f3-1ff7-45fb-b6da-efed3cc1d451
title: HTDV Engine
domain: agentictoolkit://cookbook/htdv
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The non-UI logic behind AgenticToolkitHTDV: the rail/detail navigation state
  machine, the rails-vs-stack layout decision, the data model, and the declarative
  Forms subsystem.'
platforms:
- swift
- macos
- ios
tags:
- htdv
- engine
- navigation
- forms
- validation
depends-on: []
related: []
references:
- packages/apple/AgenticToolkit/HTDV/Controller/HTDVController.swift (agentictoolkit)
- packages/apple/AgenticToolkit/HTDV/Model/HTDVModel.swift (agentictoolkit)
- packages/apple/AgenticToolkit/HTDV/Model/HTDVCellContent.swift (agentictoolkit)
- packages/apple/AgenticToolkit/HTDV/Layout/HTDVLayoutEngine.swift (agentictoolkit)
- packages/apple/AgenticToolkit/HTDV/Forms/FormSpec.swift (agentictoolkit)
- packages/apple/AgenticToolkit/HTDV/Forms/FormValue.swift (agentictoolkit)
- packages/apple/AgenticToolkit/HTDV/Forms/FormState.swift (agentictoolkit)
- packages/apple/AgenticToolkit/HTDV/Forms/FormValidator.swift (agentictoolkit)
- packages/apple/AgenticToolkit/HTDV/Markdown/MarkdownEditing.swift (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitHTDVTests/HTDVControllerTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitHTDVTests/HTDVLayoutEngineTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitHTDVTests/HTDVModelTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitHTDVTests/FormStateTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitHTDVTests/FormValidatorTests.swift
  (agentictoolkit)
- packages/apple/AgenticToolkit/Tests/AgenticToolkitHTDVTests/PlainTextMarkdownEditingTests.swift
  (agentictoolkit)
- docs/htdv.md (agentictoolkit)
approved-by: ''
approved-date: ''
---

# HTDV Engine

## Overview

The HTDV engine is the non-UI logic that `AgenticToolkitHTDVViewController` and
`FormViewController` render: it owns no view and draws nothing. It is four
cooperating pieces, all under `packages/apple/AgenticToolkit/HTDV/`:

- **`HTDVController`** (`Controller/HTDVController.swift`) — the `@MainActor`
  navigation/selection/loading state machine that walks an `HTDVDataSource`
  tree one level at a time and exposes `levels`, `selection`, `detail`,
  `loadingLevelIndex`, and `error` to a host view.
- **The data model** (`Model/HTDVModel.swift`, `Model/HTDVCellContent.swift`)
  — `HTDVItem`, `HTDVLevel`, `HTDVDetail`, `HTDVChild`, `HTDVBadge`,
  `HTDVCreateAction`, the `HTDVDataSource` protocol the host implements, and
  `HTDVCellContent`, the platform-neutral row projection both the AppKit and
  UIKit rail cells render from.
- **`HTDVLayoutEngine`** (`Layout/HTDVLayoutEngine.swift`) — a pure function
  from available width, level count, and compactness to a rails-vs-stack
  layout `Mode`, called by both platform view controllers on resize.
- **The Forms subsystem** (`Forms/FormSpec.swift`, `Forms/FormValue.swift`,
  `Forms/FormState.swift`, `Forms/FormValidator.swift`) — the declarative
  shape of a detail form (`FormSpec`), its field value type (`FormValue`),
  its mutable, dirty-tracked, save-lifecycle model (`FormState`), and its
  per-field validation rules (`FormValidator`).

`MarkdownEditing.swift` (`Markdown/MarkdownEditing.swift`) is included because
it is the injectable factory contract the Forms subsystem's `markdown` field
kind depends on (per `docs/htdv.md`'s Concepts table: "`markdown` (rendered
via `MarkdownEditing`)"); its default, `PlainTextMarkdownEditing`, is itself
logic (`String` in, `String` out via a callback) even though the concrete
`PlainTextEditorViewController`/`PlainTextViewerViewController` it vends are
platform view controllers — see Design Decisions.

`AgenticToolkitHTDVViewController` (macOS/iOS) and `FormViewController`
(macOS/iOS) are the presentation layer that consumes this engine; they are
out of this recipe's given sources and are not described here except where a
doc comment in a given source states what the presentation layer is
responsible for.

## Behavioral Requirements

### HTDVModel.swift — data model and data source contract

- **item-shape**: `HTDVItem` MUST be an `Identifiable`, `Hashable`,
  `Sendable` struct exposing immutable `id: String`, `label: String`,
  `sublabel: String?`, `systemImage: String?`, `dividerAfter: Bool`,
  `leadsTo: HTDVLeadsTo`, and `badge: HTDVBadge?`, constructible only through
  its public `init`, whose `dividerAfter` defaults to `false`, `leadsTo`
  defaults to `.list`, and `sublabel`/`systemImage`/`badge` default to `nil`.
- **level-shape**: `HTDVLevel` MUST be an `Identifiable`, `Sendable` struct
  exposing immutable `id: String`, `title: String`, `items: [HTDVItem]`,
  `emptyMessage: String`, and `createAction: HTDVCreateAction?`, whose
  `emptyMessage` defaults to the literal `"Nothing here yet"` and whose
  `createAction` defaults to `nil`.
- **detail-shape**: `HTDVDetail` MUST be a `Sendable` struct exposing
  immutable `id: String`, `title: String`, and a `make: @MainActor @Sendable
  () -> PlatformViewController` factory, constructible only through its
  public `init`.
- **child-shape**: `HTDVChild` MUST be a `Sendable` enum with exactly three
  cases — `.level(HTDVLevel)`, `.detail(HTDVDetail)`, and `.empty` — the
  three possible answers to "what lies beneath a selected path."
- **leads-to-shape**: `HTDVLeadsTo` MUST be a `Sendable`, `Hashable` enum with
  exactly two cases, `.list` and `.detail`, naming what selecting an item
  reveals to its right.
- **badge-shape**: `HTDVBadge` MUST be a `Sendable`, `Hashable` enum with
  exactly two cases, `.dot(HTDVBadgeColor)` and `.count(Int)`.
- **badge-color-theme-role**: `HTDVBadgeColor.themeRole` MUST map `.red` to
  `.danger`, `.green` to `.success`, `.blue` to `.accent`, `.gray` to
  `.secondaryText`, and both `.orange` and `.yellow` to `.warning` — the two
  names collapsing onto one role because, per the source's own comment, "the
  palette has no separate orange."
- **create-action-shape**: `HTDVCreateAction` MUST be a `Sendable` struct
  exposing an immutable `title: String` and a `perform: @MainActor @Sendable
  (PlatformViewController) async -> Void` closure that receives the hosting
  view controller so it can present its own UI.
- **data-source-contract**: `HTDVDataSource` MUST be a `Sendable`,
  `AnyObject`-constrained protocol declaring `func rootLevel() async throws
  -> HTDVLevel` and `func child(for path: [HTDVItem]) async throws ->
  HTDVChild`; per its own doc comment, implementations are typically actors
  or `@unchecked Sendable` classes wrapping a client.
- **platform-view-controller-alias**: `PlatformViewController` MUST resolve
  to `NSViewController` when `AppKit` is importable and the build is not
  Mac Catalyst, and to `UIViewController` when `UIKit` is importable, so
  every closure in this file that vends or receives a view controller
  (`HTDVDetail.make`, `HTDVCreateAction.perform`) is typed identically on
  both platforms.

### HTDVCellContent.swift — rail-row projection

- **cell-content-projection**: `HTDVCellContent.init(item:)` MUST copy
  `label`, `sublabel`, `systemImage`, and `badge` from the given `HTDVItem`
  unchanged, and MUST set `isDisclosing` to `true` if and only if
  `item.leadsTo == .list`.
- **cell-content-equality**: `HTDVCellContent` MUST be `Hashable` and
  `Sendable` so a rail's diffable data source can key rows by it and pass it
  across the `@MainActor` boundary to the view layer.

### HTDVController.swift — navigation, selection, and loading state machine

- **initial-state**: A newly constructed `HTDVController` MUST have empty
  `levels`, empty `selection`, a `nil` `detail`, a `nil`
  `loadingLevelIndex`, and a `nil` `error`.
- **is-loading-derivation**: `isLoading` MUST be `true` if and only if
  `loadingLevelIndex` is non-`nil`; it MUST NOT be backed by its own stored
  flag.
- **load-resets-then-fetches**: `load()` MUST clear `levels`, `selection`,
  `detail`, `error`, and `failedRequest` before fetching, MUST call
  `dataSource.rootLevel()`, and on success MUST set `levels` to the single
  returned root level.
- **select-validates-membership**: `select(itemID:atLevel:)` MUST no-op
  (leaving `levels`, `selection`, `detail`, and `error` unchanged) unless
  `levelIndex` is a valid index into `levels` and `itemID` names an item
  present in `levels[levelIndex].items`.
- **select-truncates-then-fetches**: On a valid `itemID`, `select` MUST
  first truncate `levels` to `levelIndex + 1` entries and `selection` to
  `levelIndex` entries plus the newly selected `itemID`, clear `detail` and
  `error`, and only then call `dataSource.child(for: selectedPath())`.
- **select-applies-whatever-child-returns**: On success, `select` MUST apply
  the returned `HTDVChild` via `apply(_:)` — appending a `.level` to
  `levels`, replacing `detail` with a `.detail`, or doing nothing for
  `.empty` — regardless of whether the selected item's own `leadsTo` was
  `.list` or `.detail`; the controller does not validate agreement between
  `HTDVItem.leadsTo` and the `HTDVChild` the data source actually returns for
  it.
- **reload-root-vs-nested**: `reload(level:)` MUST call
  `dataSource.rootLevel()` when `levelIndex == 0`, and for `levelIndex > 0`
  MUST call `dataSource.child(for:)` with the path truncated to the parent
  of `levelIndex` and require the result to be `.level`; a valid `levelIndex`
  that is out of bounds for the current `levels` MUST make `reload` no-op.
- **reload-preserves-or-drops-selection**: When a nested `reload` succeeds
  with a `.level`, `reload` MUST replace `levels[levelIndex]` with the fresh
  level and MUST preserve the current selection at that level if the
  selected item's `id` still appears in the fresh level's `items`, and MUST
  otherwise truncate `levels`, `selection`, and `detail` from `levelIndex`
  onward.
- **reload-parent-became-non-level**: When a nested `reload`'s parent lookup
  (`dataSource.child(for:)` on the parent path) returns `.detail` or
  `.empty` instead of the expected `.level`, `reload` MUST drop `levels` and
  `selection` from `levelIndex` onward, clear `detail`, and apply whatever
  `HTDVChild` was actually returned (a `.detail` is shown; `.empty` shows
  nothing) rather than discarding it, per the source's own comment: "a
  `.detail` is real content the caller handed us, and throwing it away would
  show the user nothing at all."
- **retry-reissues-exact-failed-operation**: `retry()` MUST no-op unless
  `error` is non-`nil` and a `failedRequest` was recorded, and when both are
  present MUST re-invoke exactly the operation that failed — `load()` for a
  failed root load, `select(itemID:atLevel:)` with the same arguments for a
  failed selection, or `reload(level:)` with the same level for a failed
  reload.
- **stale-response-dropped**: Every fetch MUST capture the `generation`
  counter's value at the moment it began (via `beginRequest`, which
  increments `generation` first); on completion — success or failure — the
  controller MUST discard the result and make no state change whenever the
  captured generation no longer equals the current `generation`, because a
  newer request (or a `popToLevel`/`clearDetail` call) started in the
  interim.
- **error-shape**: On a thrown error, `fail(gen:levelIndex:_:request:)` MUST
  set `error` to an `HTDVLoadError` carrying the failing `levelIndex` and a
  `message` derived from `(error as? LocalizedError)?.errorDescription ??
  String(describing: error)`, MUST record the `failedRequest` so `retry()`
  can reissue it, and MUST clear `loadingLevelIndex` — unless the failure is
  itself stale (see stale-response-dropped), in which case none of this MUST
  happen.
- **pop-to-level-contract**: `popToLevel(_:)` MUST no-op when `levelIndex <
  -1` or `levelIndex >= levels.count - 1`; otherwise it MUST bump
  `generation` (discarding any in-flight deeper load), truncate `levels` to
  `levelIndex + 1` entries (or to zero entries when `levelIndex == -1`),
  truncate `selection` to `max(0, levelIndex)` entries, clear `detail`,
  clear `error` and `failedRequest`, clear `loadingLevelIndex`, and fire
  `onChange` exactly once.
- **clear-detail-contract**: `clearDetail()` MUST no-op when `detail` is
  already `nil`; otherwise it MUST bump `generation` (discarding any
  in-flight detail load), clear `detail`, `error`, `failedRequest`, and
  `loadingLevelIndex`, leave `levels` and `selection` untouched, and fire
  `onChange` exactly once.
- **on-change-fires-after-every-transition**: `onChange` MUST be invoked
  after every state transition made by `load`, `select`, `reload`,
  `popToLevel`, and `clearDetail` — including the loading-started transition
  at the start of a fetch (`beginRequest` calls `onChange` before the
  `await`) — and MUST default to a no-op closure (`{ _ in }`) until a host
  assigns one.
- **single-observer-callback**: `onChange` MUST be a single-slot property,
  not a multicast; assigning it a second time MUST silently replace the
  first observer with no diagnostic, per `docs/htdv.md`'s "One host per
  controller" note — each `HTDVController` MUST be driven by exactly one
  host.
- **main-actor-confinement**: `HTDVController` MUST be declared
  `@MainActor` and MUST NOT declare `Sendable` conformance of its own; every
  one of its mutable properties and methods is therefore confined to the
  main actor's isolation domain, and a caller on a different isolation
  domain MUST hop to the main actor (`await`) to read or mutate it.
- **selected-path-and-item-queries**: `selectedPath()` MUST return the
  `HTDVItem` at each selected id in `selection`, skipping (via
  `compactMap`) any level/id pair that no longer resolves — for example
  after a level was replaced by `reload` — and `selectedItem(atLevel:)` MUST
  return `nil` when `levelIndex` is out of bounds for `selection` or for
  `levels`.

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

## Appearance

Not applicable — this is the HTDV navigation, layout, and forms logic, not a
visual component.

## States

Not applicable — this is the HTDV navigation, layout, and forms logic, not a
visual component. The runtime state machines it does own —
`HTDVController`'s idle/loading/loaded/error cycle and `FormState`'s
clean/dirty/saving/save-failed cycle — are captured as requirements above
(`is-loading-derivation`, `error-shape`, `is-dirty-derivation`,
`save-lifecycle`, `save-failure-preserves-dirty-state`), not in a visual-state
table.

## Accessibility

Not applicable — this is the HTDV navigation, layout, and forms logic, not a
visual component. `HTDVController`, `HTDVLayoutEngine`, `FormState`, and
`FormValidator` produce no view, role, trait, or label of their own; any
accessibility surface belongs to the presentation layer that renders their
output (out of this recipe's given sources).

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| htdv-engine-001 | load-resets-then-fetches | `controller.load()` against a data source whose `rootLevel()` returns a level with one item (`HTDVControllerTests.testLoadPopulatesRootLevel`). | `levels == [root]`, `selection == []`, `detail == nil`, `error == nil`. |
| htdv-engine-002 | select-truncates-then-fetches, select-applies-whatever-child-returns | `controller.select(itemID: "list-item", atLevel: 0)` where `child(for:)` returns `.level(childLevel)` (`testSelectListItemAppendsLevel`). | `levels == [root, childLevel]`, `selection == ["list-item"]`. |
| htdv-engine-003 | select-applies-whatever-child-returns | `controller.select(itemID: "detail-item", atLevel: 0)` where `child(for:)` returns `.detail(someDetail)` (`testSelectDetailItemSetsDetail`). | `detail?.id == someDetail.id`, `levels` unchanged in count (no new rail appended). |
| htdv-engine-004 | select-validates-membership | `controller.select(itemID: "not-in-level", atLevel: 0)` (`testSelectUnknownItemIsIgnored`). | `levels`, `selection`, `detail`, and `error` are all unchanged from before the call. |
| htdv-engine-005 | select-truncates-then-fetches | `controller.select(itemID:, atLevel: 0)` again after a deeper level/detail is already loaded (`testSelectingAtShallowerLevelTruncatesDeeperLevels`). | `levels` is truncated to one entry before the new fetch is applied; the previously loaded deeper level is gone. |
| htdv-engine-006 | reload-preserves-or-drops-selection | `controller.reload(level: n)` where the fresh level still contains the currently selected item's id (`testReloadKeepsSelectionWhenItemStillExists`). | `levels[n]` is replaced with the fresh level; `selection[n]` is unchanged. |
| htdv-engine-007 | reload-preserves-or-drops-selection | `controller.reload(level: n)` where the fresh level no longer contains the selected id (`testReloadDropsSelectionWhenItemDisappeared`). | `selection`, `levels`, and `detail` are truncated from `n` onward. |
| htdv-engine-008 | reload-parent-became-non-level | `controller.reload(level: n)` (`n > 0`) where the parent path's `child(for:)` now returns `.detail` instead of `.level` (`testReloadAppliesDetailReturnedWhereLevelWasExpected`). | `levels`/`selection` truncated to before `n`; `detail` is set to the returned `.detail` rather than left `nil`. |
| htdv-engine-009 | error-shape, retry-reissues-exact-failed-operation | `controller.load()` fails, then `controller.retry()` is called against a data source that now succeeds (`testErrorSurfacesAndRetryRecovers`, `testRootErrorRetryReloadsRoot`). | After the failure, `error != nil` and `failedRequest` records `.load`; after `retry()`, `error == nil` and `levels` reflects the successful root load. |
| htdv-engine-010 | stale-response-dropped | `controller.select(itemID: a, atLevel: 0)` starts, then `controller.select(itemID: b, atLevel: 0)` starts before the first resolves; the first's `child(for:)` call then resolves (`testStaleResultIsDropped`). | The first (stale) result is discarded; `levels`/`selection`/`detail` reflect only the second selection's outcome. |
| htdv-engine-011 | pop-to-level-contract | `controller.popToLevel(1)` on a controller with 3 loaded levels and a `detail` set (`testPopToLevelTruncatesLevelsAndSelection`, `testPopToLevelClearsDetailAndError`). | `levels.count == 2`, `selection.count == 1`, `detail == nil`, `error == nil`. |
| htdv-engine-012 | pop-to-level-contract | `controller.popToLevel(-1)` on any non-empty controller (`testPopToLevelNegativeOneClearsEverything`). | `levels == []`, `selection == []`, `detail == nil`. |
| htdv-engine-013 | pop-to-level-contract | `controller.popToLevel(levels.count - 1)` (at current depth) or `controller.popToLevel(-2)` (below `-1`) (`testPopToLevelNoOpsWhenAtOrBeyondCurrentDepth`, `testPopToLevelBelowNegativeOneIsNoOp`). | No-op: `levels`, `selection`, `detail`, and `error` are all unchanged. |
| htdv-engine-014 | clear-detail-contract | `controller.clearDetail()` while `detail` is set (`testClearDetailClearsDetailAndFiresOnChangeOnce`, `testClearDetailLeavesLevelsAndSelectionUntouched`). | `detail == nil`; `levels` and `selection` are byte-for-byte unchanged; `onChange` fires exactly once. |
| htdv-engine-015 | can-save-derivation, save-lifecycle | `FormState(spec:)` with a `save` action, then `state.set(validValue, for: requiredKey)` followed by `state.save()` (`testSuccessfulSavePerformsAndRebaselines`). | `save()` returns `true`; `baseline == values`; `isDirty == false` afterward. |
| htdv-engine-016 | save-lifecycle | `state.save()` while a required field is still empty (`testSaveWithInvalidValuesDoesNotPerform`). | `save()` returns `false`; the save action's `perform` closure is never invoked; `errors` is populated for the invalid field. |
| htdv-engine-017 | save-failure-preserves-dirty-state | `state.set(value, for: key)` then `state.save()` where the save action throws (`testFailedSaveKeepsDirtyAndReportsError`). | `save()` returns `false`; `saveError != nil`; `isDirty == true` (baseline not updated). |
| htdv-engine-018 | concurrent-edit-during-save-stays-dirty | `state.save()` is started (not yet resolved) and, before it resolves, `state.set(newValue, for: key)` is called; the save then succeeds (`testConcurrentEditDuringSaveSurvivesAndStaysDirty`). | After the save resolves, `values[key] == newValue` but `isDirty == true`, because `baseline` was set from the snapshot taken before the concurrent edit. |
| htdv-engine-019 | duplicate-field-key-detection | `FormState.duplicateFieldKeys(in:)` on a spec whose sections repeat the key `"name"` across two sections and repeat `"email"` within one section (`testDuplicateFieldKeysAcrossSectionsAreDetected`, `testDuplicateFieldKeysReportsEachKeyOnceInFirstSeenOrder`). | Returns `["name", "email"]` — each duplicated key exactly once, in first-seen order. |
| htdv-engine-020 | text-pattern-is-whole-value-anchored | `FormValidator.validate` on a `.text` field with `pattern: "[a-z]+"` and value `"My Slug!! (draft)"` (`testUnanchoredPatternRejectsValueWithOnlyAnEmbeddedMatch`). | Returns a non-`nil` format-error message, because the whole value does not match `^(?:[a-z]+)$` even though `"raft"` inside it does. |
| htdv-engine-021 | number-required-bounds-and-integer | `FormValidator.validate` on a `.number` field with `minimum: 2`, `maximum: 10` for values `1`, `2`, `10`, and `11` (`testNumberBoundsAndInteger`). | `1` and `11` return a bounds-violation message; `2` and `10` (the inclusive boundaries) return `nil`. |
| htdv-engine-022 | bound-formatting-does-not-trap-on-extreme-values | `FormValidator.validate` on a `.number` field with `maximum: 1e19` and a value above it (`testOutOfIntRangeBoundFormatsInsteadOfTrapping`). | Returns a bounds-violation message containing the formatted bound, with no crash. |
| htdv-engine-023 | bound-message-uses-locale-aware-formatting | `FormValidator.validate` on a `.number` field with a fractional `minimum` under a `de_DE`-style locale, for a value below it (`testBoundFormattingFollowsTheSuppliedLocale`). | The returned message quotes the bound using that locale's decimal separator (e.g. a comma). |
| htdv-engine-024 | rail-width-divisor-clamp | `HTDVLayoutEngine(railWidth: 240).layout(availableWidth: 800, levelCount: 3, hasDetail: false, isCompact: false)` after mutating `railWidth = 0` on the instance (`testZeroRailWidthDividesByOnePointInstead`). | Returns a `.columns` mode with `visibleRails` computed against a divisor of `1`, not a crash. |
| htdv-engine-025 | fitting-count-is-floored-and-clamped | `layout(availableWidth: .infinity, levelCount: 5, hasDetail: false, isCompact: false)` (`testInfiniteAvailableWidthShowsEveryRailInsteadOfTrapping`). | Returns `.columns(visibleRails: 0..<5, showsDetail: false)` — capped at `levelCount`, not a trapping `Int` conversion. |
| htdv-engine-026 | compact-always-stacks | `layout(availableWidth: 2000, levelCount: 5, hasDetail: true, isCompact: true)` (`testCompactAlwaysStacks`). | Returns `.stack`. |
| htdv-engine-027 | cell-content-projection | `HTDVCellContent(item:)` for an item with `leadsTo: .list` and one with `leadsTo: .detail` (`testCellContentFromListItem`, `testCellContentFromDetailItemIsNotDisclosing`). | `isDisclosing == true` for the `.list` item; `isDisclosing == false` for the `.detail` item. |

## Edge Cases

- **Null and empty input**: `HTDVController.select(itemID:atLevel:)` MUST
  no-op on an `itemID` absent from the given level's items (MUST, see
  `select-validates-membership`). `FormState.set(_:for:)` MUST no-op on a
  `key` absent from the spec's fields (MUST, `testSetUnknownKeyIsIgnored`).
  A required `.text`/`.textArea`/`.markdown` field with an empty or
  whitespace-only value MUST fail validation with an "is required" message;
  the same field, when optional, MUST pass with `nil` (MUST, see
  `text-required-and-trims`). An empty `.stringSet` MUST fail validation
  only when `isRequired` is `true` (MUST, see `string-set-required`).
- **Boundary values**: A number field's value exactly equal to `minimum` or
  `maximum` MUST pass validation — the comparisons are strict `<`/`>`, not
  `<=`/`>=` (MUST, see `number-required-bounds-and-integer`,
  `testNumberBoundsAndInteger`). `HTDVLayoutEngine.layout` with
  `levelCount == 0` MUST return an empty `visibleRails` range, while any
  `levelCount > 0` MUST return at least one visible rail (MUST, see
  `zero-levels-shape`, `at-least-one-rail-when-levels-exist`). A `railWidth`
  of `0` or negative (settable after construction despite the `init`
  precondition) MUST be clamped to a divisor of at least `1` rather than
  dividing by zero or a negative number (MUST, see
  `rail-width-divisor-clamp`). `HTDVController.popToLevel(_:)` MUST treat
  `-1` as "clear everything" and anything below `-1`, or at/above the
  current depth, as a no-op (MUST, see `pop-to-level-contract`).
- **Concurrent access**: `HTDVController` and `FormState` are each
  `@MainActor`-confined with no `Sendable` conformance of their own, so all
  of their mutable state is serialized onto the main actor and cannot be
  touched concurrently from another isolation domain without an `await` hop
  (MUST, see `main-actor-confinement`, `form-state-main-actor-confinement`).
  Overlapping asynchronous fetches on the same `HTDVController` (a second
  `select`/`reload`/`load` starting before an earlier one resolves) are not
  prevented outright; instead, each fetch's result is validated against the
  `generation` counter captured when it began, and a result whose
  generation is stale is silently dropped rather than applied out of order
  (MUST, see `stale-response-dropped`, `testStaleResultIsDropped`). A
  `set(_:for:)` call landing on `FormState` while its own `save()` is
  in flight is not blocked; it mutates `values` immediately, and the
  in-flight save's already-captured value snapshot is unaffected, which
  MUST leave the form dirty even after that save later succeeds (MUST, see
  `concurrent-edit-during-save-stays-dirty`).
- **Error states**: A thrown error from `HTDVDataSource.rootLevel()` or
  `.child(for:)` MUST populate `HTDVController.error` with the failing
  level index and a message derived from the error (or MUST be dropped
  silently if a newer request has since started) — it is never left
  unreported to a still-current caller (MUST, see `error-shape`). A thrown
  error from a `FormAction.perform` (the save action) MUST populate
  `FormState.saveError` with a derived message and MUST leave `isDirty ==
  true` (MUST, see `save-failure-preserves-dirty-state`). `HTDVCreateAction.perform`
  and `FormDeleteAction.perform`/`FormActions.extra` entries have no
  channel of their own for the engine to observe or record a failure — see
  **create-action-error-path** below and
  `delete-and-extra-actions-are-outside-the-save-lifecycle`.
- **Offline or disconnected state**: None of the nine given sources make a
  network call directly; `HTDVDataSource.rootLevel()`/`.child(for:)` are
  the only points where a network-backed implementation could fail, and
  that failure surfaces to `HTDVController` exactly like any other thrown
  error (see Error states above) — the engine defines no timeout, retry, or
  connectivity-aware behavior of its own around those calls (fact, not a
  gap: an absent feature, not a swallowed signal — the failure is not lost,
  it is reported as `error`, just without a time bound).

- **create-action-error-path**: `HTDVCreateAction.perform` is declared `@MainActor @Sendable (PlatformViewController) async -> Void` — non-throwing, with no return value — so the engine defines no path for a creation failure to reach `HTDVController.error` or trigger a `reload`. The signature makes it the closure's precondition to present and recover from its own failures without engine involvement.

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

## Deep Linking

Not applicable: none of the nine given sources define a URL scheme, route,
or navigation destination. `HTDVController`'s navigation (`levels`,
`selection`) is in-memory rail/detail state, not app-level deep linking; a
host that wants a deep link into a specific `HTDVItem` path would build one
on top of `selectedPath()`/`select(itemID:atLevel:)`, but the given sources
do no such thing themselves.

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

## Accessibility Options

Not applicable: none of the nine given sources present any UI of their own,
so none responds to Reduce Motion, Increase Contrast, or Differentiate
Without Color. (`MarkdownEditing.swift`'s concrete `PlainTextEditorViewController`/
`PlainTextViewerViewController` render text but declare no motion,
contrast, or color-differentiation handling of their own beyond following
the ambient theme's `code` font role.)

## Feature Flags

Not applicable: none of the nine given sources read a feature-flag or
on/off settings key. `FormValidator`'s and `HTDVLayoutEngine`'s behavior is
unconditional given their inputs; nothing here is gated by a flag.

## Analytics

Not applicable: none of the nine given sources contain an analytics or
event-tracking call.

## Privacy

- **Data collected**: None of the given sources collect data on their own;
  `FormState`/`FormValidator` operate only on whatever field values the
  host's form spec asks the user to enter (arbitrary `String`/`Bool`/
  `Double`/`Date`/`[String]`, per `FormValue`'s shape) — the engine itself
  has no knowledge of whether any given key is sensitive.
- **Storage**: None of the nine given sources persist anything to disk, a
  database, or `UserDefaults`; `FormState.values`/`baseline` and
  `HTDVController.levels`/`selection`/`detail` are in-memory only and are
  discarded when the owning object is deallocated.
- **Transmission**: `HTDVController` transmits whatever `HTDVDataSource`'s
  `rootLevel()`/`child(for:)` implementation does internally (not among the
  given sources); `FormState.save()` transmits whatever the host's
  `FormAction.perform` closure does internally. Neither given file performs
  a network call itself.
- **Retention**: Not applicable — nothing here is retained beyond the
  lifetime of the in-memory `HTDVController`/`FormState` instance.

## Logging

Not applicable: none of the nine given sources make a logging call (no
`import os`, no `Logger`, no `print` appears in any of them). A load or
save failure surfaces only as the `error`/`saveError` state described under
Behavioral Requirements; if a host wants to log it, that logging happens
outside these sources.

## Platform Notes

- **SwiftUI**: A SwiftUI host would wrap `HTDVController` and `FormState`
  in `@Observable` (or bridge their existing `onChange` callback into
  `@Published` properties on an `ObservableObject`) rather than reuse them
  unchanged, since both types are hand-rolled `@MainActor` classes with a
  single-slot callback, not `Observable`/`ObservableObject` themselves.
  Replace `HTDVLayoutEngine`'s manual width tracking with a
  `NavigationSplitView`/`HStack` chosen by a `GeometryReader`-measured
  width and the environment's `horizontalSizeClass`, but keep
  `HTDVLayoutEngine.layout(...)` itself as the pure decision function
  driving that choice. Model each `FormField` case as a `Form` row (`TextField`,
  `Toggle`, `Picker`, `TextField(value:)` with a `Formatter`, `DatePicker`,
  a custom chip-entry view for `.stringSet`) bound to `FormState.value(for:)`/`set(_:for:)`.
- **Compose**: Model `HTDVController` as a `ViewModel` exposing
  `StateFlow<HTDVUiState>` (levels/selection/detail/loading/error collapsed
  into one data class) instead of a single-slot callback, and `FormState`
  similarly as a `ViewModel` with `mutableStateOf`/`StateFlow` per field.
  Use Material 3 adaptive's `ListDetailPaneScaffold` (or a custom
  `BoxWithConstraints`-driven row of `LazyColumn`s) in place of
  `HTDVLayoutEngine`'s manual rail-count arithmetic, again keeping an
  equivalent pure `layout(...)` function as the actual decision. Map field
  kinds to `OutlinedTextField`, `Switch`, `ExposedDropdownMenuBox`,
  `OutlinedTextField` with a numeric `KeyboardType` and `visualTransformation`,
  and a `DatePickerDialog`.
- **React/Web**: Model `HTDVController` as a custom hook (e.g.
  `useHtdvController(dataSource)`) built on `useReducer`, with the
  `generation` counter held in a `useRef` so a stale async response can
  still be detected and ignored after a state update triggers a re-render;
  model `FormState` as `useReducer`-driven `values`/`baseline`/`errors`
  state with a `validate` function that mirrors `FormValidator` field-by-
  field (including anchoring a user regex with `` `^(?:${pattern})$` ``
  before calling `.test()`, and wrapping `JSON.parse` in a `try`/`catch`
  for the `.json` field kind). Use a `ResizeObserver`-driven width plus a
  media-query-style compact breakpoint in place of `isCompact`, feeding the
  same rails-vs-stack decision.
- **AppKit / UIKit**: This is the source: `Controller/HTDVController.swift`,
  `Model/HTDVModel.swift`, `Model/HTDVCellContent.swift`,
  `Layout/HTDVLayoutEngine.swift`, `Forms/FormSpec.swift`,
  `Forms/FormValue.swift`, `Forms/FormState.swift`,
  `Forms/FormValidator.swift`, and `Markdown/MarkdownEditing.swift`. The
  engine types themselves (`HTDVController`, `HTDVLayoutEngine`,
  `FormState`, `FormValidator`, `FormSpec`, `FormValue`) import only
  `Foundation` and hold no AppKit/UIKit dependency beyond the
  `PlatformViewController` type alias used as an opaque return/parameter
  type; `MarkdownEditing.swift` is the one file among the nine that also
  ships concrete AppKit (`NSTextView`/`NSViewController`) and UIKit
  (`UITextView`/`UIViewController`) implementations side by side behind
  `#if canImport(AppKit) && !targetEnvironment(macCatalyst)` /
  `#elseif canImport(UIKit)`, selected once at compile time per platform —
  see Design Decisions.
- **WinUI 3**: Model `HTDVController` as a plain C# class (or a
  `CommunityToolkit.Mvvm` `ObservableObject`) exposing `ObservableCollection<HTDVLevel>`-
  style properties and raising `INotifyPropertyChanged`/a C# `event` in
  place of the single-slot `onChange` closure; keep the `generation`-based
  stale-response guard using a plain `int` field checked after each
  `await`ed `Task<HTDVLevel>`/`Task<HTDVChild>` completes (a `CancellationToken`
  is a valid alternative for the *deeper* in-flight load `popToLevel`/
  `clearDetail` want to discard, but the source's own approach is result-
  discarding, not task-cancelling — see Design Decisions). Use a
  `NavigationView` in "left compact" mode, or a hand-built
  `Grid`/`AdaptiveTrigger`+`VisualStateManager` pair, to switch between
  side-by-side rail columns and a single-pane stack, mirroring
  `HTDVLayoutEngine.Mode`. Model `FormField` as an `abstract record`
  hierarchy (`TextField`, `ToggleField`, `SelectField`, `NumberField`,
  `DateField`, `StringSetField`, `ReadOnlyField`, `MarkdownField`,
  `JsonField`) and bind to `TextBox`, `ToggleSwitch`, `ComboBox`,
  `NumberBox`, `CalendarDatePicker`, and a `TokenizingTextBox`-style control
  for the string-set kind; validate with `System.Text.RegularExpressions.Regex`,
  anchoring a supplied pattern with `^(?:...)$` exactly as `FormValidator`
  does, and use `double.ToString("G", CultureInfo)`-based formatting (not
  `int.Parse`) for bounds messages so an out-of-`int`-range `maximum` cannot
  throw while building the message. `HTDVDataSource`'s network-backed
  implementations would use `HttpClient` and `System.Text.Json`; nothing in
  these nine sources needs `Windows.Storage`, since none of them persists
  anything (see Privacy).

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/HTDV/` |

## Design Decisions

**Decision**: `HTDVController` discards a stale response by comparing a
captured `generation` snapshot against the current `generation` after an
`await` resolves, rather than cancelling the underlying `Task`.
**Rationale**: The in-flight `dataSource.rootLevel()`/`child(for:)` call is
allowed to keep running to completion even after `popToLevel`, `clearDetail`,
or a newer `select`/`reload` has moved on; only the *result* is thrown away
(`stale-response-dropped`). This is simpler and safer than plumbing
`Task` cancellation through an arbitrary `HTDVDataSource` implementation
(which the doc comment says is "typically actors or `@unchecked Sendable`
classes wrapping a client" the engine does not control), at the cost of
occasionally letting a now-useless network/database call run to completion
in the background.
**Approved**: pending

**Decision**: `FormState`'s doc comment scopes it to "the save lifecycle";
it exposes no method invoking `spec.actions.delete` or `spec.actions.extra`,
and tracks no `isDeleting`/`deleteError` for them.
**Rationale**: Delete and "extra" actions are typically presented behind a
confirmation dialog (`FormDeleteAction.confirmationText`) that is
inherently a presentation-layer concern; keeping only the save lifecycle in
the engine layer means the presentation layer (`FormViewController`,
outside these given sources) owns exactly one additional, simple
responsibility — call the closure and handle its `throws` itself — instead
of duplicating `FormState`'s dirty-tracking machinery for actions that have
no "dirty" concept of their own.
**Approved**: pending

**Decision**: Both `HTDVController.fail(...)` and `FormState.save()` reduce
a thrown error to a single string via `(error as? LocalizedError)?.errorDescription
?? String(describing: error)`, discarding the original error's type and any
structured payload.
**Rationale**: `HTDVLoadError` and `FormState.saveError` are both declared
as plain strings meant to be shown directly to the user, so a uniform
reduction avoids either type having to know about every error type a given
`HTDVDataSource`/`FormAction` implementation might throw; the tradeoff is
that a non-`LocalizedError` type without a friendly `CustomStringConvertible`
description surfaces its raw Swift debug description to the user.
**Approved**: pending

**Decision**: `HTDVLayoutEngine.layout(...)` clamps its effective rail-width
divisor to a minimum of `1` even though `init(railWidth:minDetailWidth:)`
already `precondition`s `railWidth > 0`.
**Rationale**: `railWidth` is a mutable public `var`, so the init-time
precondition cannot stop a later assignment of `0` or a negative value (for
example, a caller collapsing a sidebar to width `0` for one layout pass);
clamping inside `layout` itself is what actually prevents a division-by-zero
or a trapping `Int` conversion at the point the value is used, rather than
only at construction.
**Approved**: pending

**Decision**: `MarkdownEditing.swift` defines the `MarkdownEditing` protocol
and ships a concrete default implementation (`PlainTextMarkdownEditing`,
with AppKit and UIKit view controllers) in the same file, unlike the other
eight given sources, which hold no AppKit/UIKit-specific code.
**Rationale**: Per the source's own comment, `PlainTextMarkdownEditing` is
explicitly a placeholder — "adequate for configuration notes until the
markdown module lands" — with the hub app expected to inject a real
implementation through `HubModules.markdownEditing`; bundling a working
default alongside the protocol lets every consumer of the Forms subsystem's
`.markdown` field render *something* today without depending on that
richer, not-yet-given module.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | partial | Best Practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | Best Practices |
| [explicit-error-handling](agenticdevelopercookbook://compliance/best-practices#explicit-error-handling) | passed | Best Practices |
| [error-recovery](agenticdevelopercookbook://compliance/reliability#error-recovery) | passed | Reliability |
| [state-recovery](agenticdevelopercookbook://compliance/reliability#state-recovery) | passed | Reliability |
| [main-thread-freedom](agenticdevelopercookbook://compliance/performance#main-thread-freedom) | passed | Performance |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | failed | Internationalization |

Notes: separation-of-concerns is partial because eight of the nine given
sources (`HTDVController`, `HTDVModel`, `HTDVCellContent`, `HTDVLayoutEngine`,
`FormSpec`, `FormValue`, `FormState`, `FormValidator`) import only
`Foundation` and hold no view-framework dependency beyond the opaque
`PlatformViewController` type, but the ninth, `MarkdownEditing.swift`,
bundles the `MarkdownEditing` protocol together with a concrete
AppKit/UIKit default implementation in the same file — see Design
Decisions. unit-test-coverage passes because every one of the nine sources
has a corresponding test file with meaningful assertions:
`HTDVControllerTests.swift` (29 tests, including stale-result protection),
`HTDVLayoutEngineTests.swift`, `HTDVModelTests.swift`, `FormStateTests.swift`,
`FormValidatorTests.swift`, and `PlainTextMarkdownEditingTests.swift`.
explicit-error-handling passes because every `throws` boundary in these
sources is caught and turned into explicit, observable state —
`HTDVController.fail(...)` sets `error`, `FormState.save()` sets
`saveError` — with the one narrower exception noted under Edge Cases'
**create-action-error-path**, where the action's own signature is
non-throwing rather than an error being caught and dropped.
error-recovery passes because `retry()` re-issues exactly the operation
that failed and `FormState.revert()`/a subsequent `save()` let a failed
save be corrected and retried. state-recovery passes because `reload`
reconciles a level whose selected item disappeared or whose parent stopped
being a `.level`, truncating rather than leaving stale, inconsistent state
in place. main-thread-freedom passes because `HTDVController` and
`FormState` are `@MainActor`-confined but their `dataSource`/action calls
are `await`ed, which suspends rather than blocks the main actor while a
data source or save action does its work. no-hardcoded-strings fails
because every user-facing string these sources produce — `FormValidator`'s
messages, `HTDVLevel.emptyMessage`'s default, `FormDeleteAction`'s
documented confirmation fallback — is a hardcoded English literal with no
localization key, per Localization above.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation |
