---
id: 28fc5136-e1bf-4672-b783-ed2f3a8983f5
title: Extension Tree View
domain: agentictoolkit://cookbook/workspace/extensions/vscode-api/tree-views/extension-tree-view
type: ingredient
version: 1.2.0
status: review
language: en
created: '2026-09-23'
modified: '2026-09-27'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: 'A pane for a contributed tree view: a placeholder until an extension
  registers a tree data provider, then a lazily-loaded, identity-preserving tree
  bound to it.'
platforms:
- swift
- macos
tags:
- extensions
- tree-view
- accessibility
depends-on: []
related:
- agenticdevelopercookbook://guidelines/cookbook/ui/platform-design-languages
references: []
approved-by: ''
approved-date: ''
---

# Extension Tree View

## Overview

This is the pane a contributed tree view occupies: a placeholder's explanation until the extension registers a tree data provider for the view, then a tree bound to that provider. It is a webview-presenting pane's twin and deliberately a different shape — a webview panel is the app's own object handed to the extension, while a tree data provider is the extension's object that may not exist yet, so the answer arrives asynchronously through a resolution callback rather than being returned.

This recipe also covers the internal component that actually draws the tree once a data source has resolved: it pulls children from the provider lazily (never asking for a branch nobody opens), caches every answer in a row table so rows keep their object identity — and therefore their disclosure and selection — across refreshes, bounds each children ask with a wall-clock budget, and reports the user's selection, expansion, activation and visibility back through the tree data source. Both are documented together here because one is the other's sole means of appearing on screen; the placeholder, the row table and the tree data source are collaborators consulted for grounding but are out of this recipe's scope.

## Behavioral Requirements

### Construction & the placeholder

- **contributed-view-retained**: The pane MUST retain the contributed view and extension display name given at construction, using them respectively as the placeholder's subject and as the pane title's fallback until a tree is shown.
- **explicit-construction-only**: The pane MUST support construction only through its explicit initializer; construction through a generic archive/coder-based path MUST fail fast rather than produce a usable instance.
- **initial-placeholder-shown**: Before any data source has resolved, the pane MUST show the placeholder for the contributed view.
- **container-background-tracks-theme**: The container view's background MUST track the `.surface` semantic theme color.
- **resolve-requested-after-view-loads**: The pane MUST request resolution of the data source only once its view has finished loading, not while the view is still being constructed.

### Swapping to a tree once resolved

- **first-resolve-shows-outline**: The first time resolution delivers a data source, the pane MUST replace the placeholder with a tree bound to that data source.
- **resolve-after-discard-ignored**: A resolution delivered after the pane has begun teardown MUST NOT change what is displayed.
- **duplicate-resolve-ignored**: A second resolution delivered once the tree is already showing MUST be ignored — regardless of whether it carries the same or a different data source; only provider replacement (below) may install a different data source once one is showing.
- **provider-replacement-swaps-source**: When the currently-bound data source signals that it has been replaced, the pane MUST replace the displayed tree with a new one bound to the replacement data source, and MUST re-hook the replacement signal on the replacement so a further replacement continues the chain.
- **swap-tears-down-previous-content**: Swapping displayed content MUST tear down the outgoing child's content when it supports teardown, and MUST clear its title-change notification, before removing it from view.
- **swap-pins-new-content-to-edges**: The newly shown child's view MUST be constrained to all four edges of the container.
- **swap-notifies-title-change**: Swapping displayed content MUST invoke the pane's own title-change notification once, since the pane title may now answer differently.

### Pane title & teardown (outer pane)

- **outer-pane-title-delegates**: The pane title MUST return the currently-shown child's own title when that child provides one, and MUST return the contributed view's name otherwise (i.e. while the placeholder is showing).
- **outer-teardown-marks-discarding**: Teardown MUST set an internal flag that suppresses any further reaction to resolution.
- **outer-teardown-forwards-to-content**: Teardown MUST forward to the currently-shown child's own teardown when that child supports it.

### Tree construction & layout

- **outline-single-column-no-header**: The tree MUST be built with exactly one column and MUST hide its header.
- **outline-row-height**: The tree's row height MUST be 22pt.
- **outline-indentation-per-level**: The tree's indentation per level MUST be 14pt.
- **outline-inset-style**: The tree MUST use an inset visual style.
- **outline-allows-empty-selection**: The tree MUST allow an empty selection.
- **message-banner-shown-conditionally**: A non-empty data-source message MUST be shown as a banner above the tree; when there is no message, the tree MUST instead be pinned to the container's top edge and the banner MUST be hidden.
- **message-banner-inset**: The message banner MUST be inset 16pt from the container's leading and trailing edges and 8pt from its top edge; the tree MUST sit 8pt below the banner's bottom edge when the banner is shown.
- **message-banner-wraps**: The message banner MUST wrap onto multiple lines with no line-count limit and left alignment.
- **accessibility-ids-assigned**: The tree MUST carry the accessibility identifier `"<accessibilityPrefix>.tree"` and the message label MUST carry `"<accessibilityPrefix>.message"`, where `accessibilityPrefix` is the contributed view's registry id.

### Loading lifecycle

- **initial-load-when-view-is-ready**: When the tree's view becomes ready to use, it MUST request the root's children and MUST apply the data source's chrome (title/message/allows-multiple-selection).
- **callback-ownership-transfers-to-latest-pane**: Installing this pane's callbacks on a data source MUST record this pane as that data source's current callback owner, superseding whichever pane owned them before.
- **visibility-forwarded-only-by-owner**: Reporting visibility to the data source when the pane becomes visible or becomes hidden MUST happen only when this pane is still that data source's recorded callback owner; a superseded pane's visibility changes MUST NOT be reported.
- **message-label-wrap-width-tracks-container**: The message label's preferred maximum layout width MUST track the container's width minus 32pt (16pt inset on each side).
- **multiple-selection-mirrors-source**: The tree's support for selecting multiple rows MUST mirror the data source's allows-multiple-selection setting, re-applied every time chrome is applied.

