"use client";
import { useQuery } from "@tanstack/react-query";
import type { HistoryResponse } from "../types";

export function useHistory(slug: string | null) {
  return useQuery<HistoryResponse>({
    queryKey: ["history", slug],
    queryFn: async () => {
      const r = await fetch(`/api/history?service=${encodeURIComponent(slug!)}&hours=24`);
      if (!r.ok) throw new Error(`history ${r.status}`);
      return r.json();
    },
    enabled: !!slug,
  });
}
