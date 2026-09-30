<!-- leaf: implement-window-matching/shortcuts--test-vectors · source: window-matching-shortcuts.md -->

# Window Matching Shortcuts

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| wms-001 | index-shortcut-count | Read `contextSwitchByIndex.count` | `9` (from `SystemWindowShortcutNamesTests.contextSwitchByIndexHasNineEntries`) |
| wms-002 | all-shortcuts-list | Read `allWindowContextShortcuts.count` | `14` (from `allShortcutsCount`) |
| wms-003 | unique-names | Map `allWindowContextShortcuts` to raw values; compare count with the count of the set of them | Counts equal (from `namesAreUnique`) |
| wms-004 | index-shortcut-order, stable-raw-values | Map `contextSwitchByIndex` to raw values | `["switchToContext1", …, "switchToContext9"]` in that order (from `contextSwitchNamesAreOrdered`) |
| wms-005 | every-name-has-default | For each name in `allWindowContextShortcuts`, read `defaultShortcut` | Non-nil for all fourteen (from `allShortcutsHaveDefaults`) |
| wms-006 | action-shortcut-names, default-picker-chord, all-shortcuts-list | Read `contextPicker.rawValue`, `contextPicker.defaultShortcut`, `allWindowContextShortcuts.contains(.contextPicker)` | `"contextPicker"`, non-nil, `true` (from `contextPickerShortcutIsRegistered`) |
| wms-007 | default-index-chords | Read `switchToContext3.defaultShortcut` | Key `3`, modifiers exactly Control+Option |
| wms-008 | default-add-chord, default-remove-chord, default-next-chord, default-previous-chord | Read the defaults of `addWindow`, `removeWindow`, `nextContext`, `previousContext` | A, X, N, P respectively, each with exactly Control+Option |
| wms-009 | all-shortcuts-list | Read `allWindowContextShortcuts` elements 9…13 | `addWindow`, `removeWindow`, `nextContext`, `previousContext`, `contextPicker` |
| wms-010 | register-on-init, dispatch-index | Model with contexts `[A, B, C]`; construct the manager; fire key-down for `switchToContext2` | `model.switchContext(to: B.id)` called once |
| wms-011 | index-out-of-range-noop | Model with 2 contexts; fire key-down for `switchToContext5` | No model method called; no error set |
| wms-012 | index-out-of-range-noop | Model with 0 contexts; fire key-down for `switchToContext1` | No model method called |
| wms-013 | index-read-at-fire-time | Construct the manager with 1 context; append a second context; fire `switchToContext2` | `model.switchContext(to:)` called with the new context's id |
| wms-014 | dispatch-add, result-ignored | Fire key-down for `addWindow` | `model.addFrontmostWindow()` called once; manager takes no further action on either return value |
| wms-015 | dispatch-remove | Fire key-down for `removeWindow` | `model.removeFrontmostWindow()` called once |
| wms-016 | dispatch-next | Fire key-down for `nextContext` | `model.switchToNextContext()` called once |
| wms-017 | dispatch-previous | Fire key-down for `previousContext` | `model.switchToPreviousContext()` called once |
| wms-018 | dispatch-picker | Fire key-down for `contextPicker` twice | `model.toggleContextPicker()` called twice (picker visibility returns to its starting value) |
| wms-019 | reserve-external | Construct the manager; ask `KeyCommandRegistry.shared.availability(of:for:)` about Control+Option+A for an unrelated command id | `.unavailable("taken by window contexts")` |
| wms-020 | reservation-follows-customization | Construct the manager; set `addWindow` to Control+Option+Z; query availability of Control+Option+Z and of Control+Option+A for an unrelated command | Z is `.unavailable("taken by window contexts")`; A is not refused by the window-contexts reservation |
| wms-021 | weak-handler-capture, no-unregister-on-release | Construct a manager, drop every strong reference, fire key-down for `addWindow` | No model method called; the chord remains reserved in the registry |
| wms-022 | init-log | Construct the manager | One info log `SystemWindowShortcutManager initialized, all handlers registered` in category `SystemWindowShortcutManager` |
| wms-023 | main-actor-isolation | Construct the manager from a non-main-actor context without `await` | Compile-time error |
