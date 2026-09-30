<!-- leaf: implement-general-controller/multi-tabbed-view-controller--edge-cases · source: multi-tabbed-view-controller.md -->

# MultiTabbedViewController

**Rules** (cite as `implement-general-controller/multi-tabbed-view-controller--edge-cases#<slug>`):

- `null-empty-input-tabs-return-edge-tabs` MUST — Null/empty input (MUST): tabs(on:) MUST return [] for an edge with no tabs, never trap. …
- `boundary-values-inserttab-clamp-max-min` MUST — Boundary values (MUST): insertTab(_:at:on:)'s clamp (max(0, min(index, count))) and moveTab(id:to:on:)'s clamp (max(0, …
- `error-states-edge-fortabid-returning-nil` MUST — Error states (MUST): edge(forTabID:) returning nil for an unknown id MUST make removeTab(id:), renameTab(id:title:), …
- `tab-content-callers-supply-distinct-controller-per` MUST — Reusing one view-controller instance across two tabs: unguarded caller precondition. Nothing in addTab/insertTab …

## Edge Cases

- Null/empty input (MUST): `tabs(on:)` MUST return `[]` for an edge with no
  tabs, never trap. `selectedTab(on:)`/`selectedTabID(on:)` MUST return `nil`
  when the active tab (if any) is not a member of the given edge. With both
  `mainContentViewController == nil` and no active tab, the shared content
  area MUST be left with no mounted controller at all rather than showing a
  blank placeholder controller.
- Boundary values (MUST): `insertTab(_:at:on:)`'s clamp
  (`max(0, min(index, count))`) and `moveTab(id:to:on:)`'s clamp
  (`max(0, min(index, count - 1))`) MUST both handle an index below `0` or
  past the end of the list the same way as one already in range — neither
  traps nor silently ignores the call.
- Concurrent access: Not applicable — `MultiTabbedViewController`, `Tab`'s
  storage (`EdgeState`), and `TabBarView` are all `@MainActor`-isolated; every
  mutating entry point (`addTab`, `removeTab`, `moveTab`, `setEdgeEnabled`,
  `selectTab`, and the internal sync/activation methods) runs on the main
  actor, so source provides no path for two threads to mutate one instance at
  the same time.
- Error states (MUST): `edge(forTabID:)` returning `nil` for an unknown id
  MUST make `removeTab(id:)`, `renameTab(id:title:)`, and `setTabItem(id:item:)`
  silent no-ops rather than trap. `selectTab(id:on:)` MUST be silently ignored
  when `id` is not a member of the given edge's own list — it does not search
  other edges for it. `delegate` is `weak`; a deallocated delegate MUST make
  every `delegate?...` call a no-op without preventing the underlying tab
  mutation from completing.
- Offline/disconnected: Not applicable — this component performs no
  networking of any kind; it manages an in-memory set of tab bars and mounts
  caller-supplied view controllers.
- Reusing one view-controller instance across two tabs: unguarded caller
  precondition. Nothing in `addTab`/`insertTab` refuses or dedupes a `Tab`
  whose `viewController` is already parented elsewhere or already mounted as
  another tab's content; callers MUST supply a distinct controller per tab,
  and AppKit's own view-controller containment is the only thing that reacts
  to a violation.
