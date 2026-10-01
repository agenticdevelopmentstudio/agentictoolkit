---
id: faa2c3f3-1ff7-45fb-b6da-efed3cc1d451
title: Hierarchical Topic Detail View
domain: agentictoolkit://cookbook/ui/navigation/htdv
type: ingredient
version: 1.1.0
status: review
language: en
created: '2026-09-24'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'The non-UI logic behind the hierarchical topic detail view: the rail/detail
  navigation state machine, the rails-vs-stack layout decision, the data model,
  and the declarative forms subsystem.'
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

# Hierarchical Topic Detail View

## Overview

This is the non-UI logic that a hierarchical topic detail view's
presentation layer renders: it owns no view and draws nothing. It is four
cooperating pieces:

- **The navigation controller** - a UI-thread-confined navigation/selection/
  loading state machine that walks a data source's tree one level at a time
  and exposes the levels, selection, detail, loading level index, and error
  to a host view.
- **The data model** - an item, a level, a detail destination, a child
  (what lies beneath a selected path), a badge, a create action, the
  data-source contract the host implements, and the row projection, the
  platform-neutral row shape every rail cell renders from.
- **The layout engine** - a pure function from available width, level
  count, and compactness to a rails-vs-stack layout mode, called by the
  presentation layer on resize.
- **The forms subsystem** - the declarative shape of a detail form (the
  form specification), its field value type, its mutable, dirty-tracked,
  save-lifecycle model (the form model), and its per-field validation rules
  (the validator).

The markdown editing contract is included because it is the injectable
factory contract the forms subsystem's markdown field kind depends on; its
default implementation is itself logic (text in, text out via a callback)
even though the concrete editor/viewer it vends are platform view
controllers - see Design Decisions.

The presentation layer that consumes this engine is out of this recipe's
scope and is not described here except where a requirement below states
what the presentation layer is responsible for.

## Behavioral Requirements

### Data model and data source contract

- **item-shape**: An item MUST expose an immutable identity, a label, an
  optional sub-label, an optional icon, a flag for whether a divider
  follows it, a leads-to designation, and an optional badge, and MUST
  support equality comparison and safe use across concurrent contexts. It
  MUST be constructible only through its own initializer, whose divider
  flag defaults to `false`, whose leads-to designation defaults to "list,"
  and whose sub-label/icon/badge default to none.
- **level-shape**: A level MUST expose an immutable identity, a title, its
  items, an empty-state message, and an optional create action, and MUST
  be safe to use across concurrent contexts. Its empty-state message MUST
  default to the literal "Nothing here yet" and its create action MUST
  default to none.
- **detail-shape**: A detail destination MUST expose an immutable
  identity, a title, and a factory that produces the destination's own
  view controller, constructible only through its own initializer, and
  MUST be safe to use across concurrent contexts.
- **child-shape**: The child - what lies beneath a selected path - MUST be
  exactly one of three things: a level, a detail destination, or nothing,
  and MUST be safe to use across concurrent contexts.
- **leads-to-shape**: An item's leads-to designation MUST be exactly one
  of two values, "list" or "detail," naming what selecting the item
  reveals to its right, and MUST support equality comparison and safe use
  across concurrent contexts.
- **badge-shape**: A badge MUST be exactly one of two kinds - a colored
  dot or a numeric count - and MUST support equality comparison and safe
  use across concurrent contexts.
- **badge-color-theme-role**: A dot badge's color MUST map red to the
  danger role, green to the success role, blue to the accent role, gray to
  the secondary-text role, and both orange and yellow to the warning role
  - the two names collapsing onto one role because the shared theme
  palette has no separate orange.
- **create-action-shape**: A create action MUST expose an immutable title
  and a callback that receives the hosting view controller (so it can
  present its own UI) and runs to completion before returning, and MUST be
  safe to use across concurrent contexts.
- **data-source-contract**: A data source MUST be an object that can fetch
  the root level and can fetch the child beneath any given path of items,
  both asynchronously and both able to fail with an error; it MUST be safe
  to use across concurrent contexts. Implementations are typically
  wrappers around a client with their own internal concurrency handling.

### Row projection

- **cell-content-projection**: The row projection MUST copy an item's
  label, sub-label, icon, and badge unchanged, and MUST mark itself as
  disclosing if and only if the item's leads-to designation is "list."
- **cell-content-equality**: The row projection MUST support equality
  comparison, hashing, and safe use across concurrent contexts, so a rail
  can key its rows by it and share it between the loading logic and the
  view layer.

### Navigation, selection, and loading state machine

- **initial-state**: A newly constructed controller MUST have no levels,
  no selection, no detail, no loading level index, and no error.
- **is-loading-derivation**: Whether the controller is loading MUST be
  true if and only if a loading level index is set; this MUST be derived,
  not tracked as a separate stored flag.
- **load-resets-then-fetches**: Loading MUST clear the levels, selection,
  detail, error, and any recorded failed request before fetching, MUST ask
  the data source for the root level, and on success MUST set the levels
  to that single returned root level.
- **select-validates-membership**: Selecting an item MUST no-op (leaving
  the levels, selection, detail, and error unchanged) unless the given
  level index is valid and the given item id names an item present in that
  level's items.
- **select-truncates-then-fetches**: On a valid selection, the controller
  MUST first truncate the levels to the levels up to and including the
  selected one and truncate the selection to the levels above it plus the
  newly selected item, clear the detail and error, and only then ask the
  data source for the child beneath the newly selected path.
- **select-applies-whatever-child-returns**: On success, the controller
  MUST apply whatever child the data source returns - appending a level to
  the levels, replacing the detail with the returned one, or doing nothing
  when the answer is empty - regardless of whether the selected item's own
  leads-to designation was "list" or "detail"; the controller does not
  validate agreement between an item's leads-to designation and the child
  the data source actually returns for it.
