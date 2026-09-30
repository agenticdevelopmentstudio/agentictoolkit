<!-- leaf: implement-composable-tabs/add-pane-view-controller--part-2 · source: composable-tabs-add-pane-view-controller.md -->

# ComposableTabsAddPaneViewController — continued (part 2)

## Accessibility Options

- **Reduce Motion**: Not applicable — source defines no animation,
  transition, or `NSAnimationContext` call; the sheet's content is built
  once, synchronously, in `loadView()`.
- **Increase Contrast**: Every color in this file comes from a `ThemeRole`
  (`.windowBackground`, `.primaryText`) resolved by the shared theme
  system; the file itself sets no literal `NSColor` and performs no
  contrast-specific branching. Whether the resolved colors meet a minimum
  contrast ratio is determined by theme resolution, not this file — see
  Compliance's **contrast-ratio** check, marked partial for the same
  reason.
- **Differentiate Without Color**: Not applicable — the component conveys
  no state through color alone; the Add/Where choices and the OK/Cancel
  actions are identified by text and icons, not color.

## Privacy

- **Data collected**: None beyond the in-memory popup selections the user
  makes while the sheet is open.
- **Storage**: None — selections live only in the two popups' selection
  state for the sheet's lifetime; nothing is written to disk,
  `UserDefaults`, or any other store by this file.
- **Transmission**: None — `onAdd` hands the selected
  `ComposableTabsViewID` and `Direction` directly to the caller in-process;
  this file makes no network or IPC call.
- **Retention**: None beyond the sheet's lifetime; the selection is
  discarded once the sheet is dismissed, whether via Cancel, OK, or an
  invalid-selection confirm.

## Platform Notes

- **SwiftUI**: Model the sheet as a small form presented via
  `.sheet(isPresented:)`, with a `Picker("Add:", selection: $selectedChoice)`
  populated from `choices` and a `Picker("Where:", selection:
  $selectedDirection)` populated from the four `Direction` cases,
  defaulting `selectedDirection` to `.right`. Give an "Add" option a
  `Label(choice.displayName, systemImage: choice.symbolName)` when a symbol
  exists, mirroring the source's per-item image. A footer `Button("Cancel")`
  with `.keyboardShortcut(.cancelAction)` and `Button("OK")` with
  `.keyboardShortcut(.defaultAction)` reproduce the Escape/Return bindings,
  and `.disabled(choices.isEmpty)` computed once at sheet-open time
  reproduces the fixed-at-load OK enablement.
- **Compose**: Use two dropdown-menu composables inside an `AlertDialog`
  (or a `Dialog` with custom content) — one bound to a `selectedChoice`
  state seeded to the first entry, or to no selection when `choices` is
  empty, one to a `selectedDirection` state seeded to the "right"
  direction. Render each Add-menu item with an
  optional leading icon when a symbol equivalent exists, mirroring the
  source's per-item image. Wire the dialog's confirm/dismiss actions
  through its own confirm/dismiss slots, disabling the confirm action once,
  at open time, when `choices` is empty, mirroring the fixed-at-load
  `okButton.isEnabled`.
- **React/Web**: A small modal built on a dialog primitive, containing two
  native selection controls — one populated from `choices` (each option
  carrying the choice's `displayName`, with an optional leading icon
  rendered alongside if icons are needed), one populated from the four
  direction labels defaulting to "Right" — plus "Cancel" and "OK" buttons.
  Bind Escape to Cancel and Enter/form submit to OK, mirroring the AppKit
  key equivalents, and set the OK button's disabled state once, at open
  time, from `choices.length === 0`, mirroring the source's fixed-at-load
  enablement rather than a reactive binding.
