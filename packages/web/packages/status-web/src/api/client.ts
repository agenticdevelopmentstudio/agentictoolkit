"use client";
import { createContext, createElement, useContext, useMemo, type ReactElement, type ReactNode } from "react";

// The dashboard's one port onto its backend. Every panel and hook asks this
// contract for JSON, a raw Response, or an EventSource instead of naming a base
// path itself — the host is the only place that knows where the proxy lives.

/**
 * A JSON/SSE client scoped to a base path. `path` is always relative to that
 * base (e.g. `"/auth/me"`, `"/live/stream"`) — callers never see or state the
 * base themselves.
 */
export interface StatusApiClient {
  /** The absolute URL for a path relative to the base. */
  url(path: string): string;
  /** `fetch`, resolved against the base. */
  fetch(path: string, init?: RequestInit): Promise<Response>;
  /** JSON request/response: throws `Error` with `${method} ${url} → ${status}`
   *  plus any `error`/`message` detail the body carries, and treats a `204` as
   *  `undefined` rather than an empty-body parse failure. */
  json<T>(path: string, init?: RequestInit): Promise<T>;
  /** An `EventSource` for a path relative to the base. */
  eventSource(path: string): EventSource;
}

/** The same-origin default every host gets unconfigured — the Next host's own
 *  `/api/[...path]` proxy. A host overrides it via `StatusApiProvider`'s
 *  `basePath` when it proxies elsewhere. This is the package's one hard-coded
 *  `/api` — every other module reaches the backend through a `StatusApiClient`. */
export const DEFAULT_API_BASE = "/api";

interface ErrorBody {
  error?: string | { message?: string };
  message?: string;
}

async function errorDetail(res: Response): Promise<string> {
  const body = (await res.json().catch(() => null)) as ErrorBody | null;
  const text = typeof body?.error === "string" ? body.error : (body?.error?.message ?? body?.message);
  return text ? ` — ${text}` : "";
}

/** Builds the one adapter that joins a base path to a relative one and talks
 *  `fetch`/`EventSource` — the thin translation layer behind the port above. */
export function createStatusApiClient({
  basePath = DEFAULT_API_BASE,
  fetch: fetchImpl,
}: { basePath?: string; fetch?: typeof fetch } = {}): StatusApiClient {
  const url = (path: string): string => `${basePath}${path}`;
  // The global is looked up per call, never captured: the default client is built at
  // module load, before a test (or a polyfill) has installed its own `fetch`.
  const fetchFromBase = (path: string, init?: RequestInit): Promise<Response> =>
    (fetchImpl ?? globalThis.fetch)(url(path), init);

  return {
    url,
    fetch: fetchFromBase,
    async json<T>(path: string, init?: RequestInit): Promise<T> {
      const res = await fetchFromBase(path, {
        ...init,
        headers: { "Content-Type": "application/json", ...(init?.headers ?? {}) },
      });
      if (!res.ok) {
        throw new Error(`${init?.method ?? "GET"} ${url(path)} → ${res.status}${await errorDetail(res)}`);
      }
      return (res.status === 204 ? undefined : await res.json()) as T;
    },
    eventSource(path: string): EventSource {
      return new EventSource(url(path));
    },
  };
}

const defaultClient = createStatusApiClient();

const StatusApiContext = createContext<StatusApiClient | null>(null);

/** Mount at the host's composition root to point the dashboard at a non-default
 *  base path, or to inject a test double. Without one, every panel falls back
 *  to the same-origin default client. */
export function StatusApiProvider({
  client,
  basePath,
  children,
}: {
  client?: StatusApiClient;
  basePath?: string;
  children: ReactNode;
}): ReactElement {
  const value = useMemo(() => client ?? createStatusApiClient({ basePath }), [client, basePath]);
  return createElement(StatusApiContext.Provider, { value }, children);
}

/** The host's API client, or the same-origin default when no provider is mounted. */
export function useStatusApi(): StatusApiClient {
  return useContext(StatusApiContext) ?? defaultClient;
}
