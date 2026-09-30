<!-- leaf: implement-status-web-hooks/use-follow-new-items--edge-cases · source: status-web-hooks-use-follow-new-items.md -->

# useFollowNewItems

**Rules** (cite as `implement-status-web-hooks/use-follow-new-items--edge-cases#<slug>`):

- `empty-list` MUST — With no rows the anchor MUST be null, so a scrolled-away reader gets only the fallback (gated on the head key …
- `container-not-yet-mounted` MUST — When the list starts empty and its container is rendered conditionally, ref.current is null on the first run; both …
- `null-keys` MUST — When the head key is null (for example PaneShell with following off), the fallback MUST NOT fire; re-pinning while …
- `non-overflowing-list` MUST — A list shorter than its viewport MUST count as at both edges (follow-005), so it stays pinned.
- `overscroll` MUST — A negative distance to the edge (for example elastic overscroll) MUST count as at the edge, since the comparison is <= …
- `anchor-row-removed` MUST — When the held anchor row is disconnected or no longer inside the container, the hook MUST fall back to total …
- `no-layout` MUST — With every rect zero, the anchor MUST be null and only the fallback path MUST run.
- `change-entirely-below-the-reader` MUST — The anchored row's shift is 0, so scrollTop MUST NOT be written (follow-018).
- `programmatic-re-pin` MUST — A scrollTop write by the hook dispatches a scroll event that MUST re-evaluate pinned state like any user scroll; a …
- `resize-without-resizeobserver` MUST — Resizes MUST go unhandled; the reader MAY see tail rows slide out of view until the next list change.
- `edge-changed-mid-life` MUST — A new edge MUST re-attach listeners and re-run the pass; the pinned flag MUST carry over and be re-evaluated on the …
- `concurrent-access` MUST — The hook runs on the single-threaded browser main thread; scroll, resize and layout-effect callbacks MUST NOT …
- `cancellation-and-timeouts` MUST — The hook starts no asynchronous work; unmount MUST remove the listener and disconnect the observer, and no timeout …

## Edge Cases

- **Empty list**: With no rows the anchor MUST be null, so a scrolled-away reader gets only the fallback (gated on the head key changing); a pinned reader MUST still be re-pinned.
- **Container not yet mounted**: When the list starts empty and its container is rendered conditionally, `ref.current` is null on the first run; both effects MUST return without work, and the listener effect MUST attach once `count` changes after the container mounts.
- **Null keys**: When the head key is null (for example `PaneShell` with following off), the fallback MUST NOT fire; re-pinning while pinned and anchor compensation still MUST apply on passes that run.
- **Non-overflowing list**: A list shorter than its viewport MUST count as at both edges (follow-005), so it stays pinned.
- **Overscroll**: A negative distance to the edge (for example elastic overscroll) MUST count as at the edge, since the comparison is `<= slack`.
- **Anchor row removed**: When the held anchor row is disconnected or no longer inside the container, the hook MUST fall back to total `scrollHeight` growth gated on the head key; that fallback MUST be accepted as understating the insert when rows also left the far end in the same update, as the source comment states it is correct only "whenever nothing left the far end".
- **No layout (jsdom)**: With every rect zero, the anchor MUST be null and only the fallback path MUST run.
- **Change entirely below the reader**: The anchored row's shift is 0, so `scrollTop` MUST NOT be written (follow-018).
- **Programmatic re-pin**: A `scrollTop` write by the hook dispatches a `scroll` event that MUST re-evaluate pinned state like any user scroll; a re-pin to the edge leaves the reader pinned.
- **Resize without `ResizeObserver`**: Resizes MUST go unhandled; the reader MAY see tail rows slide out of view until the next list change.
- **Edge changed mid-life**: A new `edge` MUST re-attach listeners and re-run the pass; the pinned flag MUST carry over and be re-evaluated on the next scroll event.
- **Concurrent access**: The hook runs on the single-threaded browser main thread; scroll, resize and layout-effect callbacks MUST NOT interleave.
- **Errors and offline state**: The hook performs no I/O and raises no errors, so dependency failure and connectivity loss do not apply to it.
- **Cancellation and timeouts**: The hook starts no asynchronous work; unmount MUST remove the listener and disconnect the observer, and no timeout exists.
