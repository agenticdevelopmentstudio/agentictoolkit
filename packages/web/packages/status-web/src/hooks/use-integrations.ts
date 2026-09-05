"use client";
import { useQuery } from "@tanstack/react-query";
import type { IntegrationsResponse } from "../types";

export function useIntegrations() {
  return useQuery<IntegrationsResponse>({
    queryKey: ["integrations"],
    queryFn: async () => {
      const r = await fetch("/api/integrations");
      if (!r.ok) throw new Error(`status ${r.status}`);
      return r.json();
    },
    refetchOnWindowFocus: true,
  });
}
