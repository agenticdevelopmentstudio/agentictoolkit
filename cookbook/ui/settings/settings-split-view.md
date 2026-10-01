---
id: a11f34ff-116c-47d6-bffa-edd0799cbcb2
title: Settings Split View
domain: agentictoolkit://cookbook/ui/settings/settings-split-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: A settings window's sidebar/detail split view, with back/forward
  history and optional search.
platforms:
- swift
- macos
tags:
- settings
- split-view
- view-controller
- navigation
- search
depends-on:
- agentictoolkit://cookbook/ui/settings/settings-panel-list
- agentictoolkit://cookbook/ui/settings/layout/panel-host-view
- agentictoolkit://cookbook/ui/settings/layout/panel-scroll-view
related:
- agentictoolkit://cookbook/ui/settings/settings-panel-split
- agentictoolkit://cookbook/ui/settings/settings-window
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references:
- https://developer.apple.com/design/human-interface-guidelines/split-views
approved-by: ''
approved-date: ''
---

# Settings Split View

## Overview

The Settings Split View is the base component for a topic/detail
split-pane container used throughout the settings window: a
non-collapsible sidebar of panels on the left, driven by a panel list
component, and a themed detail pane on the right that shows whichever
panel is currently selected, hosted inside a detail-pane host component.
It builds on a themed split-container base (supplying theme-aware
split-view chrome and a divider-hiding safety fix) and implements a
search-field arrow-key redirect solely to steer the sidebar search
field's Down/Up presses to sidebar-row navigation instead of moving the
text caret. A client subclasses this component and populates it during
its own setup step by adding panels.

A hosted panel MAY itself be a settings split view (see the nested split's
own recipe), in which case this component treats it as a nested split: it
unifies every nested sibling's sidebar to one content width and raises its
own detail floor so the nested content is never squeezed.

**Owns:**
- Panel storage and ordering, including optional alphabetical sorting
- An in-place back/forward navigation trail
- Sidebar sizing — draggable-and-autosaved, or content-sized and pinned
- An optional sidebar search field and its arrow-key-to-selection redirect
- Repainting the window/detail backgrounds from the active theme
- Forwarding help state to a detail-pane host component

**Delegates to:**
- The panel list — sidebar row rendering and search matching (its own
  recipe)
- The detail-pane host — the detail pane's help-button chrome (its own
  recipe)
- The panel scroll wrapper — the scroll wrapper around non-self-scrolling
  panel content (its own recipe)
- The settings window — the window-level toolbar that drives this
  component's back/forward navigation and help presentation (its own
  recipe)

This recipe documents only what this component itself declares.

## Behavioral Requirements

- **exposes-hosted-panels-read-only**: The component MUST expose its panel
  list as read-only to callers outside the type — mutable only through its
  own set/add/remove/clear operations.
- **default-detail-minimum-thickness**: The component MUST default its
  detail-pane minimum-thickness floor to `400` points when not overridden.
- **overridable-detail-minimum-thickness**: A subtype MAY override the
  detail-pane minimum-thickness floor to raise or lower the floor applied
  to the detail pane — appropriate when a subtype's own content needs a
  different minimum than the window-level default (a nested split lowers
  it to `200` for nested content; see that recipe).
- **default-sidebar-autosave-name**: The component MUST default its
  sidebar persistence key to `"ComposableSettings.RootSidebar"` when not
  overridden.
- **default-content-sized-sidebar**: The component MUST default its
  content-sized-sidebar flag to `false`.
- **injectable-list-view-controller**: The component MUST accept a panel
  list component (or subtype) at construction, defaulting to a stock panel
  list when the caller supplies none.
- **reaches-list-controller-title**: Whatever value the sidebar title
  holds MUST reach the panel list's own title — immediately, if the
  sidebar title is set after the view has loaded, or once, during the
  view's load step, if it was set (or left at its default) beforehand.
- **reports-innermost-panel-title**: The current-panel-title query MUST
  return the innermost selected panel's own title — recursing into a
  selected panel that is itself a settings split view and using its own
  current-panel-title — whenever that inner title is non-empty, rather
  than this instance's own selected panel's descriptor title.
- **forwards-help-presenter-to-detail-chrome**: Whenever the help
  presenter is set, the component MUST forward the new value to the
  detail-pane host's own help-presenter property.
- **forwards-inline-help-button-visibility**: Whenever the
  inline-help-button-visibility flag is set, the component MUST forward
  the new value to the detail-pane host's own help-button-visibility
  flag.
- **wires-help-visibility-callback-once**: The component MUST wire the
  detail-pane host's help-visibility-change callback to invoke its own
  help-visibility-change callback exactly once, during construction,
  rather than re-wiring it each time that callback is assigned.
- **toggles-help-through-detail-chrome**: Toggling help MUST delegate to
  the detail-pane host's own toggle-help operation.
- **reports-help-visibility-from-detail-chrome**: The help-visibility
  query MUST return the detail-pane host's own help-visibility value.
- **builds-search-field-lazily**: The sidebar search field MUST be built
  lazily, on first access, so a split with search disabled never
  allocates it.
- **installs-search-field-only-when-enabled**: During the view's load
  step, the component MUST install the search field as the sidebar's
  header accessory if and only if search is enabled at that moment.
- **filters-list-as-user-types**: The search field MUST report every
  keystroke immediately, not only on commit, and each report MUST set the
  panel list's own search query to the field's current text.