- **reload-root-vs-nested**: Reloading a level MUST ask the data source
  for the root level when reloading the first level, and for any deeper
  level MUST ask for the child beneath the parent path and require the
  result to be a level; a level index out of bounds for the current levels
  MUST make reloading a no-op.
- **reload-preserves-or-drops-selection**: When reloading a deeper level
  succeeds with a fresh level, the controller MUST replace that level with
  the fresh one and MUST preserve the current selection at that level if
  the selected item still appears among the fresh level's items, and MUST
  otherwise truncate the levels, selection, and detail from that level
  onward.
- **reload-parent-became-non-level**: When reloading a deeper level's
  parent lookup returns a detail destination or nothing instead of the
  expected level, reloading MUST drop the levels and selection from that
  level onward, clear the detail, and apply whatever child was actually
  returned - a detail destination is shown; nothing shows nothing - rather
  than discarding it, since a detail destination is real content the
  caller was handed, and throwing it away would show the user nothing at
  all.
- **retry-reissues-exact-failed-operation**: Retrying MUST no-op unless an
  error is present and a failed request was recorded, and when both are
  present MUST re-invoke exactly the operation that failed - a fresh load
  for a failed root load, the same selection for a failed selection, or
  the same level reload for a failed reload.
- **stale-response-dropped**: Every fetch MUST capture a monotonically
  increasing request counter's value at the moment it begins -
  incrementing the counter first, so the loading state changes before the
  fetch itself starts - and on completion, whether success or failure, the
  controller MUST discard the result and make no state change whenever the
  captured value no longer matches the current counter, because a newer
  request (or a jump back up the levels, or clearing the detail) started
  in the interim.
- **error-shape**: On a thrown error, the controller MUST set the error to
  a value carrying the failing level index and a user-facing message
  derived from the error, MUST record the failed request so retrying can
  reissue it, and MUST clear the loading level index - unless the failure
  is itself stale (see stale-response-dropped), in which case none of this
  MUST happen.
- **pop-to-level-contract**: Jumping back to a level MUST no-op when the
  target index is below `-1` or at/beyond the current deepest level;
  otherwise it MUST invalidate any in-flight deeper load, truncate the
  levels to that level (or to none when the target is `-1`), truncate the
  selection to match, clear the detail, clear the error and any recorded
  failed request, clear the loading level index, and fire the change
  callback exactly once.
- **clear-detail-contract**: Clearing the detail MUST no-op when there is
  no detail already; otherwise it MUST invalidate any in-flight detail
  load, clear the detail, error, failed request, and loading level index,
  leave the levels and selection untouched, and fire the change callback
  exactly once.
- **on-change-fires-after-every-transition**: The change callback MUST be
  invoked after every state transition made by loading, selecting,
  reloading, jumping back to a level, and clearing the detail - including
  the loading-started transition at the start of a fetch, fired before the
  fetch itself begins - and MUST default to doing nothing until a host
  assigns one.
- **single-observer-callback**: The change callback MUST be a single-slot
  property, not a multicast; assigning it a second time MUST silently
  replace the first observer with no diagnostic - each controller MUST be
  driven by exactly one host, and a second host that assigns its own
  callback silently displaces the first.
- **selected-path-and-item-queries**: Reading the selected path MUST
  return the item at each selected id in the selection, skipping any
  level/id pair that no longer resolves - for example after a level was
  replaced by a reload - and reading the selected item at a given level
  MUST return none when that level index is out of bounds for the
  selection or for the levels.

### Rails-vs-stack layout decision

- **compact-always-stacks**: Deciding the layout MUST choose the
  single-pane stack mode whenever the layout is compact, regardless of the
  available width, level count, or whether a detail is shown.
- **zero-levels-shape**: When there are no levels and the layout is not
  compact, deciding the layout MUST return the side-by-side rails mode
  with zero visible rails, showing the detail exactly when one is present.
- **rails-width-budget**: When there is at least one level and the layout
  is not compact, deciding the layout MUST subtract the reserved detail
  width from the available width only when a detail is present, before
  dividing by the (clamped) rail width to decide how many rails fit.
- **rail-width-divisor-clamp**: Deciding the layout MUST clamp the
  effective rail width used as its division's divisor to a minimum of `1`,
  so a caller who has set the rail width to `0` or a negative value MUST
  NOT cause a division-by-zero or an invalid numeric conversion.
- **at-least-one-rail-when-levels-exist**: When there is at least one
  level, deciding the layout MUST return a set of visible rails containing
  at least one rail - specifically the rails nearest the end of the
  sequence, not the beginning - even when the computed available width
  would otherwise fit zero.
- **fitting-count-is-floored-and-clamped**: Deciding the layout MUST
  compute the number of rails that fit by dividing the available rails
  width by the effective rail width and rounding down, clamped between
  zero and the level count before converting to a whole number, so that an
  unbounded or extremely large available width MUST produce visible rails
  capped at the level count rather than an invalid numeric conversion.
- **layout-is-pure**: Deciding the layout MUST hold no state of its own
  beyond the rail width and reserved detail width supplied at construction
  or mutated by the caller between calls, and MUST return a value computed
  solely from its inputs (available width, level count, whether a detail
  is shown, and whether the layout is compact) and those two settings.
- **rail-width-init-precondition**: Constructing the layout engine MUST
  require a positive rail width, failing immediately at construction time
  if a non-positive value is supplied - a guarantee `rail-width-divisor-
  clamp` exists specifically because this construction-time check does not
  protect a later mutation of the rail width setting.

### Declarative form shape

