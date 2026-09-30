<!-- leaf: implement-general-2/multi-choice-filter-button--edge-cases · source: multi-choice-filter-button.md -->

# MultiChoiceFilterButton

**Rules** (cite as `implement-general-2/multi-choice-filter-button--edge-cases#<slug>`):

- `design-decisions-callers-supply-unique-ids-across` MUST — Duplicate ids within choices: the source enforces no uniqueness on Choice.id. If two entries share an id, both of their …
- `title-many-selected-transition-from-selected-selected` MUST — Boundary values: the selection-count boundaries are 0, 1–2, and 3+, exactly the three branches in …
- `nor-onchange-runs-syncstates-still-called-immediately` MUST — Selecting "Any" while selection is already empty: selection = [] is assigned but its didSet guard (selection != …
- `checkmarks-still-resynchronized-callers-relying-onchange-detect` MUST — setSelection(_:) called with a set that intersects down to the current selection's value: the same didSet guard …

## Edge Cases

- Null/empty input: `label` (`String`) and `choices` (`[Choice]`) are
  non-optional, typed initializer parameters; Swift's type system rules out
  `nil` for either. The component therefore provides, and needs, no
  nil-handling path.
- Empty `choices` array: `buildMenu()` still produces item 0, "Any", and the
  separator, but no choice items follow. `selection` can never become
  non-empty (there is nothing to toggle), so the title is permanently
  `"<label>: Any"`. The component does not crash or special-case this; it
  falls straight out of the existing menu-building and title-formatting
  logic.
- Duplicate ids within `choices`: the source enforces no uniqueness on
  `Choice.id`. If two entries share an id, both of their menu items match
  the same membership test in `syncStates()` and are therefore always kept
  in the same checked state as each other, while `selection` (a
  `Set<String>`) holds that id only once regardless of how many menu
  entries reference it. This is the source's actual, as-written behavior —
  a duplicate id is not rejected or deduplicated by
  `MultiChoiceFilterButton` itself (see Design Decisions). Callers MUST
  supply unique ids across `choices`; behavior is undefined if two choices
  share an id.
- Boundary values: the selection-count boundaries are 0, 1–2, and 3+,
  exactly the three branches in **formats-title-none-selected**,
  **formats-title-few-selected**, and **formats-title-many-selected**. MUST:
  the transition from 2 selected ("`a`, `b`") to 3 selected ("3 selected")
  happens at exactly `selection.count == 3`, with no intermediate form.
- Concurrent access: Not applicable — the class is declared `@MainActor`,
  so all construction, menu-item actions, and `setSelection(_:)` calls are
  serialized to the main actor by the compiler (see
  **confines-to-main-actor**).
- Error states: Not applicable — every operation in this file (menu
  building, toggling, title formatting, theming) is a synchronous,
  non-throwing call; no `try`, `Result`, or error-producing API appears in
  source.
- Offline/disconnected: Not applicable — the component performs no
  networking; it only manages an in-process menu and selection set.
- Selecting "Any" while `selection` is already empty: `selection = []` is
  assigned but its `didSet` guard (`selection != oldValue`) is false, so
  neither `refreshTitle()` nor `onChange` runs. MUST: `syncStates()` is
  still called immediately after, from `clearSelection()`'s own body, so
  every choice item's checkmark is still resynchronized on this call even
  though nothing visibly changes (see **reflects-checkmarks**).
- `setSelection(_:)` called with a set that intersects down to the current
  `selection`'s value: the same `didSet` guard suppresses `refreshTitle()`/
  `onChange`, but `setSelection(_:)`'s own body calls `syncStates()`
  unconditionally on every call, so checkmarks are still resynchronized.
  MUST: callers relying on `onChange` to detect a `setSelection(_:)` call
  MUST NOT assume it fires when the resulting set is unchanged.