- **redirects-arrow-keys-to-selection**: While the search field holds
  focus, pressing Down or Up MUST move the sidebar selection by a step
  instead of moving the text caret; every other editing command MUST fall
  through to the field's default handling.
- **builds-non-collapsible-sidebar-item**: During the view's load step,
  the component MUST add a non-collapsible sidebar item hosting the panel
  list.
- **prioritizes-detail-pane-on-resize**: The sidebar item's
  resize-holding priority MUST be higher than the detail item's, so a
  window resize resizes the detail pane rather than the sidebar (see the
  source values in Platform Notes).
- **fixes-content-sized-sidebar-thickness**: Whenever the
  content-sized-sidebar flag is `true`, the component MUST set the
  sidebar item's minimum and maximum thickness to the same value (see
  **caps-content-sized-sidebar-width**), making the sidebar non-draggable.
- **constrains-draggable-sidebar-range**: Whenever the content-sized-
  sidebar flag is `false`, the component MUST constrain the sidebar
  item's thickness between `160` and `360` points.
- **persists-draggable-sidebar-width**: Whenever the content-sized-
  sidebar flag is `false`, the component MUST persist the sidebar's
  dragged width under the sidebar persistence key, so a user's dragged
  sidebar width survives across app launches.
- **omits-autosave-for-content-sized-sidebar**: Whenever the
  content-sized-sidebar flag is `true`, the component MUST NOT persist a
  dragged sidebar width.
