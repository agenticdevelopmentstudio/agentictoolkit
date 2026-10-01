---
id: 2b4d0f95-dbdf-48a9-8579-a3e5b7d488fe
title: Pane View
domain: agentictoolkit://cookbook/ui/layout/pane-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: Pane chrome providing a title bar, content hosting, host-mediated close/minimize/zoom/restore,
  and per-pane spacing, while probing its content for six optional capabilities.
platforms:
- swift
- macos
tags:
- pane
- view-controller
- accessibility
depends-on:
- agenticdevelopertoolkit://recipes/pane-title-bar-view
- agenticdevelopertoolkit://recipes/pane-minimize-picker
- agenticdevelopertoolkit://recipes/pane-minimized-strip-view
- agenticdevelopertoolkit://recipes/options-dialog-view-controller
related:
- agentictoolkit://cookbook/ui/layout/composable-tabs/leaf-pane-view
- agenticdevelopertoolkit://recipes/window-options-dialog
- agenticdevelopertoolkit://recipes/pane-control-cluster
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references: []
approved-by: ''
approved-date: ''
---

# Pane View

## Overview

The pane view is a pane: a title bar, some content, and enough memory to come back the way it was left. It knows nothing about split views, layout trees, tabs, projects, or persistent-storage internals — it reaches the world outside itself through exactly three seams: a host it sends requests to (close, zoom, minimize, restore, and two questions about what is currently legal), a state store it remembers itself through (minimize edge, zoomed flag, spacing override), and content it probes for six optional capabilities: providing a title, providing accessory views, providing option rows, representing itself while minimized, being searchable, and describing its own selection. Every one of those is supplied from outside, which is what lets the same pane be dropped into a container with different rules and still be correct. A seventh capability, consuming content spacing, is counted separately: it is not a content-capability the pane probes for chrome, but the spacing hook (see "inherited spacing" under Spacing) — the concept's own documentation names it apart from "six optional capabilities" for the same reason.

It exposes seven extension points — building its content, building its container, building its option rows, building its menu items, a fallback title, a content inset, and an accessibility identifier — and a pane that overrides none of them still gets a working, empty pane. Content that implements none of the six capabilities is a supported case, not a degraded one: it gets the fallback title, no accessories, no pane-specific options beyond the universal spacing control, the generic minimized glyph, and a search field the window leaves disabled. The composable-tabs pane view (see `related`) is this concept's own specialization, adding registry-vended content, an active-pane outline, and arrange-mode chrome on top of everything documented here.

## Behavioral Requirements

### Identity & construction

- **state-store-injection**: The pane MUST accept a state store at construction and MUST default to an ephemeral (in-memory) state store when none is supplied.

### Host relationship (requests, not actions)

- **host-weak-reference**: The pane MUST hold its reference to its host weakly, so the host is not kept alive on the pane's account.
- **close-is-a-request**: Clicking the close control MUST ask the host to close the pane and MUST NOT remove the pane or change any pane state itself.
- **zoom-is-a-request**: Clicking the zoom control MUST ask the host to zoom the pane and MUST NOT change the pane's zoomed state itself.
- **minimize-picker-uses-host-edges**: Clicking the minimize control MUST present a picker offering exactly the edges the host currently reports as available, with every other edge disabled.
- **minimize-pick-is-a-request**: Choosing an edge from the picker MUST ask the host to minimize the pane to that edge and MUST NOT change the pane's minimize edge itself.
- **restore-is-a-request**: Clicking restore, from the title bar or from the minimized rail, MUST ask the host to restore the pane and MUST NOT change the pane's minimize edge itself.
- **host-change-refreshes-controls**: Setting the host to a new value MUST immediately re-derive whether the minimize and close controls are available from the new host, without waiting for another trigger.
- **close-availability-defaults-true**: The close control MUST be treated as available when there is no host, or when the host does not override its close-permission check.
- **minimize-availability-empty-without-host**: The minimize control MUST be disabled when there is no host.

### Loading and layout

- **title-bar-above-content**: The pane's view MUST place the title bar above the content container, both inset from the container by the content inset (default `0`) on every side.
- **content-child-hierarchy**: When the content-building hook returns content, that content MUST be added as a child and its view MUST be pinned to the four edges of the content container.
- **no-content-is-supported**: When the content-building hook returns nothing, the pane MUST load a working, empty pane rather than failing.
- **accessibility-id-on-container**: The pane's container view MUST carry the accessibility identifier its accessibility-identifier hook returns (default `"pane"`).
- **clamped-pane-yields-width**: Enabling the clamping option MUST yield the title bar's width demand to the container exactly once, and disabling it MUST have no effect.
- **clamp-covers-later-installed-chrome**: Chrome installed into the title bar after clamping — the gear button, at minimum — MUST also have its width demand yielded when the pane is clamped.
- **clamp-is-one-way**: Disabling the clamping option after it was enabled MUST NOT restore the title bar's original compression resistance.

### Title

