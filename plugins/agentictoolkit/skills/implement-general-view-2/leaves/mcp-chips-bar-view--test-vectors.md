<!-- leaf: implement-general-view-2/mcp-chips-bar-view--test-vectors · source: mcp-chips-bar-view.md -->

# MCPChipsBarView

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| mcp-chips-bar-001 | hosts-swiftui-content | Initialize `MCPChipsBarView(registry:activeServerIds:)` | Its subview tree contains exactly one `NSHostingView` whose root view is `MCPChipsBar`, and reading `\.theme` from that root view's environment returns the app's active theme (see Platform Notes for the mechanism) |
| mcp-chips-bar-002 | disables-autoresizing-mask | Inspect the view and its hosted subview after init | Both report `translatesAutoresizingMaskIntoConstraints == false` |
| mcp-chips-bar-003 | fills-parent-bounds | Initialize with the parent view at frame `(0, 0, 300, 40)`, then resize the parent to `(0, 0, 500, 60)` and force a layout pass (`layoutSubtreeIfNeeded()`) | The hosted view's frame equals `(0, 0, 500, 60)`, matching the parent's new bounds on all four edges |
| mcp-chips-bar-004 | rejects-coder-initialization | Attempt `MCPChipsBarView(coder:)` | The call traps with a fatal error; no instance is returned |
| mcp-chips-bar-005 | shares-one-view-model-between-bar-and-picker | Initialize the view once, open the popover, then switch id1's row `Toggle` | The bar's button label recomputes to reflect the new active count without re-initializing the view — the bar and the popover are driven by the same active-server state |
| mcp-chips-bar-006 | snapshots-active-ids-at-init | Construct with a binding whose `wrappedValue` is `{A, B}`, then mutate the binding's external storage to `{C}` before any toggle | The view model's `activeServerIds` remains `{A, B}` |
| mcp-chips-bar-007 | subscribes-to-registry-clients, sorts-available-servers-by-name, rebuilds-server-names-on-update | Registry emits clients `[id1: "Bravo", id2: "alpha"]` | `availableServerIds == [id2, id1]` (case-insensitive "alpha" before "Bravo") and `serverNames == [id1: "Bravo", id2: "alpha"]` |
| mcp-chips-bar-008 | defaults-missing-name-to-empty-string-for-sort | Code inspection of the sort comparator in `MCPChipsBarViewModel.init` (`clients[lhs]?.name ?? ""` / `clients[rhs]?.name ?? ""`) | The comparator falls back to `""` for a missing name instead of crashing or force-unwrapping; this branch is unreachable through the current call site, since `Array(clients.keys)` is always sorted against that same `clients` dictionary, but the defensive default is present and correct if that ever changes |
| mcp-chips-bar-009 | reports-active-membership | `activeServerIds` contains id1 but not id2 | `isActive(id1) == true`, `isActive(id2) == false` |
| mcp-chips-bar-010 | toggles-membership-on-call, propagates-toggle-to-binding | `activeServerIds` does not contain id1; call `toggle(id1)` | `activeServerIds` now contains id1, and the caller's binding's `wrappedValue` equals the new set |
| mcp-chips-bar-011 | toggles-membership-on-call, propagates-toggle-to-binding | `activeServerIds` contains id1; call `toggle(id1)` | `activeServerIds` no longer contains id1, and the caller's binding's `wrappedValue` equals the new set |
| mcp-chips-bar-012 | renders-server-rack-icon | Render `MCPChipsBar` | An `Image(systemName: "server.rack")` is present, foreground-styled with `theme.secondaryText` |
| mcp-chips-bar-013 | computes-no-servers-label | `availableServerIds == []` | Button text reads exactly "No MCP servers" |
| mcp-chips-bar-014 | computes-none-active-label | `availableServerIds == [id1, id2]`, `activeServerIds == []` | Button text reads exactly "MCP: none" |
| mcp-chips-bar-015 | computes-count-active-label | `availableServerIds == [id1, id2, id3]`, `activeServerIds == {id1, id3}` | Button text reads exactly "MCP: 2 of 3" |
| mcp-chips-bar-016 | uses-borderless-button-style | Inspect the toggle button's style | `.borderless` button style is applied |
| mcp-chips-bar-017 | toggles-picker-on-tap | `showingPicker == false`; tap the button | `showingPicker == true` |
| mcp-chips-bar-018 | presents-popover-below-button | `showingPicker == true` | A popover is presented with `arrowEdge == .bottom` |
| mcp-chips-bar-019 | reapplies-theme-inside-popover | Inspect the popover's content view | `MCPServerPicker` is wrapped in its own `.themedRoot()` call, distinct from the bar's |
| mcp-chips-bar-020 | applies-bar-padding, trails-with-spacer | Inspect the bar's root `HStack` | 8pt spacing between children, 12pt horizontal / 6pt vertical padding on the stack, and a `Spacer()` as the final child |
| mcp-chips-bar-021 | shows-picker-heading | Render `MCPServerPicker` | "Active MCP Servers" is displayed in `theme.font(.heading)` |
| mcp-chips-bar-022 | shows-empty-state-message, lists-one-toggle-row-per-server | `availableServerIds == []` | The empty-state message "No connected servers.\nAdd one in Settings → MCP Servers." is shown and no `Toggle` row is rendered |
| mcp-chips-bar-023 | lists-one-toggle-row-per-server, row-label-falls-back-to-unknown | `availableServerIds == [id1, id2]`, `serverNames == [id1: "Alpha"]` (id2 missing) | Exactly two rows render, in order id1 then id2, labeled "Alpha" and "Unknown" respectively |
| mcp-chips-bar-024 | row-toggle-reflects-active-state | id1 is a member of `activeServerIds` | id1's row `Toggle` reads on (checked) |
| mcp-chips-bar-025 | row-toggle-calls-view-model-toggle | id1's row `Toggle` is switched by the user | `viewModel.toggle(id1)` is invoked exactly once |
| mcp-chips-bar-026 | uses-checkbox-toggle-style | Inspect any rendered row `Toggle` | `.checkbox` toggle style is applied |
| mcp-chips-bar-027 | applies-picker-padding-and-min-width | Inspect `MCPServerPicker`'s root `VStack` | 8pt spacing, 14pt padding on all sides, and a minimum width of 220pt |