### Reading children

- **children-answered-from-cache**: A request for an item's children MUST be answered from the cached row table, never by blocking the tree on the data source.
- **uncached-branch-triggers-load-and-empty-answer**: A request for the children of a branch with no cached answer MUST return an empty array immediately and MUST trigger a load of that branch.
- **load-skipped-while-in-flight**: A load already in flight for a handle MUST NOT trigger a second, concurrent ask of the provider for that same handle.
- **load-marked-stale-when-busy**: A load requested for a handle that already has one in flight MUST be remembered and re-issued once the in-flight one completes.
- **load-skipped-for-unreachable-handle**: A load MUST NOT be issued for a non-root handle whose row is not currently reachable in the table (never loaded, orphaned pending settlement, or already forgotten).
- **disclosure-driven-by-declared-state**: Whether a row offers a disclosure triangle MUST be determined solely by `item.collapsibleState.isExpandable`, independent of how many children (if any) a load of that row actually returns.
- **load-bounded-by-budget**: A children load MUST be bounded by `childrenBudget` (default 30 seconds).
- **timeout-logged**: A children load that exceeds `childrenBudget` MUST log an error.
- **timeout-leaves-branch-askable**: A children load that exceeds `childrenBudget` MUST NOT adopt any rows for that branch — the branch stays unread, not recorded as empty — and MUST remain askable by a later expansion, refresh, or the stale re-ask mechanism below.
- **late-answer-discarded-when-defunct**: A children answer that arrives after the pane has begun teardown, or for a non-root handle whose row no longer exists, MUST be discarded without updating the tree.
- **successful-load-updates-table-and-redraws**: A successful children answer MUST replace that branch's rows in the table — reusing the existing row object (and its already-loaded subtree) for every id that was already drawn somewhere, whether under this parent or another — and MUST redraw both that branch and any other branch a moved row was taken from.
- **duplicate-child-id-deduplicated**: When a single children answer contains the same item id more than once, only the first occurrence MUST be kept; the rest MUST be dropped.
- **moved-row-preserves-identity**: When an item dropped by one already-loaded branch is claimed by a different branch before the refresh that dropped it has settled (no loads in flight), the row MUST keep its object identity and its already-loaded subtree, regardless of the order in which the two branches' answers arrive.
- **orphan-return-by-same-parent-is-new-row**: When the same branch that stopped naming an id later names that same id again (in a separate, subsequent refresh), that id MUST be treated as a new row — its previous subtree discarded — rather than as a preserved one.
- **prune-orphans-after-settling**: Once no children loads are in flight, a row dropped during that refresh and never reclaimed by any branch MUST be forgotten, along with everything beneath it; a row still claimed by some branch MUST NOT be forgotten.
- **forget-is-cycle-safe**: Forgetting a handle and its descendants MUST terminate even when the extension's declared ids form a cycle, visiting each handle at most once.

### Redraw, expansion, selection