- **form-spec-shape**: A form specification MUST expose mutable sections
  and the form's actions (which default to none set), and MUST expose the
  flattened list of every section's fields in section-then-field display
  order; it MUST be safe to use across concurrent contexts.
- **field-kinds**: A field MUST be exactly one of ten kinds - text,
  multi-line text, toggle, select, number, date, string set, read-only,
  markdown, and JSON - each carrying at minimum a key and a label, and MUST
  be safe to use across concurrent contexts.
- **field-key-and-label-projection**: A field's key and label MUST forward
  to that specific kind's own key/label for every kind, with no
  kind-specific transformation.
- **field-default-values**: A field's default value MUST be an empty
  string for text, multi-line text, markdown, JSON, and read-only kinds;
  `false` for a toggle; an empty set for a string set; and no value for
  select, number, and date kinds.
- **field-editability**: A field's editability MUST be `false` for the
  read-only kind and `true` for every other kind.
- **action-shapes**: An action MUST carry an identity, a title, whether it
  is destructive (defaulting to `false`), and a callback that can fail
  and, when it is the save action, receives the current, already-validated
  values. The delete action MUST carry a title, an optional confirmation
  message, and a non-parameterized callback that can fail. The form's
  actions MUST group an optional save action, an optional delete action,
  and a list of extra actions, all defaulting to none/none/empty. Every one
  of these MUST be safe to use across concurrent contexts.

### Field value type

- **form-value-shape**: A field value MUST be exactly one of six kinds - a
  string, a boolean, a number, a date, a string set, or no value - one
  value type shared by every field kind, and MUST support equality
  comparison and safe use across concurrent contexts.
- **form-value-accessors**: Reading a field value as a string, boolean,
  number, date, or string set MUST each return the wrapped value when it
  is that kind and none for every other kind (including no value); whether
  it holds no value MUST be true if and only if it is the no-value kind.

### Mutable form model and save lifecycle

- **form-state-initial-values**: Constructing the form model MUST seed
  each field's initial value from the supplied values when present, and
  MUST otherwise use that field's default value; the seeded set of values
  MUST become both the current values and the dirty-tracking baseline.
- **duplicate-field-key-detection**: Detecting duplicate field keys MUST
  return every field key the form specification declares more than once,
  each key appearing exactly once in the result in first-seen order;
  construction MUST flag each such key in a development build (without
  stopping a released build) and MUST otherwise continue constructing the
  instance with last-write-wins semantics for that key, so a shipped build
  keeps today's last-write-wins render rather than crashing on a form it
  could still mostly show.
- **is-dirty-derivation**: Whether the form is dirty MUST be true if and
  only if the current values differ from the baseline; this MUST be
  derived, not tracked as a separate stored flag.
- **can-save-derivation**: Whether the form can be saved MUST be true if
  and only if a save action is set, there is no blocked reason, a save is
  not already in progress, and either changes are not required or the
  form is dirty.
- **set-validates-the-changed-field-only**: Setting a field's value MUST
  no-op for a key not present in the form's fields; for a known key it
  MUST store the value, MUST re-run validation for that single field and
  update that field's error with the result (or clear it when valid), MUST
  clear the save error, and MUST fire the change callback.
- **validate-all-replaces-error-set**: Validating every field MUST
  re-validate every field in the form, MUST replace the error set wholesale
  with exactly the fields that failed (dropping stale errors for fields
  that now pass), MUST fire the change callback, and MUST return `true` if
  and only if no field failed.
- **save-lifecycle**: Saving MUST return `false` without side effects when
  no save action is set, a blocked reason is present, or a save is already
  in progress; otherwise it MUST validate every field and return `false`
  without invoking the save action when validation fails; on a validated
  save it MUST mark a save as in progress, fire the change callback,
  invoke the save action with a snapshot of the current values, and on
  success MUST adopt that snapshot as the new baseline, clear the
  in-progress flag, fire the change callback, and return `true`.
- **save-failure-preserves-dirty-state**: When the save action fails,
  saving MUST set the save error to a user-facing message derived from the
  failure, MUST clear the in-progress flag, MUST fire the change callback,
  MUST return `false`, and MUST NOT update the baseline - so the form
  remains dirty and the caller's edits are not lost.
- **revert-restores-baseline**: Reverting MUST reset the current values to
  the baseline, clear all errors and the save error, and fire the change
  callback.
- **mark-saved-rebaselines-without-performing**: Marking the form as saved
  MUST adopt the current values as the new baseline and fire the change
  callback, without invoking the save action or any other action.
- **blocked-reason-disables-saving**: Setting a blocked reason MUST make
  the form unsavable regardless of dirtiness, and MUST fire the change
  callback on every assignment, including reassigning the same value.
- **requires-changes-toggle**: Whether changes are required MUST default
  to `true` (an edit form disables saving until something changes);
  setting it to `false` (a create dialog with nothing to change against)
  MUST make whether the form can be saved depend only on there being no
  blocked reason and no save already in progress, relying on validating
  every field during save to reject an empty or invalid form instead.
- **concurrent-edit-during-save-stays-dirty**: Setting a field's value
  while a save is in flight MUST mutate the current values immediately
  (visible via the change callback) without affecting the in-flight
  save's already-captured snapshot; when that save later succeeds, the
  baseline MUST be set to the pre-edit snapshot it captured, not to the
  newer values, so the form MUST remain dirty after the save completes.
- **delete-and-extra-actions-are-outside-the-save-lifecycle**: The form
  model exposes no method that invokes the delete action or any extra
  action, and tracks no in-progress/error state for them; it models the
  save lifecycle specifically, and invoking delete/extra actions and
  displaying the delete action's confirmation message (or its documented
  "This cannot be undone." fallback) is the presentation layer's
  responsibility.

