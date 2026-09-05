"use client";
import { type ReactElement, type ReactNode, useRef } from "react";
import { useFollowNewItems } from "../hooks/use-follow-new-items";

import { COLORS } from "../lib/colors";
interface PaneShellProps {
  /** Fixed header — stays put while the body scrolls. */
  header: ReactNode;
  /** Key of the NEWEST underlying item (null = empty); a change auto-scrolls the
   *  body to `edge` so the new row is shown. Identity, not count — see the hook. */
  newestKey: string | null;
  /** Where new rows land: "top" (newest-first) or "bottom" (newest-last feed). */
  edge: "top" | "bottom";
  /** Key of the OLDEST underlying item; a change anchors the scroll (prepend). */
  oldestKey?: string | null;
  /** Auto-scroll to `edge` when the newest item changes (default). Pass false for
   *  panes the user scrolls freely (the activity list does not follow new rows). */
  follow?: boolean;
  /** Called when the body scrolls near the start edge (older direction). */
  onReachStart?: () => void;
  /** Scroll-body padding. */
  bodyPadding?: string;
  /** Optional body background (the activity pane is slightly inset). */
  background?: string;
  /** Extra class on the root (e.g. so tests/styles can target a pane). */
  className?: string;
  children: ReactNode;
}

/**
 * One pane = a fixed header over an independently-scrolling body. Shared by all
 * three Overview panes so the header never scrolls with the content and new
 * rows always scroll into view, identically everywhere.
 */
export function PaneShell({
  header,
  newestKey,
  edge,
  oldestKey,
  follow = true,
  onReachStart,
  bodyPadding = "10px 16px 22px",
  background,
  className,
  children,
}: PaneShellProps): ReactElement {
  const bodyRef = useRef<HTMLDivElement>(null);
  // follow=false → pass a constant key so the hook never sees a "new item" and
  // never moves the user's scroll position.
  useFollowNewItems(bodyRef, edge, follow ? newestKey : null, follow ? (oldestKey ?? null) : null);
  // Near the start edge (older direction) → ask the owner to load more history.
  // Intentional: if the viewport isn't full after a prepend (scrollTop stays < 200),
  // the next scroll event triggers another load. React Query serializes the pages,
  // so this just keeps loading until the pane fills or there's no next page.
  const onScroll = (): void => {
    const el = bodyRef.current;
    if (!el || !onReachStart) return;
    if (el.scrollTop < 200) onReachStart();
  };
  return (
    <div className={className} style={{ display: "flex", flexDirection: "column", flex: 1, minHeight: 0, minWidth: 0, background }}>
      <div style={{ flex: "0 0 auto", borderBottom: `1px solid ${COLORS.border}` }}>{header}</div>
      <div ref={bodyRef} onScroll={onScroll} style={{ flex: "1 1 auto", minHeight: 0, overflowY: "auto", padding: bodyPadding }}>
        {children}
      </div>
    </div>
  );
}
