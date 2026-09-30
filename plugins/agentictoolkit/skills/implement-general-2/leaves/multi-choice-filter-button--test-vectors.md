<!-- leaf: implement-general-2/multi-choice-filter-button--test-vectors · source: multi-choice-filter-button.md -->

# MultiChoiceFilterButton

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| multi-choice-filter-button-001 | builds-fixed-menu-structure | Construct with `label: "Good for"`, `choices: [a, b]` | Menu has exactly 4 items in order: `label` (no action), "Any", a separator, then items titled `a.title` and `b.title` |
| multi-choice-filter-button-002 | sets-choice-tooltip | Choice `a` has `detail: "Runs code"`; choice `b` has `detail: ""` | `a`'s menu item has `toolTip == "Runs code"`; `b`'s menu item's `toolTip` is unset |
| multi-choice-filter-button-003 | clears-selection-on-any | `selection == ["a"]`; invoke the "Any" item's action | `selection == []` |
| multi-choice-filter-button-004 | toggles-choice-on-select | `selection == []`; invoke choice `a`'s item action | `selection == ["a"]` |
| multi-choice-filter-button-005 | toggles-choice-on-select | `selection == ["a"]`; invoke choice `a`'s item action again | `selection == []` |
| multi-choice-filter-button-006 | restricts-selection-to-known-ids | `choices` ids are `["a","b"]`; call `setSelection(["a","z"])` | `selection == ["a"]`; `"z"` is discarded |
| multi-choice-filter-button-007 | reflects-checkmarks | `selection == []`; invoke choice `a`'s item action | `a`'s menu item `state == .on`; every other choice item's `state == .off` |
| multi-choice-filter-button-008 | reflects-checkmarks | `selection == ["a"]`; manually set `a`'s menu item `state` to `.off` (simulating drift), then call `setSelection(["a"])` (no-op value) | `a`'s menu item `state` is resynchronized back to `.on` by the call |
| multi-choice-filter-button-009 | fires-on-change-on-actual-change | `onChange` recorder attached; `selection == []`; invoke choice `a`'s item action | `onChange` is invoked exactly once with `["a"]` |
| multi-choice-filter-button-010 | fires-on-change-on-actual-change | `onChange` recorder attached; `selection == []`; invoke the "Any" item's action | `onChange` is not invoked |
| multi-choice-filter-button-011 | formats-title-none-selected | `label: "Good for"`, `selection == []` | Button title == `"Good for: Any"` |
| multi-choice-filter-button-012 | formats-title-few-selected | `label: "Good for"`, `choices` titled `["Coding","Writing"]`, both selected | Button title == `"Good for: Coding, Writing"` |
| multi-choice-filter-button-013 | formats-title-many-selected | `label: "Good for"`, 4 of the choices selected | Button title == `"Good for: 4 selected"` |
| multi-choice-filter-button-014 | refreshes-title-synchronously | Invoke choice `a`'s item action | The button's displayed title already matches `"<label>: a.title"` immediately after the call returns, with no further user action needed to refresh it |
| multi-choice-filter-button-015 | resizes-for-longer-titles | Selection goes from 0 choices ("Any") to 2 choices with long titles | The button's `intrinsicContentSize.width` after the change is wide enough to display the new title without truncation, and is greater than it was before the change |
| multi-choice-filter-button-016 | exposes-readonly-selection | From outside the type, attempt `button.selection = ["a"]` | Compilation fails: `selection`'s setter is not accessible outside the type |
| multi-choice-filter-button-017 | themes-text-appearance | Construct the button, then post a theme-change notification with a new `ColorTheme` | `contentTintColor` and `font` update to the new theme's `primaryTextColor` and `font(.body)` without re-constructing the button |
| multi-choice-filter-button-018 | rejects-coder-initialization | Attempt `MultiChoiceFilterButton(coder: someCoder)` | The call traps with a fatal error; no instance is returned |
| multi-choice-filter-button-019 | confines-to-main-actor | Attempt to construct or mutate a `MultiChoiceFilterButton` from off the main actor | Compiler rejects the call at compile time under Swift's `@MainActor` isolation checking |
| multi-choice-filter-button-020 | disables-autoresizing-mask-translation | Construct the button | `translatesAutoresizingMaskIntoConstraints == false` |
| multi-choice-filter-button-021 | label-and-any-never-checked | Construct with `choices: [a, b]`; invoke choice `a`'s item action | Item 0's and the "Any" item's `state` remain `.off`; only `a`'s item is `.on` |
| multi-choice-filter-button-022 | initializes-selection-empty | Construct the button; check `selection` immediately, before any interaction | `selection == []` |