- **caps-content-sized-sidebar-width**: A content-sized sidebar's
  thickness MUST equal the lesser of an externally supplied minimum-width
  override (or, absent one, the panel list's own preferred width) and
  `480` points.
- **unifies-nested-sidebar-widths**: Whenever two or more of this
  instance's hosted panels are themselves settings split views, the
  component MUST set every one of their minimum-sidebar-width overrides
  to the same value: the widest of their own preferred widths, capped at
  `480` points.
- **raises-detail-floor-for-nested-siblings**: Whenever
  **unifies-nested-sidebar-widths** applies, the component MUST raise its
  own nested-detail floor to the largest of `widest + nested's own
  detail-minimum-thickness` across those nested siblings.
- **floors-detail-pane-thickness**: The detail item's minimum thickness
  MUST always equal the larger of the detail-minimum-thickness floor and
  the nested-detail floor.
- **selects-first-panel-on-first-appearance**: During the view's
  first-appearance step, if no panel is yet selected and the panel list is
  non-empty, the component MUST select the first panel.
- **repaints-theme-on-appearance-and-change**: The component MUST repaint
  the window's background and the detail container's background from the
  active theme's window-background color role on every appearance and on
  every theme change it is notified of.
- **replaces-panel-list-atomically**: Replacing the panel list MUST
  replace the stored panels (ordered per **sorts-panels-when-configured**),
  reset navigation history, rebuild the sidebar, and re-run
  sidebar-layout unification, in that call.
- **appends-without-unnecessary-history-reset**: Adding a panel MUST
  append the given panel to the stored panels (reordering if
  **sorts-panels-when-configured** applies) and rebuild the sidebar
  without resetting navigation history, except that when panels are
  sorted by title it MUST reset history and restore the selection, because
  sorting may have renumbered existing rows.
- **removes-and-renumbers-selection**: Removing a panel MUST remove the
  given panel by identity, reset navigation history, rebuild the sidebar,
  and restore the sidebar's highlight to whichever panel remains selected
  at its new index — or clear the detail pane if the removed panel was the
  one on screen.
- **sorts-panels-when-configured**: Whenever panels are configured to
  sort by title, replacing or adding panels MUST order the full panel
  list by section (ranked in first-encountered order) and, within equal
  rank, by a locale-aware comparison of the descriptor's title; whenever
  that configuration is off, panels MUST keep exactly the order supplied.
- **clears-search-when-restored-selection-is-hidden**: When a rebuild's
  restored selection is not among the sidebar's currently visible
  (search-filtered) rows, the component MUST clear the sidebar search
  query before re-selecting it.
- **clears-all-panels**: Clearing the panel list MUST empty the stored
  panels, reset navigation history, empty the sidebar, empty the detail
  pane, and invoke navigation change notification.
- **records-explicit-selection**: Selecting a panel, by reference or by
  index, MUST record the target index in navigation history before
  showing it.
- **steps-through-visible-rows-only**: Moving the selection by a step
  count MUST move the selection only among the sidebar's currently
  visible (search-filtered) rows, and MUST stop at the first or last
  visible row rather than wrapping.
- **preserves-search-during-arrow-navigation**: Moving the selection by a
  step count MUST leave the search field's text and the panel list's
  search query unchanged.
- **navigates-back-through-history**: Navigating back MUST, when a back
  step exists on the innermost split still able to go back, show that
  split's previous panel without recording a new history entry.
- **navigates-forward-through-history**: Navigating forward MUST,
  symmetrically with **navigates-back-through-history**, show the next
  panel in the trail without recording a new history entry.
- **resolves-arrows-to-innermost-active-split**: Navigating back and
  navigating forward MUST act on the innermost nested split whose own
  history can still move in the requested direction, falling back to this
  instance when no nested split can.
- **clears-search-on-programmatic-navigation**: Showing a panel via
  navigating back, navigating forward, or selecting a panel (by reference
  or by index) MUST clear the sidebar search field and query first, so the
  target row is never hidden by a stale filter.
- **propagates-navigation-change-upward**: Whenever this instance's
  selection, history availability, or panel title changes, it MUST invoke
  its own navigation-change notification and MUST also invoke the
  enclosing settings split view's navigation-change notification, if one
  exists.
- **reports-current-panel-from-detail-container**: The current-panel
  query MUST always reflect whichever panel is currently hosted in the
  detail pane, recomputed from the detail pane's actual content rather
  than from any separately tracked selection state (see the source
  mechanism in Platform Notes).
- **reports-effective-help-from-current-panel**: The effective-help query
  MUST return the current panel's own effective help content.
- **refreshes-help-through-detail-chrome-and-outward**: Refreshing help
  MUST hand the effective-help value to the detail-pane host's own
  set-help operation and MUST also call the enclosing split's own
  refresh-help operation, if one exists.
- **hosts-self-managing-panels-without-wrapper**: Showing a panel MUST
  host it directly in the detail-pane host (no wrapping scroll view) when
  that panel is itself a settings split view or reports that it hosts its
  own scrolling.
- **wraps-other-panels-in-scroll-view**: Showing a panel MUST wrap every
  other panel's view in a panel scroll wrapper before hosting it in the
  detail-pane host.
- **updates-help-and-floor-on-every-show**: Every call to show a panel,
  including showing none, MUST refresh the detail chrome's help content
  and MUST re-apply the detail-pane minimum-thickness floor.
- **locates-enclosing-split-by-parent-chain**: The enclosing-settings-
  split query MUST always reflect the current containment hierarchy —
  recomputed from the live containment relationship each time it is read,
  not cached — returning none when no enclosing split exists (see the
  source mechanism in Platform Notes).

## Appearance

- **Corner radius**: Not applicable — this component draws no chrome of
  its own; any corner radius shown by hosted panel content belongs to
  that content's own recipe.
- **Padding**: The detail pane's content view (the detail-pane host) is
  pinned to its container's safe-area top and to the container's leading,
  trailing, and bottom edges with zero additional inset; no other padding
  constant is set in this component.
- **Font**: Not applicable — this component sets no font of its own; the
  search field's font is that field's own responsibility.
- **Background**: The window's background and the detail container's
  background are both set to the active theme's window-background color
  role, on theme application.
- **Foreground/Text**: Not applicable — this component sets no text
  color of its own.
- **Border**: Not applicable — no border is configured in this component.
- **Shadow**: Not applicable — no shadow is configured in this component.
- **Min/Max size**: The detail-pane minimum-thickness floor defaults to
  `400`pt (raised to the nested-detail floor when larger). The sidebar
  item is either draggable between `160` and `360`pt
  (content-sized-sidebar flag `false`) or pinned at the lesser of an
  externally supplied minimum-width override (or the panel list's own
  preferred width) and `480`pt (content-sized-sidebar flag `true`). No
  maximum is set on the detail item.

## States

| State | Appearance change |
|-------|------------------|
| Default | Sidebar and detail items added; sidebar non-collapsible; window/detail background painted from the active theme; first panel auto-selected once panels exist. |
| Pressed | Not applicable — this component defines no control of its own; the search field is a stock text-search field, and the divider/rows it hosts belong to the outline component/panel list. |
| Disabled | Not applicable in this component — a disabled panel row is the panel list's concern (its descriptor's disabled flag); this component reads no disabled state. |
| Focused | While the sidebar search field holds focus, Down/Up move the sidebar selection instead of the text caret (**redirects-arrow-keys-to-selection**); every other command types normally. |
| Loading | Not applicable — every operation in this component is synchronous; there is no asynchronous load state. |
| Content-sized sidebar (content-sized-sidebar flag `true`) | Sidebar minimum thickness equals its maximum thickness, non-draggable, no persistence key set. |
| Draggable sidebar (content-sized-sidebar flag `false`, default) | Sidebar thickness ranges `160`–`360`pt, draggable, dragged width persisted under the sidebar persistence key. |
| Sidebar search shown (search enabled) | Search field installed as the sidebar's header accessory during the view's load step; typing narrows the sidebar and Down/Up steer the highlight. |
| Sidebar search hidden (search disabled, default) | Search field never built; no header accessory installed. |
| Nested split present (two or more hosted panels are themselves settings split views) | Every nested sibling's sidebar is pinned to one shared width; this instance's own detail floor is raised to accommodate the widest nested sibling's sidebar plus its own detail-minimum-thickness floor. |

## Accessibility

- **Role/trait**: Not applicable — this component assigns no
  accessibility role of its own; the sidebar rows (the panel list), the
  detail chrome's help button (the detail-pane host), and each hosted
  panel each own their own accessibility semantics in their own recipes.
- **Keyboard/assistive technology navigation**: The component MUST
  redirect Down/Up inside the sidebar search field to sidebar-row
  selection (**redirects-arrow-keys-to-selection**), leaving every other
  command (Return, Escape, Left/Right, text editing) to the field's
  default behavior. Beyond that redirect, this component adds no keyboard
  handling of its own; the standard outline/split-view tab order is
  unmodified.
- **Label requirements**: Supported for the search field: it exposes its
  placeholder text as the field's accessible description by default, and
  this component sets no additional label of its own. That placeholder
  text is not itself localized (see Localization).
