---
id: c2417a5c-953b-458e-856b-2c4f7e3a6fde
title: Breadcrumb View
domain: agentictoolkit://recipes/breadcrumb-view
type: ingredient
version: 1.1.1
status: review
language: en
created: '2026-09-23'
modified: '2026-09-24'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A chevron-separated row of buttons showing the open file's path from the project root, each opening a popover onto its directory's siblings.
platforms:
- swift
- macos
tags:
- ui
- chrome
- navigation
- breadcrumb
depends-on: []
related:
- agentictoolkit://recipes/breadcrumb-popover-view-controller
references: []
approved-by: ''
approved-date: ''
---

# Breadcrumb View

## Overview

`BreadcrumbView` is a VS Code-style breadcrumb strip shown above a document editor: a horizontal row of buttons, one per path segment between the project root and the open file, separated by chevrons, so a user can see where the current file sits and jump to any ancestor directory. Setting `fileURL` rebuilds the strip; clicking a crumb opens a popover listing that directory's siblings (handled by `BreadcrumbPopoverViewController`), and choosing an entry there — or calling `selectCrumb(at:)` directly — reports a URL back through `onSelect`: the file chosen in the popover, or the crumb's own directory when `selectCrumb(at:)` is called directly. The view itself is limited to path arithmetic and layout; it performs no filesystem access of its own.

## Behavioral Requirements

