<!-- leaf: implement-general-controller/breadcrumb-popover-view-controller--edge-cases · source: breadcrumb-popover-view-controller.md -->

# BreadcrumbPopoverViewController

**Rules** (cite as `implement-general-controller/breadcrumb-popover-view-controller--edge-cases#<slug>`):

- `null-empty-input-directoryurl-onselect-non-optional` MUST — Null/empty input (MUST): directoryURL and onSelect are non-optional, non-failable-typed initializer parameters, so …
- `boundary-values-selectrow-clamps-index-via` MUST — Boundary values (MUST): selectRow(_:) clamps any index via max(0, min(filtered.count - 1, index)) — e.g. selectRow(-5) …
- `error-states-filetreenode-loadchildren-called-synchronously` MUST — Error states (MUST): FileTreeNode.loadChildren(for:) is called synchronously and non-throwing in init, and its return …
- `directory-rows-inert-per-type-doc-comment` MUST — Directory rows are inert (MUST): Per the type's doc comment, "Choosing a directory row does nothing; only files can be …
- `empty-results-messaging-current-filter-matches-zero` MUST — No empty-results messaging (MUST): When the current filter matches zero entries, the table renders zero rows with no …
- `set-after-construction-oncancel-documented-set-breadcrumbview` MUST — onCancel set after construction (MUST): onCancel is documented as "Set by BreadcrumbView after construction, since only …

## Edge Cases

- Null/empty input (MUST): `directoryURL` and `onSelect` are non-optional,
  non-failable-typed initializer parameters, so Swift's type system rules
  out `nil` for either; the component provides, and needs, no nil-handling
  path for them. A `directoryURL` whose immediate contents are empty yields
  `entries == []` and `filtered == []`; the table shows zero rows and
  `selectRow`/`moveSelection` are no-ops (both guard on `!filtered.isEmpty`).
- Boundary values (MUST): `selectRow(_:)` clamps any index via
  `max(0, min(filtered.count - 1, index))` — e.g. `selectRow(-5)` with 3
  filtered entries selects row 0, and `selectRow(999)` selects row 2.
  `moveSelection(by:)` reuses the same clamp, so moving far past either end
  of the list settles on the nearest boundary row rather than wrapping or
  erroring.
- Concurrent access: Not applicable — the class is declared `@MainActor`, so
  Swift's concurrency checker confines all reads and writes of `entries`,
  `filtered`, and the UI to the main actor; source provides no path for two
  threads to mutate this view controller's state simultaneously.
- Error states (MUST): `FileTreeNode.loadChildren(for:)` is called
  synchronously and non-throwing in `init`, and its return value is assigned
  to `entries`/`filtered` unconditionally, with no `try`, `Result`, or error
  branch anywhere in source. The component performs no validation or error
  handling of its own on this call; whatever `loadChildren` returns —
  including an empty array, if that is how it represents an unreadable
  directory — is treated identically to a directory with no children. Any
  error handling for an unreadable directory is `FileTreeNode.loadChildren(for:)`'s
  own responsibility, and that function's implementation is outside the given
  source.
- Offline/disconnected: Not applicable — the component reads only the local
  file system via `FileTreeNode.loadChildren(for:)`; source contains no
  network call.
- Directory rows are inert (MUST): Per the type's doc comment, "Choosing a
  directory row does nothing; only files can be opened from here" —
  `chooseAction()` guards on `!node.isDirectory`, so a user cannot drill into
  a subdirectory from this popover; Return, double-click, and any other route
  into `chooseAction()` all have the same no-op outcome for a directory row.
- No empty-results messaging (MUST): When the current filter matches zero
  entries, the table renders zero rows with no placeholder text, icon, or
  "no results" view; source defines no empty-state UI for this case.
- `onCancel` set after construction (MUST): `onCancel` is documented as "Set
  by `BreadcrumbView` after construction, since only it holds the
  `NSPopover`." If Escape is pressed before the owning `BreadcrumbView` has
  assigned `onCancel`, the optional call `onCancel?()` is silently a no-op —
  the popover does not close through this path.
