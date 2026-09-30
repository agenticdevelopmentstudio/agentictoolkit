<!-- leaf: implement-composable-tabs/view-registry--test-vectors · source: composable-tabs-view-registry.md -->

# ComposableTabsViewRegistry

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| CTVR-01 | placeholder-registration | A freshly constructed `ComposableTabsViewRegistry` | `isRegistered(.placeholder)` is `true` |
| CTVR-02 | register-overwrite | Register a view id, then register it again with a different descriptor/factory | `descriptor(for:)` reflects the second registration; the first factory is never invoked |
| CTVR-03 | placeholder-protection | `unregister(.placeholder)` | Returns `false`; `isRegistered(.placeholder)` remains `true`; an error is logged |
| CTVR-04 | unregister-removal | Register a non-placeholder view id, then `unregister` it | Returns `true`; `isRegistered(_:)` is `false` afterward |
| CTVR-05 | unregister-absence | `unregister` a view id that was never registered | Returns `false` |
| CTVR-06 | view-id-ordering | Register `"z.view"`, `"a.view"`, `"m.view"` | `registeredViewIDs` returns `[a.view, m.view, .placeholder, z.view]` in ascending `rawValue` order — `.placeholder`'s `rawValue` is `"whippet.placeholder"`, which sorts between `"m.view"` and `"z.view"` |
| CTVR-07 | registration-presence | Query `isRegistered(_:)` for a registered and an unregistered id | Returns `true` and `false` respectively |
| CTVR-08 | descriptor-default | `descriptor(for:)` for an unregistered view id | Returns `ComposableTabsViewDescriptor.unknown` (`displayName == "Unknown"`) |
| CTVR-09 | factory-dispatch | Register a view id with a factory returning a distinguishable view controller, then call `makeContentViewController` for it | The returned view controller is the one the factory produced |
| CTVR-10 | unregistered-fallback | Call `makeContentViewController` for an unregistered view id with `paneNumber: 3` | Returns a `PlaceholderPaneViewController` showing "Pane 3"; an error is logged |
| CTVR-11 | tree-id-default | Call `makeContentViewController` with `treeID: nil` and a given `nodeID` | The factory's `ComposableTabsViewContext.treeID` equals that `nodeID` |
| CTVR-12 | context-passthrough | Call `makeContentViewController` with distinct `project`, `workingDirectory`, `paneNumber`, `ownerNodeID` values | The factory's `ComposableTabsViewContext` carries each value unchanged |
| CTVR-13 | state-store-owner | Call `makeStateStore(prefix:)` on a context built with a non-nil `ownerNodeID` | The returned `ProjectPaneStateStore.ownerNodeID` equals the context's `ownerNodeID` |
| CTVR-14 | explicit-holding-priority | A descriptor with `holdingPriority: .defaultHigh` and `preferredThicknessFraction: 0.5` | `resolvedHoldingPriority` equals `.defaultHigh` |
| CTVR-15 | fractioned-priority-boost | A descriptor with `holdingPriority: nil`, `preferredThicknessFraction: 0.3` | `resolvedHoldingPriority.rawValue` equals `NSLayoutConstraint.Priority.defaultLow.rawValue + 10` |
| CTVR-16 | default-low-priority | A descriptor with `holdingPriority: nil`, `preferredThicknessFraction: nil` | `resolvedHoldingPriority` equals `.defaultLow` |
| CTVR-17 | optional-teardown | A content type does not adopt `PaneContentTeardown` | Casting an instance to `PaneContentTeardown?` yields `nil`; nothing in this file requires or assumes the cast succeeds |
| CTVR-18 | optional-removal-confirmation | A content type adopts `PaneContentRemovalConfirmation` and returns `nil` from `removalConfirmationMessage`, and separately a content type that does not adopt the protocol at all | `removalConfirmationMessage` is `nil` in the adopting case; casting to `PaneContentRemovalConfirmation?` is `nil` in the non-adopting case — both mean "nothing would be lost" per this file's protocol contract |
| CTVR-19 | placeholder-pane-number | Construct `PlaceholderPaneViewController(paneNumber: 5)` and load its view | The title label's `stringValue` is "Pane 5" |
| CTVR-20 | placeholder-series-tint | Load a placeholder for `paneNumber: 2` under a theme whose `chartSeriesNSColors` has at least 2 entries | The container layer's `backgroundColor` equals `series[1]` at 0.15 alpha |
| CTVR-21 | empty-series-no-tint | Load a placeholder under a theme whose `chartSeriesNSColors` is empty | The container layer's `backgroundColor` is unchanged from its default |
| CTVR-22 | placeholder-retint | Load a placeholder, then switch the active theme | The container's tint is recomputed against the new theme's `chartSeriesNSColors` |
| CTVR-23 | placeholder-title-centering | Load a placeholder's view and lay it out | The title's center X and center Y equal the container's center X and center Y |
| CTVR-24 | coder-init-unavailable | Attempt to instantiate `PlaceholderPaneViewController` via `init(coder:)` (e.g. from a storyboard/XIB unarchive) | The process traps with a fatal error |
| CTVR-25 | stale-tint-persistence | Load a placeholder under a theme with a non-empty `chartSeriesNSColors`, note the container's tint, then switch to a theme whose `chartSeriesNSColors` is empty | The container layer's `backgroundColor` remains the tint set under the prior theme, unchanged |
