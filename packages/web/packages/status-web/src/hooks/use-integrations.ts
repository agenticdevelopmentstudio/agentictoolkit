"use client";
import { useQuery } from "@tanstack/react-query";
import { useStatusApi } from "../api/client";
import type { IntegrationsResponse } from "../types";

export function useIntegrations() {
  const api = useStatusApi();
  return useQuery<IntegrationsResponse>({
    queryKey: ["integrations"],
    queryFn: async () => {
      const r = await api.fetch("/integrations");
      if (!r.ok) throw new Error(`status ${r.status}`);
      return r.json();
    },
    refetchOnWindowFocus: true,
  });
}
