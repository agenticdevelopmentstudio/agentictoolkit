"use client";
import { type RefObject, useEffect, useLayoutEffect, useRef } from "react";

// How close to the edge (px) still counts as "pinned" — within this slack the
// list keeps tailing as items arrive; scroll further away and it leaves you put.
const PIN_SLACK_PX = 24;

/** Whether the element rests at (within `slack` of) the given edge. Pure for testing. */
export function atEdge(
  m: { scrollHeight: number; clientHeight: number; scrollTop: number },
  edge: "top" | "bottom",
  slack: number = PIN_SLACK_PX,
): boolean {
  return edge === "bottom" ? m.scrollHeight - m.clientHeight - m.scrollTop <= slack : m.scrollTop <= slack;
}

/** The row a scrolled-away reader is looking at, and how far below the scroll
 *  container's top edge it sits. Restoring that pair after the list changes is what
 *  keeps their rows under their eyes — see the layout effect. */
interface Anchor {
  el: Element;
  offset: number;
}

/**
 * The first row not entirely above the viewport, plus its offset from the container's
 * top edge. Null when there are no rows — and under jsdom, where nothing has layout
 * and every rect is zero, which is why the layout effect keeps a measurement-free
 * fallback.
 *
 * BINARY search, not a walk. Rows are in document order in a block flow, so their bottoms
 * increase monotonically and "the first one past the top edge" is a partition point. This
 * runs on every scroll event, every resize and every layout-effect pass; it used to be a
 * linear scan bounded by the server's activity cap (MAX_ACTIVITY_ROWS), and with history
 * pages loaded on top of the live page that ceiling is gone — the scan length became how
 * far back the reader had scrolled, thousands of forced-layout reads per scroll event.
 * O(log n) rect reads is the same answer for a fraction of the work.
 *
 * The loop only READS geometry (no writes in between), so the browser computes layout once
 * and serves the whole search from it. Under jsdom, where nothing has layout and every
 * rect is zero, no row satisfies `bottom > top` and this returns null — which is why the
 * layout effect keeps a measurement-free fallback.
 */
function measureAnchor(el: HTMLElement): Anchor | null {
  const top = el.getBoundingClientRect().top;
  const rows = el.children;
  let lo = 0;
  let hi = rows.length - 1;
  let found = -1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (rows[mid]!.getBoundingClientRect().bottom > top) {
      found = mid;
      hi = mid - 1;
    } else {
      lo = mid + 1;
    }
  }
  if (found < 0) return null;
  const row = rows[found]!;
  return { el: row, offset: row.getBoundingClientRect().top - top };
}

/**
 * Keep a scrolling list pinned to one edge as its content changes — the classic
 * "tail" behavior. While the viewport rests AT the edge (within PIN_SLACK_PX),
 * any change to the rendered list re-pins it there, so a newly inserted item
 * stays in view no matter WHERE in the order it lands — including a completed
 * deploy inserted next to an in-flight build (the case that keying off one row's
 * identity alone missed). Once the reader scrolls away from the edge they're left
 * alone, and rows inserted ABOVE a scrolled-away viewport keep their place
 * (anchored) so the reader doesn't jump.
 *
 * `newestKey`/`oldestKey`/`count` are the rendered list's ends + size; together
 * they re-run the effect whenever the list changes — an insert anywhere bumps
 * `count` even when neither end moves, which is what makes the tail follow it.
 *
 * `edge` says which edge the NEWEST row is rendered at, so it also fixes the
 * caller's ordering — and therefore which of the two keys names the row at the
 * TOP of the list, the only end whose growth can shift a scrolled-away reader:
 *
 * - `"bottom"` — chat-log order, oldest→newest down the list (what the status board's
 *   `/api/board` emits: `derive-activity.ts` sorts ascending by `at`). The top row is
 *   the OLDEST, so paging in history changes `oldestKey`.
 * - `"top"` — newest-first order. The top row is the NEWEST, so a fresh item landing
 *   changes `newestKey`.
 *
 * Anchoring keys off whichever of the two that is. It used to be hard-guarded to
 * `edge === "bottom"` and to `oldestKey` — which for a newest-first list is the
 * BOTTOM row, whose growth needs no compensation at all.
 *
 * The compensation is measured on the anchored ROW, not on the container's total
 * growth: a capped list (activity is server-capped at MAX_ACTIVITY_ROWS) drops a row
 * off the far end for every row that arrives at the near one, so the total delta
 * understates what was inserted above the reader — by exactly one row's height on a
 * full list, every update. See the layout effect.
 */