- **title-follows-content**: The pane's resolved title MUST equal the content's own title (when the content implements the title-providing capability), falling back to the fallback title when the content does not implement it.
- **title-change-callback-installed**: The pane MUST install its own callback into the content's title-change notification (when implemented) once, during the pane's initial setup, so the title bar updates without polling.
- **title-refresh-updates-three-readers**: Refreshing the title MUST update the title bar's title, the open options dialog's heading (when one is presented), and MUST invoke the pane's own title-change notification.
- **fallback-title-default**: The fallback title MUST be `"Pane"` when not overridden.

### Accessories and gear

- **accessories-from-content**: Refreshing accessories MUST set the title bar's accessory views to the content's own accessory views (when the content implements the accessory-providing capability), or an empty array when it does not.
- **gear-installed-trailing**: The pane MUST install a gear button in the title bar's trailing slot while its view is being built.
- **gear-menu-order**: The gear's menu MUST list the pane's own menu items first, followed by a separator only when that list is non-empty, followed by a `"Settings…"` item.
- **bare-pane-menu-is-settings-only**: A pane whose menu items are empty MUST raise a menu containing exactly one item, `"Settings…"`, with no leading separator.
- **menu-items-self-validate**: The options menu MUST have each item's enabled state decided by the item itself, rather than by a platform default validation pass.
- **settings-opens-options-dialog**: Choosing `"Settings…"` MUST present an options dialog as a sheet, seeded with the pane's option rows and headed by its resolved title.
- **options-rows-order**: The pane's option rows MUST return its own spacing control and reset button first, followed by the content's own option rows (when the content implements the options-providing capability).
- **options-dialog-close-flushes-spacing**: Dismissing the options dialog MUST flush any pending spacing-override write immediately, before the dialog closes.

### Spacing

- **spacing-defaults-to-inherited**: A pane with no stored spacing override MUST apply its inherited spacing. When the content implements the content-spacing-consuming capability, that value MUST be exactly the content's own inherited spacing (whatever the content itself reports, zero or not). When the content does not implement it, the inherited spacing MUST be all-zero, unconditionally.
- **spacing-consumer-applies-its-own-gap**: When the content implements the content-spacing-consuming capability, the pane MUST apply the resolved spacing to it directly and MUST hold its own content-spacing insets at zero.
- **spacing-non-consumer-gets-pane-applied-gap**: When the content does not implement the content-spacing-consuming capability, the pane MUST hold the content off the content container's edges by the resolved spacing's four insets itself.
- **spacing-control-range**: The pane's spacing control MUST offer the range `0...40` on every edge.
- **spacing-clamped-on-read**: A stored spacing value outside `0...40` on any edge (written by an older build, or edited by hand) MUST be clamped back into range when read from the state store, never rejected outright.
- **spacing-decode-failure-is-absent**: A spacing-override record that fails to decode MUST be treated the same as no stored override, not as an error.
- **spacing-reset-restores-inheritance**: Activating the spacing reset button MUST delete the pane's stored override rather than writing the current inherited value, and MUST leave the reset button disabled immediately afterward.
- **spacing-reset-enabled-only-when-overridden**: The spacing reset button MUST be enabled exactly when the pane currently has a stored override.
- **apply-resolved-spacing-is-idempotent**: Reapplying resolved spacing more than once with nothing changed MUST leave the resolved spacing, the spacing control's displayed value, and the content-spacing insets unchanged.

### Minimize / restore appearance

- **minimize-vertical-hides-content-only**: Minimizing to the top or bottom edge MUST hide the content container and the content's view while leaving the title bar visible, showing its minimized (restore) control state.
- **minimize-horizontal-replaces-with-rail**: Minimizing to the leading or trailing edge MUST hide the title bar and content, and MUST show a minimized rail docked to that edge.
- **rail-glyph-from-content**: The minimized rail's icon and tooltip MUST come from the content's own minimized-representation values (when the content implements that capability), falling back to the generic default icon and the pane's resolved title respectively.
- **rail-rebuilt-on-edge-change**: Flipping directly from one minimized horizontal edge to the other MUST remove the existing rail and build a new one docked to the new edge, rather than repositioning the existing view.
- **restore-clears-minimized-chrome**: Restoring MUST unhide the title bar and content, remove any rail, and reactivate the content's four edge constraints.
- **minimized-content-pins-deactivated**: While minimized to any edge, the four constraints pinning the content's view to the content container MUST be deactivated, not merely left active on a hidden view.
- **minimize-before-load-is-lossless**: Requesting a minimize edge before the pane's view has loaded MUST record the edge and MUST NOT force the view to load; the recorded edge MUST be applied exactly once when the view does load.
- **appearance-methods-noop-before-load**: Applying minimized appearance MUST NOT take effect, and MUST NOT force the view to load, while the view is not loaded.
- **title-bar-trailing-active-except-rail**: The title bar MUST span the container's full width for every pane shape except a pane minimized to a horizontal (leading/trailing) edge, where its trailing edge MUST be released so it can collapse to its own width instead of being stretched to match the (now much narrower) rail.

### Persistence