- **Announce state changes (e.g., loading, disabled)**: Not applicable —
  this component has no loading or disabled state to announce (see
  States).
- **Minimum tap target**: Not applicable — this is a pointer-driven
  container; no touch-target constant is set anywhere in this component.
  Hit sizing for the search field and split divider is standard platform
  sizing, not a value this component chooses.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| split-view-controller-001 | exposes-hosted-panels-read-only | Attempt to assign the panel list directly from outside the type | Compile error; only the set/add/remove/clear operations compile |
| split-view-controller-002 | default-detail-minimum-thickness | Construct a plain instance | The detail-pane minimum-thickness floor is `400` |
| split-view-controller-003 | overridable-detail-minimum-thickness | Subclass and override the detail-pane minimum-thickness floor to `200` | The overridden value, not `400`, governs the detail item's minimum thickness |
| split-view-controller-004 | default-sidebar-autosave-name | Construct a plain instance | The sidebar persistence key is `"ComposableSettings.RootSidebar"` |
| split-view-controller-005 | default-content-sized-sidebar | Construct a plain instance | The content-sized-sidebar flag is `false` |
| split-view-controller-006 | injectable-list-view-controller | Construct with a given custom panel-list subtype | The stored panel list is that exact same instance |
| split-view-controller-007 | reaches-list-controller-title | Set the sidebar title to `"Advanced"` after the view has loaded | The panel list's title becomes `"Advanced"` |
| split-view-controller-007b | reaches-list-controller-title | Set the sidebar title to `"Advanced"` before the view loads, then trigger the load step | The panel list's title is `"Advanced"` after load |
| split-view-controller-008 | reports-innermost-panel-title | Select a nested settings-split-view panel whose own current-panel-title is `"Accent Color"` | This instance's current-panel-title is `"Accent Color"` |
| split-view-controller-011 | forwards-help-presenter-to-detail-chrome | Set the help presenter to a given presenter | The detail-pane host's help presenter is that same presenter |
| split-view-controller-012 | forwards-inline-help-button-visibility | Set the inline-help-button-visibility flag to `false` | The detail-pane host's help-button-visibility flag is `false` |
| split-view-controller-013 | wires-help-visibility-callback-once | Assign the help-visibility-change callback twice, then have the detail-pane host fire its own callback | The most recently assigned closure fires; no double invocation and no re-wiring occurs on assignment |
| split-view-controller-014 | toggles-help-through-detail-chrome | Call the toggle-help operation | The detail-pane host's own toggle-help operation is invoked |
| split-view-controller-015 | reports-help-visibility-from-detail-chrome | Set the detail-pane host's help to visible | The help-visibility query returns `true` |
| split-view-controller-016 | builds-search-field-lazily | Construct an instance with search disabled and never read the search field | No search field is ever allocated |
| split-view-controller-017 | installs-search-field-only-when-enabled | Enable search before the view loads, then load | The panel list's header accessory is the search field |
| split-view-controller-017b | installs-search-field-only-when-enabled | Leave search disabled, then load | The panel list's header accessory is unset |
| split-view-controller-018 | filters-list-as-user-types | Type `"a"` into the search field without pressing Return | The panel list's search query is `"a"` immediately |
| split-view-controller-019 | redirects-arrow-keys-to-selection | With the search field focused and `"Advanced"` typed, press Down | Sidebar selection moves to the next visible row; search text remains `"Advanced"` |
| split-view-controller-020 | builds-non-collapsible-sidebar-item | Load the view, then attempt to collapse the sidebar item | Collapse is refused; the sidebar item cannot collapse |
| split-view-controller-021 | prioritizes-detail-pane-on-resize | Read the sidebar item's and detail item's resize-holding priority after the view loads | The sidebar item's priority is one step higher than the detail item's |
| split-view-controller-022 | fixes-content-sized-sidebar-thickness | Set the content-sized-sidebar flag to `true`, then load | The sidebar item's minimum thickness equals its maximum thickness |
| split-view-controller-023 | constrains-draggable-sidebar-range | Load with the content-sized-sidebar flag `false` (default) | The sidebar item's minimum thickness is `160`, maximum is `360` |
| split-view-controller-024 | persists-draggable-sidebar-width | Load with the content-sized-sidebar flag `false` | The sidebar's dragged width is persisted under the sidebar persistence key |
| split-view-controller-024b | persists-draggable-sidebar-width | Subclass overrides the sidebar persistence key to return none; load with the content-sized-sidebar flag `false` | No persistence key is set; width persistence is silently disabled, no fallback name is used |
| split-view-controller-025 | omits-autosave-for-content-sized-sidebar | Load with the content-sized-sidebar flag `true` | No persistence key is set |
| split-view-controller-026 | caps-content-sized-sidebar-width | The panel list's preferred width is `900`, no minimum-width override supplied | The sidebar item's fixed width is `480`, not `900` |
| split-view-controller-027 | unifies-nested-sidebar-widths | Host two nested settings-split-view panels whose own preferred widths are `180` and `220` | Both nested panels' minimum-sidebar-width override is `220` |
| split-view-controller-028 | raises-detail-floor-for-nested-siblings | Nested siblings as above, each with a detail-minimum-thickness floor of `200` | This instance's nested-detail floor is `420` (`220 + 200`) |
| split-view-controller-029 | floors-detail-pane-thickness | Detail-minimum-thickness floor is `400`, nested-detail floor is `420` | The detail item's minimum thickness is `420` |
| split-view-controller-030 | selects-first-panel-on-first-appearance | Set two panels, then trigger the view's first-appearance step with no prior selection | The first panel is shown and selected |
| split-view-controller-031 | repaints-theme-on-appearance-and-change | Switch the active theme after the view has appeared | Window and detail-container backgrounds update to the new theme's window-background color role |
| split-view-controller-032 | replaces-panel-list-atomically | Replace the panel list with `[a, b]` | The stored panels are `[a, b]`; history is empty; sidebar shows exactly `a` and `b` |
| split-view-controller-033 | appends-without-unnecessary-history-reset | With sort-by-title off, navigate to panel `a`, then add panel `c` | History still shows `a` as current; `c` appended at the end |
| split-view-controller-033b | appends-without-unnecessary-history-reset | With sort-by-title on, navigate to panel `a`, then add panel `c` where `c` sorts before `a` | History is reset; the sidebar re-selects `a` at its new (shifted) index |
| split-view-controller-034 | removes-and-renumbers-selection | Panels `[a, b, c]`, `b` selected, remove `a` | The stored panels are `[b, c]`; `b` remains selected at its new index `0` |
| split-view-controller-034b | removes-and-renumbers-selection | Panels `[a, b]`, `b` selected, remove `b` | Detail pane is cleared; nothing is selected |
| split-view-controller-035 | sorts-panels-when-configured | Sort-by-title on; add panels titled `"Zebra"`, `"Apple"` with no section | The stored panel order is `["Apple", "Zebra"]` |
| split-view-controller-036 | clears-search-when-restored-selection-is-hidden | Search query hides the currently selected panel, then removing a panel triggers a restore of that same panel | Search query is cleared before the panel is re-selected |
| split-view-controller-037 | clears-all-panels | Clear the panel list | The stored panels are `[]`; detail pane empty; navigation-change notification invoked |
| split-view-controller-038 | records-explicit-selection | Select the panel at index `1` | History's current index is `1` |
| split-view-controller-039 | steps-through-visible-rows-only | Visible rows are `[0, 2]` (row `1` filtered out), current is `0`, move the selection forward by one step | Selection moves to row `2`, not row `1` |
| split-view-controller-039b | steps-through-visible-rows-only | Current selection is the last visible row, move the selection forward by one step | No change; selection does not wrap to the first row |
| split-view-controller-040 | preserves-search-during-arrow-navigation | Search query is `"a"`, move the selection forward by one step | The panel list's search query remains `"a"` |
| split-view-controller-041 | navigates-back-through-history | History has one prior entry, navigate back | The previous panel is shown; history is not appended |
| split-view-controller-042 | navigates-forward-through-history | After navigating back, navigate forward | The panel that was current before navigating back is shown again |
| split-view-controller-043 | resolves-arrows-to-innermost-active-split | A nested split's own history can go back but the outer split's cannot, navigate back on the outer split | The nested split's back-navigation behavior runs, not the outer split's |
| split-view-controller-044 | clears-search-on-programmatic-navigation | Search query is `"a"`, navigate back | Search field and search query are cleared before the panel is shown |
| split-view-controller-045 | propagates-navigation-change-upward | This instance is nested inside an outer split, selection changes | Both this instance's navigation-change notification and the outer split's navigation-change handling fire |
| split-view-controller-046 | reports-current-panel-from-detail-container | Show panel `a` | The current-panel query returns `a` |
| split-view-controller-047 | reports-effective-help-from-current-panel | The current panel's effective help content is non-empty | The effective-help query returns that same value |
| split-view-controller-048 | refreshes-help-through-detail-chrome-and-outward | This instance is nested, refresh help | The detail-pane host's set-help operation is called with the effective-help value; the outer split's refresh-help operation is also called |
| split-view-controller-049 | hosts-self-managing-panels-without-wrapper | Show a panel that is itself a settings split view | The detail-pane host's content is that panel's view directly, no scroll wrapper |
| split-view-controller-050 | wraps-other-panels-in-scroll-view | Show a plain panel that does not host its own scrolling | The detail-pane host's content is a panel scroll wrapper wrapping that panel's view |
| split-view-controller-051 | updates-help-and-floor-on-every-show | Show no panel | The detail-pane host's content and help are both cleared, and the detail-floor recompute runs |
| split-view-controller-052 | locates-enclosing-split-by-parent-chain | This instance is added as a panel of an outer settings split view | The enclosing-settings-split query returns that outer instance |
| split-view-controller-053 | (edge case: removing a non-member panel) | Panels `[a, b]`, remove `z` where `z` is not in the panel list | The stored panels are unchanged (`[a, b]`); navigation history is still reset, the sidebar's panel list is still re-set, and the navigation-change notification still fires |
| split-view-controller-054 | (edge case: stale nested-detail floor) | Two nested settings-split-view siblings raise the nested-detail floor to `420`; removing a panel drops the nested count to one | The nested-detail floor remains `420` (not reset toward `0`), because the unification step's early exit returns before recomputing it |