### Field validation rules

- **validator-is-pure**: The validator MUST be a stateless namespace whose
  sole operation is a pure function from a field and its value to an
  optional user-facing message string, with no message meaning the value
  is acceptable; the locale used for formatting MUST default to the
  current locale.
- **text-required-and-trims**: For text, multi-line text, and markdown
  fields, validation MUST trim leading/trailing whitespace and newlines
  before checking emptiness, and MUST return "<label> is required" if and
  only if the trimmed value is empty and the field is required; an
  optional field with an empty or whitespace-only value MUST validate with
  no error.
- **text-pattern-is-whole-value-anchored**: When a text field declares a
  pattern and the untrimmed value is non-empty, validation MUST match the
  pattern against the whole value by anchoring it as `^(?:<pattern>)$`
  before evaluating it as a regular expression - so a pattern that itself
  matches only a substring of the value MUST be rejected - and MUST return
  the field's custom pattern message when set, or "<label> has an invalid
  format" otherwise, when the anchored match fails.
- **json-field-validates-text-then-parse**: For a JSON field, validation
  MUST first apply the same required/trim check as a text field with no
  pattern; if that passes and the trimmed value is non-empty, it MUST then
  attempt to parse the value as JSON (including a bare literal, not only
  an object or array), and MUST return "<label> must be valid JSON" when
  parsing fails.
- **select-required-and-membership**: For a select field, validation MUST
  return "<label> is required" when the value is empty/none and the field
  is required, and otherwise, for a non-empty value, MUST return "<label>
  must be one of the listed options" unless the value equals some option's
  value.
- **number-required-bounds-and-integer**: For a number field, validation
  MUST return "<label> is required" when the value is not a number and
  the field is required; for a present number, MUST return "<label> must
  be a whole number" when the field requires an integer and the value is
  not equal to its own rounding; and MUST return a formatted "at least"/
  "at most" message when the value falls outside a declared minimum/
  maximum (inclusive bounds - a value exactly equal to the minimum or
  maximum MUST pass).
- **date-and-toggle-and-readonly**: Toggle and read-only fields MUST always
  validate with no error; a date field MUST return "<label> is required"
  when the field is required and the value holds no date, and MUST
  otherwise validate with no error.
- **string-set-required**: For a string-set field, validation MUST return
  "<label> is required" when the field is required and the value's set (or
  an empty set when absent) is empty; validation performs no per-item
  check on the set's contents.
- **bound-message-uses-locale-aware-formatting**: The numeric bound quoted
  in a number field's "at least"/"at most" message MUST be formatted as a
  plain decimal number in the supplied locale, with no grouping separator
  and up to 15 fraction digits - so a whole-number bound prints without a
  decimal point and a fractional bound renders using the locale's own
  decimal separator - falling back to a plain numeric rendering only if
  locale-aware formatting itself is unavailable.
- **bound-formatting-does-not-trap-on-extreme-values**: Formatting a bound
  MUST use a decimal-safe numeric formatter rather than converting through
  a fixed-width integer type, so a maximum or minimum far outside a normal
  whole-number range (e.g. `1e19`) MUST NOT crash while the message that
  reports the violation is being built.

### Markdown editor/viewer factory contract

- **markdown-editing-contract**: The markdown editing contract MUST
  declare two factory operations, both confined to the UI thread: one that
  produces an editor view controller for given initial text, whose change
  callback MUST be invoked with the current text on every edit, and one
  that produces a read-only viewer view controller for fixed text. It MUST
  be safe to use across concurrent contexts.
- **markdown-text-replacing-contract**: The live-text-replacement
  capability MUST declare a single operation that replaces the editor's
  displayed text, confined to the UI thread and adopted by an editor
  produced by the editing contract's editor factory, so a caller -
  documented as the revert use case - can push a restored value back into
  the live editor without knowing its concrete type.
- **plain-text-default-implementation**: The markdown editing contract's
  default implementation MUST produce monospaced, unstyled plain-text
  editing and viewing, with no markdown rendering; it is intended as an
  adequate placeholder until a richer implementation is available, and a
  host MAY inject a richer implementation of the contract instead.
- **plain-text-editor-replace-also-notifies**: On the default
  implementation, replacing the editor's text MUST set the displayed text
  to the new value AND invoke the change callback with that same value, so
  a programmatic replacement (used by revert) is observationally identical
  to the user typing it.
- **plain-text-editor-forwards-live-edits**: On the default
  implementation, every live edit in the editor MUST invoke the change
  callback with the text area's current text, falling back to an empty
  string if the platform's text-change notification reports none.
- **plain-text-editor-disables-smart-substitution**: The default
  implementation MUST disable automatic quote/dash substitution and
  autocorrection/autocapitalization in its text editor, since markdown
  source text MUST NOT be silently rewritten by text-input conveniences
  meant for prose.
- **plain-text-uses-the-theme-code-font**: Both the default editor and
  viewer MUST observe the ambient theme and set the text area's
  background, foreground, cursor/selection tint, and font from the
  theme's code role rather than the platform's system default, since the
  code role is the theme's own monospaced role, and a plain-text markdown
  pane should follow the selected theme's code font instead of the
  system's.

## Appearance

Not applicable - this is the navigation, layout, and forms logic behind a
hierarchical topic detail view, not a visual component.

## States

Not applicable - this is the navigation, layout, and forms logic behind a
hierarchical topic detail view, not a visual component. The runtime state
machines it does own - the navigation controller's idle/loading/loaded/
error cycle and the form model's clean/dirty/saving/save-failed cycle - are
captured as requirements above (`is-loading-derivation`, `error-shape`,
`is-dirty-derivation`, `save-lifecycle`, `save-failure-preserves-dirty-
state`), not in a visual-state table.