- **minimize-edge-persisted**: Setting a minimize edge MUST write the edge's value to the state store under the minimize-edge key, or delete that key when cleared.
- **zoom-persisted**: Setting zoomed state MUST write `"1"` to the state store under the zoomed key when `true`, or delete that key when `false`.
- **state-restored-on-load**: Loading the view MUST restore the minimize edge and zoomed state from the state store.
- **unparseable-stored-edge-ignored**: A stored minimize-edge value that does not match a recognized edge MUST be treated as absent — the pane opens whole — rather than crashing or raising an error.

### Search and selection

- **search-reaches-searchable-content-only**: The pane's searchable state MUST be `true` exactly when the content implements the search capability; searching MUST forward to the content when searchable and MUST be a no-op otherwise.
- **selection-description-reported**: The pane's selection description MUST equal the content's own selection description (when the content implements the selection-describing capability), or be unset when it does not.
- **selection-change-forwarded**: The pane MUST install its own callback into the content's selection-change notification (when implemented) and MUST invoke its own selection-change callback whenever that fires.

### Sizing for the host

- **minimized-thickness-formula**: The minimized thickness for an edge MUST equal the minimized rail's thickness plus twice the content inset for a horizontal edge, and the title bar's height plus twice the content inset for a vertical edge.

## Appearance

- **Corner radius**: None drawn by the pane itself. The default container is a plain rectangle filled with the theme's `windowBackground` surface role; a pane that builds its own container may add one, out of scope here.
- **Padding**: The content inset (default `0`pt) holds both the title bar and the content off the container's edges. The title bar is a fixed 26pt tall. A minimized-to-a-side rail is a fixed 28pt thick.
- **Font**: Not set directly by the pane; the title bar's own label typography belongs to the title bar concept (`depends-on`), out of this recipe's scope.
- **Background**: The pane's own fill is whatever its container-building hook returns; the default is the theme's `windowBackground` surface role.
- **Foreground/Text**: Not set directly by the pane; delegated to the title bar and to the content.
- **Border**: None drawn by the pane anywhere in this concept.
- **Shadow**: None drawn by the pane anywhere in this concept.
- **Min/Max size**: None set by the pane. The container view is given an explicit default frame of 300×200pt when the view is created, before the layout system resolves its real size from the constraints installed immediately after; no min/max width or height constraint is authored anywhere in this concept.
- **Gear button**: A borderless button showing a gear-shaped icon only (no text), tinted with the theme's secondary-text color, with tooltip "Pane options" (see Platform Notes for the exact bezel style and icon asset).

## States

| State | Appearance change |
|-------|------------------|
| Default | — |
| Pressed | Not applicable: the pane container itself has no pressed state; its close/minimize/zoom buttons, the gear, and the spacing control and its reset button each have their own recipe and their own pressed appearance. |
| Disabled | Not applicable as a whole-pane state; the close and minimize controls are independently enabled or disabled per their own close/minimize availability — see Behavioral Requirements. |
| Focused | Not applicable as a visual state of this concept; the pane draws no focus ring of its own. |
| Loading | Not applicable: any loading indicator belongs to the hosted content, which has its own recipe. |
| Whole | Title bar over content; both held the content inset off the container's edges. |
| Minimized (top/bottom) | Content and its container are hidden; the title bar stays visible, and its minimize control shows a restore glyph (a plus icon) and tooltip "Restore Pane". |
| Minimized (leading/trailing) | Title bar and content are hidden; a minimized rail is docked to that edge, showing the content's glyph and tooltip or the generic defaults. |
| Zoomed | The zoom control's glyph and tooltip flip (an expand icon ↔ a contract icon, "Zoom Pane" ↔ "Unzoom Pane"); the pane's own size and position are unaffected by this concept — resizing is the host's responsibility. |
| Clamped to container | The title bar, every view already inside it, and any chrome installed into it afterward carries the lowest layout priority for horizontal compression resistance (value `1`), so the pane never forces its container wider. |

## Accessibility

