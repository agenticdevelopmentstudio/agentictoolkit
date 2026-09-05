"use client";
import { useQuery } from "@tanstack/react-query";
import type { UptimeResponse } from "../types";

export function useUptime(days = 90) {
  return useQuery<UptimeResponse>({
    queryKey: ["uptime", days],
    queryFn: async () => {
      const r = await fetch(`/api/uptime?days=${days}`);
      if (!r.ok) throw new Error(`uptime ${r.status}`);
      return r.json();
    },
  });
}
