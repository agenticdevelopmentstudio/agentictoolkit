---
id: 9f84dd73-abbf-4ad5-be6e-f3fb04f941c3
title: useEdgeLock
domain: agentictoolkit://cookbook/status-web/hooks/use-edge-lock
type: ingredient
version: 1.0.1
status: review
language: en
created: '2026-09-24'
modified: '2026-09-25'
author: Mike Fullerton
copyright: 2026 Mike Fullerton
license: MIT
summary: React hook that locks a scrolling list to its top or bottom edge through
  container resizes and follows new items within 24px of that edge.
platforms:
- typescript
- web
tags: []
depends-on: []
related:
- agentictoolkit://cookbook/status-web/hooks/use-activity-history
references: []
approved-by: ''
approved-date: ''
---

# useEdgeLock

## Overview

`useEdgeLock` is a client-only React hook (`"use client"`) that keeps a scrolling list locked to one edge of its scroll container. Its doc comment names the use case: "a list that sits above a details pane", where whatever touches the locked edge rides that edge through every geometry change.

The hook handles two concerns, and both read and write one `Tracked` record:

- **Container resizes** (split-divider drags, collapse/expand, window resizes). The viewport's distance from the locked edge (`dist`) is kept exactly the same, every time, whether the list is resting on the edge or scrolled away from it.
- **Item changes** (`newestKey` / `count`). While the viewport is within `PIN_SLACK_PX` (24 px) of the locked edge, the list follows new content. A reader scrolled further away than that is left where they are.

The hook returns nothing. It works only through side effects on the element held in `ref`. In the repo, only its test file (`use-edge-lock.test.ts`) imports it. The doc comment mentions ActivityPanel's list pane as the model for the CSS contract.

## Behavioral Requirements

### Signature and data shape

- **signature**: The hook MUST be callable as `useEdgeLock(ref, edge, newestKey, count = 0)`. `ref` is a `RefObject<HTMLElement | null>`, `edge` is `"top" | "bottom"`, `newestKey` is `string | null`, and `count` is a number that defaults to `0`. It MUST return `void`.
- **tracked-record**: The hook MUST keep one mutable `Tracked` record per hook instance with the fields `el` (`HTMLElement | null`), `scrollHeight`, `clientHeight` and `dist`. The record MUST start as `{ el: null, scrollHeight: 0, clientHeight: 0, dist: 0 }`.
- **dist-bottom**: When `edge` is `"bottom"`, `measure` MUST compute `dist` as `scrollHeight - clientHeight - scrollTop`.
- **dist-top**: When `edge` is `"top"`, `measure` MUST compute `dist` as `scrollTop`.
- **pin-bottom**: When `edge` is `"bottom"`, `pinToEdge` MUST set `scrollTop` to `Math.max(0, scrollHeight - clientHeight)`.
- **pin-top**: When `edge` is `"top"`, `pinToEdge` MUST set `scrollTop` to `0`.
- **no-rendered-output**: The hook MUST NOT hold React state or cause re-renders. All of its bookkeeping lives in refs (`tracked`, `detach`).

### Attaching to the scroll element

- **attach-per-render-check**: The attach effect MUST run after every render (it has no dependency array).
- **attach-identity-guard**: The attach effect MUST return early without re-wiring when `ref.current` is the element already stored in `tracked.current.el` and a `detach` function exists.
- **attach-replace**: When `ref.current` differs from the tracked element, the attach effect MUST first call the previous `detach` function (if any), which removes the old scroll listener and disconnects the old `ResizeObserver`.
- **attach-null-element**: When `ref.current` is `null`, the attach effect MUST reset `tracked` to `{ el: null, scrollHeight: 0, clientHeight: 0, dist: 0 }` and attach nothing.
- **scroll-listener-passive**: The hook MUST add a `scroll` event listener to the element with `{ passive: true }`.
- **fresh-element-pin**: Once the listeners are attached to a new element, the hook MUST pin that element to its edge with `pinToEdge` and then set `tracked` to `measure(el, edge)`. This rests a fresh list on its edge and throws away any distance measured on a previous node.
- **unmount-teardown**: A separate effect with an empty dependency array MUST call `detach` exactly once, on unmount, and clear it. The attach effect itself returns no cleanup, so the hook never tears down while it is mounted.

### Scroll tracking