- **Role/trait**: The container view carries the accessibility identifier the pane's accessibility-identifier hook returns (`"pane"` by default), set when the view is built. It is a plain view with no explicit role override. The gear button carries identifier `pane.options`; the "Settings…" menu item carries `pane.options.settings`; the spacing control carries `pane.options.spacing`; the spacing reset button carries `pane.options.spacing.reset`. The close/minimize/zoom buttons, the minimize picker, the minimized rail, and the options dialog's own controls carry their identifiers inside their own components, each with its own recipe (see `depends-on`/`related`) — out of scope here.
- **Label requirements**: The gear button's accessibility description and tooltip are both "Pane options"; its accessibility label is set separately to "Pane Options". The "Settings…" menu item's image carries the accessibility description "Settings". The spacing reset button's accessibility label is "Use Default Spacing", distinct from its visible title "Use Default".
- **Announce state changes**: No accessibility notification is posted anywhere in this concept when the title changes, when the pane minimizes, restores, or zooms — every one of those is a silent state change. A screen-reader user has no non-visual cue that any of these four things happened.
- **Minimum tap target**: Not overridden by the pane. The gear button and the spacing reset button are sized by the platform's standard intrinsic content size for a button; a pointer-driven platform's guidelines do not carry the 44×44pt minimum that applies to touch targets, and this concept sets no explicit minimum of its own.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| pvc-001 | state-store-injection | Construct a pane with no state-store argument | The state store is an ephemeral (in-memory) state-store instance |
| pvc-003 | host-weak-reference | Assign the host, then release every other strong reference to that host object | The pane's host reference becomes empty |
| pvc-004 | close-is-a-request | Click the title bar's close button | The host's close-request is invoked once; no pane state changes |
| pvc-005 | zoom-is-a-request | Click the title bar's zoom button | The host's zoom-request is invoked once; the pane's zoomed state remains `false` |
| pvc-006 | minimize-picker-uses-host-edges | The host reports that minimizing is currently allowed only to the top and bottom edges; click the minimize button | The picker offers exactly those two edges enabled, with every other edge (e.g. leading) disabled |
| pvc-007 | minimize-pick-is-a-request | Open the minimize picker; pick the leading edge | The host's minimize-request is invoked with the leading edge; the pane's recorded minimize edge remains unset |
| pvc-008 | restore-is-a-request | Minimize the pane to the trailing edge; click the rail's restore button | The host's restore-request is invoked once |
| pvc-009 | host-change-refreshes-controls | Set the host to one that currently allows no minimize edges | The minimize button is disabled immediately after the assignment, with no further call needed |
| pvc-010 | close-availability-defaults-true | A pane with no host assigned | The close control is available |
| pvc-011 | minimize-availability-empty-without-host | A pane with no host assigned | The minimize button is disabled |
| pvc-012 | title-bar-above-content | Load the pane's view with a content inset of `0` | The title bar's top/leading placement and the content container's top placement (against the title bar's bottom) all resolve with a `0` offset |
| pvc-013 | content-child-hierarchy | The content-building hook returns content | The pane's children include it; its view is pinned to all four edges of the content container by exactly four active constraints |
| pvc-014 | no-content-is-supported | The content-building hook returns nothing (the default) | The pane's view loads without error; the pane has no content |
| pvc-015 | accessibility-id-on-container | Load a pane whose accessibility-identifier hook is not overridden | The container's accessibility identifier reads "pane" |
| pvc-016 | clamped-pane-yields-width | Set the clamping option to enabled before loading the view (this takes effect immediately), then load it | The title bar's, and its close button's, horizontal compression-resistance priority is already at the lowest value before the view loads, and is still exactly that value — not reset or reapplied — after loading completes, confirming the effect ran exactly once |
| pvc-017 | clamp-covers-later-installed-chrome | Same setup, after the view finishes loading and installs the gear | The gear's horizontal compression-resistance priority is also at the lowest value |
| pvc-018 | clamp-is-one-way | Set the clamping option to enabled, then set it back to disabled | The title bar's compression-resistance priority remains at the lowest value, not restored to its original value |
| pvc-019 | title-follows-content, title-change-callback-installed | Content implementing the title-providing capability changes its title from "Files" to "Sources", then synchronously invokes its own title-change callback | The title bar already reads "Sources" by the time that callback call returns — updated synchronously in response to the callback, not via a poll or a later run-loop turn |
| pvc-021 | title-refresh-updates-three-readers | An options dialog is open; trigger a title refresh after the content's title changed | The title bar's title, the open dialog's heading, and the title-change notification all reflect the new title |
| pvc-022 | fallback-title-default | A pane overriding nothing | The fallback title reads "Pane" |
| pvc-023 | accessories-from-content | Content implementing the accessory-providing capability with one accessory view | The title bar's accessory views contain exactly one element, identical to the content's view |
| pvc-024 | gear-installed-trailing | Load any pane | The title bar has a gear view, and its layout pins it to the title bar's own trailing edge (the trailing slot), not merely somewhere in the bar |
| pvc-025 | gear-menu-order | A pane whose menu items are one "Move" item | The options menu's items read `["Move", "", "Settings…"]`, with the second item a separator |
| pvc-026 | bare-pane-menu-is-settings-only | A pane whose menu items are empty | The menu has exactly one item, titled "Settings…" |
| pvc-027 | menu-items-self-validate | Any pane's options menu | Each item's enabled state is decided by the item itself, not by a platform default validation pass |
| pvc-028 | settings-opens-options-dialog | Choose "Settings…" from the gear menu | An options dialog is presented as a sheet, seeded with the pane's option rows and headed by its resolved title |
| pvc-029 | options-rows-order | Content implementing the options-providing capability with two rows | The option rows read as four rows: a spacing control, a reset control, then the content's two rows in order |
| pvc-030 | options-dialog-close-flushes-spacing | A spacing drag has a pending coalesced write; close the options dialog | The pending write reaches the state store before the dialog finishes closing |
| pvc-031 | spacing-defaults-to-inherited | Content not implementing the content-spacing-consuming capability, no stored override | The pane's inherited spacing is all-zero, unconditionally |
| pvc-032 | spacing-consumer-applies-its-own-gap | Content implementing the content-spacing-consuming capability | The resolved spacing is applied to the content itself; the pane's own content-spacing insets are all zero |
| pvc-033 | spacing-non-consumer-gets-pane-applied-gap | Content not implementing the content-spacing-consuming capability; a stored override of `top: 10` | The pane's own content-spacing insets read `top == 10` |
| pvc-034 | spacing-control-range | Build the spacing rows | The returned spacing control's underlying range is `0...40` |
| pvc-035 | spacing-reset-restores-inheritance | Set an override, then click "Use Default" | The stored override is deleted (not rewritten with the current inherited value); the reset button becomes disabled |
| pvc-036 | spacing-reset-enabled-only-when-overridden | Toggle between an overridden and a non-overridden spacing state, reapplying resolved spacing after each | The reset button's enabled state matches whether the spacing is currently overridden, at every check |
| pvc-037 | apply-resolved-spacing-is-idempotent | Reapply resolved spacing twice in a row with nothing changed in between | The spacing control's displayed value, the resolved spacing, and the content-spacing insets are all identical after both calls |
| pvc-038 | minimize-vertical-hides-content-only | Minimize to the top edge | The title bar stays visible; the content is hidden; the title bar's minimize control shows its minimized (restore) state |
| pvc-039 | minimize-horizontal-replaces-with-rail | Minimize to the leading edge | The title bar is hidden; a minimized rail exists among the pane's subviews |
| pvc-040 | rail-glyph-from-content | Content implementing the minimized-representation capability with symbol "folder"; minimize to the leading edge | The rail's icon reads "folder" and its tooltip equals the content's minimized tooltip |
| pvc-041 | rail-rebuilt-on-edge-change | Minimize to the leading edge, then directly to the trailing edge | Exactly one rail exists afterward; it is a different instance from the first, docked to the trailing edge |
| pvc-042 | restore-clears-minimized-chrome | Minimize to the leading edge, then restore | The minimize edge is cleared; the title bar becomes visible; no minimized rail remains among the subviews |
| pvc-043 | minimized-content-pins-deactivated | Minimize to the leading edge, then to the top edge | The count of active constraints pinning the content to the content container is `0` in both cases; it is `4` when whole |
| pvc-044 | minimize-before-load-is-lossless | Construct a pane; request minimizing to the leading edge before the view is touched; then load the view | The view stays unloaded until explicitly loaded; after loading, exactly one rail exists and the minimize edge reads leading |
| pvc-045 | appearance-methods-noop-before-load | Same setup as pvc-044, checked immediately after the minimize request and before loading | The view remains unloaded; no minimized rail has been created yet; the title bar's hidden state is untouched (nothing has run to hide or show it), because the appearance update returned immediately |
| pvc-046 | title-bar-trailing-active-except-rail | Force a layout pass at a fixed container width, after minimizing to the leading edge versus after minimizing to the top edge | The title bar's width equals the container's content width (minus insets) when minimized to the top edge; it is narrower than that after minimizing to the leading edge, because its trailing edge was released |
| pvc-047 | minimize-edge-persisted | Minimize to the bottom edge, against a store | The store's value for the minimize-edge key reads "bottom" |
| pvc-048 | zoom-persisted | Set zoomed to `true`, against a store | The store's value for the zoomed key reads "1" |
| pvc-049 | state-restored-on-load | Pre-populate a store with a minimize edge of "trailing" and zoomed "1"; load a pane against it | The pane's minimize edge reads trailing; its zoomed state reads `true` |
| pvc-050 | unparseable-stored-edge-ignored | Pre-populate a store with a minimize edge of "sideways"; load a pane against it | The pane's persisted minimize edge, and its minimize edge, both read as unset; no crash |
| pvc-051 | search-reaches-searchable-content-only | Content implementing the search capability; search for "main" | The pane is searchable; the content receives the query "main" |
| pvc-052 | selection-description-reported | Content implementing the selection-describing capability with a selection description of "README.md" | The pane's selection description reads "README.md" |
| pvc-053 | selection-change-forwarded | Set the selection-change callback; change the content's selection description | The callback fires exactly once |
| pvc-054 | minimized-thickness-formula | Content inset `0`; compute the minimized thickness for the leading edge and for the top edge | Returns `28` for the leading edge; returns `26` for the top edge |
| pvc-055 | spacing-clamped-on-read | Pre-populate a store with a spacing-override record encoding `top: 999` | The resolved spacing's top value is `40` (clamped into `0...40`), not `999` |
| pvc-056 | spacing-decode-failure-is-absent | Pre-populate a store with an unparseable spacing-override record | The spacing is treated as not overridden; the resolved spacing equals the inherited spacing |
| pvc-057 | search-reaches-searchable-content-only | Content not implementing the search capability; search for "main" | The pane is not searchable; the call neither crashes nor has any observable effect on the content |
| pvc-058 | selection-description-reported | Content not implementing the selection-describing capability | The pane's selection description is unset |
| pvc-059 | accessories-from-content | Content not implementing the accessory-providing capability; refresh accessories | The title bar's accessory views are empty |
| pvc-060 | rail-glyph-from-content | Content not implementing the minimized-representation capability; minimize to the leading edge | The rail's icon reads the generic default; its tooltip equals the pane's resolved title |
| pvc-061 | clamped-pane-yields-width | Construct a pane and never enable the clamping option, then disable it | The title bar's horizontal compression-resistance priority is unchanged from its default — the yield never occurs |
| pvc-062 | spacing-defaults-to-inherited | Content implementing the content-spacing-consuming capability with an inherited spacing of `top: 10, leading: 0, bottom: 0, trailing: 0`, no stored override | The pane's inherited spacing equals exactly the content's value, `top: 10, leading: 0, bottom: 0, trailing: 0` |