## Accessibility

Not applicable - this is the navigation, layout, and forms logic behind a
hierarchical topic detail view, not a visual component. The navigation
controller, the layout engine, the form model, and the validator produce
no view, role, trait, or label of their own; any accessibility surface
belongs to the presentation layer that renders their output (out of this
recipe's scope).

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| htdv-engine-001 | load-resets-then-fetches | Loading, against a data source whose root level returns a level containing one item. | The levels become that single root level; the selection, detail, and error are all empty. |
| htdv-engine-002 | select-truncates-then-fetches, select-applies-whatever-child-returns | Selecting an item at the first level, where the data source's child lookup returns a level. | The levels become the root plus the returned child level; the selection records the selected item. |
| htdv-engine-003 | select-applies-whatever-child-returns | Selecting an item at the first level, where the data source's child lookup returns a detail destination. | The detail becomes that returned detail destination; the level count is unchanged (no new rail is appended). |
| htdv-engine-004 | select-validates-membership | Selecting an item id that is not present in the level's items. | The levels, selection, detail, and error are all unchanged from before the call. |
| htdv-engine-005 | select-truncates-then-fetches | Selecting an item at the first level again, after a deeper level and detail are already loaded. | The levels are truncated to one entry before the new fetch is applied; the previously loaded deeper level is gone. |
| htdv-engine-006 | reload-preserves-or-drops-selection | Reloading a level whose fresh contents still contain the currently selected item. | That level is replaced with the fresh level; the selection at that level is unchanged. |
| htdv-engine-007 | reload-preserves-or-drops-selection | Reloading a level whose fresh contents no longer contain the selected item. | The selection, levels, and detail are truncated from that level onward. |
| htdv-engine-008 | reload-parent-became-non-level | Reloading a deeper level whose parent path now resolves to a detail destination instead of a level. | The levels/selection are truncated to before that level; the detail is set to the returned detail destination rather than left empty. |
| htdv-engine-009 | error-shape, retry-reissues-exact-failed-operation | Loading fails, then retrying is called against a data source that now succeeds. | After the failure, the error is set and the failed request records the load; after retrying, the error clears and the levels reflect the successful root load. |
| htdv-engine-010 | stale-response-dropped | Selecting one item starts, then selecting a different item at the same level starts before the first resolves; the first selection's fetch then resolves. | The first (stale) result is discarded; the levels/selection/detail reflect only the second selection's outcome. |
| htdv-engine-011 | pop-to-level-contract | Jumping back to the second level on a controller with three loaded levels and a detail set. | There are two levels remaining, one selection entry remaining, and the detail and error are both cleared. |
| htdv-engine-012 | pop-to-level-contract | Jumping back to before the first level on any non-empty controller. | The levels, selection, and detail are all cleared. |
| htdv-engine-013 | pop-to-level-contract | Jumping to the current deepest level, or to an index below the "clear everything" index. | No-op: the levels, selection, detail, and error are all unchanged. |
| htdv-engine-014 | clear-detail-contract | Clearing the detail while a detail is set. | The detail clears; the levels and selection are byte-for-byte unchanged; the change callback fires exactly once. |
| htdv-engine-015 | can-save-derivation, save-lifecycle | Constructing the form model with a save action, then setting a valid value for a required field and saving. | Saving returns `true`; the baseline equals the current values; the form is no longer dirty afterward. |
| htdv-engine-016 | save-lifecycle | Saving while a required field is still empty. | Saving returns `false`; the save action's callback is never invoked; an error is recorded for the invalid field. |
| htdv-engine-017 | save-failure-preserves-dirty-state | Setting a field's value, then saving where the save action fails. | Saving returns `false`; a save error is set; the form remains dirty (baseline not updated). |
| htdv-engine-018 | concurrent-edit-during-save-stays-dirty | Saving is started (not yet resolved) and, before it resolves, a field's value is changed; the save then succeeds. | After the save resolves, that field holds the new value but the form remains dirty, because the baseline was set from the snapshot taken before the concurrent edit. |
| htdv-engine-019 | duplicate-field-key-detection | Detecting duplicate field keys on a form specification whose sections repeat the key "name" across two sections and repeat "email" within one section. | Returns `["name", "email"]` - each duplicated key exactly once, in first-seen order. |
| htdv-engine-020 | text-pattern-is-whole-value-anchored | Validating a text field with pattern `[a-z]+` and value `My Slug!! (draft)`. | Returns a non-empty format-error message, because the whole value does not match the anchored pattern even though "raft" inside it does. |
| htdv-engine-021 | number-required-bounds-and-integer | Validating a number field with a minimum of `2` and a maximum of `10`, for values `1`, `2`, `10`, and `11`. | `1` and `11` return a bounds-violation message; `2` and `10` (the inclusive boundaries) return no error. |
| htdv-engine-022 | bound-formatting-does-not-trap-on-extreme-values | Validating a number field with a maximum of `1e19` and a value above it. | Returns a bounds-violation message containing the formatted bound, with no crash. |
| htdv-engine-023 | bound-message-uses-locale-aware-formatting | Validating a number field with a fractional minimum under a German-style locale, for a value below it. | The returned message quotes the bound using that locale's decimal separator (e.g. a comma). |
| htdv-engine-024 | rail-width-divisor-clamp | Deciding the layout with an available width of `800`, three levels, no detail, not compact, after the rail width has been mutated to `0`. | Returns the side-by-side rails mode with visible rails computed against a divisor of `1`, not a crash. |
| htdv-engine-025 | fitting-count-is-floored-and-clamped | Deciding the layout with an unbounded available width, five levels, no detail, not compact. | Returns the side-by-side rails mode with all five rails visible and no detail shown - capped at the level count, not an invalid numeric conversion. |
| htdv-engine-026 | compact-always-stacks | Deciding the layout with an available width of `2000`, five levels, a detail shown, and the layout compact. | Returns the single-pane stack mode. |
| htdv-engine-027 | cell-content-projection | Projecting the row content for an item whose leads-to designation is "list" and one whose leads-to designation is "detail." | Marked as disclosing for the "list" item; not marked as disclosing for the "detail" item. |

## Edge Cases

- **Null and empty input**: Selecting an item id absent from the given
  level's items MUST no-op (MUST, see select-validates-membership).
  Setting a field's value for a key absent from the form's fields MUST
  no-op (MUST, see set-validates-the-changed-field-only). A required text/
  multi-line-text/markdown field with an empty or whitespace-only value
  MUST fail validation with an "is required" message; the same field,
  when optional, MUST pass with no error (MUST, see
  text-required-and-trims). An empty string-set field MUST fail
  validation only when required (MUST, see string-set-required).
- **Boundary values**: A number field's value exactly equal to its
  minimum or maximum MUST pass validation - the comparisons are strict,
  not inclusive-by-accident (MUST, see number-required-bounds-and-
  integer). Deciding the layout with a level count of `0` MUST return an
  empty visible-rails range, while any level count greater than `0` MUST
  return at least one visible rail (MUST, see zero-levels-shape,
  at-least-one-rail-when-levels-exist). A rail width of `0` or negative
  (settable after construction despite the construction-time check) MUST
  be clamped to a divisor of at least `1` rather than dividing by zero or
  a negative number (MUST, see rail-width-divisor-clamp). Jumping back to
  a level MUST treat `-1` as "clear everything" and anything below `-1`,
  or at/above the current depth, as a no-op (MUST, see
  pop-to-level-contract).
- **Concurrent access**: The navigation controller and the form model each
  serialize their mutable state onto a single execution context (see
  Platform Notes for the exact confinement mechanism), so their state
  cannot be touched concurrently from a different context without an
  explicit handoff. Overlapping asynchronous fetches on the same
  controller (a second selection/reload/load starting before an earlier
  one resolves) are not prevented outright; instead, each fetch's result
  is validated against a request counter captured when it began, and a
  result whose counter is stale is silently dropped rather than applied
  out of order (MUST, see stale-response-dropped). Setting a field's
  value on the form model while its own save is in flight is not blocked;
  it mutates the current values immediately, and the in-flight save's
  already-captured value snapshot is unaffected, which MUST leave the
  form dirty even after that save later succeeds (MUST, see
  concurrent-edit-during-save-stays-dirty).
- **Error states**: A thrown error from the data source's root-level or
  child fetch MUST populate the controller's error with the failing level
  index and a message derived from the error (or MUST be dropped silently
  if a newer request has since started) - it is never left unreported to
  a still-current caller (MUST, see error-shape). A thrown error from the
  save action MUST populate the form model's save error with a derived
  message and MUST leave the form dirty (MUST, see
  save-failure-preserves-dirty-state). The create action and the delete/
  extra actions have no channel of their own for the engine to observe or
  record a failure - see **create-action-error-path** below and
  delete-and-extra-actions-are-outside-the-save-lifecycle.
- **Offline or disconnected state**: Nothing in this scope makes a network
  call directly; the data source's root-level/child fetches are the only
  points where a network-backed implementation could fail, and that
  failure surfaces to the controller exactly like any other thrown error
  (see Error states above) - the engine defines no timeout, retry, or
  connectivity-aware behavior of its own around those calls (fact, not a
  gap: an absent feature, not a swallowed signal - the failure is not
  lost, it is reported as an error, just without a time bound).

- **create-action-error-path**: The create action's callback is declared
  to run on the UI thread, receive the hosting view controller, and
  complete with no return value and no ability to fail - so the engine
  defines no path for a creation failure to reach the controller's error
  or trigger a reload. The signature makes it the callback's own
  precondition to present and recover from its own failures without
  engine involvement.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| Data source (supplied when constructing the controller) | An object implementing the data-source contract | none - required | The tree the controller navigates; the host supplies its own implementation. |
| Change callback (property on the controller) | A callback receiving the controller | Does nothing | Callback fired after every state transition; single-slot, not multicast. |
| Rail width (property on the layout engine) | A width | `240` | Width budgeted per rail column when deciding how many fit. |
| Reserved detail width (property on the layout engine) | A width | `480` | Width reserved for the detail pane, subtracted from the available width when a detail is shown. |
| Sections, actions (parameters when constructing a form specification) | A list of sections, and the form's actions | none - required / no actions set | The form's fields grouped into sections, and its save/delete/extra actions. |
| Initial values (parameter when constructing the form model) | A set of field values keyed by field | Empty | Initial field values; any field absent here falls back to its own default value. |
| Requires changes (property on the form model) | A boolean | `true` | Whether the form can be saved requires the form to be dirty; a create dialog sets this to `false`. |
| Blocked reason (property on the form model) | An optional message | none | When set, disables saving and is shown as the reason (e.g. a read-only member). |
| Change callback (property on the form model) | A callback receiving the form model | Does nothing | Callback fired after every state transition; single-slot, not multicast. |
| Locale (parameter to validation) | A locale | The current locale | Locale used to format numeric bounds quoted in validation messages. |
| Pattern, pattern message (fields on a text field) | An optional regular expression, and an optional custom message | none, none | An optional whole-value-anchored regular expression and its custom failure message. |
| Minimum, maximum, requires integer (fields on a number field) | Optional numbers, and a boolean | none, none, `false` | Inclusive numeric bounds and whether a non-integral value is rejected. |

No settings-key or environment-variable constants appear anywhere in this
scope: nothing here reads an environment variable or a named settings key.
Every field kind's own configuration is supplied programmatically by the
caller building the form specification, not read from a store.

## Deep Linking

Not applicable: nothing in this scope defines a URL scheme, route, or
navigation destination. The controller's navigation (levels, selection) is
in-memory rail/detail state, not app-level deep linking; a host that wants
a deep link into a specific item's path would build one on top of reading
the selected path and selecting an item, but nothing here does so itself.

## Localization

Nothing in this scope references a string-key or localization table; every
user-facing string is a hardcoded English literal composed inline:

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none - literal, no key) | `Nothing here yet` | A level's empty-state message default. |
| (none - literal, no key) | `This cannot be undone.` | The delete action's documented fallback confirmation message when none is set (the display of this text is outside this engine's own scope). |
| (none - literal, no key) | `<label> is required` | The validator - required text, select, number, date, and string-set fields. |
| (none - literal, no key) | `<label> has an invalid format` | The validator's default pattern-mismatch message. |
| (none - literal, no key) | `<label> must be one of the listed options` | The validator's select-field membership check. |
| (none - literal, no key) | `<label> must be a whole number` | The validator's integer check. |
| (none - literal, no key) | `<label> must be at least <value>` / `<label> must be at most <value>` | The validator's numeric bounds check. |
| (none - literal, no key) | `<label> must be valid JSON` | The validator's JSON-field parse check. |