- **pure-scroll-records-dist**: When a `scroll` event fires and the element's `scrollHeight` and `clientHeight` both equal the tracked values, the hook MUST replace `tracked` with a fresh `measure(el, edge)`, which records the user's new `dist`.
- **geometry-changed-scroll-keeps-dist**: When a `scroll` event fires and either `scrollHeight` or `clientHeight` differs from the tracked values, the hook MUST adopt the new `scrollHeight` and `clientHeight` but keep the previously tracked `dist`.

### Resize lock

- **resize-observer-attach**: When `ResizeObserver` exists in the global scope, the hook MUST create one and observe the scroll element.
- **resize-bottom-restores-dist**: On a `ResizeObserver` callback with `edge` `"bottom"`, the hook MUST set `scrollTop` to `Math.max(0, scrollHeight - clientHeight - tracked.dist)`.
- **resize-top-no-write**: On a `ResizeObserver` callback with `edge` `"top"`, the hook MUST NOT write `scrollTop`.
- **resize-resync**: After every `ResizeObserver` callback, the hook MUST set `tracked` to `measure(el, edge)`, so the tracked `dist` matches the position the browser actually allowed, including any clamping.
- **resize-unconditional**: The resize lock MUST apply whatever the current `dist` is. It has no slack threshold and no "only while pinned" condition.
- **resize-observer-absent**: When `ResizeObserver` is `undefined`, the hook MUST still attach the scroll listener and do the fresh-element pin, and MUST skip the resize lock.

### Item-change follow

- **item-effect-timing**: The item-change handler MUST run as a layout effect, synchronously after DOM mutation and before paint, whenever `ref`, `edge`, `newestKey` or `count` changes.
- **item-effect-identity-guard**: The item-change handler MUST do nothing when `ref.current` is `null` or is not the element stored in `tracked.current.el`.
- **item-follow-within-slack**: When the tracked `dist` is less than or equal to `PIN_SLACK_PX` (24), the item-change handler MUST call `pinToEdge(el, edge)`.
- **item-leave-reader-put**: When the tracked `dist` is greater than 24, the item-change handler MUST NOT change `scrollTop`.
- **item-resync**: After every item-change handler run that passes the identity guard, the hook MUST set `tracked` to `measure(el, edge)`.
- **no-prepend-compensation**: The hook MUST NOT shift `scrollTop` to make up for content inserted above the viewport. The source says there is "no prepend compensation" because the sole consumer is a fixed-window store, and a scroll delta applied to a filtered-list swap corrupted the reader's place.

### Ordering and concurrency

- **main-thread-only**: Every read and write happens on the browser's single JavaScript thread, inside React effects and DOM event or observer callbacks. Operations therefore never interleave, and the hook MUST NOT need locking.
- **mount-order**: On the render where an element first appears, the layout effect runs before the attach effect. The layout effect MUST skip, because the element is not tracked yet, and the attach effect MUST then pin the element.
- **edge-change-while-mounted**: `edge` is effectively fixed for the life of an element. The attach effect's scroll and `ResizeObserver` closures capture `edge` when they are wired and are re-wired only when the element identity changes, while the layout effect reads the current `edge`; if a caller changes `edge` while the same element stays mounted, the scroll and resize handlers keep measuring `dist` from the old edge. No consumer in the repository calls `useEdgeLock` outside its test, and none toggles `edge`. A port that needs a switchable edge re-wires the handlers when `edge` changes.

### Caller preconditions

- **css-bottom-anchor**: For a bottom-locked list, the caller MUST anchor short content to the bottom in layout (a flex column, with the row block wrapped in `margin-top: auto`). The doc comment states this as the CSS contract, because no scroll position can close the gap an underfull list leaves above the container's bottom edge.
- **item-signal**: To trigger item-change follow, the caller MUST change `newestKey` or `count`. A height change with neither of these and no container resize MUST NOT trigger a pin.

## Appearance

Not applicable — this is a non-visual React scroll-behavior hook, not a visual component.

## States

Not applicable — this is a non-visual React scroll-behavior hook, not a visual component.

## Accessibility

Not applicable — this is a non-visual React scroll-behavior hook, not a visual component.

## Conformance Test Vectors

Vectors 001–008 come from the assertions in `use-edge-lock.test.ts`. That test uses a mock `ResizeObserver` and an element whose `scrollTop` is clamped to `[0, scrollHeight - clientHeight]`. Vectors 009–012 are traced to the source directly.

