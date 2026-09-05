"use client";
import { type RefObject, useEffect, useLayoutEffect, useRef } from "react";

// How close to the locked edge (px) still counts as "resting on it" — within this
// slack the list keeps tailing as items arrive; scroll further away and new items
// leave you put. Applies to ITEM changes only; the resize lock has no threshold.
const PIN_SLACK_PX = 24;

/** The scroll container's last known geometry plus the viewport's distance from
 *  the locked edge, tagged with the ELEMENT it was measured on. `dist` is the
 *  single source of truth: the resize lock preserves it exactly, the new-item pin
 *  checks it against PIN_SLACK_PX, and `el` lets a remount discard a dead node's
 *  distance instead of applying it to the fresh one. */
interface Tracked {
  el: HTMLElement | null;
  scrollHeight: number;
  clientHeight: number;
  dist: number;
}

function measure(el: HTMLElement, edge: "top" | "bottom"): Tracked {
  return {
    el,
    scrollHeight: el.scrollHeight,
    clientHeight: el.clientHeight,
    dist: edge === "bottom" ? el.scrollHeight - el.clientHeight - el.scrollTop : el.scrollTop,
  };
}

function pinToEdge(el: HTMLElement, edge: "top" | "bottom"): void {
  el.scrollTop = edge === "bottom" ? Math.max(0, el.scrollHeight - el.clientHeight) : 0;
}

/**
 * Lock a scrolling list to one edge of its container — the contract for a list
 * that sits above a details pane: whatever touches the locked edge RIDES that
 * edge through every geometry change. Two concerns share one `Tracked` record,
 * keyed to the scroll element so a remount can't apply a dead node's distance:
 *
 * - **Container resizes** (split-divider drags, collapse/expand, window
 *   resizes): the viewport's distance from the locked edge is preserved
 *   EXACTLY, unconditionally — resting on the edge (dist 0) or scrolled away
 *   (dist N). The row at the edge stays at the edge; rows appear and disappear
 *   at the far side. This replaces the old "re-pin only while pinned" rule,
 *   whose hidden pinned flag (cleared by any wheel notch or a keyboard-nav
 *   scrollIntoView) made the lock hold only some of the time.
 * - **Item changes** (`newestKey`/`count`): within PIN_SLACK_PX of the edge the
 *   list follows new content — a newly inserted item stays in view no matter
 *   WHERE in the order it lands (an insert anywhere bumps `count` even when
 *   neither end moves). A reader scrolled away is left where they are; nothing
 *   is shifted under them, so a filter narrowing/clearing the list can't yank
 *   their place.
 *
 * CSS contract for a bottom-locked list: scroll position cannot close the gap
 * an UNDERFULL list leaves between its last row and the container's bottom
 * edge, so the caller must bottom-anchor short content in layout (flex column;
 * the row block wrapped with `margin-top: auto`). See ActivityPanel's list pane.
 */
export function useEdgeLock(
  ref: RefObject<HTMLElement | null>,
  edge: "top" | "bottom",
  newestKey: string | null,
  count = 0,
): void {
  const tracked = useRef<Tracked>({ el: null, scrollHeight: 0, clientHeight: 0, dist: 0 });
  const detach = useRef<(() => void) | null>(null);

  // Attach the scroll listener + ResizeObserver to the scroll element, and
  // re-attach ONLY when the element identity changes — a mount, or the caller
  // swapping the container for an empty-state node and back. This effect has no
  // dependency array: it runs after every render but early-returns once the
  // current element is the one already wired, so a poll/SSE tick that only bumps
  // `count` costs a single ref comparison instead of tearing down and rebuilding
  // the observer (whose fresh observe() would redundantly rewrite scrollTop).
  useEffect(() => {
    const el = ref.current;
    if (el === tracked.current.el && detach.current) return;
    detach.current?.();
    detach.current = null;
    if (!el) {
      tracked.current = { el: null, scrollHeight: 0, clientHeight: 0, dist: 0 };
      return;
    }

    const onScroll = (): void => {
      const m = measure(el, edge);
      const t = tracked.current;
      if (m.scrollHeight === t.scrollHeight && m.clientHeight === t.clientHeight) {
        // Pure scroll (geometry unchanged) — the user moved; record their distance.
        tracked.current = m;
      } else {
        // Geometry changed under the scroll (a resize clamp forcing scrollTop back
        // into a shrunken range, or content growing in place): KEEP the user's
        // tracked distance — the ResizeObserver re-asserts it for resizes — but
        // adopt the new geometry so the NEXT real scroll isn't rejected. (Dropping
        // the event outright, as the first cut did, permanently wedged the tracker
        // the moment any content-height change slipped past without a scroll.)
        tracked.current = { el, scrollHeight: m.scrollHeight, clientHeight: m.clientHeight, dist: t.dist };
      }
    };
    el.addEventListener("scroll", onScroll, { passive: true });

    // THE RESIZE LOCK: a surrounding split-drag/collapse/window resize changes
    // the viewport without touching the rendered list, so the item-keyed layout
    // effect never fires. Left alone the browser keeps scrollTop (anchoring the
    // TOP) and the bottom rows slide behind whatever grew — re-assert the tracked
    // distance from the locked edge instead. The top edge needs no write.
    let ro: ResizeObserver | undefined;
    if (typeof ResizeObserver !== "undefined") {
      ro = new ResizeObserver(() => {
        if (edge === "bottom") {
          el.scrollTop = Math.max(0, el.scrollHeight - el.clientHeight - tracked.current.dist);
        }
        // Re-sync to what the browser actually allowed — a grow can clamp `dist`
        // smaller when the remaining scroll range can't honor it, and the next
        // resize must restore THAT position, not a stale wish.
        tracked.current = measure(el, edge);
      });
      ro.observe(el);
    }

    // A freshly wired element rests ON its edge (the fresh-list contract); this
    // is also the remount reset that discards the previous node's distance.
    pinToEdge(el, edge);
    tracked.current = measure(el, edge);

    detach.current = () => {
      el.removeEventListener("scroll", onScroll);
      ro?.disconnect();
    };
  });

  // Final teardown on unmount (the attach effect above never returns a cleanup,
  // so it never tears down mid-life; this runs once, on unmount).
  useEffect(() => () => {
    detach.current?.();
    detach.current = null;
  }, []);

  // Item changes: within slack of the locked edge, follow the new content so the
  // newest row stays in view; a reader scrolled away is left where they are. No
  // prepend compensation — the sole consumer is a fixed-window store that never
  // pages older history in above a scrolled-up reader, and applying a scroll
  // delta on what was really a filtered-list swap corrupted the reader's place.
  useLayoutEffect(() => {
    const el = ref.current;
    // Skip until the attach effect has wired THIS element (on a mount render the
    // layout effect runs first, before the element is tracked; the attach effect
    // then pins it). Guarding on identity also means a remount never re-pins with
    // a stale distance carried over from the previous node.
    if (!el || el !== tracked.current.el) return;
    if (tracked.current.dist <= PIN_SLACK_PX) {
      pinToEdge(el, edge);
    }
    tracked.current = measure(el, edge);
  }, [ref, edge, newestKey, count]);
}
