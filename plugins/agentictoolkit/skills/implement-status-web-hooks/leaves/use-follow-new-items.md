<!-- leaf: implement-status-web-hooks/use-follow-new-items · source: status-web-hooks-use-follow-new-items.md -->

**Rules** (cite as `implement-status-web-hooks/use-follow-new-items#<slug>`):

- `at-edge-signature` MUST
- `at-edge-default-slack` MUST
- `at-edge-bottom` MUST
- `at-edge-top` MUST
- `at-edge-inclusive` MUST
- `at-edge-purity` MUST
- `hook-signature` MUST
- `hook-return` MUST
- `edge-meaning` MUST
- `head-key` MUST
- `list-change-trigger` MUST
- `count-insert-trigger` MUST
- `null-container` MUST
- `row-order-precondition` MUST
- `pinned-initial` MUST
- `pinned-on-scroll` MUST
- `scroll-listener-passive` MUST
- `scroll-reanchor` MUST
- `anchor-definition` MUST
- `anchor-empty` MUST
- `anchor-binary-search` MUST
- `pass-timing` MUST
- `repin-when-pinned` MUST
- `repin-wins` MUST
- `anchor-compensation` MUST
- `anchor-zero-shift` MUST
- `anchor-capped-list` MUST
- `fallback-growth` MUST
- `fallback-far-end` MUST
- `fallback-first-pass` MUST
- `pass-bookkeeping` MUST
- `pass-reanchor` MUST
- `resize-observer` MUST
- `resize-repin` MUST
- `resize-leave-unpinned` MUST
- `resize-reanchor` MUST
- `resize-absent` MUST
- `listener-deps` MUST
- `listener-cleanup` MUST
- `single-thread` MUST
- `no-persistence` MUST
- `no-network` MUST

# useFollowNewItems

## Overview

`useFollowNewItems` gives a scrolling list the classic "tail" behavior. While the viewport rests at the edge where the newest row is rendered (within `PIN_SLACK_PX` = 24 px), every change to the rendered list and every resize of the scroll container re-pins the viewport to that edge, so a newly inserted row stays in view wherever in the order it lands. Once the reader scrolls away from the edge they are left alone, and rows inserted above a scrolled-away viewport do not move the row they are reading: the hook measures that row (the "anchor") and compensates `scrollTop` by exactly the distance it shifted.

The module also exports `atEdge`, the pure predicate that decides whether an element rests at a given edge. The hook returns nothing; its only effects are writes to the scroll container's `scrollTop`. In the status board it is used by `ActivityPanel` and by `PaneShell`, which passes `null` keys when following is switched off.

## Behavioral Requirements

### atEdge

- **at-edge-signature**: `atEdge(m, edge, slack)` MUST take a measurement object with numeric `scrollHeight`, `clientHeight` and `scrollTop`, an `edge` of `"top"` or `"bottom"`, and an optional `slack` in pixels, and MUST return a boolean.
- **at-edge-default-slack**: When `slack` is omitted, `atEdge` MUST use `PIN_SLACK_PX`, which is 24.
- **at-edge-bottom**: For `edge === "bottom"`, `atEdge` MUST return true exactly when `scrollHeight - clientHeight - scrollTop <= slack`.
- **at-edge-top**: For `edge === "top"`, `atEdge` MUST return true exactly when `scrollTop <= slack`.
- **at-edge-inclusive**: The slack comparison MUST be inclusive: a distance equal to `slack` counts as at the edge.
- **at-edge-purity**: `atEdge` MUST read only its arguments and MUST NOT touch the DOM or any other state.

### Hook contract

- **hook-signature**: `useFollowNewItems(ref, edge, newestKey, oldestKey, count)` MUST accept a ref to the scroll container (`RefObject<HTMLElement | null>`), an `edge` of `"top"` or `"bottom"`, a `newestKey` of type `string | null`, an optional `oldestKey` of type `string | null` (default `null`) and an optional numeric `count` (default `0`).
- **hook-return**: The hook MUST return `void`; its only observable output is the container's `scrollTop`.
- **edge-meaning**: `edge` MUST name the edge at which the caller renders the NEWEST row: `"bottom"` for oldest-to-newest (chat-log) order, `"top"` for newest-first order.
- **head-key**: The hook MUST treat `newestKey` as the key of the row at the top of the list when `edge` is `"top"`, and `oldestKey` as that key when `edge` is `"bottom"` (the "head key").
- **list-change-trigger**: The list-change pass MUST run after every render in which any of `ref`, `edge`, `newestKey`, `oldestKey`, the head key or `count` changed.
- **count-insert-trigger**: A change to `count` alone, with both keys unchanged, MUST trigger the list-change pass, so an insert in the middle of the list is followed.
- **null-container**: When `ref.current` is null, both the listener setup and the list-change pass MUST do nothing.
- **row-order-precondition**: The container's direct children are the rows; per the `measureAnchor` doc comment the caller MUST render them in document order in a block flow, so their bottom edges increase monotonically.

