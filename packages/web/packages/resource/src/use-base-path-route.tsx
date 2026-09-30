"use client";

import { useCallback } from "react";
import { useRouter } from "next/navigation";
import type { TopicSelectOptions } from "@agenticdevelopertoolkit/ui/blocks";

/**
 * URL push helpers for a deep-linked feature mounted at an explicit `basePath`
 * (the host route supplies it — `/<slug>/<feature>` on the hub, `/home` on a
 * feature site; never derived from useParams inside the package). The port of
 * the hub's `useFeatureRoute` with the base made a parameter:
 *   - `pushSegment(id)`  → `<basePath>/<id>`, or the base when id is null.
 *   - `pushNested(parent, child)` → `<basePath>/<parent>/<child>`, `.../<parent>`
 *     when the child is null, or the base when there's no parent — for two-level
 *     selections (persona ▸ sub-tab, dashboards section ▸ row).
 *   - `pushDeep(...segs)` → `<basePath>/<seg>/<seg>/…` for three-plus-level
 *     selections; falsy segments are dropped, so a null tail clears that level.
 * Scroll is preserved on every push so drilling in doesn't jump the page. `pushSegment` and
 * `pushNested` honour `{ replace: true }` (a `TopicLeaf.onSelect`'s options), so a redirect off
 * an old address replaces it instead of leaving it in history for Back to land on again.
 */
export function useBasePathRoute(basePath: string): {
  pushSegment: (id: string | null, opts?: TopicSelectOptions) => void;
  pushNested: (parent: string | undefined, child: string | null, opts?: TopicSelectOptions) => void;
  pushDeep: (...segs: (string | null | undefined)[]) => void;
} {
  const router = useRouter();
  const go = useCallback(
    (href: string, opts?: TopicSelectOptions) =>
      opts?.replace ? router.replace(href, { scroll: false }) : router.push(href, { scroll: false }),
    [router],
  );
  const pushSegment = useCallback(
    (id: string | null, opts?: TopicSelectOptions) => go(id ? `${basePath}/${id}` : basePath, opts),
    [go, basePath],
  );
  const pushNested = useCallback(
    (parent: string | undefined, child: string | null, opts?: TopicSelectOptions) =>
      go(parent ? (child ? `${basePath}/${parent}/${child}` : `${basePath}/${parent}`) : basePath, opts),
    [go, basePath],
  );
  const pushDeep = useCallback(
    (...segs: (string | null | undefined)[]) => {
      // Drop falsy (null/undefined/empty) segments from the tail so clearing a deeper level routes
      // to the shorter URL (`.../member/persona/subtab` → `.../member/persona` when subtab is null).
      const tail = segs.filter((s): s is string => Boolean(s)).join("/");
      router.push(tail ? `${basePath}/${tail}` : basePath, { scroll: false });
    },
    [router, basePath],
  );
  return { pushSegment, pushNested, pushDeep };
}
