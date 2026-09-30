<!-- leaf: implement-general-view-1/breadcrumb-view--states · source: breadcrumb-view.md -->

# Breadcrumb View

## States

| State | Appearance change |
|-------|------------------|
| With file | Strip shows one button per path segment, chevron-separated, root to leaf |
| No file (`fileURL == nil`) | Strip is empty; no crumbs or chevrons are rendered |
| Single crumb (file outside `rootURL`, or equal to it) | Strip shows exactly one button, the file's last path component; no chevrons |
| Popover open | One `NSPopover` is visible, anchored to the clicked crumb, listing that crumb's directory; any previously open popover has been closed first |
| Crumb pressed | Not applicable: crumb buttons are stock `NSButton`s using the `.inline` bezel style; pressed appearance is AppKit's own button-press rendering, not code in `BreadcrumbView` |
| Crumb focused | Not applicable: keyboard focus is AppKit's own default `NSButton` focus-ring rendering; the source draws no custom focus indicator |
| Crumb disabled | Not applicable: the source never sets `isEnabled = false` on a crumb button; every crumb is enabled once created |
| Loading | Not applicable: `rebuild()` is synchronous; the component has no asynchronous or loading state |