| ID | Requirements | Input | Expected |
|----|-------------|-------|----------|
| edge-lock-001 | fresh-element-pin, pin-bottom | Element with `scrollHeight` 1000 and `clientHeight` 400; mount with `edge` `"bottom"`, `newestKey` `"newest"`, `count` 3 | `scrollTop` is 600 |
| edge-lock-002 | resize-bottom-restores-dist, resize-unconditional | 001 mounted (dist 0); `clientHeight` set to 300; resize fired | `scrollTop` is 700 |
| edge-lock-003 | pure-scroll-records-dist, resize-bottom-restores-dist, resize-resync | 001 mounted; user scrolls to 100 (dist 500); `clientHeight` set to 300 and resize fired; then `clientHeight` set back to 400 and resize fired | `scrollTop` is 200 after the first resize and 100 after the second |
| edge-lock-004 | item-follow-within-slack | 001 mounted with `newestKey` `"a"`; user scrolls to 580 (dist 20); `scrollHeight` set to 1100; rerender with `newestKey` `"b"`, `count` 4 | `scrollTop` is 700 |
| edge-lock-005 | item-leave-reader-put | 001 mounted; user scrolls to 100 (dist 500); `scrollHeight` set to 1100; rerender with `newestKey` `"b"`, `count` 4 | `scrollTop` stays 100 |
| edge-lock-006 | no-prepend-compensation, item-leave-reader-put | Mounted with `newestKey` `"z"`, `count` 9; user scrolls to 100; `scrollHeight` set to 700; rerender with `newestKey` `"y"`, `count` 4 | `scrollTop` stays 100 |
| edge-lock-007 | geometry-changed-scroll-keeps-dist, pure-scroll-records-dist, item-signal | 001 mounted (`scrollTop` 600); `scrollHeight` set to 1100 with no event; user scrolls to 500, then to 200 (dist 500); `scrollHeight` set to 1200; rerender with `newestKey` `"b"`, `count` 4 | `scrollTop` stays 200 |
| edge-lock-008 | attach-replace, attach-null-element, fresh-element-pin | Mounted on element A (1000/400); user scrolls A to 100; `ref.current` set to `null` and rerendered; `ref.current` set to new element B (800/400) and rerendered | B's `scrollTop` is 400 |
| edge-lock-009 | pin-top, fresh-element-pin | Element with `scrollTop` 300; mount with `edge` `"top"` | `scrollTop` is 0; tracked `dist` is 0 |
| edge-lock-010 | resize-top-no-write, resize-resync | `edge` `"top"`, user scrolled to 150; resize fired | The hook does not write `scrollTop`; tracked `dist` equals the browser's `scrollTop` (150 unless the browser clamped it) |
| edge-lock-011 | resize-observer-absent | `ResizeObserver` undefined; mount a bottom-locked element (1000/400) | `scrollTop` is 600; no observer is created; a later resize changes nothing |
| edge-lock-012 | item-follow-within-slack | Bottom edge, dist exactly 24; rerender with a new `count` after `scrollHeight` grows by 100 | The element is pinned to the tail (24 is inside the slack, since the comparison is `<=`) |

## Edge Cases

