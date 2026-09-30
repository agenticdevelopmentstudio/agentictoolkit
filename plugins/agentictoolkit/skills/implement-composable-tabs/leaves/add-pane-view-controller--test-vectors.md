<!-- leaf: implement-composable-tabs/add-pane-view-controller--test-vectors · source: composable-tabs-add-pane-view-controller.md -->

# ComposableTabsAddPaneViewController

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| add-pane-001 | populates-view-popup-from-choices | `choices = [A (no symbol), B (symbol "terminal")]` | "Add" popup has 2 items, titled A's `displayName` then B's, in that order |
| add-pane-002 | sets-choice-icon-when-symbol-present | `choices` includes an entry with `symbolName == "terminal"` | That item's image is the "terminal" SF Symbol, with accessibility description equal to its `displayName` |
| add-pane-003 | omits-choice-icon-when-symbol-absent | `choices` includes an entry with `symbolName == nil` | That item's image is `nil` |
| add-pane-004 | populates-where-popup-in-fixed-order | Any `choices` value | "Where" popup contains exactly 4 items titled "Left", "Right", "Above", "Below" in that order |
| add-pane-005 | defaults-where-selection-to-right | Load the sheet | The "Where" popup's selected item is "Right" |
| add-pane-006 | arranges-add-and-where-as-two-row-grid | Inspect the grid after `loadView()` | The grid has exactly 2 rows and 2 columns |
| add-pane-007 | add-row-precedes-where-row | Inspect the grid's rows | Row 0 holds the Add label/popup; row 1 holds the Where label/popup |
| add-pane-008 | ok-button-disabled-when-choices-empty | `choices = []` | `okButton.isEnabled == false` |
| add-pane-009 | ok-button-enabled-when-choices-present | `choices = [A]` | `okButton.isEnabled == true` |
| add-pane-010 | ok-button-enabled-state-fixed-at-load | Load with `choices = [A]`; change the Where selection, then the Add selection | `okButton.isEnabled` remains `true`, unchanged by either selection |
| add-pane-011 | cancel-precedes-ok-in-button-order | Inspect the button stack's `views` | `views[0]` is Cancel, `views[1]` is OK |
| add-pane-012 | cancel-bound-to-escape-key | Inspect `cancel.keyEquivalent` | Equals `"\u{1b}"` |
| add-pane-013 | ok-bound-to-return-key | Inspect `okButton.keyEquivalent` | Equals `"\r"` |
| add-pane-014 | cancel-dismisses-without-invoking-onadd | Click Cancel | The sheet is dismissed; `onAdd` is never called |
| add-pane-015 | confirm-dismisses-before-invoking-onadd | Select a valid Add and Where combination; click OK | `dismiss(_:)` is invoked before `onAdd` (observable via call-order instrumentation) |
| add-pane-016 | confirm-invokes-onadd-with-selection | "Add" popup selects `choices[1]`; "Where" popup selects "Above" | `onAdd` is called once, with `(choices[1].viewID, .above)` |
| add-pane-017 | confirm-dismisses-without-onadd-on-invalid-selection | `choices = []`; force-invoke the private confirm action by selector name (`NSApp.sendAction(Selector(("confirm:")), to: controller, from: nil)`), leaving the "Add" popup's selected index `== -1` | The sheet is dismissed; `onAdd` is never called |
| add-pane-018 | enforces-minimum-container-width | Measure the container's width constraint after `loadView()` | A `greaterThanOrEqualToConstant` constraint of 320pt exists on the container's width |
| add-pane-019 | root-view-accessibility-identifier | Inspect the container's accessibility identifier | Equals "composable-tabs.add-pane" |
| add-pane-020 | view-popup-accessibility-identifier | Inspect the "Add" popup's accessibility identifier | Equals "composable-tabs.add-pane.view" |
| add-pane-021 | where-popup-accessibility-identifier | Inspect the "Where" popup's accessibility identifier | Equals "composable-tabs.add-pane.where" |
| add-pane-022 | cancel-button-accessibility-identifier | Inspect the Cancel button's accessibility identifier | Equals "composable-tabs.add-pane.cancel" |
| add-pane-023 | ok-button-accessibility-identifier | Inspect the OK button's accessibility identifier | Equals "composable-tabs.add-pane.ok" |
| add-pane-024 | add-row-label-text | Inspect the Add row's label | Text reads "Add:"; alignment is right |
| add-pane-025 | where-row-label-text | Inspect the Where row's label | Text reads "Where:"; alignment is right |
| add-pane-026 | coder-initialization-unsupported | Attempt to construct the component via its coder initializer | Execution traps with a fatal error; no instance is produced |
