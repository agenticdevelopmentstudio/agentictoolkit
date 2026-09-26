"use client";

import { useQuery } from "@tanstack/react-query";
import { ecosystemsApi } from "./ecosystems";
import { useToolkitQueryClient } from "../query";
import { useTenantId } from "../tenant";

/**
 * The default (account-infrastructure) ecosystem id — THE resolver for workspace-level panes
 * (Storage / Integrations) that scope to the ecosystem their PRINCIPAL owns, and for the create
 * dialogs that preview the address a new ecosystem will be minted at. Ownership-correct:
 * resolved server-side via `infrastructure=true` — never a "default/first manageable" fallback,
 * which on an org workspace silently lands on a DIFFERENT principal's (the member's personal)
 * ecosystem for reads AND writes.
 *
 * `workspaceSlug` selects WHOSE row: given, the workspace principal's (`?workspace=`,
 * membership-gated); omitted, the CALLER's own — which is the right answer, not the absence of
 * one, for a slug-less host (a feature-site mount whose creates are caller-owned). The query is
 * therefore always enabled: gating it on the slug left a disabled query PENDING forever, and a
 * caller that treats pending as "still resolving" then waited on an answer that was never coming
 * — which is how every create on a slug-less mount ended up permanently blocked.
 *
 * Lives here — on the toolkit's own query client, next to the API it wraps — so there is ONE cache
 * entry per slug platform-wide; hosts must consume this hook rather than re-implementing the query
 * on their own QueryClient (two caches, double fetch, split invalidation).
 *
 * `ecosystemId` stays undefined while loading AND when there is no infrastructure ecosystem;
 * `isLoadingError` distinguishes a failed resolution (`retry: false` — one shot) so callers can
 * show a retry surface instead of a dead pane, and `isPending` separates the two undefined cases for the
 * callers that must not act on "no infrastructure ecosystem" until it is actually the answer.
 */
export function useWorkspaceDefaultEcosystemId(workspaceSlug: string | undefined): {
  ecosystemId?: string;
  /** True unless the caller can only VIEW (not manage) the workspace's infrastructure ecosystem
   *  — a plain org member. Defaults to true while loading / when there is no infra row, so a
   *  host only gates when the resolution definitively says the caller can't manage. */
  canManage: boolean;
  /** The LAST read failed — including a background re-read behind an answer still on screen. For a
   *  gate that replaces the pane with an error, read {@link isLoadingError} instead: gating on this
   *  one threw away a perfectly good cached resolution the moment a refetch hiccupped. */
  isError: boolean;
  /** The read failed and there is NO answer — the first read failed, so `ecosystemId` is undefined
   *  because nobody knows it, not because there is none. The flag a "couldn't resolve" gate wants:
   *  a failed re-read behind a cached answer keeps that answer, and this stays false. */
  isLoadingError: boolean;
  /** No answer yet — the query is in flight. Distinct from a resolved `ecosystemId: undefined`,
   *  which is the definitive "there is no infrastructure ecosystem". A caller that PREVIEWS
   *  something derived from the id (an address prefix) must show nothing while this is true
   *  rather than the no-parent shape, which is a different, wrong answer. This is only ever
   *  TRANSIENT — the query is never disabled, so it always settles. */
  isPending: boolean;
  /** A read is in flight, whether or not there is already an answer on screen. Wider than
   *  {@link isPending} on purpose: after the first visit the resolution is cached, so `isPending`
   *  is false on every subsequent mount — including the ones that re-read behind the copy being
   *  shown, once the entry has gone stale. A host that reports progress — a topic list's spinner —
   *  wants this one, or the only visit it ever admits to reading is the first. */
  isFetching: boolean;
} {
  // The TENANT is a key segment, exactly as it is for every resource list and item. The answer is
  // resolved server-side FOR THE CALLER (`?workspace=` is membership-gated), so an unscoped key
  // would let a sign-in as somebody else read the previous account's resolution as fresh — and the
  // client that holds it is at module scope now, so that entry survives every navigation in the
  // tab rather than dying with the page subtree that created it.
  const tenantId = useTenantId();
  // The client PASSED, not read from context — the same shape `useResourceList` and
  // `useResourceItemQuery` use, and for the same reason: this hook is called from panes
  // (`EcosystemConfigGate`, `IntegrationsFeature`, an integration's destinations) that a host can
  // mount anywhere, and reading it from context alone makes an absent `ToolkitQueryProvider` a
  // "No QueryClient set" THROW at the top of the pane rather than a pane that simply works. The
  // provider hands out this very singleton, so a host that does mount one is unaffected — and the
  // "ONE cache entry per slug platform-wide" the doc above promises is now true by construction
  // instead of by contract.
  const client = useToolkitQueryClient();
  const query = useQuery(
    {
      queryKey: ["workspace-default-ecosystem", tenantId, workspaceSlug ?? null],
      queryFn: () => ecosystemsApi.workspaceDefaultEcosystemId(workspaceSlug),
      retry: false,
    },
    client,
  );
  return {
    ecosystemId: query.data?.id ?? undefined,
    canManage: query.data?.canManage ?? true,
    isError: query.isError,
    isLoadingError: query.isLoadingError,
    isPending: query.isPending,
    isFetching: query.isFetching,
  };
}