## Accessibility Options

Not applicable: nothing in this scope presents any UI of its own, so none
responds to Reduce Motion, Increase Contrast, or Differentiate Without
Color. (The markdown editing contract's default editor/viewer
implementation render text but declare no motion, contrast, or
color-differentiation handling of their own beyond following the ambient
theme's code font role.)

## Feature Flags

Not applicable: nothing in this scope reads a feature-flag or on/off
settings key. The validator's and the layout engine's behavior is
unconditional given their inputs; nothing here is gated by a flag.

## Analytics

Not applicable: nothing in this scope contains an analytics or
event-tracking call.

## Privacy

- **Data collected**: None of this scope collects data on its own; the
  form model and validator operate only on whatever field values the
  host's form specification asks the user to enter (arbitrary strings,
  booleans, numbers, dates, or string sets) - the engine itself has no
  knowledge of whether any given key is sensitive.
- **Storage**: Nothing in this scope persists anything to disk, a
  database, or a settings store; the form model's values/baseline and the
  controller's levels/selection/detail are in-memory only and are
  discarded when the owning object is released.
- **Transmission**: The controller transmits whatever the data source's
  root-level/child fetch implementation does internally (outside this
  scope); saving transmits whatever the host's save-action callback does
  internally. Neither performs a network call itself.