### Pinned state

- **pinned-initial**: The pinned state MUST start true on mount, so a freshly mounted list snaps to its edge on the first list-change pass.
- **pinned-on-scroll**: On every `scroll` event of the container, the hook MUST set the pinned state to `atEdge(container, edge)` with the default 24 px slack.
- **scroll-listener-passive**: The `scroll` listener MUST be registered as passive.
- **scroll-reanchor**: On every `scroll` event, the hook MUST re-measure the anchor.

### Anchor measurement

- **anchor-definition**: The anchor MUST be the first direct child of the container whose bounding-rect bottom is greater than the container's bounding-rect top, together with its offset (row top minus container top).
- **anchor-empty**: When no child satisfies that condition (no children, or no layout so every rect is zero), the anchor MUST be null.
- **anchor-binary-search**: The anchor search MUST find the partition point by binary search over the children, reading O(log n) rects, and MUST NOT write layout between reads.

### List-change pass (layout effect)

- **pass-timing**: The list-change pass MUST run synchronously after the DOM update and before the browser paints.
- **repin-when-pinned**: While pinned, the pass MUST set `scrollTop` to `scrollHeight` for `edge === "bottom"` and to `0` for `edge === "top"`.
- **repin-wins**: While pinned, re-pinning MUST take precedence over anchoring, even when a held anchor exists.
- **anchor-compensation**: While not pinned, when the held anchor row is still connected and is still a descendant of the container, the pass MUST add to `scrollTop` the anchor row's current offset from the container's top minus its recorded offset.
- **anchor-zero-shift**: When that shift is exactly 0, the pass MUST NOT write `scrollTop`.
- **anchor-capped-list**: Anchor compensation MUST hold the reader's row even when a row arriving at the top is matched by a row leaving the bottom, so the container's total height does not change.
- **fallback-growth**: While not pinned and with no usable anchor, the pass MUST add `scrollHeight - previousScrollHeight` to `scrollTop` only when the head key is non-null, a previous head key has been recorded, and the head key differs from the previous one.
- **fallback-far-end**: When only the far-end key changes (the key that is not the head key), the fallback MUST NOT move `scrollTop`.
- **fallback-first-pass**: On the first list-change pass after mount no previous head key exists, so the fallback MUST NOT fire.
- **pass-bookkeeping**: At the end of every pass that has a container, the hook MUST record the current head key and `scrollHeight` as the previous values.
- **pass-reanchor**: At the end of every pass that has a container, the hook MUST re-measure the anchor.

### Resize handling

- **resize-observer**: When `ResizeObserver` exists in the environment, the hook MUST observe the container for size changes.
- **resize-repin**: On a container resize while pinned, the hook MUST set `scrollTop` to `scrollHeight` for `"bottom"` or `0` for `"top"`.
- **resize-leave-unpinned**: On a container resize while not pinned, the hook MUST NOT change `scrollTop`.
- **resize-reanchor**: On every container resize, the hook MUST re-measure the anchor.
- **resize-absent**: When `ResizeObserver` is undefined, the hook MUST skip resize handling and MUST NOT throw.

### Lifecycle and ordering

- **listener-deps**: The scroll listener and resize observer MUST be (re)attached whenever `ref`, `edge` or `count` changes, so the listeners attach once a conditionally rendered container mounts.
- **listener-cleanup**: Before re-attaching and on unmount, the hook MUST remove the `scroll` listener and disconnect the resize observer.
- **single-thread**: All reads and writes MUST happen on the browser main thread; scroll events, resize callbacks and the layout effect cannot interleave, so their ordering is the order the browser dispatches them.
- **no-persistence**: The hook MUST keep pinned state, anchor, previous head key and previous height in memory for the component's lifetime only, and MUST NOT persist any of them.
- **no-network**: The hook MUST NOT perform network, storage, logging or timer side effects.

## Configuration

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `ref` | `RefObject<HTMLElement \| null>` | required | The scroll container; its direct children are the rows. |
| `edge` | `"top" \| "bottom"` | required | The edge at which the newest row is rendered. |
| `newestKey` | `string \| null` | required | Key of the newest rendered row; the head key when `edge` is `"top"`. |
| `oldestKey` | `string \| null` | `null` | Key of the oldest rendered row; the head key when `edge` is `"bottom"`. |
| `count` | `number` | `0` | Number of rendered rows; a change re-runs both effects. |
| `slack` (on `atEdge`) | `number` | `PIN_SLACK_PX` (24) | Pixels from the edge that still count as pinned. |
| `PIN_SLACK_PX` | constant | `24` | Module constant; not configurable from the hook. |
| `ResizeObserver` | environment global | optional | Enables resize re-pinning when present. |