## Edge Cases

- **Null/empty input** (MUST): The content-building hook returning nothing results in a working, empty pane rather than a failure (`no-content-is-supported`). A spacing-override record that fails to decode (`spacing-decode-failure-is-absent`), or a minimize-edge value that fails to parse (`unparseable-stored-edge-ignored`), is treated as absent rather than as an error.
- **Boundary values** (MUST): A stored spacing override outside the `0...40` range — written by an older build, or edited by hand — is clamped back into range on read, never rejected outright (`spacing-clamped-on-read`). A content inset of `0`, the default, means minimized thickness reduces to exactly the docked chrome's own thickness (26pt for a vertical edge, 28pt for a horizontal one) with no border allowance added.
- **Concurrent access** (MUST): The pane is confined to a single thread, and every piece of mutable state it owns is read and written only on that thread, so there is no concurrent-access hazard by construction. The one timing subtlety is the spacing override's 300ms coalescing timer for persisted spacing writes: it still fires on that same thread, not a background one, so it introduces no data race — only a bounded lag between a drag gesture and its write reaching the store (see Design Decisions).
- **Error states** (MUST): An encode/decode failure while persisting or reading the spacing override is silently ignored — the write or read simply does not happen, with no error surfaced to the caller or the user. This is the concept's actual behavior, described as-is rather than as an idealized richer error path; the state store's two methods return no error value at all, so there is no channel to report through even if it wanted to.
- **Offline or disconnected state**: Not applicable. This component makes no network request of any kind; its only persistence goes through the injected state store, and nothing references a network resource.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `stateStore` | State store | An ephemeral (in-memory) state store | Where the pane persists its minimize edge, zoomed flag, and spacing override; injected at construction. |
| `host` | Host reference (optional, held weakly) | None | The container the pane sends close/minimize/zoom/restore requests to and asks for available minimize edges and close permission. |
| `clampsToContainer` | Boolean | `false` | When `true`, yields the title bar's — and any later-installed chrome's — width demand to the container instead of asking for its own; one-way once set. |
| `onSelectionChange` | Callback (no arguments, optional) | None | Called when the content's selection description changes, for a host that shows a display path. |
| `onTitleChange` | Callback (no arguments, optional) | None | Called when the pane's resolved title would now answer differently, for a host that names the pane elsewhere (e.g. a window footer). |

