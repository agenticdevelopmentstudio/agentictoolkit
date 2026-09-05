"use client";
import { useQuery } from "@tanstack/react-query";
import type { StatusResponse } from "../types";

export function useStatus() {
  return useQuery<StatusResponse>({
    queryKey: ["status"],
    queryFn: async () => {
      const r = await fetch("/api/status");
      if (!r.ok) {
        // The route returns `{ error }` with the real reason (e.g. a DB outage);
        // surface that as the thrown message so the UI shows WHY, not "status 503".
        const detail = await r
          .json()
          .then((b: { error?: string }) => b.error)
          .catch(() => null);
        throw new Error(detail || `status ${r.status}`);
      }
      return r.json();
    },
    refetchOnWindowFocus: true,
  });
}