## Edge Cases

- **Null/empty input**: Replacing the panel list with `[]` and clearing
  the panel list both leave the stored panels empty, the sidebar empty,
  and the detail pane empty (MUST). Constructing with no panel-list
  argument uses a stock panel list rather than requiring a caller-supplied
  one (MUST).
- **Boundary values**: Selecting a panel by index and navigating to an
  index both guard against out-of-bounds access and are silent no-ops out
  of range (MUST). Moving the selection by a step stops at the first or
  last *visible* row rather than wrapping, and is a no-op when no rows are
  visible (MUST, see **steps-through-visible-rows-only**). A
  content-sized sidebar's width is capped at `480`pt regardless of how
  wide the panel list's preferred width reports (MUST, see
  **caps-content-sized-sidebar-width**).
- **Concurrent access**: Not applicable — the component's construction and
  every property access are confined to a single, serialized execution
  context (see Platform Notes), so there is no concurrent-access surface
  for this component to define behavior for.
- **Error states**: Not applicable — every member in this component is
  synchronous and non-throwing; there is no dependency, network call, or
  fallible operation in this component.
- **Offline/disconnected state**: Not applicable — this component performs
  no networking and has no dependency on connectivity.
- **Removing a panel not in the panel list**: The removal step removes
  nothing, but the operation still unconditionally resets navigation
  history, re-sets the sidebar's panel list, and invokes the
  navigation-change notification — the same side effects as a real
  removal. This is a documented observation of the component's actual
  behavior, not a deliberate contract (see split-view-controller-053).