## Deep Linking

Not applicable: a pane is chrome built entirely from constructor arguments and content supplied by whoever creates it. No URL scheme, universal link, or system activity-handoff handling appears anywhere in this concept.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| (none — literal string) | "Pane" | Fallback title's default value. |
| (none — literal string) | "Pane options" | Gear button's tooltip and accessibility description. |
| (none — literal string) | "Pane Options" | Gear button's separately-set accessibility label. |
| (none — literal string) | "Settings…" | Title of the gear menu's final item. |
| (none — literal string) | "Settings" | Accessibility description on that item's image. |
| (none — literal string) | "Use Default" | Title of the spacing reset button. |
| (none — literal string) | "Use Default Spacing" | Accessibility label of the spacing reset button. |

Every string above is set as a literal value with no localization key or automatic catalog lookup; each one is a hardcoded English literal.

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: every appearance change — minimize, restore, zoom, clamping — is an immediate state change (visibility, constraint activation/deactivation, icon swap); no animation context, layer animation, or transition appears anywhere in this concept. |
| Increase Contrast | Not observed in this concept: colors are resolved through the theme system; any contrast adaptation belongs to that system, out of this ingredient's scope. |
| Differentiate Without Color | Not applicable: the pane draws no state distinction using color alone. Its container's fill comes entirely from its container-building hook, which a specialization with a color-only cue (e.g. an active/inactive border) may override — that is the composable-tabs pane view's concern, documented in its own recipe, not this one's. |

## Feature Flags

Not applicable: no feature-flag or remote-config lookup of any kind appears anywhere in this concept.

## Analytics

Not applicable: no analytics event is emitted anywhere in this concept.

## Privacy

- **Data collected**: Only this pane's own chrome state — minimize edge, zoomed flag, and spacing override — written through the injected state store. No personal or otherwise sensitive data is read or written by this concept.
- **Storage**: Whatever the injected state store implements. The ephemeral default keeps values in memory only, for exactly as long as the pane exists. A persistent store is the caller's own choice and out of this recipe's scope.
- **Transmission**: None. No network call appears anywhere in this concept.
- **Retention**: Governed entirely by whichever state store is injected; the pane defines no retention policy of its own.

