<!-- leaf: implement-status-web-hooks/use-edge-lock--edge-cases · source: status-web-hooks-use-edge-lock.md -->

# useEdgeLock

**Rules** (cite as `implement-status-web-hooks/use-edge-lock--edge-cases#<slug>`):

- `null-ref-at-mount` MUST — If ref.current is null, the hook MUST attach nothing, MUST keep tracked at its zero record, and the layout effect MUST …
- `element-swapped-for-an-empty-state-node-and-back` MUST — Detaching when the element becomes null, then wiring the new element and pinning it, MUST rest the new element on its …
- `underfull-list-bottom-edge` MUST — When scrollHeight <= clientHeight, pinToEdge MUST set scrollTop to 0 (the Math.max(0, …) floor). Any visual bottom …
- `resize-grows-past-the-remaining-scroll-range` MUST — When restoring dist asks for a negative scrollTop, the hook MUST write 0 and then re-measure. The smaller dist the …
- `content-grows-in-place-with-no-scroll-or-resize` MUST — The tracked geometry goes stale until the next scroll event. That event MUST adopt the new geometry and keep dist …
- `browser-clamps-scroll-during-a-resize` MUST — A scroll event caused by a clamp arrives with changed geometry. It MUST NOT overwrite dist. The ResizeObserver callback …
- `slack-boundary` MUST — dist of 24 MUST follow new items. dist of 25 MUST NOT.
- `frequent-count-ticks` MUST — A render that only changes count MUST cost one identity check in the attach effect (no re-wiring). It MUST run the …

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
