<!-- leaf: implement-general-view-1/breadcrumb-view--part-2 · source: breadcrumb-view.md -->

# Breadcrumb View — continued (part 2)

## Accessibility Options

Document which accessibility display options this component responds to:

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: `rebuild()` adds and removes arranged subviews immediately with no animation or animation context in source, so there is no motion for this setting to reduce. |
| Increase Contrast | The chevron's `secondaryLabelColor` and the crumb buttons' default system title color are semantic AppKit colors that adjust automatically for Increase Contrast; no fixed, non-semantic color appears in source. |
| Differentiate Without Color | Not applicable: no state or meaning in this component is conveyed by color alone — crumb identity is conveyed by text, and the chevron separator is conveyed by its arrow shape, not by a color cue. |

## Privacy

- **Data collected**: Not applicable — the component collects nothing of its own.
- **Storage**: Not applicable — the component persists nothing; `crumbTitles` and `crumbDirectories` are recomputed on every `fileURL` change and held only in memory.
- **Transmission**: Not applicable — the component transmits nothing; it reports a directory or file URL back to its caller through `onSelect` only.
- **Retention**: Not applicable — no data is retained beyond the current `fileURL`'s in-memory crumb state.

## Platform Notes

- **SwiftUI**: A SwiftUI port would build the strip as an `HStack` iterating the crumb titles with `ForEach`, inserting an `Image(systemName: "chevron.right")` marked `.accessibilityHidden(true)` between items (mirroring the decorative, description-less chevron) and a `Button` per crumb with `.buttonStyle(.plain)` (SwiftUI has no direct equivalent of AppKit's `.inline` bezel; `.plain` is the closest borderless style), `.lineLimit(1)` and `.truncationMode(.middle)` for the middle-truncation requirement, and `.accessibilityIdentifier` set to the same `breadcrumb.crumb.<index>` pattern. The popover maps directly to SwiftUI's `.popover(isPresented:attachmentAnchor:arrowEdge:)` modifier attached to the crumb button, with an edge matching the source's `.maxY` preferred edge; enforcing "only one open at a time" needs a single shared selection state rather than one flag per crumb.
- **Compose**: Jetpack Compose has no built-in file-breadcrumb composable; a port would use a `Row` of `TextButton`s separated by an `Icon` with a null content description, reproducing the source's decorative, non-announced chevron. Compose's `Text` supports only end-ellipsis out of the box, so the middle-truncation requirement needs custom text-layout measurement, unlike the source's built-in middle-truncating line break mode. The popover, whether a dropdown menu or a custom popup, needs the same "close the previous one before opening the next" guard the source implements in `presentPopover(for:relativeTo:)`, since Compose does not enforce single-popup-at-a-time on its own.
- **React/Web**: A web port renders the strip as a navigation landmark containing an ordered list of button elements, with the chevron marked hidden from assistive technology between list items (matching the decorative chevron's nil accessibility description). Standard CSS text truncation only elides at the end of a line, so the middle-truncation requirement needs a small measurement-based helper rather than a single style property. The popover maps to a positioned panel opened by the clicked crumb's button, and the source's "close any open popover before opening the next" rule needs to be implemented explicitly, since a browser does not close one open custom popover just because a different button was clicked.
- **AppKit / UIKit**: Source: BreadcrumbView.swift (packages/apple/AgenticToolkit/macOS/UI/ViewControllers/DocumentPane/), built entirely from AppKit — NSView, NSStackView for the horizontal layout, NSButton (inline bezel, borderless) for each crumb, NSImageView with a symbol configuration for the chevrons, and NSPopover with NSPopoverDelegate for the sibling-listing popup; all layout uses Auto Layout constraints, and the path arithmetic is pure, static functions with no filesystem access. A UIKit port (iOS) would replace NSStackView with UIStackView, NSButton with a plain-style UIButton (UIKit has no inline bezel style), and NSImageView/NSPopover with UIImageView plus a popover presented via a popover presentation controller — noting that on a compact-width iPhone, that presentation adapts to a full-screen or sheet style by default unless the presentation delegate forces it to stay a popover, unlike NSPopover's consistently anchored macOS popover.
- **WinUI 3**: WinUI 3 ships a native BreadcrumbBar control (Microsoft.UI.Xaml.Controls.BreadcrumbBar, Windows App SDK) that is the direct analogue of this whole component: bind its ItemsSource to the crumb-title list and handle the ItemClicked event, whose event-args Index plays the role of crumbClicked's sender.tag. Reproduce presentPopover's "close any open popover before opening the next" rule (see **single-popover-at-a-time**) by closing a previously opened Flyout before showing a new one anchored to the clicked BreadcrumbBarItem, listing that directory's contents inside it. BreadcrumbBar truncates overflow items into a leading ellipsis drop-down by default, which is a different truncation strategy from the source's per-crumb middle truncation (see **crumb-truncates-middle**); matching the source exactly requires setting each item's text-trimming behavior and providing a custom middle-ellipsis conversion, since WinUI's built-in trimming values only truncate at the end.

## Design Decisions

- **Decision**: `presentPopover(for:relativeTo:)` unconditionally closes `activePopover` before showing a new popover.
  **Rationale**: A `.transient` popover (see **popover-transient**) closes when the user clicks outside it, but clicking a second crumb is not that click — the button's own click action is delivered first — so without this guard, two popovers listing different directories' siblings could end up open at once.
  **Approved**: pending

- **Decision**: `popoverDidClose(_:)` clears `activePopover` only when the closing popover is the one currently tracked as active.
  **Rationale**: A `.transient` popover dismissed by an outside click reports its closure asynchronously. Clearing `activePopover` unconditionally would wrongly discard the reference to a popover that has already replaced it by the time the closure notification arrives; the guard keeps the field pointing at whichever popover is actually still open.
  **Approved**: pending

- **Decision**: All crumb-title and crumb-directory computation is pure `URL` path-component arithmetic; `BreadcrumbView` performs no filesystem access itself.
  **Rationale**: Confining filesystem access to `BreadcrumbPopoverViewController`, shown only once a crumb is clicked, keeps the crumb-to-directory mapping testable without touching disk and keeps the strip's own behavior fully predictable from its `rootURL` and `fileURL` inputs alone.
  **Approved**: pending

- **Decision**: `rebuild()` runs on every `fileURL` assignment, including a reassignment of the same value, rather than skipping the rebuild when the new value equals the old one (see **rebuild-on-every-file-assignment**).
  **Rationale**: `fileURL`'s `didSet` observer calls `rebuild()` unconditionally, with no equality check. This is the plain, simple behavior of a Swift property observer rather than a deliberate optimization; a port is free to add an equality check to skip redundant rebuilds without breaking any observable contract of this component.
  **Approved**: pending
