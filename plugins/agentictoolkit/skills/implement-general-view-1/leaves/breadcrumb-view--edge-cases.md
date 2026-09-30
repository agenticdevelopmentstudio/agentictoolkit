<!-- leaf: implement-general-view-1/breadcrumb-view--edge-cases · source: breadcrumb-view.md -->

# Breadcrumb View

**Rules** (cite as `implement-general-view-1/breadcrumb-view--edge-cases#<slug>`):

- `null-input` MUST — fileURL == nil clears the strip entirely (see clear-strip-when-file-nil). MUST. rootURL is a required, non-optional …
- `boundary-file-equals-root` MUST — A fileURL whose standardized path equals rootURL's standardized path falls back to a single crumb of the root's own …
- `boundary-single-crumb` MUST — A file exactly one level under the root produces exactly one crumb and no chevrons, since the chevron is only inserted …
- `concurrent-access` MUST — BreadcrumbView is @MainActor-isolated, so every mutation of fileURL, crumbTitles, crumbDirectories, and activePopover …
- `popover-replacement-race` MUST — A .transient popover (see popover-transient)'s outside-click dismissal and a second crumb's click action can be …
- `stale-popover-close-notification` MUST — A .transient popover's closure can be reported after a different popover has already replaced it as activePopover. …
- `out-of-range-crumb-index` MUST — Both selectCrumb(at:) and the internal click handler silently ignore an index outside the current crumb range rather …
- `symbol-resolution-failure` MUST — If the chevron.right system symbol cannot be resolved, the chevron view is given an empty NSImage() rather than being …

## Edge Cases

- **Null input (no file)**: `fileURL == nil` clears the strip entirely (see **clear-strip-when-file-nil**). MUST. `rootURL` is a required, non-optional value supplied at initialization, so it has no null case to handle.
- **Boundary — file equals root**: A `fileURL` whose standardized path equals `rootURL`'s standardized path falls back to a single crumb of the root's own last path component, because the comparison in `titles(for:rootURL:)` requires strictly more file components than root components. MUST.
- **Boundary — single crumb**: A file exactly one level under the root produces exactly one crumb and no chevrons, since the chevron is only inserted when a crumb's index is greater than 0. MUST.
- **Concurrent access**: `BreadcrumbView` is `@MainActor`-isolated, so every mutation of `fileURL`, `crumbTitles`, `crumbDirectories`, and `activePopover` is serialized on the main actor; `rebuild()` always finishes removing old crumb views and adding new ones before another main-actor task can observe the strip, so no interleaving of two rebuilds, or of a rebuild and a click, is possible. MUST.
- **Popover replacement race**: A `.transient` popover (see **popover-transient**)'s outside-click dismissal and a second crumb's click action can be delivered in an order where two sibling-listing popovers would otherwise both end up open. `presentPopover(for:relativeTo:)` closes `activePopover` unconditionally before opening the next popover to prevent this (see **single-popover-at-a-time**); this is a documented workaround in source, not incidental behavior. MUST.
- **Stale popover-close notification**: A `.transient` popover's closure can be reported after a different popover has already replaced it as `activePopover`. `popoverDidClose(_:)` clears `activePopover` only when the closing popover is the one currently tracked, so a stale notification cannot discard the reference to the live popover (see **track-only-the-open-popover**). MUST.
- **Out-of-range crumb index**: Both `selectCrumb(at:)` and the internal click handler silently ignore an index outside the current crumb range rather than trapping or raising an error (see **ignore-out-of-range-crumb-index**). MUST.
- **Symbol resolution failure**: If the `chevron.right` system symbol cannot be resolved, the chevron view is given an empty `NSImage()` rather than being left without an image or causing a crash (see **chevron-fallback-image**). MUST.
- **Error states**: `BreadcrumbView` itself performs no operation that can fail (network, database, or file system) — the source's own documentation states it is "kept to pure path arithmetic and layout — no filesystem access here, ever." The one filesystem-touching operation, listing a directory's contents, happens inside `BreadcrumbPopoverViewController`, outside this component's own source file, so `BreadcrumbView` has no error-handling path of its own to document. Not applicable.
- **Offline or disconnected state**: Not applicable. `BreadcrumbView` performs no networking of any kind; it only computes and lays out `URL` path components already supplied to it.
