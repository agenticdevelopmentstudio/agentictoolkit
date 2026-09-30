<!-- leaf: implement-site/menu--edge-cases · source: site-menu.md -->

# SiteMenu

## Edge Cases

- **Not-yet-addressable view.** A recorded place whose view is not URL-addressable
  records the feature route; its recent reopens the feature page (label still tells
  the user what it was). As deep-linking lands, the same place records a precise URL.
- **Workspaces still loading / empty.** Workspaces flyout shows the shared `Spinner`
  while loading and the shared `EmptyState` when the user has none.
- **Recents referencing a deleted entity.** Clicking navigates to the deep URL; the
  feature renders its own not-found/empty state (recents is not authoritative and is
  not pruned server-side).
- **localStorage unavailable** (private mode / quota) — reads return `[]`, writes are
  swallowed; the menu still renders (Recents simply stays empty/hidden).
- **Logged-out device with stale recents in storage.** Recents is a logged-in-only
  section; the recorder only runs and the flyout only shows when authenticated.
- **Very long labels / descriptions** truncate with the existing row ellipsis; the
  icon slot never shrinks.