- **Sidebar persistence key set to none while the content-sized-sidebar
  flag is `false`**: A subtype MAY override the sidebar persistence key
  to return none. In that case no persistence key is set, which silently
  disables width-persistence for that instance — no fallback name is
  substituted and nothing fails (see split-view-controller-024b).
- **Stale nested-detail floor after a nested split is removed**: The
  sidebar-unification step only recomputes the nested-detail floor when
  at least two nested settings-split-view panels remain; when a removal
  or a panel-list replacement drops the nested count from two-or-more to
  one or zero, this early exit leaves the nested-detail floor at its
  previous, now-stale value rather than resetting it toward `0`. The
  detail pane's floor can therefore stay wider than the current panel set
  requires until a later state again has two or more nested siblings.
  This is the component's actual, undocumented behavior — see Design
  Decisions and split-view-controller-054.
- **Toggling search-enabled or sort-by-title after their first effect has
  already run**: Neither setting reacts to a later change on its own.
  Search-enabled is read only once, during the view's load step, to
  decide whether to install the header accessory view — flipping it
  afterward has no further effect on an already-loaded view. Sort-by-title
  is read only inside the replace/add operations — flipping it does not
  retroactively reorder a panel list already installed; it only changes
  the outcome of the next mutating call.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `detailMinimumThickness` | number (overridable) | `400` | Floor on the detail pane's minimum thickness. |
| `sidebarAutosaveName` | string, optional (overridable) | `"ComposableSettings.RootSidebar"` | Persistence key used when the content-sized-sidebar flag is `false`. |
| `contentSizedSidebar` | boolean (overridable) | `false` | `true` pins the sidebar to its content width and disables dragging/persistence; `false` keeps the draggable, persisted band. |
| `minimumSidebarWidthOverride` | number, optional | none | External floor for a content-sized sidebar's width, set by a parent split to unify nested siblings. |
| `sidebarTitle` | string, optional | none | Header title shown above the sidebar's panel list. |
| `showsSidebarSearch` | boolean | `false` | Whether the sidebar leads with a search field; read once, during the view's load step. |
| `sortsPanelsByTitle` | boolean | `false` | Whether the replace/add operations alphabetize panels (within section) instead of keeping supplied order. |
| `showsInlineHelpButton` | boolean | `true` | Whether the detail pane's own host component draws its help button. |
| `helpPresenter` | help-presenting reference, optional | none | Where help content and visibility are shown; forwarded to the detail-pane host's help presenter. |
| `listViewController` | panel list component | a stock panel list | The sidebar component; injectable at construction. |

## Deep Linking

Not applicable: no URL scheme, route, or deep-link handling appears
anywhere in this component.

## Localization

| String Key | Default (en) | Context |
|-----------|-------------|---------|
| `"Search"` | Search | Placeholder text for the sidebar's search field, stored as the field's platform placeholder text — a literal string, not routed through any localization lookup in this component. |

The `"Search"` placeholder is not localized: this component passes it as a
hardcoded literal to the search field, never routing it through a
localization lookup, both of which are used elsewhere in the surrounding
codebase (outside this component).

## Accessibility Options

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: no animation, transition, or motion effect appears anywhere in this component. |
| Increase Contrast | Not applicable to this component: colors come from the active theme's palette via a palette-change observer; any Increase Contrast adaptation is that type's responsibility, not something this component computes. |
| Differentiate Without Color | Not applicable: this component has no color-only state indicator; row selection is the panel list's concern. |

## Feature Flags

Not applicable: no feature-flag lookup or conditional gate appears anywhere
in this component.

## Analytics

Not applicable: this component contains no analytics or telemetry call.

## Privacy

- **Data collected**: None beyond the panels and search text the host
  supplies at runtime; the sidebar search query lives only in memory.
- **Storage**: When the content-sized-sidebar flag is `false` (the
  default), the sidebar's dragged width is persisted locally via the
  platform's own split-view width-persistence mechanism, keyed by the
  sidebar persistence key. No other state in this component is persisted;
  the search query and navigation history are in-memory only and are
  discarded when the panel list is replaced or cleared, or on app
  relaunch.
