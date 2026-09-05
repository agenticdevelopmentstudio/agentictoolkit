"use client";
import { useCallback, useEffect } from "react";
import { useQueryClient } from "@tanstack/react-query";

/**
 * Refresh the supporting queries (uptime, integrations, response history, …)
 * together on one shared interval, so the dashboard never shows a mix of
 * fresh + stale datasets. The LIVE query is excluded: it drives itself on its
 * own refetchInterval (use-live-snapshot) — refetching it here too would
 * double the provider fan-out to two polls per minute per client.
 */
export function useRefreshAll(intervalMs = 60_000): { refreshAll: () => void } {
  const queryClient = useQueryClient();
  const refreshAll = useCallback(() => {
    // Disabled queries are skipped: an observer with `enabled: false` (e.g. the
    // board's config-status while Settings isn't the topic) opted OUT of
    // fetching — refetching it here would undo that gate every 60s.
    void queryClient.refetchQueries({ predicate: (q) => q.queryKey[0] !== "live" && !q.isDisabled() });
  }, [queryClient]);

  useEffect(() => {
    const id = setInterval(refreshAll, intervalMs);
    return () => clearInterval(id);
  }, [refreshAll, intervalMs]);

  return { refreshAll };
}