- **Retention**: Not applicable - nothing here is retained beyond the
  lifetime of the in-memory controller/form-model instance.

## Logging

Not applicable: nothing in this scope makes a logging call. A load or save
failure surfaces only as the error/save-error state described under
Behavioral Requirements; if a host wants to log it, that logging happens
outside this scope.

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
  driving that choice. Model each `FormField` case as a `Form` row
  (`TextField`, `Toggle`, `Picker`, `TextField(value:)` with a
  `Formatter`, `DatePicker`, a custom chip-entry view for `.stringSet`)
  bound to `FormState.value(for:)`/`set(_:for:)`.
- **Compose**: Model `HTDVController` as a `ViewModel` exposing
  `StateFlow<HTDVUiState>` (levels/selection/detail/loading/error
  collapsed into one data class) instead of a single-slot callback, and
  `FormState` similarly as a `ViewModel` with `mutableStateOf`/`StateFlow`
  per field. Use Material 3 adaptive's `ListDetailPaneScaffold` (or a
  custom `BoxWithConstraints`-driven row of `LazyColumn`s) in place of
  `HTDVLayoutEngine`'s manual rail-count arithmetic, again keeping an
  equivalent pure `layout(...)` function as the actual decision. Map
  field kinds to `OutlinedTextField`, `Switch`, `ExposedDropdownMenuBox`,
  `OutlinedTextField` with a numeric `KeyboardType` and
  `visualTransformation`, and a `DatePickerDialog`.
- **React/Web**: Model `HTDVController` as a custom hook (e.g.
  `useHtdvController(dataSource)`) built on `useReducer`, with the
  request counter held in a `useRef` so a stale async response can still
  be detected and ignored after a state update triggers a re-render;
  model `FormState` as `useReducer`-driven `values`/`baseline`/`errors`
  state with a `validate` function that mirrors `FormValidator`
  field-by-field (including anchoring a user regex with
  `` `^(?:${pattern})$` `` before calling `.test()`, and wrapping
  `JSON.parse` in a `try`/`catch` for the `.json` field kind). Use a
  `ResizeObserver`-driven width plus a media-query-style compact
  breakpoint in place of `isCompact`, feeding the same rails-vs-stack
  decision.
