"use client";

import { QueryClientProvider, type QueryClient } from "@tanstack/react-query";
import { getToolkitQueryClient } from "@agentic-toolkit/data/query";
import type { ReactNode } from "react";

/**
 * How long an admin read counts as fresh: 30 seconds, the admin site's own client default since
 * before the panes were extracted.
 *
 * Admin data is platform-wide and changed by OTHER operators — a role granted, a flag flipped, an
 * invite accepted — so the toolkit's 5-minute default is wrong for it: an operator would act on a
 * list up to five minutes out of date. Before this was pinned here the panes were fresh for 30s on
 * admin.agenticdeveloperhub and 5 minutes in the hub's Admin workspace, i.e. the same pane behaved
 * differently depending on which host mounted it.
 */
export const ADMIN_STALE_TIME = 30 * 1000;

// Every key prefix the panes read under. Pinned on the CLIENT, by prefix, rather than on each of
// the ~35 reads: a prefix default also governs the entries a prefetch or a `setQueryData` mints
// with no observer, which a per-hook option would never reach. A new read under a new prefix must
// be added here — `adminQueryDefaults.test.ts` holds this list to the keys the sources use.
export const ADMIN_QUERY_KEY_PREFIXES: readonly (readonly string[])[] = [
  ["admin"],
  // Two segments where the first is a word other features also key under (`auth`, `system`):
  // the admin freshness must not leak onto a non-admin read that happens to share the client.
  ["auth", "invitation-requests"],
  ["auth", "pending-users"],
  ["auth", "invitations"],
  ["system", "admin-notes"],
  ["system", "entity-history"],
  ["system", "reserved-identifiers"],
  ["llm-sync-status"],
  ["llm-sync-keys"],
];

/** Pin the admin freshness onto `client`. Idempotent: `setQueryDefaults` replaces by key. */
export function applyAdminQueryDefaults(client: QueryClient): QueryClient {
  for (const prefix of ADMIN_QUERY_KEY_PREFIXES) {
    client.setQueryDefaults([...prefix], { staleTime: ADMIN_STALE_TIME });
  }
  return client;
}

/**
 * The query scope every admin pane reads through, on every host.
 *
 * It hands down the TOOLKIT's client — the module-scope singleton `@agentic-toolkit/data/query`
 * owns — because the panes import react-query from the toolkit's copy, and a provider built from
 * any other copy is invisible to them ("No QueryClient set"). That is exactly what the admin site
 * shipped with: its `QueryClientProvider` is built from the SITE's react-query, so the extracted
 * panes found no client there. Sharing the singleton rather than minting an admin client also
 * keeps its sign-out `clear()` (see that module's `watchSession`), which admin data needs more
 * than anything.
 *
 * Nesting is harmless: under a host's `ToolkitQueryProvider` this publishes the same client again,
 * so the hub's panes and the rest of its toolkit features still share one cache.
 */
export function AdminQueryProvider({ children }: { children: ReactNode }) {
  return (
    <QueryClientProvider client={applyAdminQueryDefaults(getToolkitQueryClient())}>
      {children}
    </QueryClientProvider>
  );
}