- **Transmission**: Not applicable — no networking call appears anywhere
  in this component.
- **Retention**: The persisted sidebar width remains under its key
  indefinitely, until the user drags it again or the underlying storage
  entry is cleared by the OS or the app; it is never written by this
  component when the content-sized-sidebar flag is `true`.

## Logging

Not applicable: no logging call appears anywhere in this component.

## Platform Notes

- **SwiftUI**: Use `NavigationSplitView` with a `List` (built from the
  panel list) as the sidebar column and the selected panel's view as the
  detail column. For a content-sized sidebar, set the sidebar column's
  `.navigationSplitViewColumnWidth(min:ideal:max:)` to the same fixed
  value (min == ideal == max), the nearest SwiftUI analog of a pinned,
  non-draggable width; for the draggable default, use `min: 160, ideal:
  <persisted>, max: 360` and persist the ideal width yourself (SwiftUI has
  no built-in per-split autosave equivalent to a native width-persistence
  mechanism). Use `.searchable(text:)` on the sidebar for the
  search-enabled option, and drive back/forward with a small custom index
  stack, since `NavigationSplitView` has no built-in in-place trail
  matching this component's discard-forward-on-new-step semantics.
- **Compose**: Compose a two-pane `ListDetailPaneScaffold` (Material 3
  adaptive) or a manual `Row` of a fixed-width `LazyColumn` sidebar plus a
  weighted detail `Box`. Size the sidebar with
  `Modifier.width(IntrinsicSize.Max)` for the content-sized case, or a
  draggable divider whose width is saved to `DataStore`/`SharedPreferences`
  (mirroring the persistence) for the default case. Filter the list with
  an `OutlinedTextField` bound to a `mutableStateOf` query; implement
  back/forward as a small `MutableList<Int>` index trail, since Compose
  Navigation's back stack tracks destinations, not row selections within
  one screen.
- **React/Web**: A CSS Grid two-column layout
  (`grid-template-columns: <sidebar> 1fr`), sidebar `<nav>` of `<button>`s
  or links, detail `<main>`. For the content-sized case, size the sidebar
  column `max-content`; for the draggable default, add a resizer handle
  that persists its width to `localStorage` under a key analogous to the
  sidebar persistence key. Filter with a controlled `<input
  type="search">`; implement back/forward as an in-memory index stack
  rather than the browser History API, since each panel is not
  necessarily its own route.
- **AppKit / UIKit** (source platform): Source file
  `SplitViewController.swift` (`ComposableSettingsWindow/SplitViewController/`),
  AppKit-only — an `NSSplitViewController` subclass of `ThemedSplitViewController`,
  composing a `PanelListViewController` sidebar item and a `PanelHostView`-hosted
  detail item, wrapping non-self-scrolling panel content in a
  `PanelScrollView`, and tracking navigation with a
  `SettingsNavigationHistory` value type. The class is `@MainActor`, so
  construction and every property access are rejected off the main actor
  at compile time. It does not support construction via `init?(coder:)`:
  that initializer is `@available(*, unavailable)` and its body is
  `fatalError()`. `panels` is declared `private(set)`, enforcing
  **exposes-hosted-panels-read-only** at compile time. The sidebar item's
  `holdingPriority` is `.defaultLow + 1` against the detail item's
  `.defaultLow`, which is how **prioritizes-detail-pane-on-resize** is
  implemented. `currentPanel` is computed by reading
  `detailContainer.children.first`, and `enclosingSettingsSplit` walks
  `parent` upward looking for the nearest
  `ComposableSettings.SplitViewController` — the mechanisms behind
  **reports-current-panel-from-detail-container** and
  **locates-enclosing-split-by-parent-chain**. No UIKit counterpart exists
  in this codebase (`ComposableSettingsWindow/` is entirely AppKit); a
  UIKit port would reach for `UISplitViewController` with `.doubleColumn`
  style, though it has no analog of the content-sized-sidebar flag's
  pinned min==max thickness or of `NSSplitView`'s dragging-based
  `autosaveName` persistence.