## Logging

Not applicable: no logging call of any kind appears anywhere in this concept.

## Platform Notes

- **SwiftUI**: This is an `NSViewController`/AppKit subclass, not SwiftUI. A SwiftUI-first rebuild would replace the class hierarchy with a `View` driven by an `@Observable` pane view-model exposing `resolvedTitle`, `isZoomed`, and `minimizedEdge`; the title bar becomes a custom `HStack` (close/minimize/zoom buttons, a `Text(title).lineLimit(1).truncationMode(.middle)`, an accessory `HStack`, and a gear `Menu`); the six capability protocols continue to be probed with `as?` against an `AnyObject` content, the same idiom the source uses; spacing becomes a `.padding(EdgeInsets(...))` fed by the same spacing-override mechanism; the minimized rail is swapped in with a plain `if`, not a transition, to preserve the source's "no animation" behavior.
- **Compose**: Model the pane as a `Column` with a fixed-height title `Row` (26dp-equivalent) over a `Box` holding the content. The six capability protocols become sealed interfaces the content composable optionally implements, probed the same way (`is`/`as` in Kotlin) rather than through compile-time generics. Minimizing to a side swaps the content `Row`/`Column` for a narrow `IconButton` column; persistence goes through a state-store-equivalent `DataStore` keyed the same way (`minimize.edge`, `zoomed`, `spacing.override`).
- **React/Web**: A `<div>` pane wrapper with a fixed-height header `<div>` (26px) holding the same left-to-right regions — window controls, title, accessory slot, gear. The capability protocols become optional props/callbacks (`onTitleChange`, `renderAccessories`, `renderOptionRows`) checked for existence the way `as?` is checked here. The minimized rail is a `<div>` swapped in by conditional render, not a CSS transition, matching the source's instant appearance change. Persisted chrome state goes to the same key-value abstraction (`localStorage`, or a server-backed store) keyed by the same three strings.
- **AppKit/UIKit**: This recipe's own platform (`NSViewController`, `NSView`, `NSButton`, `NSMenu`); nothing in this file targets UIKit/iOS. The pane does not support `NSCoder`-based initialization: invoking `init(coder:)` calls `fatalError` — a pure framework construction rule, not a behavior of the concept itself. The `host` property is declared `weak`, the standard Cocoa mechanism for the pane not to keep its host alive. The class is `@MainActor`-isolated, which is what backs the single-thread confinement described under Edge Cases → Concurrent access. The options menu sets `autoenablesItems = false` so AppKit's default menu-validation chain never overrides an item's own enabled state (`menu-items-self-validate`). The gear button is built via `WindowOptionsDialog.makeGearButton(tooltip: "Pane options")` — borderless, `.accessoryBarAction` bezel, the `gearshape` SF Symbol shown image-only, tinted with the theme's secondary-text color. String literals are set through plain `String`-typed properties (`toolTip`, `title`, `setAccessibilityLabel`, `accessibilityDescription`), none of which resolve against a `.strings` catalog or `NSLocalizedString` automatically. Colors are resolved through `ThemedBackgroundView` and `WindowOptionsDialog.makeGearButton`'s `observeTheme` tinting; no `NSAnimationContext` or layer animation appears anywhere in this file. A UIKit port has no exact analogue for an `NSPopover`-anchored minimize picker or an app-modal sheet; it would present the minimize choices as a `UIMenu` on a long-press or a `UIPopoverPresentationController`-anchored sheet, and the "Settings…" dialog as a `UISheetPresentationController` detent sheet instead of `presentAsSheet`. The six probed capability protocols carry over unchanged — continuing to check with `as?` against `UIViewController` subclasses. Internally, the source wires the push-callback capabilities once in `wireContentCallbacks()`, re-evaluates control availability in `refreshControlAvailability()`, tracks the content's four edge pins in `contentEdgeConstraints`, and drops the title bar's `titleBarTrailing` constraint while docked to a rail — private mechanics specific to this file that a port reproduces by whatever means fits its own framework, not by name.
- **WinUI 3**: Recreate the pane as a `UserControl` with a two-row `Grid`: a fixed-height title row (a `GridLength` matching the title bar's height, 26px-equivalent) hosting a `StackPanel` of close/minimize/zoom `Button`s at the left, a `TextBlock` with `TextTrimming="CharacterEllipsis"` for the middle-truncated title, an accessory `StackPanel`, and a trailing gear `Button` (a `FontIcon` glyph for the gearshape symbol) that opens a `ContentDialog` mirroring the options dialog — an optional heading, a `StackPanel` of option rows (the spacing control plus its "Use Default" `Button`, then the content's own rows), and a single closing action. Model the clamping option by setting every child's `HorizontalAlignment="Stretch"` with `MinWidth="0"` rather than letting `Auto`-sized columns demand room, matching "the bar stops insisting on the width its contents would prefer." Minimizing to a vertical edge collapses the content row's `RowDefinition` to `Height="0"` while keeping the title row; minimizing to a horizontal edge swaps the whole `Grid` for a narrow rail `Border` (28px-equivalent width, matching the minimized rail's thickness) hosting a single glyph `Button`, docked with `HorizontalAlignment="Left"` or `"Right"` per edge — the direct analogue of the source's dock-to-one-side-only rail. Persist the minimize edge, zoomed flag, and spacing override through whatever local settings store the app uses (e.g. `ApplicationData.Current.LocalSettings`), matching the string-keyed, absent-means-default contract the state store defines.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/UI/ViewControllers/Panes/PaneViewController.swift` |

## Design Decisions

**Decision**: A pane's four host-facing controls — close, minimize, zoom, restore — send requests rather than performing actions directly.
**Rationale**: The source's own doc comment states the host is free to refuse, substitute, or do something else entirely with the same click, and the pane changes its own state only when the host calls `setMinimized(to:)` / `setZoomed(_:)` back — this is what lets the same class be dropped into a container with different rules and still be correct. (AppKit/UIKit.)
**Approved**: pending

**Decision**: `clampsToContainer` only ever yields the title bar's width demand; it never restores it once set.
**Rationale**: The setter's `didSet` guards on `false` and does nothing there; the doc comment explains a pane does not stop being clamped once it starts, and that restoring would mean tracking a priority per view for a case that never happens. (AppKit/UIKit.)
**Approved**: pending

**Decision**: Resetting the spacing override deletes the stored row rather than writing the current inherited value into it.
**Rationale**: `PaneSpacingOverride.reset()`'s own comment states that overwriting with today's global would freeze it, so a later app-wide change would no longer reach the pane; deletion is what keeps "use default" meaning "inherit" rather than "freeze." (AppKit/UIKit.)
**Approved**: pending

**Decision**: Spacing-override writes are coalesced behind a 300ms timer instead of writing on every tick of a drag.
**Rationale**: The spacing steppers are continuous and produce roughly seventeen values a second; the source's comment traces the uncoalesced cost to a JSON encode plus a synchronous SQLite write on the main thread per tick, and accepts a lag no longer than the pause between two deliberate presses. (AppKit/UIKit.)
**Approved**: pending

**Decision**: `setMinimized(to:)` called before the view loads only records the edge; it does not force the view to load.
**Rationale**: The source's comment on `applyMinimizedAppearance()` explains that forcing a load would re-enter through `viewDidLoad`'s call to `restorePersistedState()`, building a second, untracked rail. Recording the edge now and applying it once at load time is lossless, because the edge and the store are already written by the time this method is called. (AppKit/UIKit.)
**Approved**: pending

**Decision**: A `JSONEncoder`/`JSONDecoder` failure while persisting or reading the spacing override (`spacing-decode-failure-is-absent`) is silently ignored rather than surfaced to any caller.
**Rationale**: The state store's two methods, `setPaneStateValue(_:forKey:)` and `paneStateValue(forKey:)`, return no error value at all, so this class has no channel to report through even if it wanted to; failing open — treating unreadable or unwritable state as absent — keeps the pane opening whole rather than blocking on state it cannot use. (AppKit/UIKit.)
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | Accessibility |
| [string-externalization](agenticdevelopercookbook://compliance/internationalization#string-externalization) | failed | Internationalization |
| [data-integrity](agenticdevelopercookbook://compliance/reliability#data-integrity) | partial | Reliability |
| [state-recovery](agenticdevelopercookbook://compliance/reliability#state-recovery) | partial | Reliability |

Statuses rest on `PaneViewController.swift` and `PaneSpacingOverride.swift` as built: the gear and spacing-reset buttons carry real accessibility labels and identifiers, but no `NSAccessibility` notification is posted anywhere when the title, minimize state, or zoom state changes (`screen-reader-support`, partial); every user-facing string (`fallbackTitle`, the gear's tooltip/label, the "Settings…" and "Use Default" titles) is a hardcoded Swift literal with no localization key (`string-externalization`, failed); `PaneSpacingOverride`'s `JSONEncoder`/`JSONDecoder` calls are wrapped in `try?` so a corrupt or unwritable row is silently dropped rather than reported (`data-integrity`, partial); and the default `EphemeralPaneStateStore` keeps state in memory only, so nothing survives an actual process restart unless the caller injects a persistent store (`state-recovery`, partial).

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: reformatted Design Decisions to the bold three-line form and added one for the swallowed spacing JSON errors; moved the cookbook guideline out of `references` into `related`; fixed the `PaneTitleBarView` cross-reference and removed leftover template-instruction text; clarified the seventh spacing protocol in the Overview and disambiguated `spacing-defaults-to-inherited`'s two cases; added named requirements and vectors for spacing clamp-on-read, spacing decode-failure, and other untested fallback paths; strengthened weak vectors and folded an unverifiable one into its pair; restated internals-coupled requirements and vectors as observable behavior; rebuilt the Compliance table against real catalog checks (compliance_fix.py cleanup) |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/layout/. |