- **AppKit / UIKit** (source platform): This is the source:
  `Controller/HTDVController.swift`, `Model/HTDVModel.swift`,
  `Model/HTDVCellContent.swift`, `Layout/HTDVLayoutEngine.swift`,
  `Forms/FormSpec.swift`, `Forms/FormValue.swift`, `Forms/FormState.swift`,
  `Forms/FormValidator.swift`, and `Markdown/MarkdownEditing.swift`. The
  engine types themselves (`HTDVController`, `HTDVLayoutEngine`,
  `FormState`, `FormValidator`, `FormSpec`, `FormValue`) import only
  `Foundation` and hold no AppKit/UIKit dependency beyond the
  `PlatformViewController` type alias used as an opaque return/parameter
  type; `MarkdownEditing.swift` is the one file among the nine that also
  ships concrete AppKit (`NSTextView`/`NSViewController`) and UIKit
  (`UITextView`/`UIViewController`) implementations side by side behind
  `#if canImport(AppKit) && !targetEnvironment(macCatalyst)` /
  `#elseif canImport(UIKit)`, selected once at compile time per platform.
  `HTDVController` and `FormState` are each declared `@MainActor` with no
  `Sendable` conformance of their own, confining every mutable property
  and method to the main actor's isolation domain and requiring a caller
  on a different isolation domain to `await` a hop onto it (formerly the
  normative requirements `main-actor-confinement` and
  `form-state-main-actor-confinement`; this is the source of the
  Concurrent Access edge case above). `PlatformViewController` resolves to
  `NSViewController` when AppKit is importable and the build is not Mac
  Catalyst, and to `UIViewController` when UIKit is importable, so every
  closure that vends or receives a view controller (`HTDVDetail.make`,
  `HTDVCreateAction.perform`, the markdown editing contract's factories)
  is typed identically on both platforms (formerly the normative
  requirement `platform-view-controller-alias`). `PlainTextEditorViewController`
  forwards live edits through `NSTextViewDelegate.textDidChange(_:)`
  (reading the text view's `string`) on AppKit and
  `UITextViewDelegate.textViewDidChange(_:)` (reading the text view's
  `text`, falling back to `""` when `nil`) on UIKit, and disables
  automatic quote/dash substitution via
  `isAutomaticQuoteSubstitutionEnabled`/`isAutomaticDashSubstitutionEnabled`
  on AppKit and `smartQuotesType`/`smartDashesType` (plus
  `autocorrectionType`/`autocapitalizationType`) on UIKit.
  `FormValidator`'s bound-formatting helper builds a fresh
  `NumberFormatter` per call rather than a cached `static let`, since
  `NumberFormatter` is not `Sendable`, and formats via
  `NumberFormatter`/`NSNumber` rather than `Int(_:)` so an out-of-`Int`-
  range bound cannot trap - see Design Decisions.
- **WinUI 3**: Model `HTDVController` as a plain C# class (or a
  `CommunityToolkit.Mvvm` `ObservableObject`) exposing
  `ObservableCollection<HTDVLevel>`-style properties and raising
  `INotifyPropertyChanged`/a C# `event` in place of the single-slot
  `onChange` closure; keep the request-counter-based stale-response guard
  using a plain `int` field checked after each `await`ed
  `Task<HTDVLevel>`/`Task<HTDVChild>` completes (a `CancellationToken` is
  a valid alternative for the *deeper* in-flight load `popToLevel`/
  `clearDetail` want to discard, but the source's own approach is
  result-discarding, not task-cancelling - see Design Decisions). Use a
  `NavigationView` in "left compact" mode, or a hand-built
  `Grid`/`AdaptiveTrigger`+`VisualStateManager` pair, to switch between
  side-by-side rail columns and a single-pane stack, mirroring
  `HTDVLayoutEngine.Mode`. Model `FormField` as an `abstract record`
  hierarchy (`TextField`, `ToggleField`, `SelectField`, `NumberField`,
  `DateField`, `StringSetField`, `ReadOnlyField`, `MarkdownField`,
  `JsonField`) and bind to `TextBox`, `ToggleSwitch`, `ComboBox`,
  `NumberBox`, `CalendarDatePicker`, and a `TokenizingTextBox`-style
  control for the string-set kind; validate with
  `System.Text.RegularExpressions.Regex`, anchoring a supplied pattern
  with `^(?:...)$` exactly as `FormValidator` does, and use
  `double.ToString("G", CultureInfo)`-based formatting (not
  `int.Parse`) for bounds messages so an out-of-`int`-range `maximum`
  cannot throw while building the message. `HTDVDataSource`'s
  network-backed implementations would use `HttpClient` and
  `System.Text.Json`; nothing in these nine sources needs
  `Windows.Storage`, since none of them persists anything (see Privacy).

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
responsibility - call the closure and handle its `throws` itself - instead
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

**Decision (AppKit/UIKit)**: `MarkdownEditing.swift` defines the
`MarkdownEditing` protocol and ships a concrete default implementation
(`PlainTextMarkdownEditing`, with AppKit and UIKit view controllers) in
the same file, unlike the other eight given sources, which hold no
AppKit/UIKit-specific code.
**Rationale**: Per the source's own comment, `PlainTextMarkdownEditing` is
explicitly a placeholder - "adequate for configuration notes until the
markdown module lands" - with the hub app expected to inject a real
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
AppKit/UIKit default implementation in the same file - see Design
Decisions. unit-test-coverage passes because every one of the nine sources
has a corresponding test file with meaningful assertions:
`HTDVControllerTests.swift` (29 tests, including stale-result protection),
`HTDVLayoutEngineTests.swift`, `HTDVModelTests.swift`, `FormStateTests.swift`,
`FormValidatorTests.swift`, and `PlainTextMarkdownEditingTests.swift`.
explicit-error-handling passes because every `throws` boundary in these
sources is caught and turned into explicit, observable state -
`HTDVController.fail(...)` sets `error`, `FormState.save()` sets
`saveError` - with the one narrower exception noted under Edge Cases'
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
because every user-facing string these sources produce - `FormValidator`'s
messages, `HTDVLevel.emptyMessage`'s default, `FormDeleteAction`'s
documented confirmation fallback - is a hardcoded English literal with no
localization key, per Localization above.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/navigation/. |
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | | | Initial creation |
