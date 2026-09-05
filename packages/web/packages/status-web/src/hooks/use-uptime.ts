"use client";
import { useQuery } from "@tanstack/react-query";
import { useStatusApi } from "../api/client";
import type { UptimeResponse } from "../types";

export function useUptime(days = 90) {
  const api = useStatusApi();
  return useQuery<UptimeResponse>({
    queryKey: ["uptime", days],
    queryFn: async () => {
      const r = await api.fetch(`/uptime?days=${days}`);
      if (!r.ok) throw new Error(`uptime ${r.status}`);
      return r.json();
    },
  });
}