- **AppKit / UIKit** (source platform): Implemented in
  `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/ComposableTabs/ComposableTabsAddPaneViewController.swift`
  as a `@MainActor`, `final` `NSViewController` with no nib/XIB —
  `loadView()` builds an `NSGridView` of two `NSPopUpButton`s and their
  `ThemedLabel` captions, plus an `NSStackView` of Cancel/OK `NSButton`s,
  laid out with Auto Layout against a `ThemedBackgroundView` root. Arrange
  mode presents it as a sheet from its Add button. There is no UIKit code
  path in source; a UIKit port would replace the two `NSPopUpButton`s with
  `UIButton`s presenting menus (or two rows of a grouped table/picker
  view), replace the grid with a stack view of horizontal rows, and present
  the whole thing as a small view controller in a form-sheet presentation,
  since UIKit has no direct analog of `NSGridView`/`NSPopUpButton`.
- **WinUI 3**: Build the sheet as a
  `ContentDialog` with `PrimaryButtonText="OK"` and
  `CloseButtonText="Cancel"` — `ContentDialog` already binds its primary
  button to Enter and its close button to Escape, the direct analogs of the
  source's Return/Escape key equivalents — and set `IsPrimaryButtonEnabled`
  once, at open time, from `Choices.Count > 0`, mirroring the fixed-at-load
  `okButton.isEnabled` rather than a live binding. Lay out two rows of
  `TextBlock` + `ComboBox` in a `Grid` with two `RowDefinitions` and two
  `ColumnDefinitions` (label column `HorizontalAlignment="Right"`,
  matching the source grid's trailing label placement) — an "Add:" row
  bound to a `ComboBox` populated from the choices collection (each item a
  horizontal panel of an optional icon glyph plus a text run for the
  display name, mirroring the source's per-item SF Symbol image) and a
  "Where:" row bound to a `ComboBox` of the four direction labels, with
  `SelectedIndex` initialized to the index of "Right". Handle the
  `ContentDialog`'s primary-button-click event to read both `ComboBox`
  selections and raise the add-pane event only after `ShowAsync()` has
  returned and the dialog has closed, mirroring the source's
  dismiss-before-invoke ordering in the confirm action.

## Design Decisions

**Decision**: Split "what to add" and "where to put it" into two independent
popups rather than one flattened list (e.g. "Add Terminal Below").
**Rationale**: Per the type's doc comment, the second answer (the four
directions) is the same regardless of the first, so a flattened list would
force the user to read a cross product of eight or twelve items instead of
making two small choices.
**Approved**: pending

**Decision**: Default the "Where" popup's selection to "Right" rather than
the first item ("Left") or no selection.
**Rationale**: Per the source comment, the pane the user is looking at is on
the left of a document more often than not, so placing the new pane to its
right is the least surprising default.
**Approved**: pending

**Decision**: Dismiss the sheet before invoking `onAdd` in the confirm
action, rather than invoking `onAdd` first.
**Rationale**: Per the source comment, `onAdd` re-parents view controllers by
splitting the pane; doing that while the sheet is still presented would
leave the sheet anchored to a window whose content has already moved out
from under it.
**Approved**: pending

**Decision**: Fix the direction list to the hardcoded order left, right,
above, below and reuse that same list both to populate the "Where" popup
and to map its selected index back to a direction.
**Rationale**: Per the source comment, a fixed order makes the popup read
the way the pane visually looks; reusing one list for both population and
index-mapping keeps the two in sync by construction rather than by
convention.
**Approved**: pending

**Decision**: Center-align the grid's rows instead of using `NSGridView`'s
default first-baseline row alignment.
**Rationale**: Per the source comment, a label baseline-aligned against a
popup sits high in it, which reads as a row that did not quite line up;
centering both views in the row instead makes the label and popup look
vertically aligned.
**Approved**: pending

**Decision**: Leave a defensive fallback to index 0 for the "Right" lookup,
even though the direction list is a hardcoded literal that always contains
"Right".
**Rationale**: Not explained in source; recorded here as an observed,
currently-unreachable defensive path, so other-platform implementations do
not need to reproduce a "what if Right is missing" branch.
**Approved**: pending
