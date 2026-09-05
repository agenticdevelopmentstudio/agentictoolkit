"use client";
import { useQuery } from "@tanstack/react-query";
import { useStatusApi } from "../api/client";

export interface ResponseHistory {
  hours: number;
  /** Average response time (ms) of UP checks per time bucket, oldest → newest; null = no data/all-down. */
  points: (number | null)[];
}

/** Portfolio-wide response-time history over the last `hours`, for the overview graph. */
export function useResponseHistory(hours: number) {
  const api = useStatusApi();
  return useQuery<ResponseHistory>({
    queryKey: ["response-history", hours],
    queryFn: async () => {
      const r = await api.fetch(`/response-history?hours=${hours}`);
      if (!r.ok) throw new Error(`response-history ${r.status}`);
      return r.json();
    },
    refetchInterval: 60_000,
  });
}
