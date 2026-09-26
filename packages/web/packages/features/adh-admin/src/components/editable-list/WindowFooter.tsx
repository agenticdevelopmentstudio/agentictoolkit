"use client";

import type { ReactElement } from "react";
import { Button } from "@agenticdevelopertoolkit/ui/components/button";

export interface WindowFooterProps {
  /** How many rows the window holds — everything fetched, before any filtering. */
  loaded: number;
  /** How many are showing after the filters. */
  showing: number;
  /**
   * Roughly how many rows the whole log holds, as the server reports it. Deliberately vague in
   * the copy: the routes behind these lists cap their own COUNT to keep a full scan off an
   * unbounded table, so this number saturates and must never be presented as exact.
   */
  total?: number;
  hasMore: boolean;
  busy?: boolean;
  onLoadMore: () => void;
  /** Plural noun for the rows, e.g. "events". */
  noun: string;
  /**
   * What the window holds, as an adjective ("the NEWEST of about 4,000").
   *
   * An append-only log is read newest-first, which is what the defaults say. A catalog fetched in
   * the server's own order has no such story: calling its first hundred rows "the newest" is a
   * claim about an ordering it does not have, and an operator who believes it stops looking for a
   * template they think must be older.
   */
  windowWord?: string;
  /** What is NOT loaded, as an adjective ("OLDER events are not loaded", "Load OLDER events"). */
  unloadedWord?: string;
  /** What the complete thing is called once it is all loaded ("the whole LOG"). */
  wholeWord?: string;
}

/**
 * The strip under an append-only list: what the window currently holds, and a way to grow it.
 *
 * SAYS THE EXTENT OUT LOUD, which is the part a pager never did. On a list showing the newest N
 * of something unbounded, "nothing matches" is ambiguous in a way that matters — it can mean the
 * thing does not exist, or that it is older than what has been loaded — and an operator who reads
 * the first as the second stops looking. So the footer states which of the two it is, even when
 * nothing is filtering.
 *
 * The button APPENDS. Every row already fetched stays in the list, filterable and sortable, so
 * growing the window can only ever reveal rows, never exchange one set for another. That is the
 * whole difference from the pager this replaces, and the reason `EditableList` has a footer slot
 * but no page control.
 */
export function WindowFooter({
  loaded,
  showing,
  total,
  hasMore,
  busy = false,
  onLoadMore,
  noun,
  windowWord = "newest",
  unloadedWord = "older",
  wholeWord = "log",
}: WindowFooterProps): ReactElement {
  const counted = showing === loaded ? `${loaded} ${noun}` : `${showing} of ${loaded} ${noun}`;
  const extent = !hasMore
    ? `the whole ${wholeWord}`
    : total && total > loaded
      ? `the ${windowWord} of about ${total.toLocaleString()} — ${unloadedWord} ${noun} are not loaded`
      : `${unloadedWord} ${noun} are not loaded`;

  return (
    <div className="flex items-center gap-3 rounded-b-lg border-x border-b border-apt-border px-3 py-2">
      {/* `role="status"` (not a bare aria-live) so the sentence is announced when the window
          grows — the caption changing is the only feedback that "Load older" did anything. */}
      <span className="text-xs text-apt-text-muted" role="status">
        {counted} — {extent}
      </span>
      <div className="flex-1" />
      {hasMore && (
        <Button variant="secondary" size="sm" onClick={onLoadMore} disabled={busy}>
          {busy ? "Loading…" : `Load ${unloadedWord} ${noun}`}
        </Button>
      )}
    </div>
  );
}