- **redraw-preserves-selection**: Redrawing a branch MUST preserve the prior selection across the reload for every previously-selected row that still exists afterward.
- **redraw-narrowing-selection-notifies-source**: If a redraw's restored selection contains fewer rows than were selected before it, the data source MUST be told the selection changed.
- **redraw-suppresses-source-notifications**: While the tree reloads for a redraw, the tree's own selection and expand/collapse notifications that the reload itself triggers MUST NOT be forwarded to the data source.
- **default-expansion-applied-once**: A child row whose `collapsibleState` is `.expanded` MUST be automatically expanded exactly once, the first time it is drawn under its current parent; a branch the user has since closed MUST stay closed through every later redraw.
- **expansion-request-triggers-load**: Expanding a row whose children have not yet been loaded MUST trigger a load for that row's handle.
- **expand-collapse-reported-to-source**: Expanding or collapsing a row by user action (not by the pane's own automatic expansion or a redraw) MUST report the corresponding expand/collapse to the data source.

### Tree-data change notifications

- **targeted-change-reloads-one-branch**: A tree-data change reported for a specific handle whose row is currently in the table MUST reload only that branch.
- **untargeted-change-reloads-loaded-branches**: A tree-data change reported with no handle, or with a handle not currently in the table, MUST re-ask every branch this pane has already loaded.
- **untargeted-change-reasks-root-when-empty**: If the table holds no loaded branches at all when an untargeted change arrives, the root MUST also be asked.
- **change-after-teardown-ignored**: A tree-data change reported after the pane has begun teardown MUST be ignored.

### Row rendering

- **row-view-recycled**: Rows MUST be drawn with a recycled row view, not a freshly built view hierarchy per row.
- **row-icon-from-symbol-name**: A row whose `symbolName` resolves to a system symbol image MUST show that image tinted the `.secondaryText` semantic color; a row with no symbol name, or one that fails to resolve, MUST hide the icon entirely.
- **row-label-shows-item-label**: A row's label MUST show `item.label`, truncating with a tail ellipsis when it does not fit.
- **row-caption-from-description**: A row's caption MUST show `item.description` when it is non-nil and non-empty, and MUST be hidden otherwise.
- **row-tooltip-fallback**: A row's tooltip MUST be `item.tooltip` when present, and MUST fall back to `item.label` otherwise.
- **row-background-recycled**: The row's background view MUST also be a recycled view rather than a freshly built one per row.

### Activation

- **double-click-activates**: Double-clicking a row MUST activate that row's item through the data source.
- **return-key-activates-selection**: Pressing Return or the numeric-keypad Enter while a row is selected MUST activate the selected row's item.
- **alternate-return-path-activates-selection**: When the platform delivers Return through an alternate text-editing-command path instead of a raw key event, the pane MUST activate the selected row's item — the same outcome as `return-key-activates-selection`, reached through the other path the platform can take.
- **other-keys-pass-through**: A key event that is neither Return nor keypad Enter MUST be left unhandled by the pane (passed through to the platform's default handling) rather than consumed.

### Pane title & teardown (tree component)

- **outline-pane-title-source-or-fallback**: The tree component's pane title MUST be the data source's title when it is non-nil and non-empty, and MUST fall back to the contributed view's manifest name otherwise.
- **outline-teardown-idempotent**: Teardown MUST have no additional effect when invoked more than once on the same instance.
- **outline-teardown-releases-callbacks-only-if-owner**: Teardown MUST clear the tree-data-change, chrome-change and provider-replacement callbacks on the data source, and MUST report visibility `false`, only when this pane is still that data source's recorded callback owner at teardown time; a superseded pane's teardown MUST NOT touch a data source it no longer owns.

## Appearance

- **Corner radius**: None anywhere in this component.
- **Padding**: Message banner inset 16pt from the container's leading/trailing edges and 8pt from its top edge (half of the 16pt message inset); the tree sits 8pt below the banner when shown, flush with the container's top edge otherwise. Inside a row, the icon/label/caption stack is inset 2pt from the row's leading edge and at most 6pt from its trailing edge, with 4pt spacing between the three pieces.
- **Font**: Not set as literal point sizes in this component. Message banner: tertiary-text role at caption text scale. Row label: primary-text role at body text scale. Row caption: tertiary-text role at caption text scale. All are theme-resolved semantic fonts, not literal sizes.
- **Background**: The container view's fill and the tree's own background both track the `.surface` semantic color; the tree's grid color tracks the `.divider` semantic color.
- **Foreground/Text**: Row icon tinted `.secondaryText`; row label `.primaryText`; row caption and message banner `.tertiaryText`. All theme-resolved semantic tokens, never literal color values.
- **Border**: None drawn anywhere in this component.
- **Shadow**: None drawn anywhere in this component.
- **Min/Max size**: The container view's initial frame is 300×200 points — only the layout system's starting point, not an enforced minimum or maximum. No other size constraint is set by this component; the pane's actual bounds are governed by whatever hosts it, which is out of scope here.

## States

| State | Appearance change |
|-------|------------------|
| Default | — |
| Pressed | Not applicable: this component draws no custom pressed appearance for a row; clicking selects it via the tree's own default selection chrome. |
| Disabled | Not applicable: neither pane nor row has a disabled representation in this component; whether an activated item does anything is entirely the extension's command wiring, not this pane's concern. |
| Focused | Not applicable as a visual state drawn by this component: keyboard focus ring and focus chrome are inherited, undrawn platform default behavior. |
| Loading | Not applicable as a whole-pane state: there is no spinner or full-pane loading indicator anywhere in this component; loading is per-branch — see "Branch unloaded" and "Branch timed out" below. |
| Placeholder | Shown until a data source resolves; drawn by the placeholder component, out of this recipe's scope. |
| Tree shown | The placeholder is replaced by the tree once a data source resolves (`first-resolve-shows-outline`). |
| Message banner visible | Shown, wrapped, above the tree whenever the data source's message is non-empty. |
| Message banner hidden | Hidden, tree pinned to the container's top edge, whenever the data source's message is empty. |
| Branch unloaded | Drawn with zero rows while a load is in flight or has not yet been triggered; its own disclosure triangle still shows if `collapsibleState` is not `.none` (`disclosure-driven-by-declared-state`). |
| Branch timed out | Drawn with zero rows after `childrenBudget` elapses with no answer; stays re-askable rather than being recorded as permanently empty. |
| Row selected | Standard tree selection highlighting, not drawn by this component; reported to the data source's selection-changed callback unless the change was the pane's own redraw sync. |
| Row expanded/collapsed | Standard tree disclosure, not drawn by this component; reported via expand/collapse callbacks unless the change was the pane's own auto-expand or redraw sync. |

## Accessibility

- **Role/trait**: The tree is a plain tree control (the platform's own outline/row accessibility roles) carrying the identifier `"<accessibilityPrefix>.tree"`; the message banner is a plain text label carrying `"<accessibilityPrefix>.message"`. Neither identifier is an accessibility role or label — it only sets a UI-test identifier, and this component overrides no accessibility role anywhere.
- **Label requirements**: A row's label (`item.label`) and caption (`item.description`) are plain text values, which the platform's default accessibility exposes as the row's accessible text. The icon is given no separate accessibility description, relying on the adjacent label text to name the row rather than describing the icon separately. The message banner's accessible text is its own text value.
- **Announce state changes**: Not implemented. Redrawing a branch, toggling the message banner, and the placeholder-to-tree swap post no explicit accessibility notification (e.g. a layout-changed event or an announcement) anywhere in this component; a screen-reader user gets no non-visual cue, beyond whatever the platform's own row-reload mechanism announces on its own, that a branch's children arrived, that the message banner appeared or disappeared, or that the pane swapped from the placeholder to a live tree.
- **Minimum tap target**: Not overridden in this component; row height is a fixed 22pt (`outline-row-height`) with no accessibility-driven exception. A pointer-driven platform's guidance does not carry the touch-target minimum that applies on touch platforms, and this component sets no explicit minimum of its own.

## Conformance Test Vectors

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| etvc-001 | contributed-view-retained | Construct the pane with a contributed view named "Files" and display name "Acme" | The placeholder shows "Files"/"Acme"; the pane title before any resolution is "Files" |
| etvc-002 | explicit-construction-only | Attempt construction through the generic archive/coder-based path | Fails fast (the process traps rather than returning a usable instance) |
| etvc-003 | initial-placeholder-shown | Load the pane's view before resolution has delivered a data source | Displayed content is the placeholder |
| etvc-004 | container-background-tracks-theme | Switch the active theme after the pane loads | The container's background color updates to the new theme's `.surface` color |
| etvc-005 | resolve-requested-after-view-loads | Instrument view construction and the view-ready lifecycle point | Resolution is requested only after the view has finished being constructed |
| etvc-006 | first-resolve-shows-outline | Deliver a data source through resolution | Displayed content becomes a tree bound to that data source |
| etvc-007 | resolve-after-discard-ignored, outer-teardown-marks-discarding | Begin teardown, then deliver a resolution | Displayed content is unchanged; no tree is created — the discard flag teardown sets is what suppresses it |
| etvc-008 | duplicate-resolve-ignored | Deliver two resolutions, back to back, with two different data sources | Only the first data source's tree is shown; the second delivery has no effect |
| etvc-009 | provider-replacement-swaps-source | With a tree shown for source A, signal that A has been replaced by B | Displayed content becomes a new tree bound to B; B's provider-replacement signal is wired afterward |
| etvc-010 | swap-tears-down-previous-content | Swap from a placeholder that supports teardown to a tree | Teardown is invoked on the placeholder before it is removed from view |
| etvc-011 | swap-pins-new-content-to-edges | Swap in a new child | The child's view has four active constraints pinning it to the container's leading/trailing/top/bottom |
| etvc-012 | swap-notifies-title-change | Swap in a new child while the title-change notification is set | The notification fires exactly once as part of the swap |
| etvc-013 | outer-pane-title-delegates | Read the pane title while the placeholder is shown, then again once the tree (title "Explorer") is shown | First read is the contributed view's name; second read is "Explorer" |
| etvc-015 | outer-teardown-forwards-to-content | Content is a tree that supports teardown; invoke teardown on the outer pane | The tree's own teardown runs |
| etvc-016 | outline-single-column-no-header | Load the tree's view | The tree has exactly one column; its header is hidden |
| etvc-017 | outline-row-height | Read the tree's row height | Equals 22 |
| etvc-018 | outline-indentation-per-level | Read the tree's indentation per level | Equals 14 |
| etvc-019 | outline-inset-style | Read the tree's visual style | Equals the inset style |
| etvc-020 | outline-allows-empty-selection | Read whether the tree allows an empty selection | `true` |
| etvc-021 | message-banner-shown-conditionally | Set the data source's message to "No results", then clear it | Banner visible and tree offset below it in the first case; banner hidden and tree flush to the top in the second |
| etvc-022 | message-banner-inset | Banner shown | Its leading/trailing constraints use a 16pt constant; its top constraint uses 8pt; the tree's top-offset constraint uses 8pt from the banner's bottom |
| etvc-023 | message-banner-wraps | Set the data source's message to a string longer than the pane's width | The label renders on multiple lines rather than truncating to one |
| etvc-024 | accessibility-ids-assigned | The contributed view's registry id is "acme.files" | The tree's accessibility identifier is "acme.files.tree"; the message label's is "acme.files.message" |
| etvc-025 | initial-load-when-view-is-ready | Load the tree's view with a data source whose message is "Loading…" | A root children ask is issued; the banner shows "Loading…" immediately |
| etvc-026 | callback-ownership-transfers-to-latest-pane | Build a second tree component for the same data source | The data source's tree-data-change/chrome-change callbacks now point at the second tree component's handlers |
| etvc-027 | visibility-forwarded-only-by-owner | Pane B has superseded pane A per etvc-026; report pane A as having become visible | The data source's visibility callback is NOT invoked by pane A |
| etvc-028 | message-label-wrap-width-tracks-container | Resize the container to 250pt wide | The message label's preferred wrap width becomes 218 (250 − 32) |
| etvc-029 | multiple-selection-mirrors-source | The data source allows multiple selection; apply chrome | The tree allows multiple selection |
| etvc-030 | children-answered-from-cache | Ask for the children of an item whose branch is already cached | Returns the cached rows synchronously; no new ask is issued |
| etvc-031 | uncached-branch-triggers-load-and-empty-answer | Ask for the children of a branch never asked before | Returns an empty list immediately; a load for that handle begins |
| etvc-032 | load-skipped-while-in-flight | Ask for the same branch's children twice before the first ask's provider call returns | Exactly one children request reaches the data source |
| etvc-033 | load-marked-stale-when-busy | While a load for handle H is in flight, trigger a tree-data change for H | Once the in-flight load completes and adopts, a second load for H is issued automatically |
| etvc-034 | load-skipped-for-unreachable-handle | Request a load for a handle whose row was already forgotten | No children request reaches the data source |
| etvc-035 | disclosure-driven-by-declared-state | Item has `collapsibleState == .collapsed` and its load answers zero children | The row still reports itself expandable |
| etvc-036 | load-bounded-by-budget | Set `childrenBudget` to a short, injected value; provider never answers | No rows are adopted for that branch (see etvc-038's later, successful ask); the ask does not wait indefinitely |
| etvc-037 | timeout-logged | Trigger a timeout as in etvc-036 | An error is logged: "A tree provider did not answer getChildren in time; the branch stays unread" |
| etvc-038 | timeout-leaves-branch-askable | After a timeout on handle H, request H's children again | A fresh load for H is issued and can succeed |
| etvc-039 | late-answer-discarded-when-defunct | Begin teardown while a load is in flight, then let the provider answer | The answer is not adopted; the tree is not reloaded |
| etvc-040 | successful-load-updates-table-and-redraws | Handle H moves from parent P1 (already drawn) to parent P2 in a refresh | Both P1 and P2's branches redraw; H's row object is the same instance as before |
| etvc-041 | duplicate-child-id-deduplicated | A `getChildren` answer for parent P lists id "x" twice | P's children contain exactly one row for "x" |
| etvc-042 | moved-row-preserves-identity | P2's answer (claiming H) arrives before P1's answer (which no longer lists H), within the same settling refresh | H keeps the same row object and its loaded subtree under P2 |
| etvc-043 | orphan-return-by-same-parent-is-new-row | Parent P drops id "x" in refresh 1, then names "x" again in a later, separate refresh 2 | "x" is a new row in refresh 2; any subtree it had before refresh 1 is gone, and its default expansion (if `.expanded`) is re-applied |
| etvc-044 | prune-orphans-after-settling | Parent P drops id "x" and nothing claims it; wait for all in-flight loads to finish | Row "x" and its descendants are forgotten from the table |
| etvc-045 | forget-is-cycle-safe | An extension declares item "a" as its own descendant (a cycle) and it is later forgotten | Forgetting completes without hanging or crashing |
| etvc-046 | redraw-preserves-selection | Row H is selected; a redraw of H's parent branch runs and H is still present afterward | H remains selected after the redraw |
| etvc-047 | redraw-narrowing-selection-notifies-source | Rows H1 and H2 are selected; a redraw drops H2 | The data source's selection-changed callback is called with only H1's item |
| etvc-048 | redraw-suppresses-source-notifications | Trigger a reload as part of a redraw | The data source's selection/expand/collapse callbacks are not called for the notifications the reload itself generates |
| etvc-049 | default-expansion-applied-once | Row H has `collapsibleState == .expanded`; it is drawn, the user collapses it, then a refresh redraws it again | H auto-expands the first time only; it stays collapsed after the user's action and the later refresh |
| etvc-050 | expansion-request-triggers-load | User expands a row whose children were never loaded | A load for that row's handle begins |
| etvc-051 | expand-collapse-reported-to-source | User expands a row (not via auto-expand or redraw sync) | The data source's expand callback is called with that row's item |
| etvc-052 | targeted-change-reloads-one-branch | Data source fires a tree-data change for "h1" where h1 is a loaded row | Only h1's branch reloads |
| etvc-053 | untargeted-change-reloads-loaded-branches | Data source fires an untargeted tree-data change with branches "" and "h1" already loaded | Both "" and "h1" are re-asked |
| etvc-054 | untargeted-change-reasks-root-when-empty | Data source fires an untargeted tree-data change before the root has ever loaded | The root ("") is asked |
| etvc-055 | change-after-teardown-ignored | Begin teardown, then fire an untargeted tree-data change | No load is triggered |
| etvc-056 | row-view-recycled | Draw one screenful of rows, then scroll through 500 rows | Each newly-scrolled-in row reuses a previously-created row view instance rather than constructing a fresh view hierarchy |
| etvc-057 | row-icon-from-symbol-name | Item with `symbolName == "folder"`, and item with `symbolName == nil` | First row shows a tinted `.secondaryText` icon; second row's icon is hidden |
| etvc-058 | row-label-shows-item-label | Item label longer than the column width | Label truncates with a tail ellipsis |
| etvc-059 | row-caption-from-description | Item with `description == "3 items"`, and item with `description == nil` | First row's caption shows "3 items"; second row's caption is hidden |
| etvc-060 | row-tooltip-fallback | Item with `tooltip == nil`, `label == "README.md"` | The row's tooltip is "README.md" |
| etvc-061 | row-background-recycled | Draw one screenful of rows, then scroll through 500 rows | Each newly-scrolled-in row reuses a previously-created background view instance rather than constructing a fresh one |
| etvc-062 | double-click-activates | Double-click a row | The data source's activation callback is called with that row's item |
| etvc-063 | return-key-activates-selection | A row is selected; press Return | The data source's activation callback is called with the selected row's item |
| etvc-064 | other-keys-pass-through | Press a key that is neither Return nor keypad Enter (e.g. Space) | The key event passes through unhandled; no activation occurs |
| etvc-065 | outline-pane-title-source-or-fallback | The data source's title is empty, then "Explorer" | First read of the pane title is the manifest's fallback name; second read is "Explorer" |
| etvc-066 | outline-teardown-idempotent | Invoke teardown twice | The second call has no additional effect (e.g. the visibility-false notification is not sent twice) |
| etvc-067 | outline-teardown-releases-callbacks-only-if-owner | Tree component B has superseded tree component A for the same data source (etvc-026); invoke teardown on A | The data source's callbacks (still pointing at B) are left untouched; the visibility callback is not called by A |
| etvc-068 | alternate-return-path-activates-selection | A row is selected; deliver Return through the alternate text-editing-command path directly | The data source's activation callback is called with the selected row's item |

## Edge Cases

- **Null/empty input**: A data source title that is empty falls back to the manifest name (`outline-pane-title-source-or-fallback`); a data source message that is empty hides the banner (`message-banner-shown-conditionally`); an item's icon reference that is absent hides the icon, and an item's description that is absent or empty hides the caption (`row-icon-from-symbol-name`, `row-caption-from-description`); an empty children answer draws a branch with zero rows — and, per `disclosure-driven-by-declared-state`, a row can still show a disclosure triangle that opens onto that empty list if the extension declared it `.expanded`/`.collapsed`, a quirk this recipe documents rather than smooths over (see Design Decisions). The tree data source's own children method has no error channel: per that protocol's own documentation, a thrown error, a rejected thenable, and a genuinely empty answer are all indistinguishable empty results by the time they reach this component — that conversion happens in the (out-of-scope) adaptor that implements the protocol, not here.
- **Boundary values**: The platform's tree control asks for a child count and then for each child by index in separate calls, and an answer can land from the extension in between, shrinking the list; an out-of-range index is answered with a throwaway placeholder row rather than crashing, and the reload the new answer triggers replaces it. The children budget's default is 30 seconds; a load that completes at exactly the budget is undefined behavior — a genuine race between the operation and the budget-enforcing wait, and this recipe does not pick a winner. Both the adopted-answer path and the timeout path are source-correct outcomes for that instant. The in-flight-load tracking holds at most one entry per handle, so loads for different handles proceed fully concurrently; only same-handle re-entrancy is serialized.
- **Concurrent access**: All this component's mutable state (the in-flight and stale-handle tracking, the selection/expansion sync flags, the row table, callback ownership) is confined to a single thread and read/written only there. The one boundary crossing is the asynchronous wait that enforces the budget on a children ask; the data source itself is read only within that ask, on the thread that owns it, because the data source's own state may not be safe to share across threads, and only a plain list of items (or nothing, on timeout) crosses back into the completion.
- **Error states**: A provider that never answers a children request surfaces only as a logged error (`timeout-logged`) — there is no inline error banner, no thrown error, and no user-facing message anywhere in this component for that case; the recipe describes that as-is. A resolution that arrives after teardown, or a second resolution once a tree is already shown, is silently ignored with no error surfaced (`resolve-after-discard-ignored`, `duplicate-resolve-ignored`).
- **Offline or disconnected state**: Not applicable. This component makes no network requests of its own; children, title, message and activation all flow through the in-process tree data source interface. Whatever the extension's own provider implementation does over a network, if anything, is outside this component's scope.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `view` | contributed view | required at init | The extension's manifest-declared tree view this pane hosts; drives the placeholder, the pane title's fallback, and the tree's accessibility-id prefix (registry id). |
| `extensionDisplayName` | string | required at init | Shown by the placeholder while no provider has registered; not consulted again once a tree is shown. |
| `resolve` | callback | required at init | Invoked exactly once, once the view is ready, to supply the data source. It is never invoked again; a later replacement arrives only through the provider-replacement signal on that data source (`provider-replacement-swaps-source`). |
| `childrenBudget` | duration (seconds) | `30` | How long a single `getChildren` ask may take before its branch is treated as unanswered; settable, intended for tests. |

## Deep Linking

Not applicable: no URL scheme, universal link, or platform continuation-activity handling appears anywhere in this component. The pane is built entirely from an in-process contributed view / resolution callback pair handed down by whatever hosts it, which is out of this recipe's scope.

## Localization

Not applicable: every string this component displays — the message banner, the row label, the row caption, the row tooltip, and the resolved pane title — comes from the extension's own data (the data source's message and title; the tree item's label, description and tooltip; the contributed view's name), not from an app string catalog, so this component owns no localization keys of its own. The one literal string in this component (`"A tree provider did not answer getChildren in time; the branch stays unread"`) is a diagnostic log message, not user-facing text — see Logging.

## Accessibility Options

Document which accessibility display options this component responds to:

| Option | Behavior |
|--------|----------|
| Reduce Motion | Not applicable: every visual transition in this component (the placeholder-to-tree swap, a reload, the message banner's show/hide) is an immediate view/constraint change; no animation context or animated transition appears anywhere in this component. |
| Increase Contrast | Not observed in this component: every color is a semantic token resolved by the theme system (`.surface`, `.primaryText`, `.secondaryText`, `.tertiaryText`, `.divider`); any contrast adaptation belongs to that theme system, out of this recipe's scope. |
| Differentiate Without Color | Not applicable: this component draws no state — selected, expanded, timed-out, or otherwise — using color as the sole distinguishing cue. Text roles differ in weight and size (body vs. caption text scale), not color alone, and selection/expansion are drawn by the tree's own default chrome rather than a custom color-only cue defined in this component. |

## Feature Flags

Not applicable: no feature-flag or remote-config lookup of any kind appears anywhere in this component.

## Analytics

Not applicable: no analytics event is emitted anywhere in this component.

## Privacy

- **Data collected**: This component displays whatever tree item fields (label, description, tooltip, symbol name) and tree chrome (title, message) the extension's own data source supplies, and forwards the user's selection, expansion, and activation back to that same data source. It introduces no data collection of its own beyond that pass-through.
- **Storage**: None persistent. The row cache and all loading/stale-handle bookkeeping are in-memory only and are discarded with the pane.
- **Transmission**: None directly. No network call appears anywhere in this component; whatever the extension's own provider implementation does over a network, if anything, is outside this recipe's scope.
- **Retention**: Tied to the pane's lifetime — the in-memory table and bookkeeping are released when the pane (or its tree component) is torn down; nothing here persists across launches.

## Logging

Subsystem: the app's own bundle identifier | Category: this component's tree-rendering piece

| Event | Level | Message |
|-------|-------|---------|
| A children load exceeds `childrenBudget` | error | `A tree provider did not answer getChildren in time; the branch stays unread` |

## Platform Notes

- **SwiftUI**: Replace both classes with a `List` driven by `OutlineGroup` (or `List(_:children:)`) over an `@Observable` view model that exposes the same lazy, cached `children(of:)` shape — a `Task`-backed fetch per expanded node, answered from a dictionary cache the way `ExtensionTreeRowTable` is here — plus `@State` sets for the current selection and the auto-expanded handles (mirroring `autoExpandedHandles`, applied only once per handle). The placeholder/tree swap becomes a simple `if`/`switch` over a `@State` "resolved data source" value instead of a `PaneContentTeardown`-driven `NSViewController` swap.
- **Compose**: Compose has no built-in expandable-tree widget, so build one over `LazyColumn` with a manually flattened row list (visible rows recomputed from an expanded-id `Set` and an in-memory row cache, mirroring `ExtensionTreeRowTable`), applying `Modifier.padding(start = level * 14.dp)` for indentation (matching the source's 14pt `indentationPerLevel`). Model the async `getChildren` fetch as a `ViewModel`-scoped coroutine with a `withTimeoutOrNull(30_000)` wrapping the call, mirroring `withWallClockBudget`'s bounded wait and its "leave unread, not empty" outcome on timeout.
- **React/Web**: A component with `role="tree"`/`role="treeitem"` (or a virtualized tree library) whose expand handler lazily fetches and caches a node's children exactly like `children(of:)`/`loadChildren(of:)` here — return nothing cached yet, kick off the fetch, and re-render on arrival. Guard the same-handle-in-flight case with a `Set` of pending node ids (mirroring `loadingHandles`), and wrap the fetch in a client-side timeout (e.g. `Promise.race` with a 30-second timer) that leaves the node "not yet loaded" rather than "loaded empty" on expiry, matching `timeout-leaves-branch-askable`. Handle `Enter`/double-click activation with a single `keydown` handler scoped to the focused row, matching the source's Return-or-keypad-Enter check.
- **AppKit/UIKit**: This recipe's own platform. `ExtensionTreeViewController.swift` is macOS/AppKit-only (`NSViewController`, `NSOutlineView`, `NSScrollView`, `NSTableRowView`, `NSImageView`); nothing in this file targets UIKit/iOS. The pane supports construction only through its designated initializer — `init(coder:)` is unimplemented and calls `fatalError`, matching `explicit-construction-only`. `resolve` is invoked from `viewDidLoad()`, never `loadView()` (`resolve-requested-after-view-loads`), and the initial children ask fires from the same `viewDidLoad()` hook (`initial-load-when-view-is-ready`); visibility is reported from `viewDidAppear`/`viewDidDisappear`. The tree itself is `NSOutlineView` with `.style = .inset`; `accessibilityID` only sets `accessibilityIdentifier`, a UI-test hook, never an AX role; row/caption/tooltip labels are plain `NSTextField`s whose default accessibility exposes `stringValue`; the row icon's `NSImage` gets `accessibilityDescription: nil`. Return is delivered either as a raw `keyDown` with key code 36, or as numeric-keypad Enter with key code 76, or — when AppKit routes it as the text-editing command instead — as a call to `insertNewline(_:)`; either path activates the selection (`return-key-activates-selection`, `alternate-return-path-activates-selection`), and any other key falls through to `super.keyDown(_:)` unconsumed (`other-keys-pass-through`). `NSOutlineView` asks `numberOfChildrenOfItem` and `child(index:ofItem:)` in separate calls; an out-of-range index answered mid-flight gets a throwaway `ExtensionTreeRow.placeholder()` row rather than crashing. Both `ExtensionTreeViewController` and `ExtensionTreeOutlineViewController` are `@MainActor`-isolated, and all mutable state — `loadingHandles`, `staleHandles`, `isSyncingSelection`, `isSyncingExpansion`, the row table, `callbackOwners` — lives only on the main actor; the one crossing is the `Task` that awaits `askChildren(of:)` under `withWallClockBudget`, since `any ExtensionTreeDataSource` is not `Sendable` and only a plain `[ContributedTreeItem]` (or nothing, on timeout) crosses back into the closure. Constraints use Auto Layout (the tree's top-offset constraint is named `treeBelowMessage`); banner/row text uses `ThemedLabel(role:textRole:)` resolving `SemanticPalette.font(_:)`. No `NSAccessibility` notification (e.g. `.layoutChanged`) is posted around a redraw, banner toggle, or the placeholder-to-tree swap, and no `NSAnimationContext` wraps any of them — both `reloadData()`/`reloadItem` and the show/hide are immediate. Rows and their backgrounds are recycled through `outlineView(_:viewFor:item:)`/`makeView(withIdentifier: ExtensionTreeRowView.reuseIdentifier, owner:)` and `outlineView(_:rowViewForItem:)`/`makeView(withIdentifier: Self.backgroundRowIdentifier, owner:)` respectively (`row-view-recycled`, `row-background-recycled`). Logging uses category `ExtensionTreeOutlineViewController`. A UIKit port has no direct `NSOutlineView` analog; the closest fit is a `UICollectionView` configured with `UICollectionViewCompositionalLayout.list(using:)` and `NSDiffableDataSourceSectionSnapshot`'s hierarchical/expandable-item support (available from iOS 14), driven by the same lazy-cache-then-reload pattern, with row activation mapped to `collectionView(_:didSelectItemAt:)` since UIKit has no double-click and no hardware-Return-by-default on touch devices.
- **WinUI 3**: Recreate the outline as a `TreeView` (`Microsoft.UI.Xaml.Controls.TreeView`) bound to `TreeViewNode`s built lazily: populate a node's `Children` inside the `TreeView.Expanding` event, mirroring `outlineViewItemWillExpand`/`loadChildren(of:)`, and leave a node's children empty (not marked loaded) if the async call exceeds a 30-second `CancellationTokenSource` timer, mirroring `withWallClockBudget` and `timeout-leaves-branch-askable`. Use `TreeView.ItemInvoked` for activation, since it fires on both double-click and Enter, matching this file's combined `rowDoubleClicked`/`insertNewline`/`keyDown` handling in one place. Template each `TreeViewItem` with a horizontal `StackPanel` (`Spacing="4"`) containing a `FontIcon` (`Visibility="Collapsed"` when the item declares no icon, mirroring the hidden `NSImageView`), a `TextBlock` with `TextTrimming="CharacterEllipsis"` for the label, and a second, dimmer `TextBlock` (bound to a `TertiaryTextBrush` resource, `Visibility="Collapsed"` when the description is empty) for the caption — the same three-piece, alignment-preserving row this file builds by hiding rather than omitting subviews. Show the message banner as a `TextBlock` (or `InfoBar`) above the `TreeView`, bound to `Visibility` off whether the data source's message is null, with the `TreeView`'s own top margin swapping between 0 and the banner's height plus 8px, mirroring `treeAtTop`/`treeBelowMessage`. Bind `AutomationProperties.AutomationId` on the `TreeView` and the banner to the same `"<accessibilityPrefix>.tree"` / `"<accessibilityPrefix>.message"` scheme via a converter. There is no built-in WinUI notion of "one pane owns this data source's callbacks"; reproduce `callbackOwners`/`callbackToken` as an explicit ownership token if more than one `TreeView` can ever bind to the same extension-provided source.

## Reference Implementations

| Platform | Path |
|----------|------|
| apple | `packages/apple/AgenticToolkit/macOS/Features/Extensions/Tree/ExtensionTreeViewController.swift` |

## Design Decisions

**Decision** (AppKit/UIKit): `resolve` is invoked from `viewDidLoad()` rather than `loadView()`.
**Rationale**: An already-awake extension answers synchronously; swapping displayed content while `view` is still being assigned inside `loadView()` would have the view controller ask for its own view before it exists.
**Approved**: pending

**Decision**: A branch's children are always answered from a cache, never by blocking the tree on the provider, and a `getChildren` ask is bounded by a 30-second wall-clock budget whose expiry leaves the branch unread rather than adopted as empty.
**Rationale**: `TreeDataProvider.getChildren` is documented as commonly asynchronous, and `NSOutlineView`'s data source protocol has no way to await an answer. An unbounded wait would make a provider that never answers leave the branch not just slow but permanently unaskable — the budget stops the wait without recording a wrong (empty) answer in its place.
**Approved**: pending

**Decision**: Installing this pane's callbacks on a data source supersedes whichever pane held them before ("one pane per view id"), and a superseded pane's teardown only clears wiring it can prove it still owns (`callbackOwners`/`callbackToken`).
**Rationale**: A data source has exactly one tree-data-change/chrome-change slot; a second pane for the same contributed view (e.g. a second window) must take live updates over, and the older, now-inert pane's later teardown must not silently disable the newer, visible one. Closures can't be compared for identity, so ownership is tracked explicitly instead.
**Approved**: pending

**Decision**: A row dropped by its parent during a refresh is held as an orphan rather than forgotten immediately, and is only forgotten once every in-flight load for that refresh has settled.
**Rationale**: Refresh answers can arrive in any order; an item that genuinely moved from one open branch to another would otherwise be destroyed by whichever branch's answer happens to drop it first, discarding its whole loaded subtree and collapsing it when the claiming branch's answer arrives moments later. Deferring the forget makes both arrival orders produce the same result.
**Approved**: pending

**Decision**: A row's disclosure triangle is driven solely by the extension's declared `collapsibleState`, never by whether a load has actually found any children.
**Rationale**: This mirrors the source's own upstream contract (`TreeItemCollapsibleState`) rather than inferring expandability from data, which means an item declared `.expanded`/`.collapsed` that turns out to have zero real children still shows a disclosure triangle opening onto an empty list — documented here as a known consequence of following the declared contract, not smoothed into "expandable only when non-empty."
**Approved**: pending

**Decision** (AppKit/UIKit): Rows and their background views are drawn through recycled, pooled view instances rather than a fresh view hierarchy per row.
**Rationale**: The source's own comment notes this is what every other outline/table in the framework already does; a tree is the shape where skipping it costs the most, since a branch with a few hundred children previously rebuilt a few hundred view hierarchies on every scroll pass.
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [keyboard-navigable](agenticdevelopercookbook://compliance/accessibility#keyboard-navigable) | passed | Accessibility |
| [native-controls-preference](agenticdevelopercookbook://compliance/platform-compliance#native-controls-preference) | passed | Platform Compliance |
| [no-pii-in-logs](agenticdevelopercookbook://compliance/privacy-and-data#no-pii-in-logs) | passed | Privacy and Data |

`outline-allows-empty-selection`/`return-key-activates-selection`/`alternate-return-path-activates-selection`, this file's exclusive use of `ThemedOutlineView`/`NSOutlineView`/`ThemedLabel`/`NSTableRowView`, and the absence of any logged `ContributedTreeItem` field or user string in `timeout-logged`'s one log line ground the `passed` rows. The missing state-change announcements described under **Announce state changes** have no dedicated check in the catalog.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.0 | 2026-09-23 | Mike Fullerton | Initial creation |
| 1.1.0 | 2026-09-23 | Mike Fullerton | Lint pass: moved the cookbook guideline URI from `references` to `related`, trimmed `tags` to 5 by dropping the `platforms`-duplicate, bolded Design Decisions labels, replaced the dangling "(Rule 15)" citation, resolved `live-region-announcements` to `failed` and dropped the inapplicable `reduce-motion-support` row with a grounding sentence, corrected the `resolve`/`onProviderReplaced` Configuration description, restated the at-budget race as undefined, merged etvc-014 into etvc-007, rewrote etvc-036/etvc-056/etvc-061 as observable checks, and added `insert-newline-activates-selection` with etvc-068 for the WinUI note's `insertNewline` reference; removed Compliance rows for checks absent from the cookbook catalog |
| 1.1.1 | 2026-09-24 | Mike Fullerton | Phase 6 lint: re-audited open-question markers against the marker rules; kept markers are one-line named bullets. |
| 1.1.2 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.2.0 | 2026-09-27 | Mike Fullerton | Platform-neutral description; platform specifics in Platform Notes; moved to workspace/extensions/vscode-api/tree-views/. |
