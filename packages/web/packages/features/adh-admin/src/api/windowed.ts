"use client";

import { useCallback, useMemo } from "react";
import { useInfiniteQuery } from "@tanstack/react-query";

/** One server page of an append-only log. */
export interface WindowPage<T> {
  items: T[];
  total: number;
}

export interface UseWindowedListOptions<T> {
  /** React Query key for the whole window. Must not contain anything the operator types. */
  key: readonly unknown[];
  /** Fetch one server page, 1-based. */
  fetchPage: (page: number, pageSize: number) => Promise<WindowPage<T>>;
  /** How many rows one fetch brings back. */
  pageSize: number;
  /**
   * A row's stable identity, used to keep the window free of duplicates.
   *
   * Required, not optional, because the duplicate is not a rare case. Growing this window is
   * OFFSET paging over a log that is still being written to: one event inserted between the first
   * fetch and the second pushes every row down a place, so the row that was last on page one is
   * first on page two and the operator sees it twice. React would then see two rows with the same
   * key, and the list's selection would count one row as two.
   */
  getRowId: (item: T) => string;
}

export interface WindowedList<T> {
  /** Every row fetched so far, oldest fetch first — i.e. the window, in server order. */
  rows: T[];
  isLoading: boolean;
  isFetchingMore: boolean;
  /** The server has rows beyond the window. */
  hasMore: boolean;
  loadMore: () => void;
  /** What the server says the whole log holds — which may be a saturating estimate. */
  total: number;
  error: unknown;
}

/**
 * A GROWING WINDOW over an append-only log, for the lists whose population has no end.
 *
 * Most admin lists are bounded — every feature flag, every provider, every reserved name — so they
 * are fetched whole and narrowed in the browser, and `EditableList` has no pager for the same
 * reason it has no page size. An audit trail or a message log is different in kind: it grows
 * forever, so "fetch it all" is a promise the client cannot keep.
 *
 * A pager is still the wrong answer, and not because of taste. A pager and a filter are two ways
 * to not see a row, and the pager silently defeats the filter: the operator types a term, the
 * server returns page one of the matches, and the twenty-six-through-forty they were looking for
 * are behind a control most of them never press. What this does instead is APPEND. The window only
 * ever grows, every row in it stays filterable and sortable, and "load more" adds rows rather than
 * exchanging one set for another — so a filter is never narrowing a slice it cannot see past.
 *
 * The window is the newest N, because these logs are read newest-first and an operator looking for
 * something older narrows rather than walks. `total` is what the server reports and is often a
 * capped estimate (the audit route saturates its count deliberately, to keep a full scan off an
 * unbounded table), so it is a caption, never arithmetic anything depends on.
 */
export function useWindowedList<T>({
  key,
  fetchPage,
  pageSize,
  getRowId,
}: UseWindowedListOptions<T>): WindowedList<T> {
  const query = useInfiniteQuery({
    queryKey: [...key, pageSize],
    queryFn: ({ pageParam }) => fetchPage(pageParam, pageSize),
    initialPageParam: 1,
    // The NEXT page is asked for only when the last one came back full. A short page is the end of
    // the log, and offering "load more" there gives the operator a button that fetches nothing.
    getNextPageParam: (last, all) => (last.items.length < pageSize ? undefined : all.length + 1),
  });

  // FIRST SIGHTING WINS. A row that reappears on a later page because the log grew underneath the
  // window is the same row, already on screen, in the position the operator saw it in — replacing
  // it would make the list reorder itself under a scroll they did not ask to move.
  const rows = useMemo(() => {
    const seen = new Set<string>();
    const out: T[] = [];
    for (const page of query.data?.pages ?? []) {
      for (const item of page.items) {
        const id = getRowId(item);
        if (seen.has(id)) continue;
        seen.add(id);
        out.push(item);
      }
    }
    return out;
  }, [query.data, getRowId]);

  const { fetchNextPage } = query;
  const loadMore = useCallback(() => {
    void fetchNextPage();
  }, [fetchNextPage]);

  return {
    rows,
    isLoading: query.isLoading,
    isFetchingMore: query.isFetchingNextPage,
    hasMore: query.hasNextPage,
    loadMore,
    // The LATEST page's count, not the first's. Both are the server's answer to the same
    // question, but the first was answered when the window opened and a log that has grown
    // since would keep reporting the number it had then.
    total: query.data?.pages.at(-1)?.total ?? 0,
    error: query.error,
  };
}