export function useFollowNewItems(
  ref: RefObject<HTMLElement | null>,
  edge: "top" | "bottom",
  newestKey: string | null,
  oldestKey: string | null = null,
  count = 0,
): void {
  // Pinned = the viewport currently rests at the tail edge. Initialized true so a
  // fresh list snaps to the edge; thereafter tracked on the user's OWN scrolls so
  // auto-follow only fires while they haven't scrolled away to read history.
  const pinned = useRef(true);
  const prevHead = useRef<string | null | undefined>(undefined);
  const prevHeight = useRef(0);
  // The row under the reader's eyes, re-measured on their own scrolls (and after every
  // update) so the layout effect always compensates against a CURRENT position.
  const anchor = useRef<Anchor | null>(null);

  // The key of the row currently at the TOP of the rendered list — see the edge
  // note above. Content growing above the viewport is the only growth that moves
  // a scrolled-away reader's rows, so this is what anchoring watches.
  const headKey = edge === "top" ? newestKey : oldestKey;

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const onScroll = (): void => {
      pinned.current = atEdge(el, edge);
      // The row the reader is on changes as they move, so re-anchor with them.
      anchor.current = measureAnchor(el);
    };
    el.addEventListener("scroll", onScroll, { passive: true });

    // Re-pin on container RESIZE, not just on item changes. Dragging a surrounding
    // split (or any layout change) shrinks/grows the viewport WITHOUT touching the
    // rendered list, so the item-keyed layout effect below never fires — the browser
    // then leaves scrollTop put and, on a shrink, the tail rows slide out of view
    // behind whatever grew. While the reader still rests at the tail edge, keep them
    // pinned there as the pane resizes; once they've scrolled away, leave them be.
    let ro: ResizeObserver | undefined;
    if (typeof ResizeObserver !== "undefined") {
      ro = new ResizeObserver(() => {
        if (pinned.current) el.scrollTop = edge === "bottom" ? el.scrollHeight : 0;
        // A resize reflows the rows under a scrolled-away reader, so the anchor taken
        // before it is stale — re-take it, or the next update compensates against a
        // position the reader no longer holds.
        anchor.current = measureAnchor(el);
      });
      ro.observe(el);
    }

    return () => {
      el.removeEventListener("scroll", onScroll);
      ro?.disconnect();
    };
    // `count` is a dep so this re-runs and (re-)attaches once the scroll container
    // actually mounts — the ref can be null on the first run when the list starts
    // empty (its element is rendered conditionally), and refs don't re-trigger effects.
  }, [ref, edge, count]);

  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    const held = anchor.current;
    if (pinned.current) {
      // Still at the edge — re-pin so the new content is in view.
      el.scrollTop = edge === "bottom" ? el.scrollHeight : 0;
    } else if (held && held.el.isConnected && el.contains(held.el)) {
      // Scrolled away — hold the reader's own row exactly where it was. Its shift IS
      // the height inserted above it (or removed from above it), which is what has to
      // be compensated; nothing else moved them. Fires for a newest-first list (new
      // deploys land at the top) exactly as for a chat-log one (history pages in at
      // the top), and is a no-op when the change was entirely below them.
      //
      // This used to add the container's TOTAL scrollHeight growth, which is only the
      // same number while nothing leaves the far end. Activity is server-capped at
      // MAX_ACTIVITY_ROWS, so on a full list every row arriving at the top drops one
      // off the bottom: the total delta then reads ~0 while a whole row was inserted
      // above the reader, sliding them up by a row on every single update.
      const shift = held.el.getBoundingClientRect().top - el.getBoundingClientRect().top - held.offset;
      if (shift !== 0) el.scrollTop += shift;
    } else if (headKey !== null && prevHead.current !== undefined && headKey !== prevHead.current) {
      // No row to measure against — the reader's row left the list, or the environment
      // does no layout at all (jsdom). Fall back to the total growth, which is the
      // right answer whenever nothing left the far end, and gate it on the TOP row
      // changing so growth at the far end still doesn't move anyone.
      el.scrollTop += el.scrollHeight - prevHeight.current;
    }
    prevHead.current = headKey;
    prevHeight.current = el.scrollHeight;
    // Re-anchor after every update, so the first update following a mount (or one
    // arriving before the reader has scrolled at all) has a position to hold.
    anchor.current = measureAnchor(el);
  }, [ref, edge, newestKey, oldestKey, headKey, count]);
}