- **Null ref at mount**: If `ref.current` is `null`, the hook MUST attach nothing, MUST keep `tracked` at its zero record, and the layout effect MUST do nothing. Nothing is thrown.
- **Element swapped for an empty-state node and back**: Detaching when the element becomes `null`, then wiring the new element and pinning it, MUST rest the new element on its own edge without carrying over the old distance (edge-lock-008).
- **Underfull list, bottom edge**: When `scrollHeight <= clientHeight`, `pinToEdge` MUST set `scrollTop` to 0 (the `Math.max(0, …)` floor). Any visual bottom alignment is the caller's CSS job (css-bottom-anchor).
- **Resize grows past the remaining scroll range**: When restoring `dist` asks for a negative `scrollTop`, the hook MUST write 0 and then re-measure. The smaller `dist` the browser allowed becomes the value the next resize restores.
- **Content grows in place with no scroll or resize**: The tracked geometry goes stale until the next scroll event. That event MUST adopt the new geometry and keep `dist` (geometry-changed-scroll-keeps-dist), so later scrolls are recorded again (edge-lock-007).
- **Browser clamps scroll during a resize**: A scroll event caused by a clamp arrives with changed geometry. It MUST NOT overwrite `dist`. The `ResizeObserver` callback re-asserts `dist`.
- **Slack boundary**: `dist` of 24 MUST follow new items. `dist` of 25 MUST NOT.
- **Negative dist**: If `scrollTop` goes past its valid range, `dist` can come out negative. That is still `<= 24`, so the list follows. The source does not clamp `dist`.
- **Frequent `count` ticks (poll/SSE)**: A render that only changes `count` MUST cost one identity check in the attach effect (no re-wiring). It MUST run the layout effect once.
- **ResizeObserver unavailable (older runtime, SSR)**: The resize lock is skipped entirely (resize-observer-absent). Scroll tracking and item follow still work.
- **Concurrent access**: Not applicable. Everything runs on the single JS thread (main-thread-only).
- **Errors and offline**: Not applicable. The hook does no I/O, network or storage work, and none of its DOM reads or writes throw on a valid element.
- **Cancellation and timeouts**: The hook starts no asynchronous work, so nothing needs cancelling. Unmount teardown removes the listener and disconnects the observer (unmount-teardown).
- **`edge` changed mid-life**: The scroll and resize handlers keep the old edge until the element changes; see `edge-change-while-mounted`.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ref` | `RefObject<HTMLElement \| null>` | required | The scroll container. Its identity decides when listeners are re-wired. |
| `edge` | `"top" \| "bottom"` | required | The edge the list is locked to. |
| `newestKey` | `string \| null` | required | Key of the newest item. A change triggers the item-change handler. |
| `count` | `number` | `0` | Item count. A change triggers the item-change handler, so an insert anywhere in the list counts. |
| `PIN_SLACK_PX` | module constant | `24` | How far from the edge, in px, still counts as resting on it for item changes. Not configurable by the caller. |

No environment variables, settings keys or injected dependencies. The hook reads the global `ResizeObserver` if one exists.

## Deep Linking

Not applicable: the hook only adjusts `scrollTop` on a caller-supplied element and defines no routes or URLs.

## Localization

Not applicable: the hook has no user-facing strings.

## Accessibility Options

Not applicable: the hook reads no reduce-motion, contrast or color preference, and its `scrollTop` writes are instant assignments, not animations.

## Feature Flags

Not applicable: the hook reads no flags. It is always on for any caller that invokes it.

## Analytics

Not applicable: the hook emits no events.

## Privacy

Not applicable: the hook reads only element scroll geometry and does not collect, store or send any data.

## Logging

Not applicable: the hook has no log calls. No code path in it logs, throws or reports anything.

## Platform Notes

- **SwiftUI**: Start from `ScrollView` with `ScrollPosition` / `.defaultScrollAnchor(.bottom)` and `onScrollGeometryChange(for:)` to track `contentSize.height - containerSize.height - contentOffset.y` as `dist`. `onGeometryChange` covers the container-resize lock. SwiftUI's bottom anchor handles resizes for you, but the 24 pt follow-slack rule and the "leave a scrolled-away reader put" rule still have to be written by hand.
- **Compose**: Start from `LazyColumn` with `LazyListState` (or `Modifier.verticalScroll(ScrollState)`). `reverseLayout = true` gives a bottom-anchored list. Get `dist` from `layoutInfo` / `ScrollState.maxValue - value`. Follow new items in a `LaunchedEffect(newestKey, count)` that calls `scrollToItem` when `dist <= 24.dp`. `onSizeChanged` replaces `ResizeObserver`.
- **React/Web**: This is the source, `packages/web/packages/status-web/src/hooks/use-edge-lock.ts`, with its test file `use-edge-lock.test.ts` next to it. Web specifics: a passive `scroll` listener, `ResizeObserver` guarded by `typeof` for SSR, `useLayoutEffect` so the item pin happens before paint, a per-render identity-check attach effect instead of a dependency array, and the CSS `margin-top: auto` bottom-anchor contract.
- **AppKit / UIKit**: Start from `NSScrollView` (observe `NSView.boundsDidChangeNotification` on the `contentView`, with `postsBoundsChangedNotifications = true`) or `UIScrollView` with `scrollViewDidScroll`. Put the resize lock in `layout()` / `layoutSubviews()` or `viewDidLayoutSubviews`. Remember AppKit's flipped coordinates when working out bottom distance. UIKit uses `contentSize.height - bounds.height - contentOffset.y`.
- **WinUI 3**: Start from `ScrollViewer` (or the newer `ScrollView`) wrapping an `ItemsRepeater` / `ListView` bound to an `ObservableCollection<T>`. Compute `dist` as `ScrollableHeight - VerticalOffset` for the bottom edge and `VerticalOffset` for the top. Handle `ViewChanged` for scroll tracking (`IsIntermediate` separates in-flight from settled scrolls), and `SizeChanged` on the `ScrollViewer` for the resize lock, restoring with `ChangeView(null, ScrollableHeight - dist, null, disableAnimation: true)`. Follow new items from `CollectionChanged` (or `ItemsRepeater.ElementPrepared`), deferring the pin with `DispatcherQueue.TryEnqueue` or `LayoutUpdated` so it runs after layout, which stands in for `useLayoutEffect`. `ListView` has `ItemsStackPanel.ItemsUpdatingScrollMode="KeepLastItemInView"`, which gives unconditional tail-follow. It has no 24 px slack and does not leave a scrolled-away reader put, so write the slack rule by hand. Bottom-anchor underfull content with `VerticalAlignment="Bottom"` on the items host. Everything runs on the UI thread, as in the source. No `Task`/`async` is needed.

## Reference Implementations

| Platform | Path |
|----------|------|
| web | `packages/web/packages/status-web/src/hooks/use-edge-lock.ts` |

## Design Decisions

**Decision**: The resize lock keeps `dist` exactly and unconditionally, with no pinned flag.
**Rationale**: The doc comment says this replaced an earlier "re-pin only while pinned" rule. That rule's hidden flag was cleared by any wheel notch or keyboard-nav `scrollIntoView`, so the lock held only some of the time.
**Approved**: pending

**Decision**: Item-change follow uses a 24 px slack (`PIN_SLACK_PX`), and the resize lock uses none.
**Rationale**: For item changes, "resting on the edge" needs some tolerance so that small nudges still tail new content. For resizes, the exact distance is the contract, so the row at the edge stays at the edge.
**Approved**: pending

**Decision**: A scroll event with changed geometry adopts the new geometry but keeps `dist`, instead of being dropped.
**Rationale**: The source comment and regression test EL-1 say that dropping these events "permanently wedged the tracker" after any content-height change with no scroll event, which let new items yank a scrolled-up reader to the bottom.
**Approved**: pending

**Decision**: `Tracked` is tagged with the element it was measured on, and every new element is pinned fresh.
**Rationale**: Regression test EL-2 covers this. When a filter empties the list, the caller swaps in an empty-state node. The remounted list has to rest on its own edge, not apply the dead node's distance.
**Approved**: pending

**Decision**: The attach effect has no dependency array and returns early on the same element.
**Rationale**: The source comment says a poll/SSE tick that only bumps `count` should cost one ref comparison, instead of rebuilding the observer, whose fresh `observe()` would rewrite `scrollTop` for no reason.
**Approved**: pending

**Decision**: No prepend compensation.
**Rationale**: The sole consumer is a fixed-window store that never pages older history in above the reader. Applying a scroll delta on a filtered-list swap corrupted the reader's place (regression test "filtered under them").
**Approved**: pending

## Compliance

| Check | Status | Category |
|-------|--------|----------|
| [separation-of-concerns](agenticdevelopercookbook://compliance/best-practices#separation-of-concerns) | passed | best-practices |
| [unit-test-coverage](agenticdevelopercookbook://compliance/best-practices#unit-test-coverage) | passed | best-practices |
| [graceful-degradation](agenticdevelopercookbook://compliance/reliability#graceful-degradation) | passed | reliability |
| [resource-efficiency](agenticdevelopercookbook://compliance/performance#resource-efficiency) | passed | performance |
| [state-recovery](agenticdevelopercookbook://compliance/reliability#state-recovery) | partial | reliability |

The hook does one job, scroll-edge locking, and it touches only the DOM element it is given. `use-edge-lock.test.ts` covers mount, both resize directions, follow within the slack, leaving a reader put, the filtered-list regression, and both EL-1 and EL-2. It degrades gracefully when `ResizeObserver` is absent. It avoids re-wiring on every render and removes its listeners on unmount. State recovery is partial: element swaps reset cleanly, but a change to `edge` while the same element stays mounted leaves the scroll and resize handlers measuring from the old edge. That residual is described in `edge-change-while-mounted`.

## Change History

| Version | Date | Author | Summary |
|---------|------|--------|---------|
| 1.0.1 | 2026-09-25 | Mike Fullerton | Moved into the library cookbook; added Reference Implementations. |
| 1.0.0 | 2026-09-24 | Mike Fullerton | Initial creation |