- **render-one-crumb-per-title**: The component MUST render exactly one button for each entry in the current crumb-title list, in the same left-to-right order as that list (root first, leaf last).
- **chevron-between-crumbs**: The component MUST insert a chevron separator between each pair of adjacent crumb buttons, and MUST NOT place a chevron before the first crumb.
- **clear-strip-when-file-nil**: The component MUST remove every crumb and chevron, leaving the strip empty, when `fileURL` is set to `nil`.
- **rebuild-on-every-file-assignment**: The component MAY recompute the crumb titles, recompute the crumb directories, and rebuild the displayed crumbs every time `fileURL` is assigned, including when the newly assigned value is unchanged from the previous one — the current implementation does this unconditionally, since `fileURL`'s `didSet` observer runs on every assignment with no equality check against the previous value (see the corresponding Design Decision).
- **relative-titles-inside-root**: The component MUST derive the crumb titles from `fileURL`'s path components with `rootURL`'s path components removed from the front, when `fileURL`'s standardized path begins with `rootURL`'s standardized path.
- **single-crumb-outside-root**: The component MUST derive a single crumb whose title is `fileURL`'s last path component when `fileURL`'s standardized path does not have strictly more path components than `rootURL`'s standardized path, or when `rootURL`'s path components are not a prefix of `fileURL`'s path components — checked component-wise, not as a raw string prefix, so a path like `/Users/x/project2/...` is correctly treated as outside `/Users/x/project` even though it shares a string prefix with it. This includes the case where `fileURL` equals `rootURL`.
- **crumb-directory-cumulative**: For every crumb before the last, the component MUST associate it with the absolute directory formed by the file's path components from the root up to and including that crumb's own segment.
- **last-crumb-directory-is-containing-folder**: The component MUST associate the last crumb (the file's own crumb) with the directory that contains the file, not with the file's own path.
- **crumb-truncates-middle**: The component MUST truncate a crumb button's displayed title in the middle, not at the end, when the title does not fit the available width.
- **crumb-yields-width-before-container**: The component MUST give every crumb button a horizontal content compression resistance priority of `.defaultLow` (250), so a crumb's text shrinks before the containing view is forced to grow.
- **crumb-borderless-inline-style**: The component MUST render every crumb as a borderless button using the inline bezel style.
- **crumb-small-system-font**: The component MUST render crumb title text in the system font at the small system font size.
- **crumb-accessibility-identifier**: The component MUST assign each crumb button the accessibility identifier `breadcrumb.crumb.<index>`, where `<index>` is the crumb's zero-based position in the strip.
- **chevron-decorative**: The component MUST render each chevron separator with no accessibility description, so it is not announced as a distinct element.
- **chevron-fallback-image**: The component MUST substitute an empty image for a chevron when the `chevron.right` symbol cannot be resolved, rather than leaving the image view without an image.
- **click-opens-popover**: The component MUST open a popover, anchored to the clicked crumb button, listing the contents of that crumb's directory, when a crumb button is clicked.
- **popover-transient**: The component MUST configure every popover it presents with `.transient` behavior, so the popover dismisses itself when the user clicks outside it.
- **single-popover-at-a-time**: The component MUST close any popover that is already open before presenting a new one.
- **popover-selection-invokes-callback**: The component MUST close the popover and invoke `onSelect` with the chosen file when the popover reports a chosen file.
- **popover-cancel-closes-without-callback**: The component MUST close the popover without invoking `onSelect` when the popover is cancelled.
- **track-only-the-open-popover**: The component MUST clear its reference to the active popover only when the popover reporting its own closure is the one currently tracked as active.
- **select-crumb-by-index**: The component MUST invoke `onSelect` with the directory of the crumb at a given index when `selectCrumb(at:)` is called with an index inside the current crumb range.
- **ignore-out-of-range-crumb-index**: The component MUST NOT invoke `onSelect`, or take any other action, when `selectCrumb(at:)` or a crumb click reports an index outside the current crumb range.
- **no-filesystem-access**: The component MUST NOT read the file system to compute crumb titles or directories; all path arithmetic MUST operate only on the `URL` values already given to it.
- **native-keyboard-activation**: The component MUST support standard AppKit keyboard focus and activation on every crumb, because crumbs are instances of `NSButton` rather than custom-drawn views: when Full Keyboard Access is enabled, Tab moves focus to each crumb button in order, and Space or Return activates the focused button. (macOS only moves Tab focus to a push button when Full Keyboard Access is on; that is AppKit's own system-wide behavior, not something this component controls.)

## Appearance

- **Corner radius**: None. No corner radius is set on the view or on any crumb button.
- **Padding**: Crumb stack inset 8pt from the leading edge, at most 8pt from the trailing edge (an upper bound, not a fixed value), 2pt from the top edge, and 2pt from the bottom edge. 2pt of stack spacing separates each crumb from its neighboring chevron.
- **Font**: Crumb titles — system font at `NSFont.smallSystemFontSize`. Chevron symbol — 9pt point size, regular weight.
- **Background**: None. No background color is set on the view or on any crumb button.
- **Foreground/Text**: Crumb button title — the default `NSButton` title color (system label color). Chevron — `NSColor.secondaryLabelColor`.
- **Border**: None. Crumb buttons are borderless (`isBordered = false`) with the `.inline` bezel style.
- **Shadow**: None specified in source.
- **Min/Max size**: None specified. No crumb button has a minimum or maximum width or height constraint; a crumb may shrink to its truncated content because of its low horizontal compression resistance priority (see **crumb-yields-width-before-container**), and the stack's trailing constraint is an upper bound (`lessThanOrEqualTo`), not a fixed width.

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

## Accessibility

- **Identifier**: Each crumb button carries the accessibility identifier `breadcrumb.crumb.<index>` (via `accessibilityID`), set from the crumb's zero-based position in the strip — an identifier for automation, not the label VoiceOver announces.
- **Label**: `NSButton`'s accessibility label derives from its `title`, which is the full crumb title text. `lineBreakMode = .byTruncatingMiddle` changes only the rendered glyphs, not `title`, so VoiceOver announces the complete crumb title even when the visible text is truncated.
- **Role**: Crumb buttons keep the default `NSButton` "button" accessibility role; no custom role or trait is set. The chevron separators are `NSImageView`s created with `accessibilityDescription: nil` — a deliberate decorative marking, so VoiceOver does not present them as a separate stop.
- **Assistive technology**: `rebuild()` replaces every crumb view whenever `fileURL` changes without posting an accessibility notification (such as a layout-changed or announcement notification) around that replacement. A VoiceOver user tracking the strip is told the path changed only if AppKit's own automatic detection of the view-tree change surfaces it; the source itself makes no explicit announcement.
- **Minimum tap target**: Not applicable: `BreadcrumbView` targets macOS pointer and trackpad input, not touch. The source sets no minimum width or height on a crumb button — each button sizes to its (possibly truncated) title — and macOS's HIG does not mandate a minimum click-target dimension for inline chrome controls the way iOS mandates a touch-target minimum.

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

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `rootURL` | `URL` | required, set at init | The project root that crumb titles and directories are computed relative to. It is fixed at initialization and cannot be changed afterward. |
| `fileURL` | `URL?` | `nil` | The file the strip currently describes. Setting it recomputes and rebuilds the crumbs (**rebuild-on-every-file-assignment**); `nil` clears the strip (**clear-strip-when-file-nil**). |
| `onSelect` | `((URL) -> Void)?` | `nil` | Callback invoked with a URL — the file a popover's user chose, or the crumb's own directory when `selectCrumb(at:)` is called directly. |
| `crumbTitles` | `[String]` (read-only) | `[]` | The crumb labels, root to leaf; empty when there is no file. |
| `selectCrumb(at:)` | Method | n/a | Reports the directory of the crumb at `index` through `onSelect`, exactly as if that crumb's popover had opened and its listener acted on the directory itself; an out-of-range index is ignored. |

## Deep Linking

Not applicable: `BreadcrumbView` has no URL scheme, route, or deep-link entry point in source. It renders a `fileURL` already resolved and supplied by its owner (a document editor), and a crumb click reports through `onSelect` rather than navigating a URL scheme.

## Localization

Not applicable: the source contains no user-facing string literals for this component to translate. Every crumb title is a file or directory name taken verbatim from `fileURL`'s path components — data supplied by the caller, not localizable UI text.

## Accessibility Options

Document which accessibility display options this component responds to:

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: `rebuild()` adds and removes arranged subviews immediately with no animation or animation context in source, so there is no motion for this setting to reduce. |
| Increase Contrast | The chevron's `secondaryLabelColor` and the crumb buttons' default system title color are semantic AppKit colors that adjust automatically for Increase Contrast; no fixed, non-semantic color appears in source. |
| Differentiate Without Color | Not applicable: no state or meaning in this component is conveyed by color alone — crumb identity is conveyed by text, and the chevron separator is conveyed by its arrow shape, not by a color cue. |

## Feature Flags

Not applicable: no feature flag is defined or checked anywhere in `BreadcrumbView.swift`.

## Analytics

Not applicable: no analytics event is emitted in source. `onSelect` routes a chosen URL back to the caller, which owns any analytics tracking of that choice.

## Privacy

- **Data collected**: Not applicable — the component collects nothing of its own.
- **Storage**: Not applicable — the component persists nothing; `crumbTitles` and `crumbDirectories` are recomputed on every `fileURL` change and held only in memory.
- **Transmission**: Not applicable — the component transmits nothing; it reports a directory or file URL back to its caller through `onSelect` only.
- **Retention**: Not applicable — no data is retained beyond the current `fileURL`'s in-memory crumb state.

## Logging

Not applicable: no logging call appears anywhere in `BreadcrumbView.swift`.

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

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |
| [dynamic-type-support](agenticdevelopercookbook://compliance/accessibility#dynamic-type-support) | partial | Accessibility |
| [contrast-ratio](agenticdevelopercookbook://compliance/accessibility#contrast-ratio) | partial | Accessibility |
| [no-hardcoded-strings](agenticdevelopercookbook://compliance/internationalization#no-hardcoded-strings) | passed | Internationalization |
| [unicode-support](agenticdevelopercookbook://compliance/internationalization#unicode-support) | passed | Internationalization |
| [rtl-layout-support](agenticdevelopercookbook://compliance/internationalization#rtl-layout-support) | partial | Internationalization |

The accessibility statuses are partial because the source sets only an accessibility identifier per crumb and leaves label, dynamic-text, and contrast behavior to AppKit's own defaults (a plain `NSButton` title and `NSColor.secondaryLabelColor`) rather than defining or verifying them itself, and because no accessibility notification accompanies a strip rebuild (see Assistive technology, above). The internationalization statuses for hardcoded strings and Unicode support are passed because the source has no hardcoded user-facing strings and displays crumb titles through `NSButton`'s native Unicode-capable text handling. `rtl-layout-support` is partial rather than passed: the strip's own leading/trailing anchors and `NSStackView` layout mirror automatically for right-to-left locales, but the chevron separator is drawn with the `chevron.right` SF Symbol, which does not mirror to point left in RTL — `chevron.forward` is the symbol that does.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: marked rtl-layout-support partial for the non-mirroring chevron.right symbol, made native-keyboard-activation's Tab behavior conditional on Full Keyboard Access, reworded the chevron-fallback-image vector to code inspection since no injection seam exists, added the popover's domain to related, restated single-crumb-outside-root as a component-wise path comparison with a new sibling-path vector, named the exact .defaultLow (250) compression-resistance priority, unified the onSelect payload description across Overview/Configuration/selectCrumb(at:), rewrote vectors that named private internals against observable public behavior, added a popover-transient requirement, downgraded rebuild-on-every-file-assignment to MAY with a supporting Design Decision, and dropped an unlinked "(Rule 15)" citation |
| 1.0.0 | 2026-09-23 | Claude | Initial creation from source code |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