- **WinUI 3** (the reason this recipe exists): Use a `NavigationView` with
  `PaneDisplayMode="Left"` as the sidebar and its `Content`/`Frame` as the
  detail region. Bind `MenuItems` to the panel list — one
  `NavigationViewItem` per panel, grouped under a `NavigationViewItemHeader`
  per section run, mirroring the panel list's section grouping — and
  drive selection through `SelectionChanged` (analogous to the panel
  list's own selection callback). For the draggable default
  (content-sized-sidebar flag `false`), set
  `IsPaneToggleButtonVisible="False"` and bind `OpenPaneLength` to a value
  restored from `ApplicationData.LocalSettings` keyed by the sidebar
  persistence key, constrained to a `160`–`360`-equivalent range; for a
  content-sized sidebar, fix `OpenPaneLength` to the pane's measured
  content width and skip persistence entirely, exactly as this component
  does. There is no WinUI analog of a per-item content-side minimum
  thickness, so approximate the detail-minimum-thickness floor (and the
  raised nested-sibling floor) with a `MinWidth` on the
  `Frame`/`ContentPresenter` hosting `Content`. For search, add an
  `AutoSuggestBox` as `NavigationView.PaneCustomContent`, wire
  `TextChanged` to filter `MenuItems.Source` the way this component's
  search-query change filters the panel list, and forward the list's
  Up/Down `KeyDown` to move `SelectedItem` while the `AutoSuggestBox`
  keeps focus — mirroring the arrow-key redirect. Implement back/forward
  with two `Stack<int>`s alongside `NavigationView.BackRequested`, since
  this component's trail semantics (discard-forward-on-new-step, no-op on
  re-selecting the current row) have no built-in WinUI equivalent; for a
  nested `NavigationView` acting as a nested settings panel split does,
  forward whichever inner item is selected up to the outer shell's single
  help affordance, mirroring the effective-help/refresh-help outward
  chain.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/SystemIntegration/ComposableSettingsWindow/SplitViewController/SplitViewController.swift` |

## Design Decisions

**Decision**: The detail-pane minimum-thickness floor floors the detail
pane's minimum thickness rather than a required-width constraint on the
detail content.
**Rationale**: This "lets the detail grow freely, unlike a required width
constraint on the content, which pins the window"; it is "the proper lever
for the window's minimum width (window min = sidebar thickness + this)."
**Approved**: pending

**Decision**: The content-sized-sidebar flag defaults to `false` for this
base component (the draggable, persisted band), even though nested splits
generally want `true`. (AppKit.)
**Rationale**: "The full-height *root* window sidebar keeps the draggable
behaviour (its outline's column-fill misbehaves under a fixed width).
Nested topic/detail splits opt in — they're the ones that visibly 'move
around' as you switch between them."
**Approved**: pending

**Decision**: Search-enabled and sort-by-title both default to `false`
and are switched on only for the window's root split.
**Rationale**: A nested split's sidebar is "a table of contents for one
panel" written in an intentional order, while the root window's list is
"a set of unrelated destinations" a reader can only find by name or by
search; a second search field inside an outer split's already-filtered
results "is a maze."
**Approved**: pending

**Decision**: Moving the selection by a step (arrow-key stepping) leaves
the search field's text and query untouched, unlike selecting a panel or
navigating back/forward, which all clear it.
**Rationale**: "The query is the very thing the reader is steering by
when they press Down, so clearing it would throw away the list they are
moving through and jump the highlight somewhere else."
**Approved**: pending

**Decision**: This component intercepts the search field's Down/Up
key commands through the platform's own field-editing delegation, rather
than through a lower-level key-event override, returning "not handled"
for every other command. (AppKit.)
**Rationale**: This is answered "rather than in a `keyDown` override
because AppKit has already turned the key into the reader's intent by this
point — and returning false for every other command leaves the rest of
text editing exactly as it was."
**Approved**: pending

**Decision**: The current-panel-title and effective-help queries both
recurse into a selected panel that is itself a settings split view,
reporting that inner split's own title/help rather than this instance's.
**Rationale**: "A split whose selected panel is itself a split answers
with the topic selected *inside* it: that is the panel the reader is
looking at," and naming the outer container instead "left the toolbar
stuck on the container's name while the reader moved down its list."
**Approved**: pending

**Decision**: The sidebar-unification step leaves the nested-detail floor
unchanged (rather than resetting it toward `0`) whenever the current
panel set has fewer than two nested settings-split-view panels.
**Rationale**: Not stated in source. The method's early exit returns
before recomputing the floor, so a detail-pane floor raised while two or
more nested splits were present can outlive their removal until a later
state again has two or more. Documented here as observed behavior (see
Edge Cases and split-view-controller-054), not as a deliberate design
tradeoff.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | accessibility |
| [screen-reader-support](agenticdevelopercookbook://compliance/accessibility#screen-reader-support) | partial | accessibility |
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | platform-compliance |

Statuses rest on: this file delegating row
rendering to `PanelListViewController`, help chrome to `PanelHostView`, and
scroll wrapping to `PanelScrollView` rather than reimplementing any of them
(separation-of-concerns); the search field's arrow-key redirect and the
unmodified standard `NSSplitViewController` tab order (keyboard-navigable);
`native-controls-preference` resting on this file composing only stock
`NSSplitViewController`/`NSSplitViewItem`/`NSSearchField` behavior with no
custom-drawn chrome. `screen-reader-support` is `partial`: the search
field's accessible description is the AppKit-default `placeholderString`,
but that placeholder is the unlocalized `"Search"` literal documented under
Localization, so a non-English VoiceOver user would hear an English word
regardless of the app's language.

## Change History

| Version | Date | Author | Summary |
|---|---|---|---|
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to ui/settings/. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: restate five implementation-mechanics requirements (private(set), fatalError(), holdingPriority, detail-container read, parent-chain walk) as observable outcomes and move their mechanics into the AppKit Platform Notes bullet; downgrade the removePanel-on-non-member edge case from a MUST-relied-upon contract to a documented observation; add an edge case, a test vector, and Design-Decisions wording for a nil sidebarAutosaveName; add test vectors pinning the removePanel-on-non-member and stale-nested-detail-floor behaviors; tighten test vector 021 to assert holdingPriority directly instead of an unstated width change; reformat Design Decisions to the bold three-line form; split the Overview into a short description plus Owns/Delegates-to lists; move the platform-design-languages reference into related and the three composed-ingredient recipes into depends-on; trim tags to 5 and summary to ~120 characters; and reconcile the Compliance table against the catalog, dropping seven cited checks that have no corresponding category or check in the compliance catalog. |
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
