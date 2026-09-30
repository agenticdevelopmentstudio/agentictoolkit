<!-- leaf: implement-general-view-1/breadcrumb-view--test-vectors · source: breadcrumb-view.md -->

# Breadcrumb View

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| breadcrumb-view-001 | render-one-crumb-per-title | rootURL = /Users/x/project; set fileURL = /Users/x/project/Sources/App/Main.swift | Strip renders exactly 3 crumb buttons titled "Sources", "App", "Main.swift", left to right in that order |
| breadcrumb-view-002 | chevron-between-crumbs | Same setup as 001; inspect the stack's arranged subviews | Exactly 2 chevron views appear, each between two consecutive crumb buttons; no chevron precedes the first crumb |
| breadcrumb-view-003 | clear-strip-when-file-nil | With crumbs already shown (as in 001), set fileURL = nil | The stack's arranged subviews become empty; crumbTitles is [] |
| breadcrumb-view-004 | rebuild-on-every-file-assignment | With fileURL already set to a value, assign fileURL to that identical URL value again | The strip's crumb and chevron views are replaced with a fresh, equivalent set (new view instances, distinguishable by object identity from the ones they replace), even though crumbTitles is unchanged |
| breadcrumb-view-005 | relative-titles-inside-root | rootURL = /Users/x/project; fileURL = /Users/x/project/a/b.txt | crumbTitles equals ["a", "b.txt"] |
| breadcrumb-view-006 | single-crumb-outside-root | rootURL = /Users/x/project; fileURL = /Users/y/other/c.txt (outside root) | crumbTitles equals ["c.txt"]; exactly one crumb button renders, with no chevrons |
| breadcrumb-view-007 | single-crumb-outside-root | rootURL = /Users/x/project; fileURL = /Users/x/project (equal to root) | crumbTitles equals ["project"]; exactly one crumb button renders |
| breadcrumb-view-008 | crumb-directory-cumulative | rootURL = /Users/x/project; fileURL = /Users/x/project/a/b/c.txt; call selectCrumb(at: 0), then selectCrumb(at: 1) | onSelect is invoked first with /Users/x/project/a, then with /Users/x/project/a/b |
| breadcrumb-view-009 | last-crumb-directory-is-containing-folder | Same setup as 008; call selectCrumb(at: 2) (the "c.txt" crumb) | onSelect is invoked with /Users/x/project/a/b — the same directory selectCrumb(at: 1) reports, not the file's own path |
| breadcrumb-view-010 | crumb-truncates-middle | rootURL = /Users/x/project; fileURL = /Users/x/project/ThisIsADirectoryNameLongEnoughToOverflowTheAvailableCrumbWidth/f.txt, with the strip constrained to a narrow width | The overflowing crumb button's visible text truncates in the middle (for example "ThisIsA…umbWidth"); lineBreakMode is .byTruncatingMiddle |
| breadcrumb-view-011 | crumb-yields-width-before-container | Inspect a crumb button's horizontal content compression resistance priority | Priority equals .defaultLow (250) |
| breadcrumb-view-012 | crumb-borderless-inline-style | Inspect a crumb button's bezelStyle and isBordered | bezelStyle equals .inline; isBordered equals false |
| breadcrumb-view-013 | crumb-small-system-font | Inspect a crumb button's font | font equals NSFont.systemFont(ofSize: NSFont.smallSystemFontSize) |
| breadcrumb-view-014 | crumb-accessibility-identifier | rootURL = /Users/x/project; fileURL = /Users/x/project/a/b.txt | The crumb at index 0 has accessibility identifier "breadcrumb.crumb.0"; the crumb at index 1 has "breadcrumb.crumb.1" |
| breadcrumb-view-015 | chevron-decorative | Inspect a chevron view's accessibilityDescription | accessibilityDescription is nil |
| breadcrumb-view-016 | chevron-fallback-image | Inspect the fallback expression in `chevron()` (no seam exists in source to inject a symbol-resolution failure at runtime, so this is verified by code inspection, not a runtime double) | `NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) ?? NSImage()` guarantees a non-nil, zero-size NSImage() if symbol resolution ever returns nil, instead of crashing or leaving the image view without an image |
| breadcrumb-view-017 | click-opens-popover, popover-transient | Strip shows 2+ crumbs; click the first crumb button | An NSPopover becomes visible, anchored to that button, with behavior .transient, whose content lists that crumb's directory |
| breadcrumb-view-018 | single-popover-at-a-time | With a popover already open from clicking crumb A, click crumb B | The popover opened for crumb A closes; a new popover opens for crumb B; only one popover is visible at a time |
| breadcrumb-view-019 | popover-selection-invokes-callback | With a popover open, its completion handler is called with a chosen file URL | onSelect is invoked exactly once with that file URL; the popover closes |
| breadcrumb-view-020 | popover-cancel-closes-without-callback | With a popover open, its onCancel callback is invoked | The popover closes; onSelect is not invoked |
| breadcrumb-view-021 | track-only-the-open-popover | Open popover A, then open popover B (which closes A); popover A's popoverDidClose(_:) notification then fires after B is already active, then a third crumb C is clicked | Popover B remains open until C is clicked; clicking C then closes B (not a no-op) before opening C's popover — proving the stale notification for A did not wrongly clear the tracked reference to B |
| breadcrumb-view-022 | select-crumb-by-index | rootURL = /Users/x/project; fileURL = /Users/x/project/a/b.txt; call selectCrumb(at: 0) | onSelect is invoked with /Users/x/project/a — the directory of the crumb at index 0 |
| breadcrumb-view-023 | ignore-out-of-range-crumb-index | With 2 crumbs present, call selectCrumb(at: 5) and selectCrumb(at: -1) | onSelect is not invoked for either call; no crash occurs |
| breadcrumb-view-024 | no-filesystem-access | Set fileURL/rootURL to a pair of paths that do not exist on disk | Crumb titles and directories are still computed correctly from the URLs' path components alone; no file-existence check or disk access occurs |
| breadcrumb-view-025 | native-keyboard-activation | With Full Keyboard Access enabled and the strip showing crumbs, Tab to a crumb button and press Space | The focused crumb's action fires, opening its popover, via standard NSButton keyboard focus and Space-activation handling (not key-equivalent handling) |
| breadcrumb-view-026 | single-crumb-outside-root | rootURL = /Users/x/project; fileURL = /Users/x/project2/other/c.txt (a sibling path that shares a string prefix with the root but not a path component) | crumbTitles equals ["c.txt"]; exactly one crumb button renders — component-wise comparison correctly treats project2 as outside project, unlike a naive string-prefix check |
